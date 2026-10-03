class_name FacadePainter
extends RefCounted
## 建築立面的程式繪製（暫代美術）。每種立面輸出：
##   ground（一樓）×2 變化、body（標準樓層）×2 變化、cap（女兒牆）×1，共 5 個模組，
##   每個模組附 glow（窗光與霓虹）。尺寸為 4 倍解析度：寬 256；ground 高 160、body 高 128、cap 高 32。

const W := 256
const GROUND_H := 160
const BODY_H := 128
const CAP_H := 32

const CATALOG: Array[Dictionary] = [
	{"id": "shopfront", "name": "街邊店面", "wall": "232838", "trim": "3a4258", "style": "shop"},
	{"id": "apartment", "name": "老公寓", "wall": "262a38", "trim": "3e445a", "style": "apartment"},
	{"id": "shutter_block", "name": "鐵捲門街屋", "wall": "20242f", "trim": "343a4a", "style": "shutter"},
	{"id": "brick_block", "name": "磚造舊樓", "wall": "3a2a2c", "trim": "55403e", "style": "brick"},
	{"id": "facility_wall", "name": "設施外牆", "wall": "222c3a", "trim": "36485c", "style": "facility"},
	{"id": "warehouse", "name": "貨運倉庫", "wall": "2c3440", "trim": "465264", "style": "warehouse"},
	{"id": "glass_tower", "name": "玻璃大樓", "wall": "18242e", "trim": "2c4252", "style": "tower"},
]

const LIT_COLORS: Array[Color] = [Color("ffd070"), Color("ffb066"), Color("8fe8ff"), Color("ff8ab8")]


## 回傳 {"ground": [[diffuse, glow], ...], "body": [...], "cap": [[diffuse, glow]]}（EnvCanvas）。
static func paint(spec: Dictionary) -> Dictionary:
	var seed_value := absi(str(spec["id"]).hash())
	var wall := Color(str(spec["wall"]))
	var trim := Color(str(spec["trim"]))
	var style := str(spec["style"])
	var result := {"ground": [], "body": [], "cap": []}
	for variant in 2:
		result["ground"].append(_ground(style, variant, wall, trim, seed_value + variant * 7))
		result["body"].append(_body(style, variant, wall, trim, seed_value + variant * 11 + 3))
	result["cap"].append(_cap(style, wall, trim, seed_value + 99))
	return result


static func _canvas_pair(w: int, h: int, seed_value: int) -> Array[EnvCanvas]:
	var diffuse := EnvCanvas.new(w, h, seed_value)
	var glow := EnvCanvas.new(w, h, seed_value + 1)
	return [diffuse, glow]


## 牆面底：依風格不同。
static func _wall_fill(c: EnvCanvas, style: String, wall: Color, trim: Color) -> void:
	match style:
		"brick":
			var colors: Array[Color] = [wall, wall.lightened(0.05), wall.darkened(0.08), trim.darkened(0.2)]
			c.bricks(0, 0, c.width(), c.height(), 32, 16, colors, wall.darkened(0.5), 3)
		"warehouse":
			c.corrugation(0, 0, c.width(), c.height(), 16, wall, 0.07, 0.1)
		"facility":
			c.fill_noise(wall, 0.015)
			c.frame(0, 0, c.width(), c.height(), wall.darkened(0.35), 3)
			c.vline(c.width() / 2, wall.darkened(0.3), 0, -1, 2)
		"tower":
			c.fill_noise(wall, 0.01)
			c.rect_gradient(0, 0, c.width(), c.height(), wall.lightened(0.04), wall.darkened(0.1))
		_:
			c.fill_noise(wall, 0.02)
			c.speckle(0.04, wall.lightened(0.08), 3)
			c.streak(30, 0, c.height() - 10, Color(0, 0, 0, 0.16), 5)
			c.streak(190, 10, c.height() - 30, Color(0, 0, 0, 0.12), 8)


