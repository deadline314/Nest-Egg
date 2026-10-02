class_name PortraitPainter
extends RefCounted
## 對話頭像的程式繪製（暫代美術，128×128，透明背景，臉朝右）。
## 正式美術以同尺寸 PNG 覆蓋 art/portraits/<角色>.png 即可。

const K := preload("res://tools/art/painter_kit.gd")
const SIZE := Vector2(128, 128)
const O := Color("07080d")
const W := 2.5

var c: CanvasItem


func paint(canvas: CanvasItem, id: String) -> void:
	c = canvas
	match id:
		"rin": _rin()
		"mei": _mei()
		"old_k": _old_k()
		"warden": _warden()
		"system": _system()
		_: push_warning("[PortraitPainter] 沒有 %s 的頭像" % id)


func _p(values: Array) -> PackedVector2Array:
	return K.pts(values)


func _head(skin: Color, center: Vector2, rx: float, ry: float) -> void:
	var shape := K.ellipse(center, rx, ry, 20, PI, TAU)
	shape.append_array(_p([center.x + rx, center.y + 6, center.x + rx - 4, center.y + ry * 0.75, center.x + 8, center.y + ry + 6,
			center.x - 8, center.y + ry + 2, center.x - rx + 4, center.y + ry * 0.4]))
	K.grad_poly(c, shape, skin.darkened(0.2), skin.lightened(0.08), Vector2.RIGHT, O, W)


func _eye(at: Vector2, iris: Color, glow := false) -> void:
	K.poly(c, _p([at.x - 8, at.y - 2, at.x + 7, at.y - 4, at.x + 9, at.y + 3, at.x - 6, at.y + 4]), Color("f4f7ff"))
	c.draw_circle(at + Vector2(2, 0), 4.2, iris.lightened(0.2) if glow else iris)
	c.draw_circle(at + Vector2(2, 0), 1.8, Color("0a0c14"))
	c.draw_circle(at + Vector2(3.5, -1.5), 1.2, Color.WHITE)
	K.line(c, _p([at.x - 9, at.y - 3, at.x, at.y - 7, at.x + 10, at.y - 5]), O, 3.0)


func _shoulders(color: Color, trim: Color) -> void:
	var body := _p([10, 128, 18, 104, 40, 94, 84, 94, 108, 104, 118, 128])
	K.grad_poly(c, body, color.darkened(0.3), color.lightened(0.1), Vector2.RIGHT, O, W)
	K.line(c, _p([40, 96, 54, 128]), trim, 2.0)
	K.line(c, _p([84, 96, 72, 128]), trim, 2.0)


func _rin() -> void:
	_shoulders(Color("1a2232"), Color("2ef2ff"))
	K.poly(c, _p([52, 82, 74, 82, 74, 98, 52, 98]), Color("e6c2b2"), O, 2.0)
	K.poly(c, _p([50, 90, 76, 90, 76, 95, 50, 95]), Color("12151c"), O, 1.5)
	_head(Color("f2d4c6"), Vector2(64, 54), 30, 32)
	c.draw_circle(Vector2(80, 70), 5.0, Color(1.0, 0.45, 0.5, 0.25))
	_eye(Vector2(78, 54), Color("2ef2ff"), true)
	K.line(c, _p([60, 74, 70, 76, 74, 80]), Color("2ef2ff"), 2.0)
	K.line(c, _p([88, 64, 90, 69, 87, 70]), Color("c79a8a"), 1.5)
	K.line(c, _p([78, 82, 84, 81]), Color("7a3a44"), 2.0)
	# 頭髮：白色短鮑伯＋洋紅髮尾
	var hair := _p([30, 66, 26, 40, 36, 20, 56, 12, 80, 14, 96, 26, 100, 40, 98, 46, 93, 38, 89, 46, 84, 36, 79, 44, 74, 34, 64, 38, 50, 34, 44, 52, 38, 74])
	K.grad_poly(c, hair, Color("c9d2e2"), Color("f4f7ff"), Vector2(0.3, -1), O, W)
	for tri: Array in [[98, 46, 93, 38, 99, 39], [89, 46, 84, 36, 90, 40], [79, 44, 74, 34, 80, 37], [38, 74, 44, 52, 33, 62]]:
		K.poly(c, _p(tri), Color("ff3fa4"))
	K.line(c, _p([44, 26, 58, 18, 76, 18]), Color(1, 1, 1, 0.8), 3.0)
	K.poly(c, _p([50, 28, 60, 25, 62, 30, 52, 33]), Color("ffd23f"), O, 1.5)


