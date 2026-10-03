class_name UiTheme
extends RefCounted
## 建立全專案共用的 Theme：按鈕、面板、頁籤、提示框、滑桿、勾選、捲軸。
## 只在 UiKit 第一次要主題時呼叫一次。

const SLIDER_H := 14


static func build(font: Font, base_size: int) -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = base_size

	# 按鈕
	t.set_stylebox(&"normal", &"Button", _button_box(Color(0.05, 0.09, 0.12, 0.92), Palette.CYAN_DIM))
	t.set_stylebox(&"hover", &"Button", _button_box(Palette.UI_PANEL_HI, Palette.CYAN))
	t.set_stylebox(&"pressed", &"Button", _button_box(Palette.UI_PANEL_SEL, Palette.CYAN))
	t.set_stylebox(&"focus", &"Button", _button_box(Palette.UI_PANEL_HI, Palette.CYAN, true))
	var disabled := _button_box(Color(0.04, 0.06, 0.08, 0.8), Palette.UI_LINE_OFF)
	disabled.dashed = true
	t.set_stylebox(&"disabled", &"Button", disabled)
	t.set_color(&"font_color", &"Button", Palette.UI_TEXT)
	t.set_color(&"font_hover_color", &"Button", Palette.CYAN)
	t.set_color(&"font_focus_color", &"Button", Palette.CYAN)
	t.set_color(&"font_pressed_color", &"Button", Palette.WHITE)
	t.set_color(&"font_disabled_color", &"Button", Palette.UI_MUTED)
	t.set_constant(&"h_separation", &"Button", 6)

	# 面板與提示框
	var panel := ChamferBox.make(Palette.UI_PANEL, Palette.CYAN_DIM, 5)
	panel.bracket = Palette.CYAN
	panel.scanlines = 0.1
	panel.margins(14, 10, 14, 10)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	var tip := ChamferBox.make(Color(0.03, 0.05, 0.07, 0.97), Palette.CYAN_DIM, 3)
	tip.margins(8, 4, 8, 4)
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_color(&"font_color", &"TooltipLabel", Palette.UI_TEXT)
	t.set_font_size(&"font_size", &"TooltipLabel", base_size)
	t.set_color(&"font_color", &"Label", Palette.UI_TEXT)

	_tabs(t)
	_sliders(t)
	_toggles(t)
	_scrollbars(t)
	return t


static func _button_box(bg: Color, line: Color, wide_line := false) -> ChamferBox:
	var box := ChamferBox.make(bg, line, 4, 2 if wide_line else 1)
	box.margins(16, 5, 12, 5)
	return box


## 頁籤：只切上面兩角；選取的頁籤下沿開口，與面板相連。
static func tab_box(selected: bool) -> ChamferBox:
	var box := ChamferBox.make(
			Palette.UI_PANEL_SEL if selected else Color(0.04, 0.07, 0.1, 0.9),
			Palette.CYAN if selected else Palette.CYAN_DIM, 4)
	box.corners = ChamferBox.Corner.TOP
	box.open_bottom = selected
	box.margins(12, 4, 12, 4)
	return box


static func _tabs(t: Theme) -> void:
	t.set_stylebox(&"tab_selected", &"TabContainer", tab_box(true))
	t.set_stylebox(&"tab_unselected", &"TabContainer", tab_box(false))
	t.set_stylebox(&"tab_hovered", &"TabContainer", tab_box(true))
	t.set_stylebox(&"tab_focus", &"TabContainer", tab_box(true))
	var content := ChamferBox.make(Color(0.03, 0.06, 0.09, 0.85), Palette.CYAN_DIM, 5)
	content.corners = ChamferBox.Corner.ALL ^ ChamferBox.Corner.TL
	content.margins(12, 10, 12, 10)
	t.set_stylebox(&"panel", &"TabContainer", content)
	t.set_color(&"font_selected_color", &"TabContainer", Palette.CYAN)
	t.set_color(&"font_unselected_color", &"TabContainer", Palette.UI_MUTED)
	t.set_color(&"font_hovered_color", &"TabContainer", Palette.UI_TEXT)


