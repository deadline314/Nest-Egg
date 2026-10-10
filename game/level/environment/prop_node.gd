class_name PropNode
extends Node2D
## 場景道具實體：貼圖（受光、有法線）、自發光層、光源、單向平台與遮光。
## 位置是道具左上角（世界座標）。貼圖缺失時顯示替代圖並記錄具體路徑（由 LitTextures 負責）。
## 有光源的道具跟招牌一樣受電力影響：停電時熄滅。

const SWAY_SHADER := preload("res://game/level/environment/sway.gdshader")
const SWAY_EMISSIVE_SHADER := preload("res://game/level/environment/sway_emissive.gdshader")
const GLOW_SCAN_SHADER := preload("res://game/level/environment/glow_scan.gdshader")
const RIPPLE_SHADER := preload("res://game/level/environment/puddle_ripple.gdshader")
const STEAM_INTERVAL := 0.3
const LOCAL_FLOW := preload("res://game/level/environment/local_water_flow.gd")

## 搖動（幅度、是否懸掛、是否自發光）→ 共用材質（同設定的道具共用同一份，數量再多也只有幾份）。
static var _sway_materials: Dictionary[Vector3, ShaderMaterial] = {}
## 螢幕掃描強度 → 共用材質。
static var _scan_materials: Dictionary[float, ShaderMaterial] = {}
static var _ripple_material: ShaderMaterial

var data: PropData
var flip := false

var _glow_sprite: Sprite2D
var _light: PointLight2D
var _time := 0.0
var _steam_timer := 0.0
var _on_screen := false
var _power_threshold := randf_range(0.1, 0.95)


func setup(p_data: PropData, top_left: Vector2, p_flip := false) -> void:
	data = p_data
	flip = p_flip
	position = top_left
	name = String(data.id)


func _ready() -> void:
	if data == null:
		return
	var size := data.size
	var tex := LitTextures.load_texture(data.texture, Vector2i(size) * PropData.TEXTURE_SCALE)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.scale = _scale_for(tex)
	_apply_flip(sprite)
	if data.sway > 0.0:
		sprite.material = sway_material(data.sway, data.sway_hang)
	add_child(sprite)
	if data.layer == PropData.Layer.FRONT:
		z_index = 3
		modulate.a = data.front_alpha
	if data.has_glow:
		_add_glow()
	if data.light_radius > 0.0:
		_add_light()
	if data.platform.size.x > 0.0:
		_add_platform()
	if data.casts_shadow:
		_add_occluder()
	if data.steam:
		_add_steam_gate()
	if data.has_local_flow():
		if data.local_flow_valid() and ResourceLoader.exists(data.texture):
			var flow := LOCAL_FLOW.new()
			flow.name = "LocalWaterFlow"
			add_child(flow)
			flow.setup(data, sprite, _glow_sprite)
		else:
			push_warning("[PropNode] %s 局部水流 UV 無效，保留靜態圖" % data.id)
	set_process(data.has_glow or data.light_radius > 0.0 or data.steam)
	_time = randf() * 10.0


static func sway_material(amplitude: float, hang: bool, emissive := false) -> ShaderMaterial:
	var key := Vector3(amplitude, 1.0 if hang else 0.0, 1.0 if emissive else 0.0)
	if not _sway_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SWAY_EMISSIVE_SHADER if emissive else SWAY_SHADER
		material.set_shader_parameter(&"amplitude", amplitude)
		material.set_shader_parameter(&"hang", hang)
		_sway_materials[key] = material
	return _sway_materials[key]


## 水窪漣漪材質（全部水窪共用同一份）。
static func ripple_material() -> ShaderMaterial:
	if _ripple_material == null:
		_ripple_material = ShaderMaterial.new()
		_ripple_material.shader = RIPPLE_SHADER
	return _ripple_material


static func _scan_material(strength: float) -> ShaderMaterial:
	if not _scan_materials.has(strength):
		var material := ShaderMaterial.new()
		material.shader = GLOW_SCAN_SHADER
		material.set_shader_parameter(&"strength", strength)
		_scan_materials[strength] = material
	return _scan_materials[strength]


