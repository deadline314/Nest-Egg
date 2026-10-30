extends Control
## Persistent recovery affordance; pause ownership remains with the Main coordinator.
signal retry_requested
signal cancel_requested
var presentation := "radio"
var allow_cancel := true
var retry_button: Button
var cancel_button: Button
var _message: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	# An automatic stage may finish before the underlying world has rendered.
	# Its recovery stays visually stable instead of exposing that stale frame.
	shade.color = Color(Palette.BG_FAR, 1.0 if presentation in ["event", "pickup"] else 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiPanel.new(copy("進度保存", "進行状況の保存", "Saving progress"), Palette.WARNING)
	panel.custom_minimum_size.x = 420
	center.add_child(panel)
	_message = UiKit.label("", UiKit.FS_BODY)
	_message.custom_minimum_size.x = 390
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_message)
	panel.body.add_child(UiDivider.new())
	retry_button = UiKit.button(copy("重試保存", "保存を再試行", "Retry saving"), retry_requested.emit)
	panel.body.add_child(retry_button)
	cancel_button = UiKit.button(copy("取消本次通訊", "今回の通信を取り消す", "Cancel this radio"), cancel_requested.emit)
	panel.body.add_child(cancel_button)
	for button: Button in [retry_button, cancel_button]:
		button.custom_minimum_size.y = 32
	for property: StringName in [&"focus_neighbor_top", &"focus_neighbor_left", &"focus_previous"]:
		retry_button.set(property, cancel_button.get_path())
		cancel_button.set(property, retry_button.get_path())
	for property: StringName in [&"focus_neighbor_bottom", &"focus_neighbor_right", &"focus_next"]:
		retry_button.set(property, cancel_button.get_path())
		cancel_button.set(property, retry_button.get_path())
	set_recovery(false)
	_focus_retry.call_deferred()


func _focus_retry() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		retry_button.grab_focus()


func set_recovery(recovery: bool) -> void:
	var cancel_had_focus := cancel_button.has_focus()
	if presentation == "pickup" and not recovery:
		_message.text = copy("這件物品尚未保存，仍留在原處。重試保存，或放回後離開再取。", "このアイテムは未保存で、元の場所に残っています。保存を再試行するか、戻して離れてから取り直してください。", "This item has not been saved and remains where it was. Retry saving, or leave it and return later.")
	elif presentation == "event" and not recovery:
		_message.text = copy("這段事件尚未保存，世界保持暫停。請重試保存後再繼續。", "このイベントは未保存です。世界は一時停止中です。保存を再試行して続けてください。", "This event has not been saved. The world remains paused. Retry saving to continue.")
	else:
		_message.text = copy("進度已保存。請重新載入已保存的進度後繼續。", "進行状況は保存済みです。保存済みの進行状況を読み込んで再開してください。", "Progress was saved. Reload the saved progress to continue.") if recovery else copy("這次通訊尚未保存，世界保持暫停。可以重試；取消後不會記為讀完，之後可以再聽。", "今回の通信は未保存です。世界は一時停止中です。再試行できます。取り消すと読了にはならず、後で再び聞けます。", "This radio has not been saved. The world remains paused. Retry, or cancel without marking it read; you can hear it again later.")
	retry_button.text = copy("重新載入已保存進度", "保存済みの進行状況を読み込む", "Reload saved progress") if recovery else copy("重試保存", "保存を再試行", "Retry saving")
	cancel_button.visible = not recovery and allow_cancel
	if presentation == "pickup":
		cancel_button.text = copy("放回", "戻す", "Leave item")
	if not cancel_button.visible:
		for property: StringName in [&"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left", &"focus_neighbor_right", &"focus_next", &"focus_previous"]:
			retry_button.set(property, retry_button.get_path())
	else:
		for property: StringName in [&"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left", &"focus_neighbor_right", &"focus_next", &"focus_previous"]:
			retry_button.set(property, cancel_button.get_path())
			cancel_button.set(property, retry_button.get_path())
	# Hiding the focused action releases GUI focus; keep the remaining safe
	# action reachable without requiring a mouse or stealing another modal.
	if cancel_had_focus and not cancel_button.visible:
		retry_button.grab_focus()

static func copy(zh: String, ja: String, en: String) -> String:
	return ja if Story.language == "ja" else (en if Story.language == "en" else zh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if cancel_button.visible:
			cancel_requested.emit()


func set_original_recovery() -> void:
	set_recovery(false)
	if presentation == "pickup":
		_message.text = copy("這件物品尚未保存，原進度保留在備份。請載入原進度後再取。", "このアイテムは未保存です。元の進行状況はバックアップに残っています。元の進行状況を読み込んでから取り直してください。", "This item was not saved. Your original progress remains in the backup. Reload it before collecting the item again.")
	elif presentation == "event":
		_message.text = copy("這段事件尚未保存，原進度保留在備份。請載入原進度後再試。", "このイベントは未保存です。元の進行状況はバックアップに残っています。元の進行状況を読み込んで再試行してください。", "This event was not saved. Your original progress remains in the backup. Reload it to try again.")
	else:
		_message.text = copy("這次通訊尚未保存，原進度保留在備份。請載入原進度後再試；取消不會記為讀完。", "今回の通信は未保存です。元の進行状況はバックアップに残っています。元の進行状況を読み込んでください。取り消しても読了にはなりません。", "This radio was not saved. Your original progress remains in the backup. Reload it to try again, or cancel without marking the radio read.")
	retry_button.text = copy("載入原進度", "元の進行状況を読み込む", "Reload original progress")
