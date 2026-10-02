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
	return ["wataru_photo", "nest_egg_chip", "old_k_order", "nest07_shard", "med_injector", "shield_cell", "maintenance_pass", "nest_roster", "wataru_wristband", "document", "recording"]


## 回傳畫好的圖示；未知 id 回傳 null。
static func paint(id: String) -> PixelCanvas:
	var canvas := PixelCanvas.new(SIZE.x, SIZE.y)
	match id:
		"wataru_photo": _photo(canvas)
		"nest_egg_chip": _chip(canvas)
		"old_k_order": _order(canvas)
		"nest07_shard": _shard(canvas)
		"med_injector": _injector(canvas)
		"shield_cell": _cell(canvas)
		"maintenance_pass": _pass(canvas)
		"nest_roster": _roster(canvas)
		"wataru_wristband": _wristband(canvas)
		"document": _document(canvas)
		"recording": _recording(canvas)
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


## 醫療針：自動注射器，粉紅色藥劑窗與醫療十字。
static func _injector(c: PixelCanvas) -> void:
	var fluid := Color("ff5c80")
	# 針頭與護套。
	c.line(Vector2i(2, 16), Vector2i(7, 16), Color("d8e2ec"))
	c.rect(7, 14, 3, 5, Color("7a8798"))
	# 筒身：上亮下暗的金屬，中間一段透明藥劑窗。
	c.rect_gradient(10, 11, 15, 11, Color("e8f0f8"), Color("8c9aae"))
	c.rect(12, 13, 10, 7, Color("1d2431"))
	c.rect(13, 14, 8, 5, fluid)
	c.rect(13, 14, 8, 1, Color("ff9ab0"))
	c.rect(15, 15, 4, 1, Color.WHITE)
	c.rect(17, 14, 1, 5, Color("ffb0c0"))
	# 後端柱塞與握把。
	c.rect(25, 12, 3, 9, Color("39475c"))
	c.rect(28, 14, 2, 5, Color("56657e"))
	c.rect(25, 12, 1, 9, Color("5d6f88"))
	# 指環與醫療十字。
	c.rect(9, 9, 2, 2, Color("56657e"))
	c.rect(9, 22, 2, 2, Color("56657e"))


## 護盾電池：青色能量槽、上方電極與閃電。
static func _cell(c: PixelCanvas) -> void:
	# 電極。
	c.rect(13, 3, 6, 3, Color("9fb0c4"))
	c.rect(14, 2, 4, 1, Color("c8d6e6"))
	# 外殼。
	c.rect_gradient(8, 6, 16, 23, Color("39475c"), Color("1d2431"))
	c.rect(8, 6, 16, 1, Color("5d6f88"))
	c.rect(8, 6, 1, 23, Color("4a5a73"))
	# 能量槽（由下往上由深到亮的四格）。
	var shades := [Color("0f7f99"), Color("1fb0cc"), Color("35e0ff"), Color("9ff3ff")]
	for i in shades.size():
		c.rect(11, 24 - i * 5, 10, 4, shades[i])
	c.rect(11, 8, 10, 1, Color("0d1119"))
	# 閃電。
	var bolt := Color("fff8c0")
	c.polygon(PackedVector2Array([Vector2(17, 9), Vector2(13, 17), Vector2(16, 17), Vector2(14, 24), Vector2(19, 15), Vector2(16, 15)]), bolt)
	c.px(11, 28, Color("0d1119"))


## 維修員通行證：磨損的塑膠卡，橘色警示條、磁條與一個小小的頭像框。
static func _pass(c: PixelCanvas) -> void:
	c.rect_gradient(4, 7, 24, 18, Color("d8dde6"), Color("9aa3b2"))
	c.rect(4, 7, 24, 1, Color("f1f4f8"))
	# 橘色警示條與斜紋。
	c.rect(4, 9, 24, 4, Color("ff7a1a"))
	for i in 6:
		c.line(Vector2i(5 + i * 4, 12), Vector2i(8 + i * 4, 9), Color("2a1608"))
	# 頭像框與文字行。
	c.rect(6, 15, 7, 8, Color("56657e"))
	c.rect(7, 16, 5, 6, Color("1d2431"))
	c.circle(9.5, 18.0, 1.5, Color("c9a58c"))
	c.rect(8, 20, 3, 2, Color("c9a58c"))
	c.rect(15, 16, 10, 1, Color("56657e"))
	c.rect(15, 19, 8, 1, Color("56657e"))
	# 磁條與磨損。
	c.rect(4, 22, 24, 2, Color("2a3342"))
	c.px(26, 8, Color("7a8493"))
	c.px(25, 24, Color("7a8493"))
	c.px(5, 24, Color("7a8493"))


