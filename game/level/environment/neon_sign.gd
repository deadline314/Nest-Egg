class_name NeonSign
extends Node2D
## 霓虹招牌：發光字樣（直式或橫式）、偶爾閃爍或單字故障、投射彩色光，並在下方濕地面畫出倒影。

const FONT_SIZE := 11
const CHAR_STEP := 12.0
const PADDING := 5.0
const REFLECTION_DEPTH := 26.0

var text := "拉麵"
var color := Palette.MAGENTA
var vertical := true
## 招牌下方地面的世界 y 座標（用來畫倒影）；INF 代表不畫。
var floor_y := INF

var _font: Font
var _light: PointLight2D
var _time := 0.0
var _off_left := 0.0
var _broken_index := -1
var _size := Vector2.ZERO


func _ready() -> void:
	_font = UiKit.font()
	var count := text.length()
	_size = Vector2(FONT_SIZE + PADDING * 2.0, count * CHAR_STEP + PADDING * 2.0) if vertical \
			else Vector2(count * CHAR_STEP + PADDING * 2.0, FONT_SIZE + PADDING * 2.0)
	_light = LightKit.create_point_light(color, maxf(_size.x, _size.y) * 1.6, 0.9)
	_light.position = _size * 0.5
	add_child(_light)
	_time = randf() * 10.0
	if count > 1 and randf() < 0.35:
		_broken_index = randi() % count


func _process(delta: float) -> void:
	_time += delta
	if _off_left > 0.0:
		_off_left -= delta
	elif randf() < 0.004:
		_off_left = randf_range(0.04, 0.25)
	_light.energy = 0.15 if _off_left > 0.0 else 0.9 + sin(_time * 30.0) * 0.05
	queue_redraw()


func _draw() -> void:
	var lit := _off_left <= 0.0
	# 外框與背板
	draw_rect(Rect2(Vector2.ZERO, _size), Color("0b0d16"))
	draw_rect(Rect2(Vector2.ZERO, _size), Color(color, 0.35 if lit else 0.12), false, 1.0)
	for i in text.length():
		var ch := text[i]
		var pos := Vector2(PADDING, PADDING + FONT_SIZE + i * CHAR_STEP - 2.0) if vertical \
				else Vector2(PADDING + i * CHAR_STEP, PADDING + FONT_SIZE - 2.0)
		var on := lit and not (i == _broken_index and fmod(_time, 1.7) < 0.9)
		var glow := LightKit.glow(color, 2.6) if on else Color(color.darkened(0.6), 0.6)
		if on:
			draw_string_outline(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color(color, 0.35))
		draw_string(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, glow)
	_draw_reflection(lit)


## 濕地倒影：在地面下方畫一條由亮到暗的垂直色帶，寬度與招牌相同。
func _draw_reflection(lit: bool) -> void:
	if floor_y == INF or not lit:
		return
	var top := floor_y - global_position.y + 1.0
	var rect := PackedVector2Array([
		Vector2(0, top), Vector2(_size.x, top), Vector2(_size.x * 0.9, top + REFLECTION_DEPTH), Vector2(_size.x * 0.1, top + REFLECTION_DEPTH)])
	var colors := PackedColorArray([Color(LightKit.glow(color, 1.4), 0.35), Color(LightKit.glow(color, 1.4), 0.35), Color(color, 0.0), Color(color, 0.0)])
	draw_polygon(rect, colors)
