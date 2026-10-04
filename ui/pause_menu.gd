class_name PauseMenu
extends CanvasLayer
## 暫停選單：暫停鍵開關。顯示操作說明，避免玩家忘記按鍵。

signal retry_requested
signal menu_requested

## 死亡或過關畫面出現時由關卡關閉，避免同時開兩個選單。
var allowed := true

## 目前章節（Level 建立時指定），暫停畫面右側顯示章節名。
var chapter: StringName = &"chapter_01"

var _root: Control
var _menu_panel: Control
var _info_panel: Control
var _resume_button: Button
var _controls_label: Label
var _status_label: Label
var _settings: SettingsScreen


func _ready() -> void:
	layer = UiLayers.PAUSE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = UiKit.full_rect_root(self)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var menu := UiPanel.new("暫停")
	menu.position = Vector2(36, 48)
	menu.custom_minimum_size = Vector2(190, 0)
	_root.add_child(menu)
	_menu_panel = menu
	_resume_button = UiKit.button("繼續", close, "回到遊戲")
	menu.body.add_child(_resume_button)
	menu.body.add_child(UiKit.button("設定", _open_settings, "音量、按鍵、顯示"))
	menu.body.add_child(UiKit.button("從檢查點重來", _on_retry, "回到最後的檢查點，武器保留"))
	menu.body.add_child(UiKit.button("回主選單", _on_menu, "放棄這次進度"))

	var info := UiPanel.new("目前進度", Palette.NEON_YELLOW)
	info.position = Vector2(250, 48)
	info.custom_minimum_size = Vector2(354, 0)
	_root.add_child(info)
	_info_panel = info
	_status_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	info.body.add_child(_status_label)
	info.body.add_child(UiDivider.new())
	info.body.add_child(UiKit.label("操作", UiKit.FS_BODY, Palette.CYAN))
	_controls_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	info.body.add_child(_controls_label)
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# 設定畫面開啟時由它自己處理輸入（Esc 會先關閉設定）。
	if is_instance_valid(_settings) or Story.is_cinematic_active():
		return
	if event.is_action_pressed(&"pause") or (_root.visible and event.is_action_pressed(&"ui_cancel")):
		if _root.visible:
			close()
		elif allowed:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	Fx.reset_time()
	get_tree().paused = true
	UiKit.set_cursor_visible(true)
	_root.visible = true
	Sfx.play(&"ui_confirm", -8.0, 0.0)
	_refresh_info()
	_resume_button.grab_focus()
	UiMotion.stagger_in([_menu_panel, _info_panel], 0.08, 16.0)


func close() -> void:
	if is_instance_valid(_settings):
		_settings.close()
	if _root.visible:
		Sfx.play(&"ui_cancel", -8.0, 0.0)
	_root.visible = false
	get_tree().paused = false
	UiKit.set_cursor_visible(false)


## 章節、時間、死亡次數、信用點與操作說明。
func _refresh_info() -> void:
	var info := Story.chapter_info(chapter)
	var lines: Array[String] = [
		str(info.get("title", "")),
		"遊玩時間　%s" % UiKit.format_time(GameState.run_time),
		"回溯次數　%d" % GameState.deaths,
		"信用點　　%d" % Progression.credits,
	]
	_status_label.text = "\n".join(lines)
	_controls_label.text = _controls_text()


## 操作提示排成兩欄，項目變多時暫停選單也不會撐滿畫面。
func _controls_text() -> String:
	var items := Hud.controls_hint().split("　", false)
	var lines := PackedStringArray()
	for i in range(0, items.size(), 2):
		var pair := items[i]
		if i + 1 < items.size():
			pair += "　　　" + items[i + 1]
		lines.append(pair)
	return "\n".join(lines)


func _open_settings() -> void:
	_settings = SettingsScreen.new()
	_settings.closed.connect(_on_settings_closed)
	UiOverlay.open(_root, _settings)


func _on_settings_closed() -> void:
	_settings = null
	if _root.visible:
		_refresh_info()


func _on_retry() -> void:
	close()
	retry_requested.emit()


func _on_menu() -> void:
	close()
	menu_requested.emit()
