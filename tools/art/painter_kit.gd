class_name PainterKit
extends RefCounted
## 程式繪圖的基本筆刷：漸層多邊形、錐形膠囊（四肢）、橢圓、描邊。
## 風格：賽璐珞上色（漸層 + 深色描邊）＋ 霓虹邊光。座標單位為貼圖像素。


static func col(style: Dictionary, key: String, fallback := Color.MAGENTA) -> Color:
	return Color(str(style[key])) if style.has(key) else fallback


## 實心多邊形 + 描邊。
static func poly(c: CanvasItem, points: PackedVector2Array, fill: Color, outline := Color.TRANSPARENT, width := 2.0) -> void:
	if points.size() < 3:
		return
	c.draw_colored_polygon(points, fill)
	if outline.a > 0.0:
		stroke(c, points, outline, width)


## 沿 axis 方向漸層的多邊形（例如由暗到亮的側光）。
static func grad_poly(c: CanvasItem, points: PackedVector2Array, from: Color, to: Color, axis := Vector2.RIGHT,
		outline := Color.TRANSPARENT, width := 2.0) -> void:
	if points.size() < 3:
		return
	var low := INF
	var high := -INF
	for p in points:
		var d := p.dot(axis)
		low = minf(low, d)
		high = maxf(high, d)
	var colors := PackedColorArray()
	colors.resize(points.size())
	for i in points.size():
		var t := 0.0 if is_equal_approx(high, low) else (points[i].dot(axis) - low) / (high - low)
		colors[i] = from.lerp(to, t)
	c.draw_polygon(points, colors)
	if outline.a > 0.0:
		stroke(c, points, outline, width)


static func stroke(c: CanvasItem, points: PackedVector2Array, color: Color, width := 2.0) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	c.draw_polyline(closed, color, width, true)


## 錐形膠囊外框（a→b，半徑 ra→rb），用於手臂、腿。
static func capsule(a: Vector2, b: Vector2, ra: float, rb: float, segments := 8) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var angle := dir.angle()
	var points := PackedVector2Array()
	for i in segments + 1:
		var t := angle - PI * 0.5 - PI * float(i) / segments
		points.append(a + Vector2.RIGHT.rotated(t) * ra)
	for i in segments + 1:
		var t := angle + PI * 0.5 - PI * float(i) / segments
		points.append(b + Vector2.RIGHT.rotated(t) * rb)
	return points


static func ellipse(center: Vector2, rx: float, ry: float, segments := 24, from := 0.0, to := TAU) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments + 1:
		var t := lerpf(from, to, float(i) / segments)
		points.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	return points


static func line(c: CanvasItem, points: PackedVector2Array, color: Color, width := 1.5) -> void:
	if points.size() >= 2:
		c.draw_polyline(points, color, width, true)


static func pts(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(0, values.size() - 1, 2):
		result.append(Vector2(values[i], values[i + 1]))
	return result