static func _windows(c: EnvCanvas, g: EnvCanvas, y: int, h: int, count: int, wall: Color, trim: Color, style: String, salt: int, lit_chance := 0.45) -> void:
	var gap := (W - count * 80) / (count + 1)
	for i in count:
		var x := gap + i * (80 + gap)
		var lit := c.noise(i * 17, salt, salt) < lit_chance
		var glass := Color("0c1220")
		if style == "tower":
			glass = Color("101c28")
		c.window(x, y, 80, h, trim.darkened(0.2), glass, style != "tower")
		# 窗台
		c.rect(x - 6, y + h, 92, 8, trim)
		c.rect(x - 6, y + h + 8, 92, 3, wall.darkened(0.4))
		if lit:
			var color: Color = LIT_COLORS[int(c.noise(i, salt, salt + 3) * LIT_COLORS.size()) % LIT_COLORS.size()]
			g.rect_gradient(x + 3, y + 3, 74, h - 6, Color(color, 0.8), Color(color.darkened(0.25), 0.6))
			# 窗框與十字窗格不發光，窗光才不會變成一塊平的色塊。
			g.erase(x + 38, y + 3, 4, h - 6)
			g.erase(x + 3, y + h / 2 - 1, 74, 3)
			# 簾子斜影
			g.line(Vector2i(x + 4, y + 4), Vector2i(x + 30, y + h - 6), Color(color.darkened(0.5), 0.5))
			g.line(Vector2i(x + 5, y + 4), Vector2i(x + 31, y + h - 6), Color(color.darkened(0.5), 0.5))
		elif style != "tower":
			c.line(Vector2i(x + 6, y + h - 8), Vector2i(x + 30, y + 8), Color(0.5, 0.6, 0.8, 0.12))
		if style == "apartment" and c.noise(i, salt, 99) < 0.5:
			# 冷氣室外機
			c.bevel(x + 52, y + h + 12, 40, 26, wall.lightened(0.1), 0.06, 0.1, 2)
			for k in 3:
				c.hline(y + h + 18 + k * 6, wall.darkened(0.5), x + 56, x + 88, 2)


static func _ground(style: String, variant: int, wall: Color, trim: Color, seed_value: int) -> Array[EnvCanvas]:
	var pair := _canvas_pair(W, GROUND_H, seed_value)
	var c := pair[0]
	var g := pair[1]
	_wall_fill(c, style, wall, trim)
	c.rect(0, 0, W, 8, trim)
	c.rect(0, 8, W, 3, wall.darkened(0.4))
	c.rect(0, GROUND_H - 8, W, 8, wall.darkened(0.3))
	match style:
		"shop":
			_shop_ground(c, g, variant, wall, trim)
		"apartment":
			_door_ground(c, g, variant, wall, trim, true)
		"shutter":
			_shutter_ground(c, g, variant, wall, trim)
		"brick":
			_door_ground(c, g, variant, wall, trim, false)
		"facility":
			_facility_ground(c, g, variant, wall, trim)
		"warehouse":
			_warehouse_ground(c, g, variant, wall, trim)
		"tower":
			_tower_ground(c, g, variant, wall, trim)
	return pair


static func _shop_ground(c: EnvCanvas, g: EnvCanvas, variant: int, wall: Color, trim: Color) -> void:
	var glow_color := Color("ffb066") if variant == 0 else Color("6ff0c0")
	# 招牌帶
	c.bevel(16, 16, 224, 28, trim.darkened(0.3), 0.05, 0.1, 2)
	for i in 6:
		g.rect(28 + i * 34, 24, 22, 12, Color(glow_color, 0.9 if (i + variant) % 3 != 0 else 0.35))
	# 玻璃店面
	c.rect(16, 52, 224, 96, trim.darkened(0.35))
	c.rect(22, 58, 212, 84, Color("0a1018"))
	g.rect(22, 58, 212, 84, Color(glow_color, 0.55))
	g.rect(22, 112, 212, 30, Color(glow_color, 0.8))
	# 玻璃反光、窗框、貨架剪影
	for i in 4:
		c.vline(22 + i * 53, trim.darkened(0.3), 58, 142, 4)
	for i in 5:
		c.rect(30 + i * 40, 96 + (i % 2) * 8, 24, 16, Color(0, 0, 0, 0.55))
	c.line(Vector2i(34, 140), Vector2i(90, 62), Color(1, 1, 1, 0.07))
	c.line(Vector2i(60, 140), Vector2i(130, 62), Color(1, 1, 1, 0.05))
	# 雨棚
	c.rect(8, 46, 240, 8, trim.lightened(0.04))
	c.rect(8, 54, 240, 4, wall.darkened(0.5))


