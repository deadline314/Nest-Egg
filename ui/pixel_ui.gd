class_name PixelUi
extends RefCounted
## 像素風介面的共用繪製：缺角像素外框、貼圖最近鄰放大、NEW 標記。
## 所有座標取整數，邊緣不做抗鋸齒，放大後保持銳利。


## 缺角像素外框（四個角各缺一格斜角）。notch = 缺角大小，thickness = 邊框粗細（整數）。
static func frame(canvas: CanvasItem, rect: Rect2, fill: Color, border: Color, notch := 3, thickness := 1) -> void:
	var origin := rect.position.round()
	var size := rect.size.round()
	if size.x <= thickness or size.y <= thickness:
		return  # Containers may draw once before assigning a nonempty size.
	# 線的中心線往內縮半個線寬，邊框正好落在像素格上。
	var inset := float(thickness) * 0.5
	var n := minf(float(notch), (minf(size.x, size.y) - thickness) * 0.5)
	var x0 := inset
	var y0 := inset
	var x1 := size.x - inset
	var y1 := size.y - inset
	var points := PackedVector2Array([
		Vector2(x0 + n, y0), Vector2(x1 - n, y0), Vector2(x1, y0 + n), Vector2(x1, y1 - n),
		Vector2(x1 - n, y1), Vector2(x0 + n, y1), Vector2(x0, y1 - n), Vector2(x0, y0 + n),
	])
	for i in points.size():
		points[i] += origin
	canvas.draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, border, float(thickness), false)


## 以最近鄰把貼圖放大 scale 倍（整數倍）畫在 position（左上角）。需要控制項設為 TEXTURE_FILTER_NEAREST。
static func texture(canvas: CanvasItem, tex: Texture2D, position: Vector2, scale: int, modulate := Color.WHITE) -> void:
	if tex == null:
		return
	canvas.draw_texture_rect(tex, Rect2(position.round(), Vector2(tex.get_size()) * float(scale)), false, modulate)


## 小標籤（NEW、數量）：像素外框底 + 文字。回傳標籤寬度。
static func badge(canvas: CanvasItem, right_top: Vector2, text: String, color: Color, font_size := 9) -> float:
	var font := UiKit.font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var size := Vector2(text_size.x + 8.0, text_size.y + 2.0)
	var rect := Rect2((right_top - Vector2(size.x, 0)).round(), size.round())
	frame(canvas, rect, Color(color, 0.22), color, 1)
	canvas.draw_string(font, rect.position + Vector2(4, size.y - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	return size.x


## 像素進度條：total 格，filled 格亮起。
static func segments(canvas: CanvasItem, position: Vector2, total: int, filled: int, color: Color, cell := Vector2(4, 6), gap := 1.0) -> void:
	for i in total:
		var rect := Rect2(position + Vector2(i * (cell.x + gap), 0), cell).abs()
		canvas.draw_rect(rect, color if i < filled else Color(color, 0.18))