func _mei() -> void:
	_shoulders(Color("2a1f3d"), Color("a46bff"))
	K.poly(c, _p([52, 82, 74, 82, 74, 98, 52, 98]), Color("d9b8a6"), O, 2.0)
	_head(Color("e8c7b5"), Vector2(64, 54), 29, 31)
	_eye(Vector2(78, 55), Color("6b4b9a"))
	K.line(c, _p([78, 82, 83, 82]), Color("7a3a44"), 2.0)
	# 紫色齊瀏海鮑伯
	var hair := _p([30, 78, 28, 44, 38, 22, 58, 14, 82, 16, 98, 30, 100, 46, 96, 46, 90, 40, 70, 42, 50, 40, 42, 56, 40, 80])
	K.grad_poly(c, hair, Color("4a2c7a"), Color("8a5cd6"), Vector2(0.4, -1), O, W)
	K.line(c, _p([46, 26, 66, 18, 84, 22]), Color(1, 1, 1, 0.45), 3.0)
	# 耳機與麥克風、半透明護目鏡
	K.poly(c, K.ellipse(Vector2(42, 56), 9, 12, 16), Color("1c1a26"), O, 2.0)
	c.draw_circle(Vector2(42, 56), 4.0, Color("a46bff"))
	K.line(c, _p([42, 44, 50, 20, 64, 12]), Color("1c1a26"), 4.0)
	K.line(c, _p([46, 66, 66, 84, 76, 86]), Color("1c1a26"), 2.5)
	c.draw_circle(Vector2(77, 86), 2.5, Color("a46bff"))
	K.poly(c, _p([62, 47, 100, 45, 100, 60, 64, 61]), Color(0.65, 0.42, 1.0, 0.35), O, 2.0)


func _old_k() -> void:
	_shoulders(Color("3a2f24"), Color("ffd23f"))
	# 高領大衣
	K.poly(c, _p([36, 96, 46, 78, 56, 96]), Color("2b221a"), O, 2.0)
	K.poly(c, _p([90, 96, 82, 78, 72, 96]), Color("2b221a"), O, 2.0)
	_head(Color("c99a82"), Vector2(64, 56), 29, 31)
	# 鬍渣、疤痕
	for i in 30:
		var x := 62.0 + (i % 10) * 3.0
		var y := 76.0 + (i / 10) * 3.0
		c.draw_circle(Vector2(x, y), 0.6, Color("6b5244"))
	K.line(c, _p([70, 40, 82, 66]), Color("8f5a4a"), 2.0)
	# 墨鏡（黃色鏡片）
	K.poly(c, _p([62, 48, 100, 46, 100, 58, 66, 60]), Color("2a2410"), O, 2.0)
	K.line(c, _p([66, 50, 96, 48]), Color("ffd23f"), 2.0)
	K.line(c, _p([80, 80, 88, 79]), Color("5a2a2a"), 2.0)
	# 灰色油頭
	var hair := _p([34, 60, 32, 36, 44, 20, 66, 14, 88, 18, 98, 32, 92, 34, 70, 26, 48, 32, 40, 48])
	K.grad_poly(c, hair, Color("5c5f66"), Color("a9adb5"), Vector2(0.4, -1), O, W)
	K.line(c, _p([50, 24, 70, 18, 86, 24]), Color(1, 1, 1, 0.4), 2.0)


func _warden() -> void:
	_shoulders(Color("2a2e37"), Color("ff2a3d"))
	var chrome := Color("c9d1db")
	var head := _p([36, 80, 32, 46, 44, 22, 70, 16, 94, 28, 100, 54, 92, 80, 70, 92, 48, 90])
	K.grad_poly(c, head, chrome.darkened(0.55), chrome.lightened(0.1), Vector2.RIGHT, O, W)
	K.line(c, _p([46, 30, 70, 22, 90, 32]), Color(1, 1, 1, 0.6), 3.0)
	K.poly(c, _p([64, 46, 100, 44, 100, 64, 66, 66]), Color("130608"), O, 2.0)
	c.draw_circle(Vector2(86, 55), 7.0, Color("ff2a3d"))
	c.draw_circle(Vector2(86, 55), 3.0, Color("ffd0d4"))
	K.line(c, _p([40, 60, 60, 66, 62, 86]), chrome.darkened(0.45), 2.0)


func _system() -> void:
	var center := SIZE * 0.5
	var hexagon := PackedVector2Array()
	for i in 7:
		hexagon.append(center + Vector2.RIGHT.rotated(-PI * 0.5 + i * TAU / 6.0) * 40.0)
	c.draw_colored_polygon(hexagon, Color(0.1, 0.5, 0.6, 0.35))
	K.line(c, hexagon, Color("35e0ff"), 4.0)
	c.draw_circle(center, 14.0, Color("35e0ff"))
	c.draw_circle(center, 7.0, Color("e8fbff"))
