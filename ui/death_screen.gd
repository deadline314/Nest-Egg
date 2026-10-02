class_name DeathScreen
extends CanvasLayer
## 失敗畫面：顯示本次解鎖的「敗北圖鑑」卡片與攻略提示，讓每次死亡都有收穫。

signal retry_requested
signal menu_requested

var _card: Dictionary = {}
var _can_continue := true


func setup(card: Dictionary, can_continue: bool) -> void:
	_card = card
	_can_continue = can_continue


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := UiKit.full_rect_root(self)
	var box := UiKit.centered_panel(root, 380.0, 0.5)
	box.add_child(UiKit.label("任務失敗", 18, Palette.DANGER, HORIZONTAL_ALIGNMENT_CENTER))

	var header := "敗北圖鑑 No.%02d" % int(_card.get("number", 0))
	if bool(_card.get("is_new", false)):
		header += "　NEW!"
	box.add_child(UiKit.label(header, 10, Palette.WARNING))
	box.add_child(UiKit.label("「%s」" % str(_card.get("title", "???")), 14, Palette.UI_TEXT))
	var text := UiKit.label(str(_card.get("text", "")), 11, Palette.UI_MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(340, 0)
	box.add_child(text)
	var hint_text := str(_card.get("hint", ""))
	if not hint_text.is_empty():
		var hint := UiKit.label("攻略：" + hint_text, 11, Palette.CYAN)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(340, 0)
		box.add_child(hint)
	if not _can_continue:
		box.add_child(UiKit.label("殘機用盡，將從關卡開頭重新開始。", 11, Palette.DANGER))

	var retry_text := "從檢查點重來" if _can_continue else "重新開始關卡"
	var retry := UiKit.button(retry_text, retry_requested.emit, "立即再挑戰")
	box.add_child(retry)
	box.add_child(UiKit.button("回主選單", menu_requested.emit, "可在主選單查看所有敗北圖鑑"))
	retry.grab_focus.call_deferred()