static func _door_ground(c: EnvCanvas, g: EnvCanvas, variant: int, wall: Color, trim: Color, mailbox: bool) -> void:
	var door_x := 88 if variant == 0 else 112
	c.bevel(door_x - 12, 40, 92, 112, trim.darkened(0.2), 0.05, 0.12, 3)
	c.rect(door_x, 52, 68, 100, Color("0e1420"))
	c.rect(door_x + 4, 56, 28, 90, wall.darkened(0.15))
	c.rect(door_x + 36, 56, 28, 90, wall.darkened(0.15))
	c.rect(door_x + 30, 100, 4, 8, trim.lightened(0.2))
	g.rect(door_x + 2, 40, 64, 8, Color("ffd070", 0.8))
	# 門牌與信箱
	c.rect(door_x + 70, 66, 14, 14, trim.darkened(0.3))
	g.rect(door_x + 72, 68, 10, 10, Color("8fe8ff", 0.7))
	if mailbox:
		for i in 3:
			c.rect(24 + i * 18, 84, 14, 18, trim.darkened(0.15))
			c.rect(26 + i * 18, 88, 10, 3, wall.darkened(0.5))
	# 台階
	c.rect(door_x - 20, 150, 124, 4, wall.lightened(0.1))
	c.rect(0, 40, door_x - 28, 4, trim)
	c.streak(door_x + 80, 60, 70, Color(0, 0, 0, 0.2), 4)


static func _shutter_ground(c: EnvCanvas, g: EnvCanvas, variant: int, wall: Color, trim: Color) -> void:
	c.rect(12, 28, 232, 124, trim.darkened(0.4))
	for y in range(34, 150, 7):
		c.hline(y, wall.lightened(0.04 + float(y % 14) * 0.002), 16, 240, 4)
		c.hline(y + 4, wall.darkened(0.4), 16, 240, 2)
	c.rect(12, 28, 232, 8, trim)
	# 噴漆塗鴉
	var tag := Color("ff2e88") if variant == 0 else Color("35e0ff")
	for i in 6:
		var x := 60 + i * 20
		c.line(Vector2i(x, 90 + (i % 2) * 14), Vector2i(x + 14, 76 + (i % 3) * 8), Color(tag, 0.55))
		c.line(Vector2i(x + 1, 90 + (i % 2) * 14), Vector2i(x + 15, 76 + (i % 3) * 8), Color(tag, 0.35))
	# 警示燈
	c.bevel(214, 12, 20, 14, trim, 0.1, 0.1, 2)
	g.rect(218, 14, 12, 8, Color("ff6a3a", 0.9))
	c.rect(120, 130, 16, 6, trim.lightened(0.15))


static func _facility_ground(c: EnvCanvas, g: EnvCanvas, variant: int, wall: Color, trim: Color) -> void:
	c.bevel(48, 28, 160, 124, wall.darkened(0.2), 0.04, 0.12, 4)
	c.diagonal_stripes(48, 132, 160, 20, Color("ffc94a").darkened(0.35), wall.darkened(0.4), 14)
	c.rect(124, 28, 8, 104, wall.darkened(0.5))
	g.rect(124, 34, 8, 92, Color("35e0ff", 0.55))
	for y in [50, 80, 110]:
		c.rivet(64, y, wall, 3)
		c.rivet(192, y, wall, 3)
	# 讀卡機
	c.bevel(26, 70, 16, 28, trim, 0.1, 0.1, 2)
	g.rect(30, 76, 8, 6, Color("3dffa0", 0.95) if variant == 0 else Color("ff5a4f", 0.95))
	g.rect(30, 86, 8, 3, Color("35e0ff", 0.7))
	c.rect(0, 20, W, 6, trim)
	g.rect(0, 22, W, 2, Color("35e0ff", 0.5))


