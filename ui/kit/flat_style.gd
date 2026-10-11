class_name FlatStyle
extends RefCounted
## 扁平終端風格（任務與地圖等資訊頁）：分頁列、分段切換、清單列、小按鈕與按鍵提示。
## 參考 docs：design/18-quest-map-ux/VISUAL_RESEARCH.md。內容不加框，層級靠字級、顏色與留白；
## 選中列整列反白（手把與鍵盤一眼看到焦點），強調色只給目前選項與追蹤目標。
## 樣式物件全部共用（第一次使用時建立），按鈕再多也不會各自配置 StyleBox。

const ROW_TEXT := Color("e8f4f8")
const ROW_INVERTED_BG := Color("d6f6ff")
const ROW_INVERTED_TEXT := Color("06121a")
const ROW_BG := Color(0.05, 0.09, 0.12, 0.82)
const ROW_HOVER := Color(0.08, 0.15, 0.2, 0.92)
const ROW_SELECTED := Color(0.07, 0.2, 0.26, 0.95)
const LINE := Color("2b3946")
const KEY_BG := Color("20333f")
const KEY_EDGE := Color("6c8997")

static var _boxes: Dictionary = {}


## 頁首分頁：未選中是淡色文字，選中是青色文字加底線；焦點時加淡底。
static func tab(button: Button, selected: bool) -> void:
	_plain_button(button)
	button.add_theme_color_override(&"font_color", Palette.CYAN if selected else Palette.UI_MUTED)
	button.add_theme_color_override(&"font_hover_color", Palette.WHITE)
	button.add_theme_color_override(&"font_focus_color", Palette.WHITE if not selected else Palette.CYAN)
	var normal := _box("tab_on" if selected else "tab_off")
	for state in [&"normal", &"pressed", &"disabled"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override(&"hover", _box("tab_hover_on" if selected else "tab_hover"))
	button.add_theme_stylebox_override(&"focus", _box("focus_ring"))


## 分段切換與小按鈕（說明小字）：on 為選中的分段。
static func chip(button: Button, on := false) -> void:
	_plain_button(button)
	UiKit.set_text_role(button, &"caption")
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override(&"font_color", Palette.CYAN if on else Palette.UI_MUTED)
	button.add_theme_color_override(&"font_pressed_color", Palette.CYAN)
	button.add_theme_color_override(&"font_hover_color", Palette.WHITE)
	button.add_theme_color_override(&"font_focus_color", Palette.WHITE)
	button.add_theme_color_override(&"font_hover_pressed_color", Palette.WHITE)
	for state in [&"normal", &"disabled"]:
		button.add_theme_stylebox_override(state, _box("chip_on" if on else "chip"))
	button.add_theme_stylebox_override(&"pressed", _box("chip_on"))
	button.add_theme_stylebox_override(&"hover", _box("chip_hover"))
	button.add_theme_stylebox_override(&"hover_pressed", _box("chip_hover"))
	button.add_theme_stylebox_override(&"focus", _box("chip_focus"))


## 清單列：暗色扁平條；selected 時左側亮條；焦點時整列反白。
static func row(button: Button, selected := false) -> void:
	_plain_button(button)
	# 清單列左側有留白，保留選取三角（和 Leyla In Veil 的 ▶ 指示同一個作用）。
	if button is UiButton:
		(button as UiButton).show_marker = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override(&"font_color", ROW_TEXT)
	button.add_theme_color_override(&"font_hover_color", Palette.WHITE)
	button.add_theme_color_override(&"font_pressed_color", ROW_TEXT)
	button.add_theme_color_override(&"font_focus_color", ROW_INVERTED_TEXT)
	button.add_theme_color_override(&"font_hover_pressed_color", Palette.WHITE)
	var base := _row_box("row_selected" if selected else "row")
	for state in [&"normal", &"pressed", &"disabled"]:
		button.add_theme_stylebox_override(state, base)
	button.add_theme_stylebox_override(&"hover", _row_box("row_hover"))
	button.add_theme_stylebox_override(&"hover_pressed", _row_box("row_hover"))
	button.add_theme_stylebox_override(&"focus", _row_box("row_focus"))


## 清單列下方預留一行說明小字的高度（跟著文字大小設定）；同一字級共用同一組樣式。
static func row_caption_space() -> int:
	return UiKit.caption_size() + 4


static func _row_box(kind: String) -> StyleBox:
	var key := "%s@%d" % [kind, row_caption_space()]
	if not _boxes.has(key):
		var box := (_box(kind) as StyleBoxFlat).duplicate() as StyleBoxFlat
		box.content_margin_bottom = row_caption_space()
		_boxes[key] = box
	return _boxes[key]


## 焦點在清單列時，列裡的小字要跟著反白換成深色，否則淺字落在淺底上看不見。
static func follow_row_focus(button: Button, labels: Array[Label], normal_colors: Array[Color]) -> void:
	var apply := func(focused: bool) -> void:
		for i in labels.size():
			if is_instance_valid(labels[i]):
				labels[i].add_theme_color_override(&"font_color", Color(ROW_INVERTED_TEXT, 0.75) if focused else normal_colors[i])
	button.focus_entered.connect(apply.bind(true))
	button.focus_exited.connect(apply.bind(false))


## 按鍵帽：目前裝置的按鍵名稱放進小框。
static func keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_stylebox_override(&"panel", _box("key"))
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(UiKit.caption(text, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	return cap


## 按鍵提示（底部提示列）：按鍵帽＋動詞按鈕（滑鼠可點，不搶手把焦點）。action 為空時只有動詞。
static func prompt(action: StringName, verb: String, on_pressed: Callable, tooltip: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	if not action.is_empty():
		var cap := keycap(InputBindings.primary_label(action))
		cap.set_meta(&"prompt_action", action)
		box.add_child(cap)
	var button := Button.new()
	_plain_button(button)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tooltip
	button.text = verb
	UiKit.set_text_role(button, &"caption")
	button.add_theme_color_override(&"font_color", Palette.UI_TEXT)
	button.add_theme_color_override(&"font_hover_color", Palette.CYAN)
	button.add_theme_color_override(&"font_pressed_color", Palette.CYAN)
	for state in [&"normal", &"pressed", &"focus", &"disabled", &"hover"]:
		button.add_theme_stylebox_override(state, _box("prompt"))
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	box.add_child(button)
	return box


## 依目前裝置更新某個節點底下所有按鍵提示的按鍵名稱（裝置或改鍵變更時呼叫）。
static func refresh_prompts(root: Node) -> void:
	for cap in root.find_children("*", "PanelContainer", true, false):
		if cap.has_meta(&"prompt_action") and cap.get_child_count() > 0:
			(cap.get_child(0) as Label).text = InputBindings.primary_label(cap.get_meta(&"prompt_action"))


## 一條細分隔線（橫向）。
static func rule(color := LINE) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## 段落小標：「目標　1／3」＋延伸到右側的細線。
static func section(text: String) -> HBoxContainer:
	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override(&"separation", 6)
	row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_box.add_child(UiKit.caption(text))
	var line := rule()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row_box.add_child(line)
	return row_box


static func _plain_button(button: Button) -> void:
	button.custom_minimum_size.x = 0
	if button is UiButton:
		(button as UiButton).show_marker = false
	button.flat = false
	button.focus_mode = Control.FOCUS_ALL


static func _box(key: String) -> StyleBox:
	if _boxes.is_empty():
		_build_boxes()
	return _boxes.get(key, _boxes["row"])


static func _flat(bg: Color, margins: Vector4 = Vector4(6, 2, 6, 2)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.content_margin_left = margins.x
	box.content_margin_top = margins.y
	box.content_margin_right = margins.z
	box.content_margin_bottom = margins.w
	return box


static func _build_boxes() -> void:
	var clear := Color(0, 0, 0, 0)
	var tab_off := _flat(clear, Vector4(4, 1, 4, 3))
	var tab_on := _flat(clear, Vector4(4, 1, 4, 1))
	tab_on.border_width_bottom = 2
	tab_on.border_color = Palette.CYAN
	var tab_hover := _flat(Color(1, 1, 1, 0.04), Vector4(4, 1, 4, 3))
	var tab_hover_on := tab_on.duplicate() as StyleBoxFlat
	tab_hover_on.bg_color = Color(1, 1, 1, 0.04)
	var focus_ring := StyleBoxFlat.new()
	focus_ring.draw_center = false
	focus_ring.set_border_width_all(1)
	focus_ring.border_color = Palette.CYAN
	focus_ring.set_expand_margin_all(1)
	var chip := _flat(Color(0.06, 0.1, 0.14, 0.9), Vector4(5, 1, 5, 1))
	var chip_on := _flat(Color(0.09, 0.21, 0.27, 0.95), Vector4(5, 1, 5, 1))
	var chip_hover := _flat(Color(0.12, 0.26, 0.32, 0.95), Vector4(5, 1, 5, 1))
	# 小按鈕的焦點用亮框：選中的分段（文字是青色）被聚焦時，淺底會讓字看不見。
	var chip_focus := _flat(Color(0.12, 0.26, 0.32, 0.95), Vector4(5, 1, 5, 1))
	chip_focus.set_border_width_all(1)
	chip_focus.border_color = Palette.CYAN
	var row := _flat(ROW_BG, Vector4(14, 2, 6, 12))
	var row_selected := _flat(ROW_SELECTED, Vector4(14, 2, 6, 12))
	row_selected.border_width_left = 2
	row_selected.border_color = Palette.CYAN
	var row_hover := _flat(ROW_HOVER, Vector4(14, 2, 6, 12))
	var row_focus := _flat(ROW_INVERTED_BG, Vector4(14, 2, 6, 12))
	var key := _flat(KEY_BG, Vector4(3, 0, 3, 0))
	key.set_border_width_all(1)
	key.border_color = KEY_EDGE
	key.set_corner_radius_all(2)
	var prompt := _flat(clear, Vector4(0, 0, 2, 0))
	_boxes = {"tab_off": tab_off, "tab_on": tab_on, "tab_hover": tab_hover, "tab_hover_on": tab_hover_on,
		"focus_ring": focus_ring, "chip": chip, "chip_on": chip_on, "chip_hover": chip_hover, "chip_focus": chip_focus,
		"row": row, "row_selected": row_selected, "row_hover": row_hover, "row_focus": row_focus, "key": key, "prompt": prompt}
