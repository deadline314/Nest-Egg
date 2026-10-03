class_name PropNode
extends Node2D
## 場景道具實體：貼圖（受光、有法線）、自發光層、光源、單向平台與遮光。
## 位置是道具左上角（世界座標）。貼圖缺失時顯示替代圖並記錄具體路徑（由 LitTextures 負責）。
## 有光源的道具跟招牌一樣受電力影響：停電時熄滅。

var data: PropData
var flip := false

var _glow_sprite: Sprite2D
var _light: PointLight2D
var _time := 0.0
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
	set_process(data.has_glow or data.light_radius > 0.0)
	_time = randf() * 10.0


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
