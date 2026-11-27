class_name CollageShapes
extends RefCounted
## 拼貼版面的形狀（NE-403）：這個世界裡的實物——貨運吊牌、當票、封條、霓虹招牌底板——加上掃描線與半色調網點。
## 全部是靜態繪製用的小工具，不配置節點；每個形狀都不是純矩形（有切角、打孔、鋸齒或斜邊）。
## 設計見 design/22-living-scenes/UI_COLLAGE.md。

## 吊牌：左端兩角切掉成箭頭狀、靠左有一個打孔。rect 是外框，notch 是切角的深度。
static func tag_polygon(rect: Rect2, notch: float) -> PackedVector2Array:
	var n := minf(notch, rect.size.y * 0.5)
	return PackedVector2Array([
		Vector2(rect.position.x + n, rect.position.y),
		Vector2(rect.end.x - 2.0, rect.position.y),
		Vector2(rect.end.x, rect.position.y + 2.0),
		Vector2(rect.end.x, rect.end.y - 2.0),
		Vector2(rect.end.x - 2.0, rect.end.y),
		Vector2(rect.position.x + n, rect.end.y),
		Vector2(rect.position.x, rect.end.y - n),
		Vector2(rect.position.x, rect.position.y + n),
	])


## 斜切的招牌底板：平行四邊形，右上角再切一刀。
static func slant_polygon(rect: Rect2, skew: float, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(rect.position.x + skew, rect.position.y),
		Vector2(rect.end.x - cut, rect.position.y),
		Vector2(rect.end.x, rect.position.y + cut),
		Vector2(rect.end.x - skew, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	])


## 當票：右側一排撕線的鋸齒（齒的大小 tooth）。
static func ticket_polygon(rect: Rect2, tooth: float) -> PackedVector2Array:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x - tooth, rect.position.y)])
	var y := rect.position.y
	var out := true
	while y < rect.end.y:
		y = minf(y + tooth, rect.end.y)
		points.append(Vector2(rect.end.x if out else rect.end.x - tooth, y))
		out = not out
	points.append(Vector2(rect.position.x, rect.end.y))
	return points


## 依 tilt（弧度）繞 pivot 轉動一組點（就地修改並回傳，方便點擊判斷與繪製共用同一份形狀）。
static func rotated(points: PackedVector2Array, pivot: Vector2, tilt: float) -> PackedVector2Array:
	var transform := Transform2D(tilt, pivot) * Transform2D(0.0, -pivot)
	for i in points.size():
		points[i] = transform * points[i]
	return points


## 點是否在多邊形裡（滑鼠的點擊範圍跟著畫面上的形狀）。
static func contains(points: PackedVector2Array, point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, points)


## 畫一個有外框的多邊形（外框閉合）。
static func draw_shape(canvas: CanvasItem, points: PackedVector2Array, fill: Color, border: Color, width := 1.0) -> void:
	canvas.draw_colored_polygon(points, fill)
	if border.a > 0.0:
		var outline := points.duplicate()
		outline.append(points[0])
		canvas.draw_polyline(outline, border, width)


## 吊牌的打孔與穿出去的繩子（繩子往左上斜出畫面外一點）。
static func draw_hole(canvas: CanvasItem, center: Vector2, radius: float, rim: Color, string_color: Color, tilt: float) -> void:
	canvas.draw_circle(center, radius, Color(0.01, 0.02, 0.03, 0.95))
	canvas.draw_arc(center, radius, 0.0, TAU, 12, rim, 1.0)
	if string_color.a > 0.0:
		var away := Vector2(-1.0, -0.55).rotated(tilt).normalized()
		canvas.draw_line(center + away * radius, center + away * (radius + 11.0), string_color, 1.0)


## 掃描線：每 gap 像素一條很淡的橫線，只畫在 rect 裡（用在大色塊上，不蓋文字）。
static func draw_scanlines(canvas: CanvasItem, rect: Rect2, color: Color, gap := 3.0) -> void:
	var y := rect.position.y
	while y < rect.end.y:
		canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), color, 1.0)
		y += gap


## 半色調網點：從 rect 的左邊往右逐漸變小（最大半徑 max_radius、間距 step），印刷的質感。
static func draw_halftone(canvas: CanvasItem, rect: Rect2, color: Color, step := 5.0, max_radius := 1.8) -> void:
	var y := rect.position.y + step * 0.5
	var row := 0
	while y < rect.end.y:
		var x := rect.position.x + step * (0.5 if row % 2 == 0 else 1.0)
		while x < rect.end.x:
			var t := (x - rect.position.x) / maxf(1.0, rect.size.x)
			var radius := max_radius * (1.0 - t)
			if radius > 0.25:
				canvas.draw_circle(Vector2(x, y), radius, color)
			x += step
		y += step * 0.87
		row += 1
