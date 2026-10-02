class_name PixelCanvas
extends RefCounted
## 逐像素繪圖的小畫布（不需要 GPU，無頭模式即可執行）：用來產生背包的高解析像素圖示。
## 所有筆刷都不做抗鋸齒，邊緣乾淨；最後可用 outline() 自動描邊、upscaled() 輸出放大預覽。

var image: Image


func _init(width: int, height: int) -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)


## 把高解析圖「像素化」：裁掉透明邊、等比縮進 size（四周留 margin）、置中、透明度二值化、顏色限階。
## gamma < 1 會提亮暗部（暗色武器在深色背包背景上才看得清楚）。
## 用來把現有的高解析美術自動轉成低解析像素圖示（之後可直接用手繪像素圖覆蓋）。
static func from_image_fit(source: Image, size: Vector2i, margin := 1, color_levels := 6, gamma := 1.0) -> PixelCanvas:
	var canvas := PixelCanvas.new(size.x, size.y)
	var used := source.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return canvas
	var cropped := source.get_region(used)
	var room := Vector2(size - Vector2i(margin * 2, margin * 2))
	var factor := minf(room.x / float(used.size.x), room.y / float(used.size.y))
	var fitted := Vector2i(maxi(1, roundi(used.size.x * factor)), maxi(1, roundi(used.size.y * factor)))
	cropped.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	var origin := (size - fitted) / 2
	for y in fitted.y:
		for x in fitted.x:
			var color := cropped.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var lifted := Color(pow(color.r, gamma), pow(color.g, gamma), pow(color.b, gamma), 1.0)
			canvas.px(origin.x + x, origin.y + y, _posterized(lifted, color_levels))
	return canvas


## 與 from_image_fit 類似，但不裁切、不置中：來源是 size 的整數倍（supersample 倍）解析度，
## 直接縮回 size，位置與其他同尺寸圖層保持對齊（立繪分層用）。
static func from_image_exact(source: Image, size: Vector2i, color_levels := 6) -> PixelCanvas:
	var canvas := PixelCanvas.new(size.x, size.y)
	var scaled := source.duplicate() as Image
	scaled.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	for y in size.y:
		for x in size.x:
			var color := scaled.get_pixel(x, y)
			if color.a >= 0.5:
				canvas.px(x, y, _posterized(Color(color, 1.0), color_levels))
	return canvas


## 把 glow 圖以加法疊到 base 上（自發光的霓虹線），回傳新圖。兩張圖尺寸需相同。
static func add_glow(base: Image, glow: Image, strength := 0.8) -> Image:
	var result := base.duplicate() as Image
	if glow == null or glow.get_size() != base.get_size():
		return result
	for y in base.get_height():
		for x in base.get_width():
			var g := glow.get_pixel(x, y)
			if g.a <= 0.0:
				continue
			var b := result.get_pixel(x, y)
			var mixed := Color(minf(1.0, b.r + g.r * g.a * strength), minf(1.0, b.g + g.g * g.a * strength),
					minf(1.0, b.b + g.b * g.a * strength), maxf(b.a, g.a))
			result.set_pixel(x, y, mixed)
	return result


## 亮度只保留 levels 階、飽和度與色相也限階，得到有限的色盤（像素畫的單純色塊感）。
func posterize(levels: int) -> void:
	for y in height():
		for x in width():
			var color := image.get_pixel(x, y)
			if color.a > 0.0:
				image.set_pixel(x, y, _posterized(color, levels))


static func _posterized(color: Color, levels: int) -> Color:
	# 在 HSV 空間限階：灰色金屬維持純灰、霓虹色維持單純的色相，避免逐通道限階產生的雜色。
	var steps := float(maxi(2, levels) - 1)
	var saturation := roundf(color.s * 8.0) / 8.0
	var hue := roundf(color.h * 24.0) / 24.0 if saturation > 0.0 else 0.0
	return Color.from_hsv(hue, saturation, roundf(color.v * steps) / steps, color.a)


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
