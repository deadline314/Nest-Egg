class_name RunOverwritePrompt
extends Control
## 使用遊戲共用實心面板；取消先取得焦點，返回會恢復原出發按鈕。

signal confirmed
signal canceled
var cancel_button: Button


func _ready() -> void:
	UiKit.fill_parent(self)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.96)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-205, -82)
	panel.size = Vector2(410, 164)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	panel.add_child(content)
	content.add_child(UiKit.label("開始新遊戲", UiKit.FS_TITLE, Palette.CYAN))
	var message := UiKit.label("將覆寫此存檔槽的整輪進度。取消會保留原存檔。", UiKit.FS_BODY)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	content.add_child(row)
	cancel_button = UiKit.button("保留原進度", _cancel, "返回難度選擇，保留原存檔")
	cancel_button.custom_minimum_size = Vector2(170, 32)
	row.add_child(cancel_button)
	var overwrite := UiKit.button("覆寫並出發", _confirm, "清除這一輪，開始新的遊戲")
	overwrite.custom_minimum_size = Vector2(170, 32)
	row.add_child(overwrite)
	cancel_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()


func _cancel() -> void:
	canceled.emit()
	queue_free()


func _confirm() -> void:
	confirmed.emit()
	queue_free()
