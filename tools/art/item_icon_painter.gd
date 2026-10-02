class_name ItemIconPainter
extends RefCounted
## 背包圖示的程式繪製（暫代美術，32×32、透明背景、逐像素、深色描邊）。
## 正式美術以同尺寸 PNG 覆蓋 art/items/icons/<id>.png 即可（最近鄰放大會保持銳利）。

const SIZE := Vector2i(32, 32)
const OUTLINE := Color("07080d")

const CREAM := Color("ece6d2")
const CREAM_SHADE := Color("b9b19c")
const PAPER := Color("e9dfb4")
const PAPER_SHADE := Color("b8ad7e")
const GOLD := Color("f6c64f")
const GOLD_DARK := Color("b9842a")
const INK := Color("2a2622")
const CYAN := Color("35e0ff")
const CYAN_DARK := Color("0f7f99")
const MAGENTA := Color("ff2e88")


static func ids() -> Array[String]:
	return ["wataru_photo", "nest_egg_chip", "old_k_order", "nest07_shard"]


## 回傳畫好的圖示；未知 id 回傳 null。
static func paint(id: String) -> PixelCanvas:
	var canvas := PixelCanvas.new(SIZE.x, SIZE.y)
	match id:
		"wataru_photo": _photo(canvas)
		"nest_egg_chip": _chip(canvas)
		"old_k_order": _order(canvas)
		"nest07_shard": _shard(canvas)
		_:
			push_warning("[ItemIconPainter] 沒有 %s 的圖示" % id)
			return null
	canvas.outline(OUTLINE)
	return canvas


## 航的照片：邊角磨損的拍立得，藍天下的小小身影。
static func _photo(c: PixelCanvas) -> void:
	c.rect(5, 4, 22, 24, CREAM)
	c.rect(26, 5, 1, 23, CREAM_SHADE)
	c.rect(6, 27, 21, 1, CREAM_SHADE)
	# 相片：天空漸層、雲、遠山。
	c.rect_gradient(8, 7, 16, 15, Color("2a6fd6"), Color("9ad8ff"))
	c.rect(19, 9, 3, 3, Color("ffe38a"))
	c.rect(18, 10, 5, 1, Color("ffe38a"))
	c.rect(10, 11, 5, 2, Color(1, 1, 1, 0.9))
	c.rect(12, 10, 3, 1, Color(1, 1, 1, 0.9))
	c.polygon(PackedVector2Array([Vector2(8, 22), Vector2(8, 18), Vector2(13, 16), Vector2(18, 19), Vector2(24, 17), Vector2(24, 22)]), Color("2a5a58"))
	c.rect(8, 21, 16, 1, Color("1d3d3a"))
	# 小孩：頭、身體、舉起的手。
	c.circle(15.5, 14.0, 2.4, Color("2b1d1a"))
	c.circle(15.5, 15.0, 1.9, Color("f2cdb8"))
	c.rect(14, 16, 3, 5, Color("e8f0ff"))
	c.line(Vector2i(17, 16), Vector2i(19, 13), Color("f2cdb8"))
	# 相片框內緣暗線與下方手寫字跡。
	c.rect(8, 22, 16, 1, Color(0, 0, 0, 0.25))
	c.line(Vector2i(9, 25), Vector2i(12, 24), INK)
	c.line(Vector2i(12, 24), Vector2i(15, 25), INK)
	c.line(Vector2i(15, 25), Vector2i(19, 24), INK)
	# 一小截透明膠帶。
	c.rect(12, 2, 8, 4, Color(1.0, 0.92, 0.5, 0.75))


## 巢蛋存款晶片：金色接點、中央一顆發光的蛋。
static func _chip(c: PixelCanvas) -> void:
	# 接點（左右各四個）。
	for i in 4:
		var y := 9 + i * 4
		c.rect(3, y, 4, 2, GOLD)
		c.rect(25, y, 4, 2, GOLD)
		c.rect(3, y + 1, 4, 1, GOLD_DARK)
		c.rect(25, y + 1, 4, 1, GOLD_DARK)
	# 晶片本體：斜角、上亮下暗。
	c.polygon(PackedVector2Array([Vector2(8, 5), Vector2(25, 5), Vector2(25, 28), Vector2(7, 28), Vector2(7, 9)]), Color("2a3342"))
	c.rect_gradient(8, 9, 17, 18, Color("323d50"), Color("1d2431"))
	c.rect(9, 6, 15, 1, Color("56657e"))
	# 電路走線通往中央晶粒。
	for i in 4:
		var y := 10 + i * 4
		c.line(Vector2i(7, y), Vector2i(11, y), CYAN_DARK)
		c.line(Vector2i(21, y), Vector2i(25, y), CYAN_DARK)
	# 中央晶粒與蛋。
	c.rect(11, 9, 11, 14, Color("0d1119"))
	c.rect(11, 9, 11, 1, CYAN_DARK)
	c.rect(11, 22, 11, 1, CYAN_DARK)
	c.ellipse(16.5, 16.5, 3.6, 4.8, GOLD_DARK)
	c.ellipse(16.2, 16.2, 3.0, 4.2, GOLD)
	c.ellipse(15.4, 14.6, 1.0, 1.6, Color("fff3c0"))
	c.px(13, 25, CYAN)
	c.px(19, 25, CYAN)


