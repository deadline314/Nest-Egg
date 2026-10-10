class_name UiCard
extends Button
## 可選取的卡片：外框與選取效果來自主題（與按鈕相同），內容由呼叫端加進 content。
## toggle_mode 開啟時可作為單選卡片（難度選擇、圖鑑）。

const PADDING := Vector2(14.0, 8.0)

var content: VBoxContainer
var _base_min_size: Vector2


func _init(min_size := Vector2(120, 60)) -> void:
	_base_min_size = min_size
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
	content.minimum_size_changed.connect(_fit_content_height)
	focus_entered.connect(Sfx.play.bind(&"ui_move", -14.0, 0.0))
	pressed.connect(Sfx.play.bind(&"ui_confirm", -6.0, 0.0))


## 文字放大或內容變多時卡片跟著長高，不裁掉內容；寬度維持版面設定，避免撐破格狀排列。
func _fit_content_height() -> void:
	var need := content.get_combined_minimum_size().y + PADDING.y * 2.0
	custom_minimum_size = Vector2(_base_min_size.x, maxf(_base_min_size.y, need))


## 方便加文字列：回傳加好的 Label。
func add_text(text: String, size := UiKit.FS_BODY, color := Palette.UI_TEXT, wrap := false) -> Label:
	var l := UiKit.label(text, size, color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l
