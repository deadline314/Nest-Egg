@abstract
class_name MechanismSwitch
extends Area2D
## 互動式開關基底：玩家站在範圍內按互動鍵切換。子類別決定切換後發生什麼（頻道或電力）。
## 狀態（開／關）存進檢查點。原點在底邊中點。

const TOGGLE_COOLDOWN := 0.35
const REACH := Vector2(28, 36)
const PROMPT_RADIUS := 60.0

var data: MechanismData
var cell := Vector2i.ZERO
## 目前是否為「啟動」狀態（頻道開關：打開；電力開關：已斷電）。
var active := false

var _player_in_range := false
var _cooldown := 0.0
var _time := 0.0
var _prompt: WorldPrompt


func configure(p_data: MechanismData, p_cell: Vector2i) -> void:
	data = p_data
	cell = p_cell


func _ready() -> void:
	if data == null:
		push_error("[MechanismSwitch] 未指定 MechanismData，已移除。")
		queue_free()
		return
	LightKit.mark_emissive(self)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = REACH
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -REACH.y * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not data.hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = data.hint
		_prompt.radius = PROMPT_RADIUS
		_prompt.reach_check = func() -> bool: return _player_in_range
		_prompt.offset = Vector2(0, -REACH.y - 8.0)
		add_child(_prompt)
	add_to_group(WorldState.GROUP)


func _physics_process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if _player_in_range and _cooldown <= 0.0 and Input.is_action_just_pressed(&"interact"):
		toggle()
	queue_redraw()


func toggle() -> void:
	_cooldown = TOGGLE_COOLDOWN
	active = not active
	_apply(active, false)
	Fx.burst(global_position + Vector2(0, -REACH.y * 0.6), data.color, 8, 90.0, 0.3)
	Sfx.play(&"switch", -3.0)


## 切換後的效果。silent = true 時是還原檢查點，不要播效果或發訊號。
@abstract func _apply(is_active: bool, silent: bool) -> void


func _on_body_entered(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_player_in_range = false


func state_key() -> String:
	return "switch@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return active


func restore_state(state: Variant) -> void:
	var wanted: bool = state == true
	if wanted != active:
		active = wanted
		_apply(active, true)
		queue_redraw()


## 開關外觀：底座、拉桿與狀態燈。
func _draw() -> void:
	draw_rect(Rect2(-7, -14, 14, 14), Palette.TERRAIN_EDGE)
	draw_rect(Rect2(-7, -14, 14, 14), Palette.TERRAIN_TOP, false, 1.0)
	var lever_tip := Vector2(-4, -26) if active else Vector2(4, -26)
	draw_line(Vector2(0, -12), lever_tip, Palette.TERRAIN_TOP, 2.0)
	draw_circle(lever_tip, 2.0, data.color)
	var blink := 1.4 + 0.5 * sin(_time * 4.0)
	draw_circle(Vector2(0, -7), 1.6, LightKit.glow(data.color, blink if active else 0.6))
