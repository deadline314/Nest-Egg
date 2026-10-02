class_name PixelCanvas
extends RefCounted
## 逐像素繪圖的小畫布（不需要 GPU，無頭模式即可執行）：用來產生背包的高解析像素圖示。
## 所有筆刷都不做抗鋸齒，邊緣乾淨；最後可用 outline() 自動描邊、upscaled() 輸出放大預覽。

var image: Image


func _init(width: int, height: int) -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)


func width() -> int:
	return image.get_width()


func height() -> int:
	return image.get_height()


## 單一像素（超出範圍會被忽略）。color.a < 1 時與底下的像素混色。
func px(x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= width() or y >= height() or color.a <= 0.0:
		return
	if color.a < 1.0:
		var below := image.get_pixel(x, y)
		color = below.blend(color) if below.a > 0.0 else color
	image.set_pixel(x, y, color)


func rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(xx, yy, color)


## 由上到下的垂直漸層。
func rect_gradient(x: int, y: int, w: int, h: int, top: Color, bottom: Color) -> void:
	for yy in h:
		var color := top.lerp(bottom, float(yy) / maxf(1.0, float(h - 1)))
		rect(x, y + yy, w, 1, color)


## 實心橢圓（以像素中心判斷，邊緣乾淨）。
func ellipse(cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	for yy in range(int(floor(cy - ry)), int(ceil(cy + ry)) + 1):
		for xx in range(int(floor(cx - rx)), int(ceil(cx + rx)) + 1):
			var dx := (xx + 0.5 - cx) / rx
			var dy := (yy + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				px(xx, yy, color)


func circle(cx: float, cy: float, r: float, color: Color) -> void:
	ellipse(cx, cy, r, r, color)


## 1 像素寬的線（Bresenham）。
func line(from: Vector2i, to: Vector2i, color: Color) -> void:
	var d := to - from
	var steps := maxi(absi(d.x), absi(d.y))
	if steps == 0:
		px(from.x, from.y, color)
		return
	for i in steps + 1:
		var p := Vector2(from) + Vector2(d) * (float(i) / steps)
		px(roundi(p.x), roundi(p.y), color)


## 實心多邊形（點座標為像素角落座標，以像素中心判斷）。
func polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in points:
		low = low.min(p)
		high = high.max(p)
	for yy in range(int(floor(low.y)), int(ceil(high.y)) + 1):
		for xx in range(int(floor(low.x)), int(ceil(high.x)) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(xx + 0.5, yy + 0.5), points):
				px(xx, yy, color)


## 在所有「透明但緊鄰不透明像素」的位置畫描邊（上下左右；diagonal = true 時含斜角）。
func outline(color: Color, diagonal := false) -> void:
	var marks: Array[Vector2i] = []
	for y in height():
		for x in width():
			if image.get_pixel(x, y).a > 0.0:
				continue
			if _touches_opaque(x, y, diagonal):
				marks.append(Vector2i(x, y))
	for p in marks:
		image.set_pixel(p.x, p.y, color)


func _touches_opaque(x: int, y: int, diagonal: bool) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx == 0 and dy == 0) or (not diagonal and dx != 0 and dy != 0):
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < width() and ny < height() and image.get_pixel(nx, ny).a > 0.0:
				return true
	return false


## 最近鄰放大（預覽與檢查用）。
func upscaled(factor: int) -> Image:
	var copy := image.duplicate() as Image
	copy.resize(width() * factor, height() * factor, Image.INTERPOLATE_NEAREST)
	return copy


func save_png(path: String) -> Error:
	return image.save_png(ProjectSettings.globalize_path(path))
