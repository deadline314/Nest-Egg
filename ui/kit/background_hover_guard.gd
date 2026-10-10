class_name BackgroundHoverGuard
extends Node
## 背景介面的滑鼠說明守門：暫停頁、人物交談或通訊出現時，收起並停用目標根節點底下的 Hover 說明，
## 連同還在等待出現的說明一起取消；閱讀與選單結束後恢復。不改任何子節點的說明文字、滑鼠設定或可見規則。
## 用法：`root.add_child(BackgroundHoverGuard.new(root))`。守門節點跟著主人暫停，暫停邊緣由通知即時處理，
## 通訊（不暫停世界）由每影格一次的布林比較處理，不配置任何物件。

## 目前是否擋住背景說明（測試與除錯用的唯讀狀態）。
var blocked := false

var _target: Control


func _init(target: Control = null) -> void:
	_target = target
	name = &"BackgroundHoverGuard"


func _ready() -> void:
	if _target == null:
		_target = get_parent() as Control
	if _target == null:
		push_error("[BackgroundHoverGuard] %s：沒有指定要守護的 Control，守門停用" % get_path())
		set_process(false)
		return
	_sync()


func _notification(what: int) -> void:
	# 暫停後主人不再跑 _process，必須在暫停邊緣當下處理，否則已排程的說明會在選單上冒出來。
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_sync()


func _process(_delta: float) -> void:
	_sync()


## 重要閱讀與選單期間背景說明一律收起：所有選單與正式閱讀都會暫停世界，通訊則以面板可見為準。
static func modal_reading_active(tree: SceneTree) -> bool:
	return tree != null and (tree.paused or DialogueLayer.radio_visible())


func _sync() -> void:
	if not is_instance_valid(_target) or not is_inside_tree():
		return
	var now_blocked := modal_reading_active(get_tree())
	if now_blocked == blocked:
		return
	blocked = now_blocked
	if blocked:
		_retire_hover()
		_target.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	else:
		_target.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED


## 引擎在「被 Hover 的控制項變成不可見」時才同時取消已顯示的說明與等待中的計時（Viewport::_gui_hide_control）。
## 在同一個呼叫內隱藏再還原，不會畫出缺一塊的影格；只動目標底下真正被 Hover 的那一個控制項。
func _retire_hover() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var hovered := viewport.gui_get_hovered_control()
	if not is_instance_valid(hovered) or not hovered.visible:
		return
	if hovered != _target and not _target.is_ancestor_of(hovered):
		return
	hovered.hide()
	hovered.show()
