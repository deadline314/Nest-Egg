class_name AmmoIconPainter
extends RefCounted
## 彈種圖示的程式繪製（暫代美術）：每個圖示 40×56 像素（HUD 縮成 10×14，4 倍解析度），三種狀態：
##   滿（彩色）、空（只剩輪廓的空槽）、低（偏紅）。要換成手繪，只要覆蓋同名 PNG。

const SIZE := Vector2i(40, 56)
const BRASS := Color("d9b24a")
const COPPER := Color("c8743a")
const STEEL := Color("aab4c0")

## id、顯示名稱（預覽用）
const CATALOG: Array[Dictionary] = [
	{"id": "pistol", "name": "手槍彈", "painter": "pistol"},
	{"id": "smg", "name": "衝鋒槍彈", "painter": "smg"},
	{"id": "rifle", "name": "步槍彈", "painter": "rifle"},
	{"id": "shell", "name": "霰彈", "painter": "shell"},
	{"id": "grenade", "name": "榴彈", "painter": "grenade"},
	{"id": "rail", "name": "電磁軌道彈", "painter": "rail"},
	{"id": "energy", "name": "能量電池", "painter": "energy"},
	{"id": "laser", "name": "雷射電池", "painter": "laser"},
	{"id": "mech", "name": "機甲砲彈", "painter": "mech"},
]


## 回傳 {"full": EnvCanvas, "empty": EnvCanvas, "low": EnvCanvas}。
static func paint(spec: Dictionary) -> Dictionary:
	var c := EnvCanvas.new(SIZE.x, SIZE.y, absi(str(spec["id"]).hash()))
	var callable := Callable(AmmoIconPainter, "_p_" + str(spec["painter"]))
	callable.call(c)
	c.outline(Color(0.02, 0.03, 0.05, 1.0))
	return {"full": c, "empty": _empty_from(c), "low": _low_from(c)}


# ---- 共用零件 ---------------------------------------------------------------

## 圓柱的明暗：左亮右暗。
static func _cylinder(c: EnvCanvas, x: int, y: int, w: int, h: int, base: Color) -> void:
	c.rect(x, y, w, h, base)
	c.rect(x, y, maxi(2, w / 4), h, base.lightened(0.28))
	c.rect(x + maxi(2, w / 4), y, maxi(2, w / 6), h, base.lightened(0.1))
	c.rect(x + w - maxi(3, w / 4), y, maxi(3, w / 4), h, base.darkened(0.3))


static func _casing_base(c: EnvCanvas, x: int, y: int, w: int, h: int) -> void:
	_cylinder(c, x, y, w, h, BRASS)
	c.rect(x - 1, y + h - 5, w + 2, 5, BRASS.darkened(0.25))
	c.rect(x - 1, y + h - 5, w + 2, 1, BRASS.lightened(0.2))
	c.circle(x + w * 0.5, y + h - 9.0, float(w) * 0.16, BRASS.darkened(0.45))


static func _round_tip(c: EnvCanvas, x: int, y: int, w: int, h: int, base: Color) -> void:
	c.rect(x, y + h / 2, w, h - h / 2, base)
	c.ellipse(x + w * 0.5, y + h * 0.5, w * 0.5, h * 0.5, base)
	c.rect(x, y + h / 2, maxi(2, w / 4), h - h / 2, base.lightened(0.28))
	c.rect(x + w - maxi(3, w / 4), y + h / 2, maxi(3, w / 4), h - h / 2, base.darkened(0.3))
	c.ellipse(x + w * 0.35, y + h * 0.4, w * 0.12, h * 0.16, base.lightened(0.45))


static func _p_pistol(c: EnvCanvas) -> void:
	_casing_base(c, 11, 26, 18, 26)
	_round_tip(c, 11, 8, 18, 20, COPPER)
	c.rect(11, 26, 18, 2, COPPER.darkened(0.35))


static func _p_smg(c: EnvCanvas) -> void:
	_casing_base(c, 13, 24, 14, 28)
	_round_tip(c, 13, 6, 14, 20, STEEL)
	c.rect(13, 22, 14, 3, COPPER)


static func _p_rifle(c: EnvCanvas) -> void:
	# 瓶頸彈殼：寬的底、斜肩、窄的頸，加上尖頭彈頭。
	_cylinder(c, 10, 34, 20, 18, BRASS)
	c.polygon(PackedVector2Array([Vector2(10, 34), Vector2(30, 34), Vector2(26, 24), Vector2(14, 24)]), BRASS.darkened(0.05))
	_cylinder(c, 14, 24, 12, 10, BRASS)
	c.rect(9, 47, 22, 5, BRASS.darkened(0.25))
	c.circle(20.0, 44.0, 3.0, BRASS.darkened(0.45))
	c.polygon(PackedVector2Array([Vector2(14, 24), Vector2(26, 24), Vector2(23, 10), Vector2(20, 3), Vector2(17, 10)]), STEEL)
	c.polygon(PackedVector2Array([Vector2(14, 24), Vector2(18, 24), Vector2(18, 8), Vector2(17, 10)]), STEEL.lightened(0.3))
	c.polygon(PackedVector2Array([Vector2(26, 24), Vector2(22, 24), Vector2(21, 8), Vector2(23, 10)]), STEEL.darkened(0.3))
	c.polygon(PackedVector2Array([Vector2(18, 10), Vector2(22, 10), Vector2(20, 3)]), COPPER)


