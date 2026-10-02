class_name Lift
extends AnimatableBody2D
## 升降梯：單向平台，在兩端停留、上下往返；玩家站上去會被帶著走，也能按「下＋跳」落下。
## 斷電時停擺；MechanismData.channel 不為空時，只在該頻道的開關啟動後運作。
## 原點在底端平台的頂面中點。

const PLATFORM_THICKNESS := 6.0

enum Phase { WAIT_BOTTOM, UP, WAIT_TOP, DOWN }

var data: MechanismData
var cell := Vector2i.ZERO

var _width := 32.0
var _travel := 96.0
var _phase := Phase.WAIT_BOTTOM
var _wait_left := 0.0
var _start_y := 0.0
var _enabled := true
var _powered := true
var _time := 0.0
var _rails: _Rails
var _prompt: WorldPrompt


func configure(p_data: MechanismData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	_width = data.size_tiles.x * tile_size
	_travel = data.travel_tiles * tile_size


func _ready() -> void:
	if data == null:
		push_error("[Lift] 未指定 MechanismData，已移除。")
		queue_free()
		return
	LightKit.mark_emissive(self)
	collision_layer = Layers.PLATFORM
	collision_mask = 0
	sync_to_physics = true
	_start_y = position.y
	_enabled = data.channel == &""
	_wait_left = data.wait_time
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_width, PLATFORM_THICKNESS)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.one_way_collision = true
	shape_node.position = Vector2(0, PLATFORM_THICKNESS * 0.5)
	add_child(shape_node)
	if not data.hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = data.hint
		_prompt.radius = 70.0
		_prompt.offset = Vector2(0, -34.0)
		add_child(_prompt)
	# 導軌固定在原地（不跟著平台移動），畫在平台後方。
	_rails = _Rails.new()
	_rails.travel = _travel
	_rails.width = _width
	_rails.position = position
	_rails.z_index = -1
	get_parent().add_child.call_deferred(_rails)
	tree_exiting.connect(_free_rails)
	EventBus.mechanism_toggled.connect(_on_channel_toggled)
	add_to_group(WorldState.GROUP)


func _free_rails() -> void:
	if is_instance_valid(_rails):
		_rails.queue_free()


func _physics_process(delta: float) -> void:
	_time += delta
	var powered := PowerGrid.is_powered(self)
	if powered != _powered:
		_powered = powered
		queue_redraw()
	if not _enabled or not _powered:
		return
	match _phase:
		Phase.WAIT_BOTTOM, Phase.WAIT_TOP:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_phase = Phase.UP if _phase == Phase.WAIT_BOTTOM else Phase.DOWN
		Phase.UP:
			position.y = maxf(_start_y - _travel, position.y - data.speed * delta)
			if position.y <= _start_y - _travel + 0.01:
				_arrive(Phase.WAIT_TOP)
		Phase.DOWN:
			position.y = minf(_start_y, position.y + data.speed * delta)
			if position.y >= _start_y - 0.01:
				_arrive(Phase.WAIT_BOTTOM)


func _arrive(next: Phase) -> void:
	_phase = next
	_wait_left = data.wait_time


func _on_channel_toggled(channel: StringName, active: bool) -> void:
	if channel == data.channel and data.channel != &"":
		_enabled = active
		queue_redraw()


func state_key() -> String:
	return "lift@%d,%d" % [cell.x, cell.y]


## 只存「頻道是否啟動」；位置重生後回到底端。
func capture_state() -> Variant:
	return _enabled


func restore_state(state: Variant) -> void:
	_enabled = data.channel == &"" or state == true


func _draw() -> void:
	var rect := Rect2(-_width * 0.5, 0, _width, PLATFORM_THICKNESS)
	draw_rect(rect, Palette.PLATFORM)
	draw_rect(rect, Palette.TERRAIN_TOP, false, 1.0)
	var running := _enabled and _powered
	var color := data.color if running else data.color.darkened(0.7)
	for x in [-_width * 0.5 + 3.0, _width * 0.5 - 3.0]:
		draw_circle(Vector2(x, 3), 1.4, LightKit.glow(color, 1.8 if running else 0.5))


## 導軌：平台行程上的兩條細線與端點燈。
class _Rails:
	extends Node2D

	var travel := 96.0
	var width := 32.0

	func _ready() -> void:
		LightKit.mark_emissive(self)

	func _draw() -> void:
		for x in [-width * 0.5 + 2.0, width * 0.5 - 2.0]:
			draw_line(Vector2(x, 0), Vector2(x, -travel), Color(Palette.TERRAIN_EDGE, 0.9), 1.0)
		draw_rect(Rect2(-width * 0.5, -travel - 2.0, width, 2.0), Palette.TERRAIN_TOP)
		draw_rect(Rect2(-width * 0.5, 4.0, width, 2.0), Palette.TERRAIN_EDGE)
