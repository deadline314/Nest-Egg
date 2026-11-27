class_name SuspendedLoad
extends StaticBody2D
## 吊掛貨物（NE-397）：鏈條吊著的貨箱。被玩家的子彈、近戰或爆炸打到就鬆開，垂直砸下去：
## 落地時傷害正下方的敵人（不傷害玩家），之後留在原地當掩體（擋路也擋子彈），遠程敵人也會躲到它後面（CoverSpots，NE-415）。
## 吊著的時候不擋路、不擋子彈，角色可以從底下走過；地上有一塊淡影標出它會砸在哪裡。
## 原點在落地那一格的底邊中點。外觀、高度與傷害來自 SuspendedLoadData。狀態（掉下來了沒）跟著檢查點保存。

signal landed(cargo: SuspendedLoad)

enum State { HANGING, FALLING, LANDED }

const GROUP := &"suspended_loads"
const CHAIN_TEXTURE := "res://art/environment/scene_props/dock_warehouse/dock_warehouse__hoist_chain.png"
## 鏈條貼圖在遊戲裡的寬度與最長長度（世界像素）；吊點比這個高時鏈條從貼圖的長度往下掛，上面接一條細纜。
const CHAIN_WIDTH := 11.0
const CHAIN_MAX_LENGTH := 96.0
const FALL_GRAVITY := 1400.0
const MAX_FALL_SPEED := 720.0
## 吊著時的輕微擺動（世界像素、每秒弧度）；「減少動態」時不擺。
const SWAY_PIXELS := 0.8
const SWAY_RATE := 1.3
## 鬆開後留在上面的那一截鏈條甩動的幅度（弧度）與衰減。
const SNAP_SWING := 0.5
const SNAP_SECONDS := 1.4
const PROMPT_REACH := 96.0
const HURTBOX_PADDING := 3.0
const SHADOW_ALPHA := 0.34
## 落地時把正下方的角色推到貨箱邊緣外多遠（像素），以及腳底在貨箱頂上方多少以內才算在底下。
const SHOVE_MARGIN := 9.0
const SHOVE_HEADROOM := 8.0

var data: SuspendedLoadData
var cell := Vector2i.ZERO
var state: State = State.HANGING
var size_px := Vector2(32, 32)
var health: HealthComponent
var hurtbox: Hurtbox

## 吊點（天花板）在原點上方多少像素；由關卡依地形算好交進來。
var _anchor_height := 128.0
var _hang_height := 64.0
var _drop := 0.0  # 貨箱底部目前離地多高（像素）
var _fall_speed := 0.0
var _time := 0.0
var _snap := 0.0
var _cargo: Node2D
var _shape_node: CollisionShape2D
var _chain: _Chain
var _shadow: _Shadow
var _prompt: WorldPrompt
var _player_ref := PlayerRef.new()


## anchor_height：吊點離落地面多高（像素）。
func configure(p_data: SuspendedLoadData, p_cell: Vector2i, tile_size: int, anchor_height: float) -> void:
	data = p_data
	cell = p_cell
	size_px = Vector2(data.size_tiles) * tile_size
	_hang_height = float(data.hang_tiles * tile_size)
	_anchor_height = maxf(anchor_height, _hang_height + size_px.y + 4.0) if is_finite(anchor_height) else _hang_height + size_px.y + 32.0
	_drop = _hang_height


func _ready() -> void:
	if data == null:
		push_error("[SuspendedLoad] 未指定 SuspendedLoadData，已移除。")
		queue_free()
		return
	add_to_group(GROUP)
	add_to_group(WorldState.GROUP)
	collision_layer = Layers.WORLD
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size_px
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = shape
	_shape_node.position = Vector2(0, -size_px.y * 0.5)
	_shape_node.disabled = true  # 吊著時不擋路
	add_child(_shape_node)

	_shadow = _Shadow.new()
	_shadow.owner_load = self
	add_child(_shadow)
	_chain = _Chain.new()
	_chain.owner_load = self
	_chain.texture = RigLibrary.optional_texture(CHAIN_TEXTURE)
	if _chain.texture == null:
		push_error("[SuspendedLoad] 找不到鏈條貼圖，改畫一條纜線：%s" % CHAIN_TEXTURE)
	add_child(_chain)
	_cargo = Node2D.new()
	_cargo.name = "Cargo"
	add_child(_cargo)
	var body_id := FixtureArt.breakable_body(BreakableData.Look.CRATE)
	var art := FixtureArt.attach(_cargo, body_id, Vector2(-size_px.x * 0.5, -size_px.y), size_px) if body_id != &"" else null
	if art == null:
		var fallback := _Fallback.new()
		fallback.size = size_px
		_cargo.add_child(fallback)

	health = HealthComponent.new()
	add_child(health)
	health.setup(data.release_health, 0.0)
	health.died.connect(_on_released)
	hurtbox = Hurtbox.new()
	_cargo.add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, size_px + Vector2.ONE * HURTBOX_PADDING, Vector2(0, -size_px.y * 0.5))
	hurtbox.hit_material = &"metal"

	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.offset = Vector2(0, -34.0)
		_prompt.reach_check = _prompt_in_reach
		add_child(_prompt)
	_place_cargo()


