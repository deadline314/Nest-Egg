class_name BackdropPainter
extends RefCounted
## 背景層（遠景天際線、中景建築、近景前景）的程式繪製（暫代美術）。
## 背景離鏡頭遠、又會被霧與雨蓋住，所以用 2 倍解析度（其他環境元件是 4 倍），避免整條貼圖吃掉太多記憶體。
## 每張貼圖的寬度是 640 邏輯像素（可左右無縫平鋪），附 `_glow.png`（窗光，自發光）。

const SCALE := 2
const WIDTH := 640 * SCALE

## id, 高度（邏輯像素）, 繪製函式
const CATALOG: Array[Dictionary] = [
	{"id": "far_skyline", "height": 200, "painter": "far"},
	{"id": "mid_buildings", "height": 220, "painter": "mid"},
	{"id": "near_foreground", "height": 150, "painter": "near"},
]

const LIT: Array[Color] = [Color("ffd070"), Color("6fe0ff"), Color("ff7ab0"), Color("ffb066")]


static func paint(spec: Dictionary) -> Dictionary:
	var h := int(spec["height"]) * SCALE
	var seed_value := absi(str(spec["id"]).hash())
	var c := EnvCanvas.new(WIDTH, h, seed_value)
	var g := EnvCanvas.new(WIDTH, h, seed_value + 1)
	match str(spec["painter"]):
		"far":
			_far(c, g)
		"mid":
			_mid(c, g)
		_:
			_near(c, g)
	return {"diffuse": c, "glow": g}


static func _rng(c: EnvCanvas, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = c.seed_value + salt
	return rng


## 把整條貼圖拼成可平鋪：建築寬度加總剛好等於 WIDTH（最後一棟補滿）。
static func _row(c: EnvCanvas, g: EnvCanvas, rng: RandomNumberGenerator, base: Color, min_h: int, max_h: int,
		min_w: int, max_w: int, window_density: float, with_roof_details: bool) -> void:
	var x := 0
	var h := c.height()
	while x < WIDTH:
		var w := rng.randi_range(min_w, max_w)
		if WIDTH - (x + w) < min_w:
			w = WIDTH - x
		var bh := rng.randi_range(min_h, max_h)
		var top := h - bh
		var shade := base.lightened(rng.randf_range(-0.02, 0.04))
		c.rect(x, top, w, bh, shade)
		c.rect(x, top, w, 2, shade.lightened(0.12))
		c.rect(x + w - 2, top, 2, bh, shade.darkened(0.2))
		if window_density > 0.0:
			var wy := top + 8
			while wy < h - 6:
				var wx := x + 6
				while wx < x + w - 8:
					if rng.randf() < window_density:
						var color: Color = LIT[rng.randi() % LIT.size()]
						g.rect(wx, wy, 4, 5, Color(color, 0.95))
					wx += 10
				wy += 12
		if with_roof_details and rng.randf() < 0.5:
			c.rect(x + w / 4, top - 10, 3, 10, shade.darkened(0.1))
			c.rect(x + w / 2, top - 6, w / 6, 6, shade.lightened(0.05))
		x += w


static func _far(c: EnvCanvas, g: EnvCanvas) -> void:
	var rng := _rng(c, 1)
	_row(c, g, rng, Color("141028"), 60, 180, 36, 70, 0.22, false)
	# 遠景霧：下方偏亮，與近處拉開層次。
	for y in range(c.height() - 60, c.height()):
		var a := float(y - (c.height() - 60)) / 60.0 * 0.25
		c.hline(y, Color(0.35, 0.18, 0.4, a), 0, -1, 1)


static func _mid(c: EnvCanvas, g: EnvCanvas) -> void:
	var rng := _rng(c, 2)
	_row(c, g, rng, Color("1a1630"), 90, 200, 56, 110, 0.3, true)
	# 招牌與水塔剪影
	for i in 5:
		var x := rng.randi_range(40, WIDTH - 80)
		var y := rng.randi_range(c.height() - 170, c.height() - 70)
		var color: Color = [Color("ff2e88"), Color("35e0ff"), Color("ffd23f")][i % 3]
		c.rect(x, y, 10, 36, Color("14102a"))
		g.rect(x + 2, y + 2, 6, 32, Color(color, 0.9))


static func _near(c: EnvCanvas, g: EnvCanvas) -> void:
	var rng := _rng(c, 3)
	var dark := Color("0c0a18")
	# 電線桿、管線與低矮屋頂的剪影（最暗，蓋在最前面）。
	var x := 0
	while x < WIDTH:
		var w := rng.randi_range(90, 200)
		if WIDTH - (x + w) < 90:
			w = WIDTH - x
		var bh := rng.randi_range(30, 80)
		c.rect(x, c.height() - bh, w, bh, dark)
		if rng.randf() < 0.6:
			c.rect(x + w / 3, c.height() - bh - 22, 4, 22, dark)
			c.hline(c.height() - bh - 18, dark, x + w / 3 - 12, x + w / 3 + 16, 3)
		x += w
	for p in [90, 330, 560, 880, 1100]:
		c.rect(p, 20, 6, c.height() - 20, dark)
		c.hline(34, dark, p - 20, p + 26, 4)
		c.hline(54, dark, p - 14, p + 20, 3)
	for i in 4:
		var x0 := i * 340
		c.line(Vector2i(x0, 40), Vector2i(x0 + 170, 66), dark)
		c.line(Vector2i(x0 + 170, 66), Vector2i(x0 + 340, 40), dark)