## 老K的委託單：泛黃的紙、黃色抬頭、一枚紅色印章。
static func _order(c: PixelCanvas) -> void:
	# 紙張，右上角折角。
	c.polygon(PackedVector2Array([Vector2(7, 4), Vector2(21, 4), Vector2(25, 8), Vector2(25, 28), Vector2(7, 28)]), PAPER)
	c.rect(24, 9, 1, 19, PAPER_SHADE)
	c.rect(8, 27, 17, 1, PAPER_SHADE)
	c.polygon(PackedVector2Array([Vector2(21, 4), Vector2(25, 8), Vector2(21, 8)]), PAPER_SHADE)
	# 黃色抬頭與「K」。
	c.rect(8, 6, 12, 5, Color("ffd23f"))
	c.line(Vector2i(10, 7), Vector2i(10, 10), INK)
	c.line(Vector2i(14, 7), Vector2i(11, 8), INK)
	c.line(Vector2i(11, 9), Vector2i(14, 10), INK)
	c.rect(16, 8, 3, 1, INK)
	# 內文字行。
	var widths := [14, 11, 14, 8]
	for i in widths.size():
		c.rect(9, 13 + i * 3, widths[i], 1, Color("6f6650"))
	# 紅色印章（半透明疊在字上）。
	c.circle(19.5, 23.0, 3.6, Color(0.85, 0.2, 0.22, 0.85))
	c.circle(19.5, 23.0, 2.2, Color(0.95, 0.88, 0.7, 0.9))
	c.line(Vector2i(18, 22), Vector2i(21, 24), Color(0.85, 0.2, 0.22, 0.95))
	c.line(Vector2i(18, 24), Vector2i(21, 22), Color(0.85, 0.2, 0.22, 0.95))


## NEST-07 資料碎片：切面分明的青色晶體，內部有洋紅色的資料光。
static func _shard(c: PixelCanvas) -> void:
	var top := Vector2(16, 2)
	var upper_left := Vector2(8, 10)
	var upper_right := Vector2(24, 8)
	var lower_left := Vector2(9, 21)
	var lower_right := Vector2(25, 19)
	var bottom := Vector2(15, 30)
	var center := Vector2(16, 15)
	# 各切面由暗到亮。
	c.polygon(PackedVector2Array([upper_left, top, center]), Color("5fe9ff"))
	c.polygon(PackedVector2Array([top, upper_right, center]), Color("c9fbff"))
	c.polygon(PackedVector2Array([upper_right, lower_right, center]), Color("2bb8d8"))
	c.polygon(PackedVector2Array([lower_right, bottom, center]), Color("147a9b"))
	c.polygon(PackedVector2Array([bottom, lower_left, center]), Color("1c93b5"))
	c.polygon(PackedVector2Array([lower_left, upper_left, center]), Color("3fd2ee"))
	# 稜線高光與內部洋紅資料光。
	c.line(Vector2i(16, 3), Vector2i(16, 14), Color(1, 1, 1, 0.8))
	c.line(Vector2i(9, 10), Vector2i(15, 14), Color(1, 1, 1, 0.5))
	c.line(Vector2i(14, 17), Vector2i(17, 25), MAGENTA)
	c.line(Vector2i(17, 17), Vector2i(20, 22), Color("ff8cc4"))
	c.px(16, 16, Color.WHITE)
	# 周圍的光點。
	for spark in [Vector2i(4, 6), Vector2i(28, 12), Vector2i(27, 26), Vector2i(5, 24)]:
		c.px(spark.x, spark.y, Color(CYAN, 0.9))
		c.px(spark.x - 1, spark.y, Color(CYAN, 0.45))
		c.px(spark.x + 1, spark.y, Color(CYAN, 0.45))
		c.px(spark.x, spark.y - 1, Color(CYAN, 0.45))
		c.px(spark.x, spark.y + 1, Color(CYAN, 0.45))
