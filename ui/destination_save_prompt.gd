extends Control
## A refused route remains an explicit, retryable operation. Automatic death or
## chapter handoffs cannot return to a finished world, so they offer retry only.
signal retry_requested
signal cancel_requested

var can_stay := true
var purpose := "area"
var retry_button: Button
var cancel_button: Button
var message: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(Palette.BG_FAR, 0.9)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiPanel.new(_copy("進度尚未保存", "進行状況を保存できませんでした", "Progress could not be saved"), Palette.WARNING)
	panel.custom_minimum_size.x = 420
	center.add_child(panel)
	message = UiKit.label(_body(), UiKit.FS_BODY)
	message.custom_minimum_size.x = 390
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(message)
	panel.body.add_child(UiDivider.new())
	retry_button = UiKit.button(_copy("重試保存", "保存を再試行", "Retry saving"), retry_requested.emit)
	panel.body.add_child(retry_button)
	cancel_button = UiKit.button(_copy("留在目前區域", "現在のエリアに留まる", "Stay in this area"), cancel_requested.emit)
	cancel_button.visible = can_stay
	panel.body.add_child(cancel_button)
	for button: Button in [retry_button, cancel_button]:
		button.custom_minimum_size.y = 32
	for key: StringName in [&"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left", &"focus_neighbor_right", &"focus_next", &"focus_previous"]:
		retry_button.set(key, cancel_button.get_path() if can_stay else retry_button.get_path())
		cancel_button.set(key, retry_button.get_path())
	_focus.call_deferred()

func _focus() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		retry_button.grab_focus()

func _body() -> String:
	match purpose:
		"ending":
			return _copy("本章的完成記錄尚未保存。請重試保存，成功後再進入結算。", "この章の完了記録を保存できませんでした。保存を再試行してください。成功後にリザルトへ進みます。", "This chapter's completion has not been saved. Retry saving to continue to the results.")
		"respawn":
			return _copy("復原進度尚未保存。原存檔仍保留，請重試保存後再復原。", "復元後の進行状況を保存できませんでした。元のセーブデータは保持されています。保存を再試行して復元を続けてください。", "Your revival could not be saved. Your original save is intact. Retry saving to continue.")
		"chapter":
			return _copy("下一章的進度尚未保存。原存檔仍保留，請重試保存後再繼續。", "次の章の進行状況を保存できませんでした。元のセーブデータは保持されています。保存を再試行して先へ進んでください。", "The next chapter could not be saved. Your original save is intact. Retry saving to continue.")
		"retry":
			return _copy("回溯進度尚未保存。目前區域與原存檔都保留，可以重試保存或留在這裡。", "チェックポイントへの復帰を保存できませんでした。現在のエリアと元のセーブデータは保持されています。再試行するか、このエリアに留まれます。", "Your checkpoint return could not be saved. Your current area and original save are intact. Retry, or stay here.")
	return _copy("區域進度尚未保存。目前區域與原存檔都保留，可以重試保存或留在這裡。", "エリアの進行状況を保存できませんでした。現在のエリアと元のセーブデータは保持されています。再試行するか、このエリアに留まれます。", "The area entry could not be saved. Your current area and original save are intact. Retry, or stay here.")

static func _copy(zh: String, ja: String, en: String) -> String:
	return ja if Story.language == "ja" else (en if Story.language == "en" else zh)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if can_stay:
			cancel_requested.emit()
