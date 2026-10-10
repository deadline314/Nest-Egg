class_name MeleeCommandInput
extends Node
## 僅保存一筆短近戰命令。自己在局部 hitstop 仍接收事件，期限不隨父節點凍結延長。

var player: Player
var _deadline_ms := 0
var _held_actions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not accepts_input():
		return
	for action: StringName in [&"melee", &"shoot"]:
		if action == &"shoot" and not player.holds_melee_weapon():
			continue
		if event.is_action_released(action):
			_held_actions[action] = false
		if event.is_action_pressed(action):
			_held_actions[action] = true
			queue_command()


func accepts_input() -> bool:
	return is_instance_valid(player) and player.state == Player.State.NORMAL and not player.is_blocking and not GameplayLock.is_locked() and not get_tree().paused


## action_press 的輪詢路徑；held latch 避免同一邊緣跨補步重複入列。
func poll(action: StringName) -> void:
	var pressed := Input.is_action_pressed(action)
	var was_pressed: bool = _held_actions.get(action, false)
	_held_actions[action] = pressed
	if pressed and not was_pressed:
		queue_command()


func queue_command() -> void:
	if accepts_input():
		_deadline_ms = Time.get_ticks_msec() + int(MeleeData.buffer_time() * 1000.0)


func remaining() -> float:
	return maxf(0.0, (_deadline_ms - Time.get_ticks_msec()) / 1000.0)


func consume() -> void:
	_deadline_ms = 0


func clear() -> void:
	consume()