static func _warehouse_ground(c: EnvCanvas, g: EnvCanvas, variant: int, wall: Color, trim: Color) -> void:
	c.bevel(24, 16, 208, 136, wall.darkened(0.25), 0.04, 0.12, 4)
	c.corrugation(32, 24, 192, 120, 12, wall.darkened(0.15), 0.06, 0.1)
	c.diagonal_stripes(24, 136, 208, 16, Color("ffc94a").darkened(0.2), wall.darkened(0.5), 14)
	c.vline(126, wall.darkened(0.5), 24, 136, 4)
	g.rect(100, 6, 56, 6, Color("ffc94a", 0.9) if variant == 0 else Color("ff6a3a", 0.9))
	c.bevel(100, 4, 56, 10, trim, 0.1, 0.1, 2)
	c.rect(0, 148, W, 12, wall.darkened(0.3))


static func _tower_ground(c: EnvCanvas, g: EnvCanvas, variant: int, wall: Color, trim: Color) -> void:
	c.rect(8, 24, 240, 128, trim.darkened(0.3))
	for i in 4:
		var x := 14 + i * 58
		c.rect(x, 30, 52, 116, Color("0a141c"))
		c.rect_gradient(x, 30, 52, 116, Color("14283a"), Color("0a141c"))
		c.line(Vector2i(x + 6, 140), Vector2i(x + 40, 36), Color(0.6, 0.85, 1, 0.1))
	g.rect(8, 22, 240, 3, Color("35e0ff", 0.8))
	g.rect(8, 150, 240, 2, Color("35e0ff", 0.3))
	if variant == 1:
		g.rect(118, 60, 20, 4, Color("ff2e88", 0.9))


static func _body(style: String, variant: int, wall: Color, trim: Color, seed_value: int) -> Array[EnvCanvas]:
	var pair := _canvas_pair(W, BODY_H, seed_value)
	var c := pair[0]
	var g := pair[1]
	_wall_fill(c, style, wall, trim)
	c.rect(0, 0, W, 4, wall.lightened(0.05))
	match style:
		"facility":
			c.rect(24, 28, 208, 72, wall.darkened(0.1))
			c.frame(24, 28, 208, 72, wall.darkened(0.45), 3)
			for i in 6:
				c.rect(40 + i * 12, 40, 6, 48, wall.darkened(0.55))
			g.rect(150, 44, 64, 4, Color("35e0ff", 0.6))
			g.rect(150, 56, 40, 3, Color("35e0ff", 0.4))
			if variant == 1:
				g.rect(150, 70, 52, 3, Color("ff5a4f", 0.8))
		"warehouse":
			c.bevel(72, 36, 112, 56, wall.darkened(0.1), 0.05, 0.1, 3)
			c.diagonal_stripes(72, 80, 112, 12, Color("ffc94a").darkened(0.3), wall.darkened(0.5), 12)
			g.rect(118, 46, 20, 6, Color("ffc94a", 0.7))
		"tower":
			c.vline(0, wall.lightened(0.15), 0, -1, 3)
			c.vline(W / 2, wall.darkened(0.4), 0, -1, 3)
			for r in 2:
				c.hline(32 + r * 48, wall.darkened(0.45), 0, -1, 3)
				g.rect(0, 33 + r * 48, W, 1, Color("35e0ff", 0.25))
			if variant == 1:
				g.rect(96, 56, 64, 6, Color("ff2e88", 0.55))
		_:
			_windows(c, g, 24, 72, 2, wall, trim, style, seed_value, 0.45 if variant == 0 else 0.6)
	return pair


static func _cap(style: String, wall: Color, trim: Color, seed_value: int) -> Array[EnvCanvas]:
	var pair := _canvas_pair(W, CAP_H, seed_value)
	var c := pair[0]
	var g := pair[1]
	c.rect(0, 0, W, CAP_H, trim)
	c.rect(0, 0, W, 8, trim.lightened(0.12))
	c.rect(0, 8, W, 3, trim.lightened(0.04))
	c.rect(0, CAP_H - 8, W, 8, wall.darkened(0.45))
	c.speckle(0.05, trim.lightened(0.2), 4)
	if style == "facility" or style == "tower":
		g.rect(0, 10, W, 2, Color("35e0ff", 0.55))
	if style == "warehouse":
		c.diagonal_stripes(0, 12, W, 6, Color("ffc94a").darkened(0.35), wall.darkened(0.5), 12)
	return pair
