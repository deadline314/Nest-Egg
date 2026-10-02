class_name PauseMenu
extends CanvasLayer
## 暫停選單：暫停鍵開關。顯示操作說明，避免玩家忘記按鍵。

signal retry_requested
signal menu_requested

## 死亡或過關畫面出現時由關卡關閉，避免同時開兩個選單。
var allowed := true

var _root: Control
var _resume_button: Button
var _controls_label: Label
var _settings: SettingsScreen


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = UiKit.full_rect_root(self)
	var box := UiKit.centered_panel(_root, 380.0)
	box.add_child(UiKit.label("暫停", 18, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER))
	_controls_label = UiKit.label("", 10, Palette.UI_MUTED)
	box.add_child(_controls_label)
	_resume_button = UiKit.button("繼續", close, "回到遊戲")
	box.add_child(_resume_button)
	box.add_child(UiKit.button("設定", _open_settings, "音量與按鍵設定"))
	box.add_child(UiKit.button("從檢查點重來", _on_retry, "回到最後的檢查點，武器保留"))
	box.add_child(UiKit.button("回主選單", _on_menu, "放棄這次進度"))
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
	_controls_label.text = _controls_text()
	_resume_button.grab_focus()


func close() -> void:
	if is_instance_valid(_settings):
		_settings.close()
	_root.visible = false
	get_tree().paused = false
	UiKit.set_cursor_visible(false)


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
	_root.add_child(_settings)


func _on_settings_closed() -> void:
	_settings = null
	if _root.visible:
		_controls_label.text = _controls_text()
		_resume_button.grab_focus()


func _on_retry() -> void:
	close()
	retry_requested.emit()


func _on_menu() -> void:
	close()
	menu_requested.emit()
