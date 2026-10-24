extends UiPanel
## Read-only text inside the paused inventory; only the text region scrolls.
signal dismissed

var _heading: Label
var _text: Label
var _scroll: ScrollContainer
var _back: Button
var _legend: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# HDR text beneath a reading pane must not bleed through its body.
	var panel := get_theme_stylebox(&"panel").duplicate() as ChamferBox
	panel.fill = Color(panel.fill, 1.0)
	add_theme_stylebox_override(&"panel", panel)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_heading = UiKit.heading("")
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_heading)
	body.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(_scroll)
	_text = UiKit.label("", UiKit.FS_BODY)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_text)
	_legend = UiKit.label("", 9, Palette.UI_MUTED)
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_legend)
	_back = UiKit.button("", func() -> void: dismissed.emit())
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(_back)
	InputBindings.bindings_changed.connect(_refresh_copy)
	_refresh_copy()
	hide()


func show_document(title: String, text: String, accent: Color) -> void:
	_heading.text = title
	_heading.add_theme_color_override(&"font_color", accent)
	_text.text = text
	_scroll.scroll_vertical = 0
	_refresh_copy()
	show()
	_back.grab_focus()


func scroll(direction: int) -> void:
	if direction != 0:
		var line := _text.get_theme_font("font").get_height(_text.get_theme_font_size("font"))
		_scroll.scroll_vertical += int(line * 3.0) * direction


func _refresh_copy() -> void:
	_back.text = _copy("返回物品", "アイテムへ戻る", "Back to items")
	_legend.text = InputBindings.format(_copy("↑↓／滾輪 捲動　{ui_cancel} 返回", "↑↓／ホイール スクロール　{ui_cancel} 戻る", "↑↓ / wheel Scroll　{ui_cancel} Back"))


static func _copy(zh: String, ja: String, en: String) -> String:
	return ja if Story.language == "ja" else (en if Story.language == "en" else zh)
