extends PanelContainer
## Compact presentation of an authored choice. The player still owns all results and cancellation.

const INSET := 14.0
const GAP := 7
const MIN_WIDTH := 256.0
const MAX_WIDTH := 300.0
const PANEL_PADDING := Vector2(24, 20)

static var _row_styles: Dictionary[StringName, StyleBox] = {}

var rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _footer := VBoxContainer.new()
var _note := UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
var _back_hint := UiKit.caption("", Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
var _notes: Dictionary[Button, String] = {}
var _safe_rect := Rect2()
var _note_font: Font
var _note_font_size := 0
var _note_width := 0.0


func _init(prompt: String, language: String) -> void:
	var plate := ChamferBox.make(Color("0d1820"), Color("36505f"), 5)
	plate.margins(PANEL_PADDING.x * 0.5, PANEL_PADDING.y * 0.5, PANEL_PADDING.x * 0.5, PANEL_PADDING.y * 0.5)
	plate.bracket = Color(Palette.CYAN, 0.65)
	add_theme_stylebox_override(&"panel", plate)

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", GAP)
	add_child(body)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 5)
	var title := UiKit.heading(prompt)
	title.language = language
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title)
	content.add_child(FlatStyle.rule(Color(Palette.CYAN_DIM, 0.78)))

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_MAXIMIZE_FIRST
	_scroll.follow_focus = true
	_scroll.add_theme_constant_override(&"scrollbar_h_separation", 4)
	rows.add_theme_constant_override(&"separation", 3)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(rows)
	_scroll.add_child(content)
	body.add_child(_scroll)

	_note.language = language
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_theme_constant_override(&"separation", 4)
	_footer.add_child(_note)
	_footer.add_child(_back_hint)
	body.add_child(_footer)
	minimum_size_changed.connect(_fit.call_deferred)


func add_row(label: String, note: String, action: Callable) -> Button:
	var button := UiKit.button(label, action)
	button.custom_minimum_size = Vector2(0, 22)
	button.language = _note.language
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _row_styles.is_empty():
		_row_styles[&"normal"] = _row_style(Color("131f29"), Color("253a47"))
		_row_styles[&"hover"] = _row_style(Color("1a3540"), Color("447580"))
		_row_styles[&"pressed"] = _row_style(Color("244a55"), Palette.CYAN_DIM)
		_row_styles[&"focus"] = _row_style(Color.TRANSPARENT, Palette.CYAN, true)
	for state: StringName in _row_styles:
		button.add_theme_stylebox_override(state, _row_styles[state])
	button.add_theme_stylebox_override(&"hover_pressed", _row_styles[&"pressed"])
	button.add_theme_color_override(&"font_focus_color", Palette.WHITE)
	button.add_theme_color_override(&"font_hover_color", Palette.WHITE)
	button.focus_entered.connect(_show_note.bind(note))
	button.mouse_entered.connect(_show_note.bind(note))
	button.mouse_exited.connect(_restore_focused_note)
	rows.add_child(button)
	_notes[button] = note
	return button


func add_reference_heading(title: String) -> void:
	rows.add_child(FlatStyle.section(title))


func focus_first_row() -> void:
	var buttons := _notes.keys()
	for index in buttons.size():
		var button := buttons[index] as Button
		button.focus_neighbor_top = button.get_path_to(buttons[maxi(0, index - 1)])
		button.focus_neighbor_bottom = button.get_path_to(buttons[mini(index + 1, buttons.size() - 1)])
		button.focus_previous = button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		button.focus_next = button.get_path_to(buttons[(index + 1) % buttons.size()])
	if not buttons.is_empty():
		(buttons[0] as Button).grab_focus()


func set_back_hint(text: String) -> void:
	_back_hint.text = text


func layout_safe_rect(rect: Rect2) -> void:
	_safe_rect = rect
	_fit()


func _fit() -> void:
	if not is_inside_tree() or _safe_rect.size.x <= 0.0 or _safe_rect.size.y <= 0.0:
		return
	var width := floorf(minf(maxf(1.0, _safe_rect.size.x - INSET * 2.0),
			clampf(_safe_rect.size.x * 0.48, MIN_WIDTH, MAX_WIDTH)))
	_reserve_note_height(maxf(1.0, width - PANEL_PADDING.x))
	var scroll_limit := maxf(1.0, floorf(_safe_rect.size.y - INSET * 2.0 - PANEL_PADDING.y
			- _footer.get_bound_minimum_size().y - GAP))
	if _scroll.custom_maximum_size.y != scroll_limit:
		_scroll.custom_maximum_size.y = scroll_limit
	position = Vector2(floorf(_safe_rect.end.x - INSET - width), ceilf(_safe_rect.position.y + INSET))
	size = Vector2(width, get_bound_minimum_size().y)


func _reserve_note_height(width: float) -> void:
	var font := _note.get_theme_font(&"font")
	var font_size := _note.get_theme_font_size(&"font_size")
	if font == _note_font and font_size == _note_font_size and width == _note_width:
		return
	_note_font = font
	_note_font_size = font_size
	_note_width = width
	# Use the label's own wrapping and fallback metrics. Measure only after a width or font change.
	var displayed := _note.text
	_note.size.x = width
	var height := 0.0
	for text: String in _notes.values():
		if not text.is_empty():
			_note.text = text
			height = maxf(height, _note.get_minimum_size().y)
	_note.text = displayed
	_note.custom_minimum_size.y = ceilf(height)
	_note.visible = height > 0.0


func _show_note(note: String) -> void:
	_note.text = note


func _restore_focused_note() -> void:
	_show_note(_notes.get(get_viewport().gui_get_focus_owner() as Button, ""))


static func _row_style(fill: Color, line: Color, focused := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width(SIDE_BOTTOM, 1 if not focused else 0)
	style.set_border_width(SIDE_LEFT, 2 if focused else 0)
	style.content_margin_left = 16
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