func _exit_tree() -> void:
	CoverSpots.unregister(self)


## 提示只在貨箱還吊著、玩家在附近的地面上時出現。
func _prompt_in_reach() -> bool:
	if state != State.HANGING:
		return false
	var player := _player_ref.get_player(get_tree())
	return player != null and absf(player.global_position.x - global_position.x) <= PROMPT_REACH \
			and absf(player.global_position.y - global_position.y) <= _hang_height + size_px.y


func is_hanging() -> bool:
	return state == State.HANGING


## 貨箱底部目前離地多高（像素；測試與量測用）。
func drop_height() -> float:
	return _drop


func cargo_center() -> Vector2:
	return global_position + Vector2(0.0, -_drop - size_px.y * 0.5)


func _on_released(_info: DamageInfo) -> void:
	release()


## 鬆開鏈條開始往下掉。已經掉了就不做事。
func release() -> void:
	if state != State.HANGING:
		return
	state = State.FALLING
	_fall_speed = 0.0
	_snap = 1.0
	hurtbox.enabled = false
	if _prompt != null:
		_prompt.enabled = false
	Fx.impact(global_position + Vector2(0.0, -_drop - size_px.y), Vector2.UP, Palette.WARNING, 6)
	Sfx.play(&"rattle", -3.0)
	EventBus.world_noise.emit(cargo_center(), 0.6)


func _physics_process(delta: float) -> void:
	if state != State.FALLING:
		return
	_fall_speed = minf(_fall_speed + FALL_GRAVITY * delta, MAX_FALL_SPEED)
	_drop -= _fall_speed * delta
	if _drop <= 0.0:
		_drop = 0.0
		_land(true)
	_place_cargo()


func _process(delta: float) -> void:
	_time += delta
	if _snap > 0.0:
		_snap = move_toward(_snap, 0.0, delta / SNAP_SECONDS)
		_chain.queue_redraw()
	if state == State.HANGING and not Settings.get_reduce_ui_motion():
		_place_cargo()
	elif state == State.LANDED and _snap <= 0.0:
		set_process(false)


func _place_cargo() -> void:
	var sway := sin(_time * SWAY_RATE + float(cell.x)) * SWAY_PIXELS if state == State.HANGING and not Settings.get_reduce_ui_motion() else 0.0
	_cargo.position = Vector2(sway, -_drop)
	_chain.queue_redraw()
	_shadow.queue_redraw()


## 落地：變成掩體；with_effects＝false 是從檢查點還原，不播效果也不造成傷害。
func _land(with_effects: bool) -> void:
	state = State.LANDED
	_drop = 0.0
	_shape_node.set_deferred(&"disabled", false)
	CoverSpots.register(self, Rect2(global_position - Vector2(size_px.x * 0.5, size_px.y), size_px))
	hurtbox.enabled = false
	if _prompt != null:
		_prompt.enabled = false
	if not with_effects:
		_snap = 0.0
		return
	_shove_clear()
	# 只傷害敵人：玩家是從遠處把它打下來的那個人，不該被自己設的陷阱砸死。
	var blast := Explosion.new()
	blast.radius = data.drop_radius
	blast.damage = data.drop_damage
	blast.team = Combat.Team.PLAYER
	blast.source_id = data.id
	blast.environmental = true
	blast.position = global_position + Vector2(0.0, -size_px.y * 0.5)
	Fx.add_world_node(blast)
	Fx.dust(global_position, 9, size_px.x)
	Fx.impact(global_position, Vector2.UP, Palette.TERRAIN_TOP, 8)
	Feel.shake_strength(4.0, 0.22, Vector2.DOWN, global_position)
	Sfx.play(&"crate_break", -1.0)
	Sfx.play(&"land", -2.0)
	EventBus.world_noise.emit(global_position, 1.0)
	landed.emit(self)