## NEST 名冊殘頁：燒焦的紙角，一列列名字，大部分被紅線劃掉。
static func _roster(c: PixelCanvas) -> void:
	c.polygon(PackedVector2Array([Vector2(7, 3), Vector2(22, 3), Vector2(25, 6), Vector2(25, 29), Vector2(9, 29), Vector2(7, 25)]), Color("d9d6cc"))
	c.rect(24, 7, 1, 22, Color("a9a698"))
	# 燒焦的邊緣。
	c.polygon(PackedVector2Array([Vector2(7, 25), Vector2(9, 29), Vector2(13, 29), Vector2(10, 25)]), Color("3a2b22"))
	c.px(8, 24, Color("6a4a30"))
	c.px(14, 28, Color("6a4a30"))
	# 名單：每行一個名字，劃掉的是紅線。
	for i in 6:
		var y := 7 + i * 3
		c.rect(10, y, 11 - (i % 3) * 2, 1, Color("5a5a64"))
		if i != 0:
			c.rect(9, y, 14, 1, Color(0.85, 0.2, 0.22, 0.95))
	# 第一行是「七」。
	c.rect(10, 6, 4, 1, Color("ff3fa4"))
	c.rect(11, 7, 1, 2, Color("ff3fa4"))
	c.px(22, 26, Color("ff3fa4"))


## 航的醫療手環：淡綠的塑膠環，一小塊印著編號的標籤。
static func _wristband(c: PixelCanvas) -> void:
	# 橢圓環：外圈淡綠，內側一圈較暗的內襯。
	for y in 32:
		for x in 32:
			var dx := (x + 0.5 - 16.0) / 12.0
			var dy := (y + 0.5 - 16.0) / 11.0
			var d := dx * dx + dy * dy
			if d <= 1.0 and d > 0.62:
				c.px(x, y, Color("8fe39a") if d < 0.9 else Color("5fa56c"))
			elif d <= 0.62 and d > 0.5:
				c.px(x, y, Color("2a3a2f"))
	# 標籤。
	c.rect(10, 4, 12, 6, Color("f1f6ee"))
	c.rect(10, 4, 12, 1, Color("ffffff"))
	c.rect(11, 6, 6, 1, Color("5a6a60"))
	c.rect(11, 8, 9, 1, Color("5a6a60"))
	c.px(20, 6, Color("ff3fa4"))
	# 扣環。
	c.rect(26, 15, 3, 4, Color("d6f7df"))
	c.px(27, 16, Color("2a3a2f"))


## 文件：折角的資料夾與文字行，右上角一枚小標籤（收集品共用圖示）。
static func _document(c: PixelCanvas) -> void:
	c.polygon(PackedVector2Array([Vector2(7, 4), Vector2(21, 4), Vector2(26, 9), Vector2(26, 28), Vector2(7, 28)]), Color("dfe6ea"))
	c.polygon(PackedVector2Array([Vector2(21, 4), Vector2(26, 9), Vector2(21, 9)]), Color("9fb0b8"))
	c.rect(25, 10, 1, 18, Color("a9b6bc"))
	c.rect(8, 27, 18, 1, Color("a9b6bc"))
	for i in 6:
		var width := 14 if i % 3 != 2 else 9
		c.rect(10, 11 + i * 3, width, 1, Color("56657e"))
	c.rect(10, 7, 7, 2, CYAN)
	c.px(20, 24, MAGENTA)
	c.px(21, 24, MAGENTA)


## 錄音：小型錄音晶片，中間一段音波。
static func _recording(c: PixelCanvas) -> void:
	c.rect_gradient(6, 8, 20, 17, Color("39475c"), Color("1d2431"))
	c.rect(6, 8, 20, 1, Color("5d6f88"))
	c.rect(8, 10, 16, 8, Color("0d1119"))
	for i in 8:
		var h: int = [2, 4, 6, 3, 5, 6, 3, 2][i]
		c.rect(9 + i * 2, 14 - h / 2, 1, h, CYAN if i % 2 == 0 else Color("9ff3ff"))
	c.circle(11.0, 21.5, 1.6, Color("56657e"))
	c.circle(21.0, 21.5, 1.6, Color("56657e"))
	c.rect(13, 21, 6, 1, Color("56657e"))
	c.px(24, 10, MAGENTA)
