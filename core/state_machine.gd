class_name StateMachine
extends RefCounted
## 輕量狀態機（可重用於敵人、頭目、載具或任何需要狀態切換的物件）。
##
## 用法：
##   _fsm = StateMachine.new()
##   _fsm.add(&"patrol", _patrol_tick, _patrol_enter)
##   _fsm.add(&"attack", _attack_tick)
##   _fsm.start(&"patrol")
##   _fsm.tick(delta)           # 於 _physics_process 呼叫
##
## tick 回呼簽名：func(delta: float) -> void
## enter / exit 回呼簽名：func() -> void
## 狀態內可用 time_in_state 取得已停留時間，用來寫預兆／冷卻非常直覺。

signal state_changed(from: StringName, to: StringName)

var current: StringName = &""
var previous: StringName = &""
var time_in_state := 0.0

var _states: Dictionary = {}  # StringName -> { tick, enter, exit }


func add(state: StringName, tick: Callable, enter := Callable(), exit := Callable()) -> StateMachine:
	if _states.has(state):
		push_warning("[StateMachine] 狀態重複註冊：%s" % state)
	_states[state] = {"tick": tick, "enter": enter, "exit": exit}
	return self


func has(state: StringName) -> bool:
	return _states.has(state)


func start(state: StringName) -> void:
	current = &""
	transition(state)


## 切換狀態。切到不存在的狀態會被忽略並警告，避免 AI 卡死。
func transition(state: StringName) -> void:
	if not _states.has(state):
		push_warning("[StateMachine] 未知狀態：%s" % state)
		return
	if current != &"":
		var exit_cb: Callable = _states[current]["exit"]
		if exit_cb.is_valid():
			exit_cb.call()
	previous = current
	current = state
	time_in_state = 0.0
	var enter_cb: Callable = _states[state]["enter"]
	if enter_cb.is_valid():
		enter_cb.call()
	state_changed.emit(previous, current)


func tick(delta: float) -> void:
	if current == &"":
		return
	time_in_state += delta
	var tick_cb: Callable = _states[current]["tick"]
	if tick_cb.is_valid():
		tick_cb.call(delta)


func is_in(state: StringName) -> bool:
	return current == state