## 落地那一刻站在正下方的角色（玩家與還活著的敵人）往比較近的那一側推開，不會被卡在貨箱裡。
func _shove_clear() -> void:
	var half := size_px.x * 0.5
	for group: StringName in [&"player", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null:
				continue
			var offset := body.global_position - global_position
			if absf(offset.x) >= half + SHOVE_MARGIN or offset.y < -size_px.y - SHOVE_HEADROOM or offset.y > 4.0:
				continue
			var side := 1.0 if offset.x >= 0.0 else -1.0
			body.global_position.x = global_position.x + side * (half + SHOVE_MARGIN)


# ---------------------------------------------------------------------------
# 檢查點狀態（WorldState）
# ---------------------------------------------------------------------------

func state_key() -> String:
	return "suspended@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return state != State.HANGING


func restore_state(saved: Variant) -> void:
	if saved == true and state != State.LANDED:
		_land(false)
		_place_cargo()


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

## 鏈條：吊著時從吊點垂到貨箱頂；鬆開後只剩上面一截，甩幾下停住。
class _Chain:
	extends Node2D

	var owner_load: SuspendedLoad
	var texture: Texture2D

	func _init() -> void:
		z_index = -1

	func _draw() -> void:
		var host := owner_load
		if host == null:
			return
		var top := -host._anchor_height
		var hanging := host.state == SuspendedLoad.State.HANGING
		var bottom := -host._drop - host.size_px.y + 2.0 if hanging else top + minf(SuspendedLoad.CHAIN_MAX_LENGTH * 0.45, host._anchor_height * 0.4)
		var length := bottom - top
		if length <= 1.0:
			return
		# 吊著：鏈條下端跟著貨箱的輕微擺動；鬆開後：留下的那一截甩幾下。
		var angle := -atan2(host._cargo.position.x, length) if hanging else sin(host._time * 9.0) * SuspendedLoad.SNAP_SWING * host._snap
		draw_set_transform(Vector2(0.0, top), angle)
		var chain_length := minf(length, SuspendedLoad.CHAIN_MAX_LENGTH)
		var cable := length - chain_length
		if cable > 0.0:
			# 吊點比鏈條貼圖長：上面先接一段細纜。
			draw_line(Vector2.ZERO, Vector2(0.0, cable), Color("2a3340"), 1.5)
		if texture != null:
			var texels := texture.get_size()
			var source := Rect2(0.0, 0.0, texels.x, texels.y * chain_length / SuspendedLoad.CHAIN_MAX_LENGTH)
			draw_texture_rect_region(texture, Rect2(-SuspendedLoad.CHAIN_WIDTH * 0.5, cable, SuspendedLoad.CHAIN_WIDTH, chain_length), source)
		else:
			draw_line(Vector2(0.0, cable), Vector2(0.0, length), Color("3d4a5a"), 2.0)
		draw_set_transform(Vector2.ZERO)


## 貨箱正下方地面上的淡影：吊得越高越淡越小，同時標出它會砸在哪裡。落地後是貼地的接觸陰影。
class _Shadow:
	extends Node2D

	var owner_load: SuspendedLoad

	func _init() -> void:
		z_as_relative = false
		z_index = WorldLayers.TERRAIN + 1

	func _draw() -> void:
		var host := owner_load
		if host == null:
			return
		var height := clampf(host._drop / maxf(host._hang_height, 1.0), 0.0, 1.0)
		var width := host.size_px.x * lerpf(1.2, 0.85, height)
		var alpha := SuspendedLoad.SHADOW_ALPHA * lerpf(1.5, 0.75, height)
		draw_texture_rect(LightKit.soft_texture(), Rect2(-width * 0.5, -2.5, width, 6.0), false, Color(0.0, 0.0, 0.0, alpha))


## 貨箱貼圖讀不到時的替代畫法（FixtureArt 已經記錄是哪一張）。
class _Fallback:
	extends Node2D

	var size := Vector2(32, 32)

	func _draw() -> void:
		var rect := Rect2(Vector2(-size.x * 0.5, -size.y), size)
		draw_rect(rect, Color(0.45, 0.4, 0.34))
		draw_rect(rect, Color(0.2, 0.18, 0.16), false, 2.0)
		draw_line(rect.position, rect.end, Color(0.2, 0.18, 0.16), 1.0)
