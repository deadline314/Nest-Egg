extends Control
## 持續顯示的斷線提示。暫停由 InputBindings 擁有；本面板只呈現及請求恢復。

signal resume_requested
var resume_button: Button
var _legend: Label
var _title: Label
var _message: Label
var _controller_available := false


func _ready() -> void:
	# 蓋住遊戲的畫面：疊在遊戲上的演出（地點標示）看到它就藏起來（UiLayers.gameplay_covered）。
	add_to_group(UiLayers.COVER_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(Palette.BG_FAR, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiPanel.new(copy("遊戲已暫停", "ゲームは一時停止中です", "Game paused"), Palette.WARNING)
	panel.custom_minimum_size.x = 380
	center.add_child(panel)
	_title = UiKit.with_role_font(UiKit.label(copy("手把已斷線", "接続が切れました", "Controller disconnected"), UiKit.FS_TITLE, Palette.UI_TEXT), &"title") as Label
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_title)
	_message = UiKit.label(copy("重新接上手把，或改用鍵盤與滑鼠。", "コントローラーを再接続するか、キーボードとマウスを使ってください。", "Reconnect your controller, or use keyboard and mouse."), UiKit.FS_BODY)
	_message.custom_minimum_size.x = 352
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_message)
	panel.body.add_child(UiDivider.new())
	resume_button = UiKit.button(copy("繼續遊戲", "ゲームを再開", "Continue game"), resume_requested.emit)
	resume_button.custom_minimum_size.y = 32
	# 單一操作的焦點固定留在面板內，避免方向鍵落到背景 HUD。
	panel.body.add_child(resume_button)
	for direction in [&"focus_neighbor_left", &"focus_neighbor_right", &"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_next", &"focus_previous"]:
		resume_button.set(direction, resume_button.get_path())
	_legend = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_legend)
	InputBindings.bindings_changed.connect(_refresh_legend)
	InputBindings.device_changed.connect(_on_device_changed)
	_refresh_legend()
	_focus_resume.call_deferred()


func _focus_resume() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		resume_button.grab_focus()


func set_connected(connected: bool) -> void:
	_controller_available = connected
	_title.text = copy("手把可用", "コントローラーを使えます", "Controller available") if connected else copy("手把已斷線", "接続が切れました", "Controller disconnected")
	_message.visible = not connected
	_refresh_legend()


func _refresh_legend() -> void:
	var keyboard := InputBindings.code_label(InputBindings.UI_ACTIONS[&"ui_accept"][0])
	if _controller_available:
		var pad := InputBindings.joy_label(&"ui_accept")
		_legend.text = copy("%s 或 %s 繼續", "%s または %s で再開", "%s or %s to continue") % [pad, keyboard]
	else:
		_legend.text = copy("%s 確認後繼續", "%s で再開", "%s to continue") % keyboard


func _on_device_changed(_gamepad: bool, _device: int) -> void:
	_refresh_legend()


static func copy(zh: String, ja: String, en: String) -> String:
	return ja if Story.language == "ja" else (en if Story.language == "en" else zh)