func _scale_for(tex: Texture2D) -> Vector2:
	var tex_size := Vector2(tex.get_size())
	return Vector2(data.size.x / maxf(tex_size.x, 1.0), data.size.y / maxf(tex_size.y, 1.0))


func _apply_flip(sprite: Sprite2D) -> void:
	if flip:
		sprite.flip_h = true


func _add_glow() -> void:
	var glow := RigLibrary.optional_texture(data.glow_path())
	if glow == null:
		push_error("[PropNode] 找不到自發光層：%s" % data.glow_path())
		return
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = glow
	_glow_sprite.centered = false
	_glow_sprite.scale = _scale_for(glow)
	_apply_flip(_glow_sprite)
	if data.sway > 0.0:
		# 自發光層跟著本體一起搖（窗光生命與螢幕掃描在搖動的道具上不使用）
		_glow_sprite.material = sway_material(data.sway, data.sway_hang, true)
	elif data.ripple and not data.has_local_flow():
		_glow_sprite.material = ripple_material()
	elif data.glow_life:
		_glow_sprite.material = LightKit.window_life_material()
	elif data.glow_scan > 0.0:
		_glow_sprite.material = _scan_material(data.glow_scan)
	else:
		LightKit.mark_emissive(_glow_sprite)
	_glow_sprite.self_modulate = LightKit.glow(Color.WHITE, data.glow_intensity)
	add_child(_glow_sprite)


func _add_light() -> void:
	_light = LightKit.create_point_light(data.light_color, data.light_radius, data.light_energy)
	var offset := data.light_offset
	if flip:
		offset.x = data.size.x - offset.x
	_light.position = offset
	add_child(_light)


func _add_platform() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.PLATFORM
	body.collision_mask = 0
	var rect := data.platform
	if flip:
		rect.position.x = data.size.x - rect.position.x - rect.size.x
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.position + rect.size * 0.5
	collision.one_way_collision = true
	body.add_child(collision)
	add_child(body)


## 只在畫面內才冒蒸汽（離開畫面就不再發射粒子）。
func _add_steam_gate() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-24, -64, data.size.x + 48, data.size.y + 96)
	notifier.screen_entered.connect(func() -> void: _on_screen = true)
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)


func _add_occluder() -> void:
	var inset := data.size * 0.12
	var rect := Rect2(inset, data.size - inset * 2.0)
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var occluder := LightOccluder2D.new()
	occluder.occluder = polygon
	add_child(occluder)


func _process(delta: float) -> void:
	_time += delta
	if data.steam and _on_screen:
		_steam_timer -= delta
		if _steam_timer <= 0.0:
			_steam_timer = STEAM_INTERVAL * randf_range(0.7, 1.4)
			Fx.steam(steam_world_position(Vector2(randf_range(-2.0, 2.0), 0.0)))
	var gate := LightKit.power_gate(LightKit.lamp_power, _power_threshold) if data.light_radius > 0.0 else 1.0
	var flick := 1.0
	if data.flicker > 0.0:
		flick = 1.0 - data.flicker * (0.5 + 0.5 * sin(_time * 29.0) * sin(_time * 6.7))
	if _light != null:
		_light.enabled = gate > 0.0
		_light.energy = data.light_energy * flick * gate
	if _glow_sprite != null:
		var k := flick * gate if data.light_radius > 0.0 else flick
		_glow_sprite.self_modulate = LightKit.glow(Color(1, 1, 1, clampf(k, 0.0, 1.0)), data.glow_intensity)


## 噴口與本體同一座標契約：支援鏡像與父節點縮放，避免蒸汽離開真正噴口。
func steam_world_position(jitter := Vector2.ZERO) -> Vector2:
	var offset := data.steam_offset if data.steam_offset.is_finite() else Vector2.ZERO
	if flip:
		offset.x = data.size.x - offset.x
	return to_global(offset + jitter)
