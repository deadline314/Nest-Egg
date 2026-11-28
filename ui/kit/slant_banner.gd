class_name SlantBanner
extends MarginContainer
## 斜切橫幅：只用在「現在要做的那一件事」（例如任務目前的步驟）。左側亮條＋向右淡出的底，右端斜切。
## 文字換行由內含的 Label 處理；只在尺寸或顏色改變時重畫。

const SLANT := 8.0

var accent := Palette.CYAN:
	set(value):
		if accent == value:
			return
		accent = value
		queue_redraw()
## 橫幅使用石墨色，只有左側短線繼承狀態色。
var fill_strength := 0.86:
	set(value):
		if is_equal_approx(fill_strength, value):
			return
		fill_strength = value
		queue_redraw()
var label: Label


func _init(text := "", p_accent := Palette.CYAN) -> void:
	accent = p_accent
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"margin_left", 10)
	add_theme_constant_override(&"margin_right", int(SLANT) + 6)
	add_theme_constant_override(&"margin_top", 3)
	add_theme_constant_override(&"margin_bottom", 3)
	label = UiKit.styled(text, &"body", Palette.WHITE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var points := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - SLANT, h), Vector2(0, h)])
	var strong := Color(UiTheme.PANEL_BODY, fill_strength)
	var faint := Color(UiTheme.PANEL_BODY, fill_strength * 0.70)
	draw_polygon(points, PackedColorArray([strong, faint, faint, strong]))
	draw_rect(Rect2(0, 4, 1.0, maxf(0.0, h - 8.0)), Color(accent, 0.82))