static func _p_shell(c: EnvCanvas) -> void:
	var red := Color("c8352c")
	_cylinder(c, 8, 8, 24, 38, red)
	c.rect(8, 8, 24, 3, red.darkened(0.35))
	for x in [11, 16, 21, 26]:
		c.rect(x, 8, 1, 4, red.darkened(0.55))
	_casing_base(c, 8, 38, 24, 14)
	c.rect(8, 36, 24, 3, BRASS.darkened(0.2))


static func _p_grenade(c: EnvCanvas) -> void:
	var olive := Color("6c7c3c")
	_cylinder(c, 8, 16, 24, 30, olive)
	c.polygon(PackedVector2Array([Vector2(8, 16), Vector2(32, 16), Vector2(28, 8), Vector2(20, 3), Vector2(12, 8)]), Color("e0732a"))
	c.polygon(PackedVector2Array([Vector2(8, 16), Vector2(13, 16), Vector2(13, 8), Vector2(12, 8)]), Color("ffa05a"))
	c.rect(8, 30, 24, 4, Color("f0c030"))
	c.rect(8, 38, 24, 2, olive.darkened(0.4))
	_casing_base(c, 9, 44, 22, 8)


static func _p_rail(c: EnvCanvas) -> void:
	var cyan := Color("45e0ff")
	c.polygon(PackedVector2Array([Vector2(16, 14), Vector2(24, 14), Vector2(22, 4), Vector2(20, 2), Vector2(18, 4)]), cyan.lightened(0.3))
	_cylinder(c, 16, 14, 8, 36, Color("7aa0b8"))
	c.rect(19, 14, 2, 36, cyan.lightened(0.5))
	c.polygon(PackedVector2Array([Vector2(16, 38), Vector2(8, 52), Vector2(16, 50)]), Color("5a7c90"))
	c.polygon(PackedVector2Array([Vector2(24, 38), Vector2(32, 52), Vector2(24, 50)]), Color("3a5a6c"))
	c.rect(15, 24, 10, 3, cyan)
	c.rect(15, 32, 10, 3, cyan)


static func _p_energy(c: EnvCanvas) -> void:
	var body := Color("27323f")
	c.rect(16, 4, 8, 6, STEEL)
	c.rect(10, 10, 20, 42, body)
	c.rect(10, 10, 4, 42, body.lightened(0.18))
	c.rect(26, 10, 4, 42, body.darkened(0.3))
	c.rect(10, 16, 20, 4, Color("ffd23f"))
	c.rect(10, 44, 20, 4, Color("ffd23f"))
	c.polygon(PackedVector2Array([Vector2(22, 22), Vector2(14, 33), Vector2(20, 33), Vector2(17, 42), Vector2(27, 29), Vector2(21, 29)]), Color("fff0a0"))


static func _p_laser(c: EnvCanvas) -> void:
	c.rect(12, 4, 16, 6, STEEL)
	c.rect(12, 48, 16, 5, STEEL.darkened(0.2))
	_cylinder(c, 11, 10, 18, 38, Color("5a2f8a"))
	c.rect(15, 14, 10, 30, Color("c48bff"))
	c.rect(17, 14, 6, 30, Color("f0d8ff"))
	c.rect(11, 22, 18, 2, Color("2e1850"))
	c.rect(11, 34, 18, 2, Color("2e1850"))


static func _p_mech(c: EnvCanvas) -> void:
	var steel := Color("48525e")
	_cylinder(c, 6, 14, 28, 36, steel)
	c.polygon(PackedVector2Array([Vector2(6, 14), Vector2(34, 14), Vector2(30, 8), Vector2(24, 3), Vector2(16, 3), Vector2(10, 8)]), Color("e8742a"))
	c.polygon(PackedVector2Array([Vector2(6, 14), Vector2(12, 14), Vector2(12, 7), Vector2(10, 8)]), Color("ffa860"))
	c.rect(6, 26, 28, 6, Color("ffc94a"))
	c.diagonal_stripes(6, 26, 28, 6, Color("ffc94a"), Color("2a323c"), 6)
	_casing_base(c, 7, 46, 26, 8)


# ---- 狀態 -----------------------------------------------------------------

## 空槽：只剩半透明暗色剪影與一圈細邊。
static func _empty_from(source: EnvCanvas) -> EnvCanvas:
	var result := EnvCanvas.new(SIZE.x, SIZE.y, source.seed_value)
	for y in SIZE.y:
		for x in SIZE.x:
			var a := source.image.get_pixel(x, y)
			if a.a <= 0.0:
				continue
			# 用原本的亮度做一點起伏，空槽才看得出原本的形狀。
			var shade := 0.10 + LightKit.luminance(a) * 0.14
			result.image.set_pixel(x, y, Color(shade * 0.9, shade, shade * 1.15, 0.55))
	var rim := Color(0.66, 0.76, 0.9, 0.95)
	var marks: Array[Vector2i] = []
	for y in SIZE.y:
		for x in SIZE.x:
			if source.image.get_pixel(x, y).a > 0.0:
				var edge := false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := x + d.x
					var ny := y + d.y
					if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y or source.image.get_pixel(nx, ny).a <= 0.0:
						edge = true
				if edge:
					marks.append(Vector2i(x, y))
	for p in marks:
		result.image.set_pixelv(p, rim)
	return result


## 彈量低：偏紅、對比拉高。
static func _low_from(source: EnvCanvas) -> EnvCanvas:
	var result := EnvCanvas.new(SIZE.x, SIZE.y, source.seed_value)
	for y in SIZE.y:
		for x in SIZE.x:
			var c := source.image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l := LightKit.luminance(c)
			result.image.set_pixel(x, y, Color(clampf(0.35 + l * 1.15, 0.0, 1.0), clampf(l * 0.28, 0.0, 1.0), clampf(l * 0.24, 0.0, 1.0), c.a))
	return result
