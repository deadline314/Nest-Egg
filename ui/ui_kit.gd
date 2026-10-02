class_name UiKit
extends RefCounted
## UI 共用工具：主題、字型、常用控制項。所有畫面共用同一份主題，確保風格一致且只建立一次。
## Tooltip 原則：一句話講重點（做什麼／怎麼用），不寫廢話。

const FONT_NAMES: Array[String] = [
	"Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "PingFang TC", "Heiti TC",
	"Source Han Sans TC", "Noto Sans CJK JP", "sans-serif",
]
const BASE_FONT_SIZE := 12

static var _theme: Theme
static var _font: Font


static func font() -> Font:
	if _font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(FONT_NAMES)
		system_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = system_font
	return _font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = BASE_FONT_SIZE
	t.set_stylebox(&"normal", &"Button", _box(Color(0.07, 0.11, 0.15, 0.92), Palette.CYAN_DIM))
	t.set_stylebox(&"hover", &"Button", _box(Color(0.09, 0.17, 0.22, 0.95), Palette.CYAN))
	t.set_stylebox(&"pressed", &"Button", _box(Color(0.05, 0.28, 0.35, 0.95), Palette.CYAN))
	t.set_stylebox(&"focus", &"Button", _box(Color(0, 0, 0, 0), Palette.CYAN, 2))
	t.set_stylebox(&"disabled", &"Button", _box(Color(0.06, 0.08, 0.1, 0.8), Palette.TERRAIN_EDGE))
	t.set_color(&"font_color", &"Button", Palette.UI_TEXT)
	t.set_color(&"font_hover_color", &"Button", Palette.CYAN)
	t.set_color(&"font_focus_color", &"Button", Palette.CYAN)
	t.set_color(&"font_pressed_color", &"Button", Palette.WHITE)
	t.set_color(&"font_disabled_color", &"Button", Palette.UI_MUTED)
	t.set_stylebox(&"panel", &"PanelContainer", _box(Palette.UI_PANEL, Palette.CYAN_DIM, 1, 10))
	t.set_stylebox(&"panel", &"TooltipPanel", _box(Color(0.03, 0.05, 0.07, 0.96), Palette.CYAN_DIM, 1, 6))
	t.set_color(&"font_color", &"TooltipLabel", Palette.UI_TEXT)
	t.set_font_size(&"font_size", &"TooltipLabel", 10)
	t.set_color(&"font_color", &"Label", Palette.UI_TEXT)
	_theme = t
	return t


static func _box(bg: Color, border: Color, border_width := 1, margin := 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(2)
	box.content_margin_left = margin * 2
	box.content_margin_right = margin * 2
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box


static func label(text: String, size := BASE_FONT_SIZE, color := Palette.UI_TEXT,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 建立按鈕；tooltip 請寫一句重點。
static func button(text: String, on_pressed: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(180, 0)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	b.pressed.connect(Sfx.play.bind(&"ui_confirm", -6.0, 0.0))
	b.focus_entered.connect(Sfx.play.bind(&"ui_move", -14.0, 0.0))
	return b


## 全螢幕置中面板（死亡／暫停／過關畫面共用）。回傳內容 VBox。
static func centered_panel(parent: Control, min_width := 360.0, dim := 0.6) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	return box


static func full_rect_root(theme_owner: Node) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme()
	theme_owner.add_child(root)
	return root


## 遊戲中隱藏系統游標（改用準星），選單與暫停時顯示。
static func set_cursor_visible(visible: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_HIDDEN


static func format_time(seconds: float) -> String:
	var total := maxf(0.0, seconds)
	return "%02d:%05.2f" % [int(total / 60.0), fmod(total, 60.0)]


## 讓「父節點不是 Control」的畫面（例如直接掛在 Main 底下）永遠填滿視窗。
static func fit_to_viewport(control: Control) -> void:
	var viewport := control.get_viewport()
	if viewport == null:
		return
	var resize := func() -> void:
		if is_instance_valid(control):
			control.position = Vector2.ZERO
			control.size = viewport.get_visible_rect().size
	resize.call()
	viewport.size_changed.connect(resize)
	# 畫面移除時解除連線，避免殘留回呼。
	control.tree_exiting.connect(func() -> void:
		if viewport.size_changed.is_connected(resize):
			viewport.size_changed.disconnect(resize), CONNECT_ONE_SHOT)
