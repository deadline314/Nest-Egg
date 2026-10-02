class_name Gate
extends StaticBody2D
## 閘門：擋路。同頻道的開關啟動時打開（滑進天花板），關閉時放下。原點在底邊中點。

const SLIDE_SPEED := 3.0

var data: MechanismData
var cell := Vector2i.ZERO
var is_open := false

var _size := Vector2(16, 64)
## 0 = 關閉、1 = 完全打開（動畫用）。
var _openness := 0.0
var _shape_node: CollisionShape2D
var _prompt: WorldPrompt
var _time := 0.0


func configure(p_data: MechanismData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	_size = Vector2(data.size_tiles) * tile_size


func _ready() -> void:
	if data == null:
		push_error("[Gate] 未指定 MechanismData，已移除。")
		queue_free()
		return
	LightKit.mark_emissive(self)
	collision_layer = Layers.WORLD
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = _size
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = shape
	_shape_node.position = Vector2(0, -_size.y * 0.5)
	add_child(_shape_node)
	var occluder := LightOccluder2D.new()
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(-_size.x * 0.5, -_size.y), Vector2(_size.x * 0.5, -_size.y), Vector2(_size.x * 0.5, 0), Vector2(-_size.x * 0.5, 0)])
	occluder.occluder = polygon
	add_child(occluder)
	if not data.hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = data.hint
		_prompt.radius = 64.0
		_prompt.offset = Vector2(0, -_size.y - 10.0)
		add_child(_prompt)
	EventBus.mechanism_toggled.connect(_on_channel_toggled)
	add_to_group(WorldState.GROUP)


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if is_open else 0.0
	if not is_equal_approx(_openness, target) or not is_open:
		_openness = move_toward(_openness, target, SLIDE_SPEED * delta)
		queue_redraw()


func _on_channel_toggled(channel: StringName, active: bool) -> void:
	if channel == data.channel:
		_set_open(active, false)


func _set_open(open: bool, silent: bool) -> void:
	if open == is_open:
		return
	is_open = open
	_shape_node.set_deferred(&"disabled", open)
	if silent:
		_openness = 1.0 if open else 0.0
		queue_redraw()
	else:
		Sfx.play(&"gate", -3.0)
		Fx.shake(1.5, 0.2)


func state_key() -> String:
	return "gate@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return is_open


func restore_state(state: Variant) -> void:
	_set_open(state == true, true)


func _draw() -> void:
	# 閘板往上收：打開時只剩頂端一小段。
	var visible_height := lerpf(_size.y, 6.0, _openness)
	var rect := Rect2(Vector2(-_size.x * 0.5, -_size.y), Vector2(_size.x, visible_height))
	draw_rect(rect, Palette.TERRAIN_FILL)
	var y := rect.position.y + 4.0
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y + 6.0), Palette.TERRAIN_EDGE, 2.0)
		y += 12.0
	draw_rect(rect, Palette.TERRAIN_TOP, false, 1.0)
	# 閘板中央的狀態燈：關閉時發紅（頻道顏色），打開時熄滅。
	var closed := 1.0 - _openness
	if closed > 0.05:
		var glow := LightKit.glow(data.color, (1.2 + 0.4 * sin(_time * 3.0)) * closed)
		draw_line(Vector2(0, rect.position.y + 4), Vector2(0, rect.end.y - 4), glow, 2.0)
