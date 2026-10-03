class_name EnvCanvas
extends PixelCanvas
## 環境貼圖用的畫布（4 倍解析度）：在 PixelCanvas 的基本筆刷上加入材質常用的雜點、接縫、鉚釘、
## 斜紋、磚縫、窗格等。所有隨機都用固定種子，重畫結果一致；雜點只用座標雜湊，貼圖邊緣可無縫平鋪。

var seed_value := 1


func _init(width: int, height: int, p_seed := 1) -> void:
	super._init(width, height)
	seed_value = p_seed


## 座標雜湊（0~1），與 x、y 對貼圖寬高取模後的結果相同，所以可以平鋪。
func noise(x: int, y: int, salt := 0) -> float:
	var xx := posmod(x, width())
	var yy := posmod(y, height())
	var h := (xx * 374761393 + yy * 668265263 + (seed_value + salt) * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## 整張填色並加細微亮度雜訊。
func fill_noise(base: Color, amount := 0.02, salt := 0) -> void:
	for y in height():
		for x in width():
			var d := (noise(x, y, salt) - 0.5) * 2.0 * amount
			image.set_pixel(x, y, Color(clampf(base.r + d, 0, 1), clampf(base.g + d, 0, 1), clampf(base.b + d, 0, 1), base.a))


## 區域填色 + 雜訊。
func rect_noise(x0: int, y0: int, w: int, h: int, base: Color, amount := 0.02, salt := 0) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var d := (noise(x, y, salt) - 0.5) * 2.0 * amount
			px(x, y, Color(clampf(base.r + d, 0, 1), clampf(base.g + d, 0, 1), clampf(base.b + d, 0, 1), base.a))


## 隨機亮點／暗點。
func speckle(density: float, color: Color, salt := 7, x0 := 0, y0 := 0, w := -1, h := -1) -> void:
	var ww := width() - x0 if w < 0 else w
	var hh := height() - y0 if h < 0 else h
	for y in range(y0, y0 + hh):
		for x in range(x0, x0 + ww):
			if noise(x, y, salt) < density:
				px(x, y, color)


## 擦成透明（自發光層裡留出窗框、十字窗格）。
func erase(x: int, y: int, w: int, h: int) -> void:
	for yy in range(maxi(0, y), mini(height(), y + h)):
		for xx in range(maxi(0, x), mini(width(), x + w)):
			image.set_pixel(xx, yy, Color(0, 0, 0, 0))


func hline(y: int, color: Color, x0 := 0, x1 := -1, thickness := 1) -> void:
	var end_x := width() if x1 < 0 else x1
	rect(x0, y, end_x - x0, thickness, color)


func vline(x: int, color: Color, y0 := 0, y1 := -1, thickness := 1) -> void:
	var end_y := height() if y1 < 0 else y1
	rect(x, y0, thickness, end_y - y0, color)


## 外框（空心矩形）。
func frame(x: int, y: int, w: int, h: int, color: Color, thickness := 1) -> void:
	rect(x, y, w, thickness, color)
	rect(x, y + h - thickness, w, thickness, color)
	rect(x, y, thickness, h, color)
	rect(x + w - thickness, y, thickness, h, color)


## 凸起的面板：上、左邊亮，下、右邊暗。
func bevel(x: int, y: int, w: int, h: int, base: Color, light := 0.08, dark := 0.12, edge := 2) -> void:
	rect(x, y, w, h, base)
	rect(x, y, w, edge, base.lightened(light))
	rect(x, y, edge, h, base.lightened(light * 0.6))
	rect(x, y + h - edge, w, edge, base.darkened(dark))
	rect(x + w - edge, y, edge, h, base.darkened(dark * 0.7))


## 內凹（反向 bevel）。
func inset(x: int, y: int, w: int, h: int, base: Color, light := 0.08, dark := 0.12, edge := 2) -> void:
	rect(x, y, w, h, base)
	rect(x, y, w, edge, base.darkened(dark))
	rect(x, y, edge, h, base.darkened(dark * 0.7))
	rect(x, y + h - edge, w, edge, base.lightened(light))
	rect(x + w - edge, y, edge, h, base.lightened(light * 0.6))


func rivet(cx: int, cy: int, base: Color, r := 2) -> void:
	circle(cx + 0.5, cy + 0.5, float(r), base.lightened(0.18))
	circle(cx + 1.0, cy + 1.0, float(r) * 0.6, base.darkened(0.3))


## 往下的鏽水／雨痕。
func streak(x: int, y: int, length: int, color: Color, salt := 3) -> void:
	for i in length:
		var fade := 1.0 - float(i) / float(length)
		var wobble := int(round((noise(x, y + i, salt) - 0.5) * 2.0))
		px(x + wobble, y + i, Color(color, color.a * fade))


## 斜線填充（警示條紋）：stripe 為條紋寬，angle 固定 45 度。
func diagonal_stripes(x: int, y: int, w: int, h: int, a: Color, b: Color, stripe := 8) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var band := int(floor(float(xx + yy) / float(stripe))) % 2
			px(xx, yy, a if band == 0 else b)


## 磚牆：rows 列、每列錯位。
func bricks(x0: int, y0: int, w: int, h: int, brick_w: int, brick_h: int, colors: Array[Color], mortar: Color, gap := 2) -> void:
	rect(x0, y0, w, h, mortar)
	var row := 0
	var y := y0
	while y < y0 + h:
		var offset := 0 if row % 2 == 0 else brick_w / 2
		var x := x0 - offset
		var index := 0
		while x < x0 + w:
			var c := colors[int(noise(x + 31, y + 17, 5) * colors.size()) % colors.size()]
			var bw := brick_w - gap
			var bh := mini(brick_h - gap, y0 + h - y)
			rect(maxi(x, x0), y, mini(x + bw, x0 + w) - maxi(x, x0), bh, c)
			rect(maxi(x, x0), y, mini(x + bw, x0 + w) - maxi(x, x0), 1, c.lightened(0.1))
			x += brick_w
			index += 1
		y += brick_h
		row += 1


## 瓦楞（垂直）。
func corrugation(x0: int, y0: int, w: int, h: int, period: int, base: Color, light := 0.07, dark := 0.1) -> void:
	for x in range(x0, x0 + w):
		var phase := float((x - x0) % period) / float(period)
		var c := base
		if phase < 0.25:
			c = base.lightened(light)
		elif phase > 0.6:
			c = base.darkened(dark)
		rect(x, y0, 1, h, c)


## 窗格：外框 + 玻璃 + 十字窗框。lit 為 true 時玻璃顏色用 glass_lit。
func window(x: int, y: int, w: int, h: int, frame_color: Color, glass: Color, mullion := true) -> void:
	rect(x, y, w, h, frame_color)
	rect(x + 2, y + 2, w - 4, h - 4, glass)
	if mullion:
		vline(x + w / 2 - 1, frame_color, y + 2, y + h - 2, 2)
		hline(y + h / 2 - 1, frame_color, x + 2, x + w - 2, 2)
	hline(y + h - 3, frame_color.lightened(0.1), x, x + w, 1)


## 柔光團（用於 glow 圖層：窗光暈、霓虹光暈）。
func glow_blob(cx: float, cy: float, radius: float, color: Color, strength := 0.6) -> void:
	for yy in range(int(cy - radius), int(cy + radius) + 1):
		for xx in range(int(cx - radius), int(cx + radius) + 1):
			var d := Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() / radius
			if d <= 1.0:
				var a := pow(1.0 - d, 2.0) * strength
				px(xx, yy, Color(color, a * color.a))


## 圖層左右鏡射（讓側邊貼圖左右對稱）。
func mirror_x() -> void:
	for y in height():
		for x in width() / 2:
			var a := image.get_pixel(x, y)
			var b := image.get_pixel(width() - 1 - x, y)
			image.set_pixel(width() - 1 - x, y, a)
			image.set_pixel(x, y, b)


## 讓畫面四周變暗（立面、道具的立體感）。
func vignette(amount := 0.2) -> void:
	for y in height():
		for x in width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var dx := absf(float(x) / float(width()) - 0.5) * 2.0
			var dy := absf(float(y) / float(height()) - 0.5) * 2.0
			var k := 1.0 - amount * maxf(dx, dy) * maxf(dx, dy)
			image.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, c.a))
