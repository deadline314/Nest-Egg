class_name StageInputLock
extends RefCounted
## 舞台的輸入鎖：實驗室裡點按鈕、在搜尋框打字都會被遊戲當成操作（例如滑鼠左鍵＝射擊），所以預設把遊戲動作的實體按鍵拿掉，
## 只留程式模擬的按鍵；要自己操作玩家時才還原（lock／unlock）。離開實驗室一定要 unlock，InputMap 才會回到原本的按鍵設定。

var _saved: Dictionary = {}


func is_locked() -> bool:
	return not _saved.is_empty()


func lock() -> void:
	if is_locked():
		return
	var actions: Array[StringName] = []
	for entry in InputBindings.ACTIONS:
		actions.append(entry["id"])
	for action: StringName in InputBindings.FIXED_ACTIONS.keys():
		actions.append(action)
	for action in actions:
		if InputMap.has_action(action) and not _saved.has(action):
			_saved[action] = InputMap.action_get_events(action)
			InputMap.action_erase_events(action)


func unlock() -> void:
	for action: StringName in _saved.keys():
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)
	_saved.clear()