static func _sliders(t: Theme) -> void:
	var track := _plain(Color(Palette.CYAN_DIM, 0.35), 3)
	var fill := _plain(Palette.CYAN, 3)
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	var grabber := _diamond(Palette.CYAN, 9)
	t.set_icon(&"grabber", &"HSlider", grabber)
	t.set_icon(&"grabber_highlight", &"HSlider", _diamond(Palette.WHITE, 9))
	t.set_icon(&"grabber_disabled", &"HSlider", _diamond(Palette.UI_LINE_OFF, 9))
	t.set_constant(&"center_grabber", &"HSlider", 1)


static func _toggles(t: Theme) -> void:
	for kind: StringName in [&"CheckButton", &"CheckBox"]:
		t.set_icon(&"checked", kind, _check_icon(true))
		t.set_icon(&"unchecked", kind, _check_icon(false))
		t.set_icon(&"checked_disabled", kind, _check_icon(true, Palette.UI_LINE_OFF))
		t.set_icon(&"unchecked_disabled", kind, _check_icon(false, Palette.UI_LINE_OFF))
		t.set_color(&"font_color", kind, Palette.UI_TEXT)
		t.set_color(&"font_hover_color", kind, Palette.CYAN)
		t.set_color(&"font_focus_color", kind, Palette.CYAN)
		t.set_color(&"font_pressed_color", kind, Palette.UI_TEXT)
		t.set_color(&"font_hover_pressed_color", kind, Palette.CYAN)
		var empty := StyleBoxEmpty.new()
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			t.set_stylebox(state, kind, empty)
		t.set_stylebox(&"focus", kind, _plain(Color(Palette.CYAN, 0.12), 0))
		t.set_constant(&"h_separation", kind, 8)
	# 下拉選單沿用按鈕外觀。
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		t.set_stylebox(state, &"OptionButton", t.get_stylebox(state, &"Button"))
	t.set_color(&"font_color", &"OptionButton", Palette.UI_TEXT)
	t.set_color(&"font_hover_color", &"OptionButton", Palette.CYAN)
	t.set_color(&"font_focus_color", &"OptionButton", Palette.CYAN)
	var popup := ChamferBox.make(Palette.UI_PANEL_DEEP, Palette.CYAN_DIM, 3)
	popup.margins(4, 4, 4, 4)
	t.set_stylebox(&"panel", &"PopupMenu", popup)
	t.set_stylebox(&"hover", &"PopupMenu", _plain(Palette.UI_PANEL_SEL, 0))
	t.set_color(&"font_color", &"PopupMenu", Palette.UI_TEXT)
	t.set_color(&"font_hover_color", &"PopupMenu", Palette.CYAN)


static func _scrollbars(t: Theme) -> void:
	for kind: StringName in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", kind, _plain(Color(Palette.CYAN_DIM, 0.15), 0))
		t.set_stylebox(&"scroll_focus", kind, _plain(Color(Palette.CYAN_DIM, 0.15), 0))
		t.set_stylebox(&"grabber", kind, _plain(Palette.CYAN_DIM, 0))
		t.set_stylebox(&"grabber_highlight", kind, _plain(Palette.CYAN, 0))
		t.set_stylebox(&"grabber_pressed", kind, _plain(Palette.WHITE, 0))


static func _plain(color: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	box.content_margin_left = margin
	box.content_margin_right = margin
	return box


## 像素菱形圖示（滑桿把手）。
static func _diamond(color: Color, px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := float(px - 1) * 0.5
	for y in px:
		for x in px:
			if absf(float(x) - c) + absf(float(y) - c) <= c:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


## 方形勾選框：邊框 + 勾選時內部填滿。
static func _check_icon(checked: bool, color: Color = Palette.CYAN) -> ImageTexture:
	var px := 11
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for i in px:
		for edge in [0, px - 1]:
			img.set_pixel(i, edge, color)
			img.set_pixel(edge, i, color)
	if checked:
		for y in range(3, px - 3):
			for x in range(3, px - 3):
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
