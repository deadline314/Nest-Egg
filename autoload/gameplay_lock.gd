extends Node
## 過場共用鎖：動畫、對話、轉場與阻擋式章節卡都以 acquire / release 管理。
## 只在第一把鎖保存原狀；最後一把鎖釋放才還原，結束順序不影響結果。
## owner 離開場景樹會自動釋放；正常結束仍應先 release，再發出完成訊號。

signal started

var _locks: Dictionary[int, Dictionary] = {}
var _next_token := 0
var _base_paused := false
var _base_mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_locked() -> bool:
	return not _locks.is_empty()


## mouse_mode = -1 表示不變更游標；其餘值為 Input.MOUSE_MODE_*。
## 無效 owner 回傳 0 並記錄錯誤，不留下無法回收的鎖。
func acquire(owner: Node, mouse_mode := -1) -> int:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion():
		push_error("[GameplayLock] owner 必須位於場景樹中且未等待刪除")
		return 0
	var first := not is_locked()
	if first:
		_base_paused = get_tree().paused
		_base_mouse_mode = Input.mouse_mode
	_next_token += 1
	var token := _next_token
	var cleanup := release.bind(token)
	_locks[token] = {"owner": weakref(owner), "cleanup": cleanup, "mouse_mode": mouse_mode}
	owner.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	maintain_pause()
	_apply_mouse_mode()
	if first:
		started.emit()
	return token


## 可重複釋放；0 或已釋放的 token 不做任何事。
func release(token: int) -> void:
	if not _locks.has(token):
		return
	var entry := _locks[token]
	_locks.erase(token)
	var owner := (entry["owner"] as WeakRef).get_ref() as Node
	var cleanup: Callable = entry["cleanup"]
	if is_instance_valid(owner) and owner.tree_exiting.is_connected(cleanup):
		owner.tree_exiting.disconnect(cleanup)
	if is_locked():
		maintain_pause()
	else:
		# 吞掉過場用的按鍵狀態，避免最後一次點擊／跳過在恢復的影格開槍或跳躍。
		_clear_actions()
		get_tree().paused = _base_paused
	_apply_mouse_mode()


## 換畫面時更新目的畫面的基礎暫停狀態，仍保留正在播放的過場鎖。
func set_base_paused(paused: bool) -> void:
	_base_paused = paused
	get_tree().paused = paused or is_locked()


## 新畫面的游標需求（例如進關卡隱藏、回主選單顯示），不覆蓋演出自己的游標。
func set_base_mouse_mode(mode: Input.MouseMode) -> void:
	_base_mouse_mode = mode
	_apply_mouse_mode()


## 外部畫面切換回呼可能改過暫停；演出繼續前維持鎖定。
func maintain_pause() -> void:
	if is_locked():
		get_tree().paused = true


func _apply_mouse_mode() -> void:
	var mode: int = _base_mouse_mode
	for entry: Dictionary in _locks.values():
		if int(entry["mouse_mode"]) >= 0:
			mode = int(entry["mouse_mode"])
	Input.mouse_mode = mode


func _clear_actions() -> void:
	for entry: Dictionary in InputBindings.ACTIONS:
		Input.action_release(entry["id"])
	for action: StringName in InputBindings.FIXED_ACTIONS:
		Input.action_release(action)
