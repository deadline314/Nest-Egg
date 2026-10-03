class_name UiCard
extends Button
## 可選取的卡片：外框與選取效果來自主題（與按鈕相同），內容由呼叫端加進 content。
## toggle_mode 開啟時可作為單選卡片（難度選擇、圖鑑）。

const PADDING := Vector2(14.0, 8.0)

var content: VBoxContainer


func _init(min_size := Vector2(120, 60)) -> void:
	custom_minimum_size = min_size
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", 3)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = PADDING.x
	content.offset_right = -PADDING.x
	content.offset_top = PADDING.y
	content.offset_bottom = -PADDING.y
	add_child(content)
	focus_entered.connect(Sfx.play.bind(&"ui_move", -14.0, 0.0))
	pressed.connect(Sfx.play.bind(&"ui_confirm", -6.0, 0.0))


## 方便加文字列：回傳加好的 Label。
func add_text(text: String, size := UiKit.FS_BODY, color := Palette.UI_TEXT, wrap := false) -> Label:
	var l := UiKit.label(text, size, color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	content.add_child(l)
	return l
