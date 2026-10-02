class_name NormalMapMaker
extends RefCounted
## 從一般貼圖自動產生法線貼圖（只用 CPU，不需要 GPU）：
##   高度 = 模糊後的透明度（讓邊緣圓滑隆起）× bevel_height + 亮度 × detail_height（亮處微微凸起）
##   法線 = 高度場的斜率；RGB 編碼法線（Godot 2D 的 Y+ 向上），Alpha 沿用原圖。
## 之後可用手繪的同名法線貼圖（<名稱>_n.png）取代。


## source 必須是 RGBA。bevel_radius：邊緣圓滑的寬度（像素）；兩個高度值越大，受光起伏越明顯。
static func make(source: Image, bevel_radius := 2, bevel_height := 3.0, detail_height := 1.4) -> Image:
	var image := source.duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	var alpha := PackedFloat32Array()
	var luma := PackedFloat32Array()
	alpha.resize(w * h)
	luma.resize(w * h)
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			alpha[y * w + x] = c.a
			luma[y * w + x] = LightKit.luminance(c) * c.a
	var blurred := _box_blur(alpha, w, h, bevel_radius)
	var height_field := PackedFloat32Array()
	height_field.resize(w * h)
	for i in w * h:
		height_field[i] = blurred[i] * bevel_height + luma[i] * detail_height
	var result := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := _sample(height_field, w, h, x + 1, y) - _sample(height_field, w, h, x - 1, y)
			var dy := _sample(height_field, w, h, x, y + 1) - _sample(height_field, w, h, x, y - 1)
			# 影像的 y 向下；法線的 Y 向上，所以 y 方向取正號。
			var normal := Vector3(-dx, dy, 2.0).normalized()
			result.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, alpha[y * w + x]))
	return result


static func _sample(field: PackedFloat32Array, w: int, h: int, x: int, y: int) -> float:
	return field[clampi(y, 0, h - 1) * w + clampi(x, 0, w - 1)]


## 可分離的方框模糊。
static func _box_blur(field: PackedFloat32Array, w: int, h: int, radius: int) -> PackedFloat32Array:
	if radius <= 0:
		return field
	var horizontal := PackedFloat32Array()
	horizontal.resize(w * h)
	var span := float(radius * 2 + 1)
	for y in h:
		for x in w:
			var total := 0.0
			for k in range(-radius, radius + 1):
				total += _sample(field, w, h, x + k, y)
			horizontal[y * w + x] = total / span
	var result := PackedFloat32Array()
	result.resize(w * h)
	for y in h:
		for x in w:
			var total := 0.0
			for k in range(-radius, radius + 1):
				total += _sample(horizontal, w, h, x, y + k)
			result[y * w + x] = total / span
	return result
