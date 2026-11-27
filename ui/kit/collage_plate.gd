class_name CollagePlate
extends Control
## 拼貼版面的標題底板（NE-403）：一塊斜切的霓虹招牌底板，微微傾斜，底邊與左邊有青色燈管，
## 右半部印著半色調網點、整塊有很淡的掃描線（只在底板裡、不蓋到文字的筆畫顏色）。
## 開啟畫面時從左邊斜著切進來（intro）；之後完全靜態、不重畫。「減少動態」時直接到位。

const INTRO_TIME := 0.22
const INTRO_SLIDE := 60.0

## 傾斜（度）、斜切量與右上角切角（像素）。
var tilt_degrees := -2.5
var skew := 18.0
var cut := 12.0
var fill := Color(0.035, 0.06, 0.085, 0.94)
var neon := Palette.CYAN

var _intro := 1.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## 從左邊斜切進來。
func intro(delay := 0.0) -> void:
	if _tween != null:
		_tween.kill()
	if Settings.get_reduce_ui_motion() or not is_inside_tree():
		_set_intro(1.0)
		return
	_set_intro(0.0)
	_tween = create_tween()
	_tween.tween_method(_set_intro, 0.0, 1.0, INTRO_TIME).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func intro_amount() -> float:
	return _intro


func _set_intro(value: float) -> void:
	_intro = value
	modulate.a = clampf(value * 1.5, 0.0, 1.0)
	queue_redraw()


func plate_points() -> PackedVector2Array:
	var rect := Rect2(Vector2(-INTRO_SLIDE * (1.0 - _intro), 0.0), size)
	return CollageShapes.rotated(CollageShapes.slant_polygon(rect, skew, cut), rect.get_center(), deg_to_rad(tilt_degrees))


func _draw() -> void:
	var points := plate_points()
	CollageShapes.draw_shape(self, points, fill, Color(neon, 0.25), 1.0)
	# 掃描線與半色調只畫在底板裡：逐條和多邊形求交。
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	var y := bounds.position.y + 2.0
	while y < bounds.end.y:
		for segment in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(bounds.position.x - 1.0, y), Vector2(bounds.end.x + 1.0, y)]), points):
			draw_line(segment[0], segment[segment.size() - 1], Color(neon, 0.05), 1.0)
		y += 3.0
	var dots := Rect2(bounds.position + Vector2(bounds.size.x * 0.55, 6.0), Vector2(bounds.size.x * 0.4, bounds.size.y - 12.0))
	_draw_halftone_inside(dots, points)
	# 燈管：底邊與左邊，帶一層淡淡的光暈。
	for pair: Array in [[points[4], points[3]], [points[4], points[0]]]:
		draw_line(pair[0], pair[1], Color(neon, 0.18), 5.0)
		draw_line(pair[0], pair[1], LightKit.glow(neon, 1.1), 1.5)


func _draw_halftone_inside(rect: Rect2, polygon: PackedVector2Array) -> void:
	var step := 5.0
	var y := rect.position.y
	var row := 0
	while y < rect.end.y:
		var x := rect.position.x + (0.0 if row % 2 == 0 else step * 0.5)
		while x < rect.end.x:
			var radius := 1.7 * (x - rect.position.x) / maxf(1.0, rect.size.x)
			if radius > 0.3 and Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				draw_circle(Vector2(x, y), radius, Color(neon, 0.16))
			x += step
		y += step * 0.87
		row += 1
