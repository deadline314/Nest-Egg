class_name HoloBillboard
extends Node2D
## 全像廣告看板：半透明面板＋掃描線＋旋轉標誌，文字帶色差；定期以故障閃爍切換廣告內容。

const AD_DURATION := 4.5
const GLITCH_TIME := 0.25
const TITLE_SIZE := 13
const TAGLINE_SIZE := 8

var size := Vector2(112, 64)
var color := Palette.CYAN
## 每則廣告格式："標題|副標"。
var ads := PackedStringArray(["天穹集團|讓天空屬於每個人"])

var _font: Font
var _light: PointLight2D
var _time := 0.0
var _index := 0


func _ready() -> void:
	_font = UiKit.font()
	_light = LightKit.create_point_light(color, size.x * 1.2, 0.55)
	_light.position = size * 0.5
	add_child(_light)
	_time = randf() * AD_DURATION
	_index = randi() % maxi(1, ads.size())


func _process(delta: float) -> void:
	_time += delta
	if _time >= AD_DURATION:
		_time = 0.0
		_index = (_index + 1) % maxi(1, ads.size())
	_light.energy = 0.55 + sin(_time * 2.0) * 0.08
	queue_redraw()


func _draw() -> void:
	var glitching := _time < GLITCH_TIME
	var jitter := Vector2(randf_range(-3, 3), 0) if glitching else Vector2.ZERO
	# 面板與掃描線
	draw_rect(Rect2(jitter, size), Color(color, 0.08))
	var y := fmod(_time * 20.0, 3.0)
	while y < size.y:
		draw_line(Vector2(0, y) + jitter, Vector2(size.x, y) + jitter, Color(color, 0.07), 1.0)
		y += 3.0
	# 四角框
	var corner := 8.0
	var frame := LightKit.glow(color, 1.6)
	for c: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var sx := 1.0 if c.x == 0.0 else -1.0
		var sy := 1.0 if c.y == 0.0 else -1.0
		draw_line(c + jitter, c + jitter + Vector2(corner * sx, 0), frame, 1.5)
		draw_line(c + jitter, c + jitter + Vector2(0, corner * sy), frame, 1.5)
	# 旋轉六角標誌
	var center := Vector2(18, size.y * 0.5) + jitter
	var hexagon := PackedVector2Array()
	for i in 7:
		hexagon.append(center + Vector2.RIGHT.rotated(_time * 0.8 + i * TAU / 6.0) * 10.0)
	draw_polyline(hexagon, LightKit.glow(color, 2.0), 1.5)
	draw_circle(center, 3.0, LightKit.glow(Palette.WHITE, 1.5))
	# 文字（色差：洋紅與青色錯位疊印）
	var parts := ads[_index].split("|") if not ads.is_empty() else PackedStringArray(["", ""])
	var title := parts[0]
	var tagline := parts[1] if parts.size() > 1 else ""
	var origin := Vector2(34, size.y * 0.5 - 2) + jitter
	draw_string(_font, origin + Vector2(-1, 0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(Palette.MAGENTA, 0.6))
	draw_string(_font, origin + Vector2(1, 0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(Palette.CYAN, 0.6))
	draw_string(_font, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, LightKit.glow(Palette.WHITE, 1.3))
	draw_string(_font, origin + Vector2(0, 13), tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, TAGLINE_SIZE, Color(LightKit.glow(color, 1.4), 0.9))
	if glitching:
		for i in 3:
			var bar_y := randf() * size.y
			draw_rect(Rect2(Vector2(0, bar_y), Vector2(size.x, randf_range(1, 4))), Color(Palette.MAGENTA if i % 2 == 0 else Palette.CYAN, 0.35))
