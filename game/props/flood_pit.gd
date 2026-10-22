class_name FloodPit
extends Node2D
## 水坑（第一章水位謎，以死解謎）：站上坑底的踏板，水在 rise_time 秒內漲滿，頭頂被淹過就溺斃；
## 踏板一被踩下，data.channel 的閘門就打開（EventBus.mechanism_toggled）。水位與閘門在死後保留（WorldState），
## 漲滿之後水面上浮著一排貨櫃（單向平台）讓人走過坑。原點是踏板所在格的底邊中點（坑底正中），
## 坑的內部由 data.size_tiles（寬×深，格）決定，地形要在這個範圍挖空。
##
## 設計成「踩下就回不了頭」：坑深比跳躍高度大，所以進了坑只剩踏板這條路；進坑前有提示牌與踏板上的提示。

const PLATE_HALF_WIDTH := 20.0
const PLATE_HEIGHT := 10.0
## 頭頂高度：水面超過腳底往上這麼多就溺斃。
const HEAD_HEIGHT := 40.0
const DROWN_SOURCE := &"flood"
const WATER_Z := 9
const RAFT_THICKNESS := 6.0
const PROMPT_TEXT := "踩住坑底踏板，讓閘門保持開啟。"

var data: MechanismData
var cell := Vector2i.ZERO
## 是否已經被觸發（漲水中或已漲滿）；存進世界狀態。
var triggered := false

var _tile := 16
## 0＝乾，1＝漲滿。
var _water := 0.0
var _time := 0.0
var _interior := Rect2()
var _raft: StaticBody2D
var _raft_shape: CollisionShape2D
var _plate_in_range := false
var _prompt: WorldPrompt


func configure(p_data: MechanismData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	_tile = tile_size


func _ready() -> void:
	if data == null:
		push_error("[FloodPit] 未指定 MechanismData，已移除。")
		queue_free()
		return
	var size := Vector2(data.size_tiles) * float(_tile)
	_interior = Rect2(Vector2(-size.x * 0.5, -size.y), size)
	z_index = WATER_Z
	LightKit.mark_emissive(self)
	_build_plate()
	_build_raft()
	add_to_group(WorldState.GROUP)


func _build_plate() -> void:
	var area := Area2D.new()
	area.name = "Plate"
	area.collision_layer = 0
	area.collision_mask = Layers.PLAYER
	area.monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(PLATE_HALF_WIDTH * 2.0, PLATE_HEIGHT)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -PLATE_HEIGHT * 0.5)
	area.add_child(shape_node)
	area.body_entered.connect(_on_plate_entered)
	area.body_exited.connect(_on_plate_exited)
	add_child(area)
	_prompt = WorldPrompt.new()
	_prompt.text = PROMPT_TEXT
	_prompt.radius = 44.0
	_prompt.offset = Vector2(0, -PLATE_HEIGHT - 52.0)
	add_child(_prompt)


func _build_raft() -> void:
	_raft = StaticBody2D.new()
	_raft.name = "Raft"
	_raft.collision_layer = Layers.PLATFORM
	_raft.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_interior.size.x, RAFT_THICKNESS)
	_raft_shape = CollisionShape2D.new()
	_raft_shape.shape = shape
	_raft_shape.one_way_collision = true
	_raft_shape.position = Vector2(0, _interior.position.y + RAFT_THICKNESS * 0.5)
	_raft_shape.disabled = true
	_raft.add_child(_raft_shape)
	add_child(_raft)


func _on_plate_entered(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_plate_in_range = true
		trigger()


func _on_plate_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_plate_in_range = false


## 觸發漲水（踩下踏板；測試也直接呼叫）。已經觸發過就不再做。
func trigger() -> void:
	if triggered:
		return
	triggered = true
	_prompt.enabled = false
	EventBus.mechanism_toggled.emit(data.channel, true)
	EventBus.toast_requested.emit("水閘開了，水在漲")
	Sfx.play(&"gate", -2.0)
	Feel.play(&"gate_open")


func is_flooded() -> bool:
	return _water >= 1.0


## 水面的世界座標 y。
func surface_y() -> float:
	return global_position.y + _interior.end.y - _interior.size.y * _water


func _physics_process(delta: float) -> void:
	_time += delta
	if triggered and _water < 1.0:
		_water = minf(1.0, _water + delta / data.rise_time)
		if _water >= 1.0:
			_set_raft(true)
	if _water > 0.0:
		_check_drowning()
		queue_redraw()


func _check_drowning() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.is_dead():
		return
	var local := player.global_position - global_position
	if local.x < _interior.position.x or local.x > _interior.end.x or local.y < _interior.position.y:
		return
	if player.global_position.y - HEAD_HEIGHT > surface_y():
		var info := DamageInfo.create(player.health.current, Combat.Team.ENEMY, DROWN_SOURCE)
		info.ignore_invulnerability = true
		player.health.kill(info)


func _set_raft(on: bool) -> void:
	_raft_shape.set_deferred(&"disabled", not on)


func _draw() -> void:
	if _water <= 0.0:
		return
	var top := _interior.end.y - _interior.size.y * _water
	var body := Rect2(_interior.position.x, top, _interior.size.x, _interior.end.y - top)
	draw_rect(body, Color(0.10, 0.36, 0.52, 0.55))
	draw_rect(Rect2(body.position.x, body.end.y - body.size.y * 0.35, body.size.x, body.size.y * 0.35), Color(0.04, 0.16, 0.30, 0.35))
	# 水面的波紋。
	var points := PackedVector2Array()
	var steps := int(_interior.size.x / 8.0)
	for i in steps + 1:
		var x := _interior.position.x + _interior.size.x * float(i) / float(steps)
		points.append(Vector2(x, top + sin(_time * 3.0 + float(i) * 0.9) * 1.5))
	draw_polyline(points, LightKit.glow(Palette.CYAN, 1.3), 1.5)
	if is_flooded():
		# 漂浮的貨櫃：三個一排，輕輕上下晃。
		var count := 3
		var width := _interior.size.x / float(count)
		for i in count:
			var bob := sin(_time * 1.6 + float(i) * 2.1) * 1.2
			var rect := Rect2(_interior.position.x + float(i) * width + 3.0, top - 2.0 + bob, width - 6.0, 10.0)
			draw_rect(rect, Color(0.36, 0.22, 0.16))
			draw_rect(rect, Palette.TERRAIN_TOP, false, 1.0)
			draw_line(rect.position + Vector2(0, 3.0), rect.position + Vector2(rect.size.x, 3.0), Color(0.55, 0.34, 0.22), 1.0)


# ---------------------------------------------------------------------------
# 世界狀態：任何非乾的狀態（含漲水中）都存成「已漲滿」，死亡後回來水已經滿了。
# ---------------------------------------------------------------------------

func state_key() -> String:
	return "flood@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return triggered


func restore_state(state: Variant) -> void:
	if state == true:
		triggered = true
		_prompt.enabled = false
		_water = 1.0
		_set_raft(true)
		queue_redraw()
