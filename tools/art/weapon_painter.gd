class_name WeaponPainter
extends RefCounted
## 武器外觀的程式繪製（暫代美術）。槍口朝右；依 weapons.json 的 grip／foregrip／muzzle 擺放。

const K := preload("res://tools/art/painter_kit.gd")
const O := Color("07080d")
const METAL := Color("2c323d")
const METAL_LIGHT := Color("5d6878")
const ACCENTS := {
	"rifle": Color("2ef2ff"), "shotgun": Color("ffb347"), "railgun": Color("c28bff"), "smg": Color("ff7a1a"),
	"launcher": Color("ffa31a"), "pistol": Color("ffd000"), "minigun": Color("ff2a3d"), "laser": Color("ff2e88"),
}


static func paint(c: CanvasItem, def: Dictionary, glow: bool) -> void:
	var style := str(def.get("style", "rifle"))
	var grip := _v(def.get("grip"))
	var muzzle := _v(def.get("muzzle"))
	var accent: Color = ACCENTS.get(style, Color("2ef2ff"))
	var top := muzzle.y - 5.0
	var bottom := grip.y + 1.0
	var heavy := style in ["launcher", "minigun", "shotgun"]
	if not glow:
		# 握把
		K.grad_poly(c, K.pts([grip.x - 5, grip.y - 4, grip.x + 4, grip.y - 4, grip.x + 2, grip.y + 10, grip.x - 7, grip.y + 9]),
				METAL.darkened(0.3), METAL, Vector2.RIGHT, O, 2.0)
		# 槍身
		var body_end := muzzle.x - (14.0 if style != "pistol" else 6.0)
		K.grad_poly(c, K.pts([grip.x - 22, top + 2, body_end, top, body_end + 2, bottom - 3, grip.x - 18, bottom]),
				METAL.darkened(0.2), METAL_LIGHT, Vector2(0, -1), O, 2.0)
		# 槍管
		var barrel_h := 6.0 if heavy else 4.0
		K.grad_poly(c, K.pts([body_end - 2, muzzle.y - barrel_h * 0.5, muzzle.x, muzzle.y - barrel_h * 0.5, muzzle.x, muzzle.y + barrel_h * 0.5, body_end - 2, muzzle.y + barrel_h * 0.5]),
				METAL_LIGHT.darkened(0.2), METAL_LIGHT.lightened(0.2), Vector2(0, -1), O, 1.5)
		if style == "minigun":
			for i in 3:
				K.line(c, K.pts([body_end - 2, muzzle.y - 4 + i * 4, muzzle.x, muzzle.y - 4 + i * 4]), O, 1.0)
		# 槍托（手槍與發射器沒有）
		if style in ["rifle", "railgun", "smg", "shotgun", "laser"]:
			K.grad_poly(c, K.pts([grip.x - 22, top + 3, grip.x - 30, top + 5, grip.x - 30, bottom + 2, grip.x - 20, bottom]),
					METAL.darkened(0.35), METAL, Vector2.RIGHT, O, 2.0)
		# 瞄具與彈匣
		K.poly(c, K.pts([grip.x + 4, top - 4, grip.x + 16, top - 4, grip.x + 16, top + 1, grip.x + 4, top + 1]), Color("1b1f27"), O, 1.5)
		if style in ["rifle", "smg", "railgun", "laser"]:
			K.poly(c, K.pts([grip.x + 8, bottom - 2, grip.x + 16, bottom - 2, grip.x + 14, bottom + 10, grip.x + 7, bottom + 9]), METAL.darkened(0.2), O, 1.5)
		if style == "launcher":
			K.poly(c, K.ellipse(Vector2(grip.x + 18, (top + bottom) * 0.5), 9.0, 8.0, 16), METAL.darkened(0.25), O, 2.0)
		K.line(c, K.pts([grip.x - 18, top + 3, body_end - 4, top + 1]), Color(1, 1, 1, 0.35), 1.2)
	# 自發光：側面霓虹線、瞄具光點、槍口環
	var line_color := accent if not glow else accent.lightened(0.2)
	K.line(c, K.pts([grip.x - 14, (top + bottom) * 0.5, muzzle.x - 16, (top + bottom) * 0.5 - 1]), line_color, 1.5)
	c.draw_circle(Vector2(grip.x + 14, top - 1.5), 1.3, line_color)
	if style == "laser":
		# 能量槍：槍口的聚焦鏡片與兩段散熱鰭片。
		c.draw_circle(Vector2(muzzle.x - 3, muzzle.y), 3.0, line_color)
		for i in 2:
			K.line(c, K.pts([muzzle.x - 26 + i * 8, muzzle.y - 5, muzzle.x - 26 + i * 8, muzzle.y + 5]), line_color, 1.5)
	if style == "railgun":
		for i in 4:
			c.draw_circle(Vector2(muzzle.x - 30 + i * 6, muzzle.y), 1.4, line_color)


static func _v(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
