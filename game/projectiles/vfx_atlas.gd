class_name VfxAtlas
extends RefCounted
## 特效用的柔邊貼圖圖集（程式生成，不需要美術檔）：一張圖裡 8 格，所有粒子共用同一張貼圖，所以整個粒子場是一次批次繪製。
## 格子：GLOW 光暈（柔邊圓）、PUFF_A／PUFF_B 煙團（雜訊邊緣，兩種形狀）、STREAK 火花拖尾（橫向膠囊，頭亮尾淡）、
##       RING 衝擊環（細環加柔邊）、SHARD 碎片（不規則多邊形加亮邊）、FLARE 星芒（十字光芒）、EMBER 餘燼（小亮點加光暈）。
## 每格 64×64，圖集 256×128。貼圖是白色加透明度，顏色由粒子的調色決定。

enum Cell { GLOW, PUFF_A, PUFF_B, STREAK, RING, SHARD, FLARE, EMBER }

const CELL := 64
const COLUMNS := 4

static var _texture: ImageTexture
static var _noise: ImageTexture


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_build())
	return _texture


## 可平鋪的雜訊貼圖（燒融 shader 用）：128×128，灰階，值分布平均。
static func noise_texture() -> ImageTexture:
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.seed = 5
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		noise.frequency = 0.03
		var image := noise.get_seamless_image(128, 128, false, false, 0.15)
		image.convert(Image.FORMAT_L8)
		# 把值拉開到 0~1（雜訊原本集中在中間），燒融的進度才會接近線性。
		var low := 1.0
		var high := 0.0
		for y in 128:
			for x in 128:
				var v := image.get_pixel(x, y).r
				low = minf(low, v)
				high = maxf(high, v)
		for y in 128:
			for x in 128:
				var v := (image.get_pixel(x, y).r - low) / maxf(0.001, high - low)
				image.set_pixel(x, y, Color(v, v, v, 1.0))
		_noise = ImageTexture.create_from_image(image)
	return _noise


## 某一格在圖集裡的範圍。
static func region(cell: int) -> Rect2:
	return Rect2(float(cell % COLUMNS * CELL), float(cell / COLUMNS * CELL), float(CELL), float(CELL))


static func _build() -> Image:
	var image := Image.create(CELL * COLUMNS, CELL * 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	_paint_glow(image, Cell.GLOW)
	_paint_puff(image, Cell.PUFF_A, 11)
	_paint_puff(image, Cell.PUFF_B, 47)
	_paint_streak(image, Cell.STREAK)
	_paint_ring(image, Cell.RING)
	_paint_shard(image, Cell.SHARD)
	_paint_flare(image, Cell.FLARE)
	_paint_ember(image, Cell.EMBER)
	return image


static func _put(image: Image, cell: int, x: int, y: int, alpha: float) -> void:
	var origin := region(cell).position
	image.set_pixel(int(origin.x) + x, int(origin.y) + y, Color(1, 1, 1, clampf(alpha, 0.0, 1.0)))


static func _paint_glow(image: Image, cell: int) -> void:
	var c := (CELL - 1) * 0.5
	for y in CELL:
		for x in CELL:
			var d := Vector2(x - c, y - c).length() / c
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			_put(image, cell, x, y, a)


static func _paint_puff(image: Image, cell: int, seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.045
	var c := (CELL - 1) * 0.5
	for y in CELL:
		for x in CELL:
			var d := Vector2(x - c, y - c).length() / c
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# 邊緣被雜訊啃出缺口，中心較實：像一團煙。
			var body := clampf(1.0 - d * (0.78 + 0.5 * (1.0 - n)), 0.0, 1.0)
			_put(image, cell, x, y, smoothstep(0.0, 0.6, body) * (0.55 + 0.45 * n))


static func _paint_streak(image: Image, cell: int) -> void:
	var c := (CELL - 1) * 0.5
	for y in CELL:
		for x in CELL:
			var u := float(x) / float(CELL - 1)  # 0 尾 → 1 頭
			var v := absf(float(y) - c) / c
			var width := lerpf(0.12, 0.55, pow(u, 0.7))
			var edge := clampf(1.0 - v / width, 0.0, 1.0)
			var along := pow(u, 1.6) * (1.0 - smoothstep(0.88, 1.0, u) * 0.5)
			_put(image, cell, x, y, pow(edge, 1.4) * along)


static func _paint_ring(image: Image, cell: int) -> void:
	var c := (CELL - 1) * 0.5
	for y in CELL:
		for x in CELL:
			var d := Vector2(x - c, y - c).length() / c
			var band := exp(-pow((d - 0.82) / 0.07, 2.0))
			var halo := exp(-pow((d - 0.82) / 0.2, 2.0)) * 0.35
			_put(image, cell, x, y, (band + halo) * (1.0 - smoothstep(0.92, 1.0, d)))


static func _paint_shard(image: Image, cell: int) -> void:
	var points := PackedVector2Array([Vector2(6, 34), Vector2(26, 8), Vector2(58, 26), Vector2(44, 56), Vector2(14, 52)])
	for y in CELL:
		for x in CELL:
			var p := Vector2(x, y)
			if not Geometry2D.is_point_in_polygon(p, points):
				continue
			var edge := INF
			for i in points.size():
				var a := points[i]
				var b := points[(i + 1) % points.size()]
				var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
				edge = minf(edge, p.distance_to(closest))
			var shade := 0.62 + 0.38 * (1.0 - float(y) / float(CELL))
			_put(image, cell, x, y, clampf(shade + (1.0 - smoothstep(0.0, 4.0, edge)) * 0.4, 0.0, 1.0))


static func _paint_flare(image: Image, cell: int) -> void:
	var c := (CELL - 1) * 0.5
	for y in CELL:
		for x in CELL:
			var dx := absf(x - c) / c
			var dy := absf(y - c) / c
			var d := Vector2(dx, dy).length()
			var cross := maxf(exp(-pow(dy / 0.07, 2.0)) * (1.0 - dx), exp(-pow(dx / 0.07, 2.0)) * (1.0 - dy))
			var core := pow(clampf(1.0 - d, 0.0, 1.0), 3.0)
			_put(image, cell, x, y, clampf(cross * 0.9 + core, 0.0, 1.0))


static func _paint_ember(image: Image, cell: int) -> void:
	var c := (CELL - 1) * 0.5
	for y in CELL:
		for x in CELL:
			var d := Vector2(x - c, y - c).length() / c
			var core := 1.0 - smoothstep(0.0, 0.22, d)
			var halo := pow(clampf(1.0 - d, 0.0, 1.0), 3.0) * 0.45
			_put(image, cell, x, y, core + halo)
