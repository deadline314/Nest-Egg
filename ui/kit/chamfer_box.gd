class_name ChamferBox
extends StyleBox
## 共用像素面板：實心底、階梯轉角、低亮內緣與角標。
## 所有繪製座標取整數，邊線落在像素格上；禁用狀態改畫虛線。
## 這是全專案共用的面板形狀，按鈕、頁籤、提示框、面板都由它組成。

enum Corner { TL = 1, TR = 2, BR = 4, BL = 8, ALL = 15, TOP = 3 }

var fill: Color = Palette.UI_PANEL
var border: Color = Palette.CYAN_DIM
var border_width: int = 1
var notch: int = 4
var corners: int = Corner.ALL
## 角落小括號（亮色）；alpha 為 0 表示不畫。
var bracket: Color = Color(0, 0, 0, 0)
var scanlines: float = 0.0
var dashed: bool = false
## 頁籤用：不畫下邊線，讓選取中的頁籤與面板相連。
var open_bottom: bool = false
## 階梯像素角保持水平／垂直線段；舊工具仍可選斜切角。
var pixel_corners: bool = true
## 低亮度內緣；焦點覆蓋框關閉此項，避免覆蓋下方材質。
var bevel: bool = true
## 內側光暈（亮度 0 表示不畫）。
var glow: Color = Color(0, 0, 0, 0)

const SCAN_STEP := 3
const BRACKET_LEN := 6
const DASH := 4.0


static func make(fill_color: Color, border_color: Color, notch_size := 4, width := 1) -> ChamferBox:
	var box := ChamferBox.new()
	box.fill = fill_color
	box.border = border_color
	box.notch = notch_size
	box.border_width = width
	box.margins(12, 6, 12, 6)
	return box


## 內容邊距：左、上、右、下。
func margins(left: float, top: float, right: float, bottom: float) -> ChamferBox:
	set_content_margin(SIDE_LEFT, left)
	set_content_margin(SIDE_TOP, top)
	set_content_margin(SIDE_RIGHT, right)
	set_content_margin(SIDE_BOTTOM, bottom)
	return self


func _outline(rect: Rect2) -> PackedVector2Array:
	var origin := rect.position.round()
	var size := rect.size.round()
	var half := float(border_width) * 0.5
	var x0 := origin.x + half
	var y0 := origin.y + half
	var x1 := origin.x + size.x - half
	var y1 := origin.y + size.y - half
	var n := float(mini(notch, int(minf(size.x, size.y) * 0.5) - 1))
	if pixel_corners:
		return pixel_outline(x0, y0, x1, y1, maxf(n, 0.0), corners)
	var pts := PackedVector2Array()
	pts.append(Vector2(x0 + (n if corners & Corner.TL else 0.0), y0))
	pts.append(Vector2(x1 - (n if corners & Corner.TR else 0.0), y0))
	if corners & Corner.TR:
		pts.append(Vector2(x1, y0 + n))
	pts.append(Vector2(x1, y1 - (n if corners & Corner.BR else 0.0)))
	if corners & Corner.BR:
		pts.append(Vector2(x1 - n, y1))
	pts.append(Vector2(x0 + (n if corners & Corner.BL else 0.0), y1))
	if corners & Corner.BL:
		pts.append(Vector2(x0, y1 - n))
	pts.append(Vector2(x0, y0 + (n if corners & Corner.TL else 0.0)))
	if corners & Corner.TL:
		pts.append(Vector2(x0 + n, y0))
	return pts


## 自繪卡片與 StyleBox 共用輪廓，避免兩套像素轉角不一致。
static func pixel_outline(x0: float, y0: float, x1: float, y1: float, n: float, corner_flags: int) -> PackedVector2Array:
	if n < 2.0:
		return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1), Vector2(x0, y0)])
	var h := floorf(n * 0.5)
	var pts := PackedVector2Array([Vector2(x0 + (n if corner_flags & Corner.TL else 0.0), y0)])
	pts.append(Vector2(x1 - (n if corner_flags & Corner.TR else 0.0), y0))
	if corner_flags & Corner.TR:
		pts.append(Vector2(x1 - n, y0 + h))
		pts.append(Vector2(x1 - h, y0 + h))
		pts.append(Vector2(x1 - h, y0 + n))
		pts.append(Vector2(x1, y0 + n))
	pts.append(Vector2(x1, y1 - (n if corner_flags & Corner.BR else 0.0)))
	if corner_flags & Corner.BR:
		pts.append(Vector2(x1 - h, y1 - n))
		pts.append(Vector2(x1 - h, y1 - h))
		pts.append(Vector2(x1 - n, y1 - h))
		pts.append(Vector2(x1 - n, y1))
	pts.append(Vector2(x0 + (n if corner_flags & Corner.BL else 0.0), y1))
	if corner_flags & Corner.BL:
		pts.append(Vector2(x0 + n, y1 - h))
		pts.append(Vector2(x0 + h, y1 - h))
		pts.append(Vector2(x0 + h, y1 - n))
		pts.append(Vector2(x0, y1 - n))
	pts.append(Vector2(x0, y0 + (n if corner_flags & Corner.TL else 0.0)))
	if corner_flags & Corner.TL:
		pts.append(Vector2(x0 + h, y0 + n))
		pts.append(Vector2(x0 + h, y0 + h))
		pts.append(Vector2(x0 + n, y0 + h))
	if pts[pts.size() - 1] != pts[0]:
		pts.append(pts[0])
	return pts


func _draw(canvas: RID, rect: Rect2) -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	var pts := _outline(rect)
	# 輪廓是封閉折線（最後一點等於第一點），填色用的多邊形要去掉重複點。
	var fill_pts := pts.duplicate()
	fill_pts.remove_at(fill_pts.size() - 1)
	RenderingServer.canvas_item_add_polygon(canvas, fill_pts, PackedColorArray([fill]))
	if bevel and fill.a > 0.0:
		_draw_bevel(canvas, rect)
	if glow.a > 0.0:
		_draw_glow(canvas, rect)
	if scanlines > 0.0:
		_draw_scanlines(canvas, rect)
	_draw_border(canvas, pts)
	if bracket.a > 0.0:
		_draw_brackets(canvas, rect)


func _draw_bevel(canvas: RID, rect: Rect2) -> void:
	var origin := rect.position.round()
	var size := rect.size.round()
	var inset := float(maxi(notch + 1, border_width + 2))
	if size.x <= inset * 2.0 or size.y <= 6.0:
		return
	var top := Color(fill.lightened(0.16), fill.a)
	var bottom := Color(fill.darkened(0.55), fill.a)
	RenderingServer.canvas_item_add_line(canvas, origin + Vector2(inset, 2), origin + Vector2(size.x - inset, 2), top, 1.0)
	if not open_bottom:
		RenderingServer.canvas_item_add_line(canvas, origin + Vector2(inset, size.y - 3), origin + Vector2(size.x - inset, size.y - 3), bottom, 2.0)


func _draw_border(canvas: RID, pts: PackedVector2Array) -> void:
	var width := float(border_width)
	if dashed:
		for i in pts.size() - 1:
			_dashed_line(canvas, pts[i], pts[i + 1], width)
		return
	if open_bottom:
		# 頁籤：左右兩邊停在底部，不連到下邊。
		RenderingServer.canvas_item_add_polyline(canvas, _without_bottom(pts), PackedColorArray([border]), width)
		return
	RenderingServer.canvas_item_add_polyline(canvas, pts, PackedColorArray([border]), width)


## 頁籤用：從路徑中去掉最底下的那條邊。路徑順序是順時針，所以把起點轉到最底邊之後。
func _without_bottom(pts: PackedVector2Array) -> PackedVector2Array:
	var max_y := -INF
	for p in pts:
		max_y = maxf(max_y, p.y)
	var cut := -1
	for i in pts.size() - 1:
		if is_equal_approx(pts[i].y, max_y) and is_equal_approx(pts[i + 1].y, max_y):
			cut = i
			break
	if cut < 0:
		return pts
	var out := PackedVector2Array()
	for i in range(cut + 1, pts.size() - 1):
		out.append(pts[i])
	for i in range(0, cut + 1):
		out.append(pts[i])
	return out


func _dashed_line(canvas: RID, a: Vector2, b: Vector2, width: float) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var dir := (b - a) / length
	var t := 0.0
	var on := true
	while t < length:
		var step := minf(DASH, length - t)
		if on:
			RenderingServer.canvas_item_add_line(canvas, a + dir * t, a + dir * (t + step), border, width)
		t += step
		on = not on


func _draw_scanlines(canvas: RID, rect: Rect2) -> void:
	var origin := rect.position.round()
	var size := rect.size.round()
	var color := Color(0, 0, 0, scanlines)
	var n := float(notch)
	var y := float(SCAN_STEP)
	while y < size.y - 1.0:
		var left := 1.0
		var right := size.x - 1.0
		if corners & Corner.TL and y < n:
			left = n - y
		if corners & Corner.TR and y < n:
			right = size.x - (n - y)
		var from_bottom := size.y - y
		if corners & Corner.BL and from_bottom < n:
			left = maxf(left, n - from_bottom)
		if corners & Corner.BR and from_bottom < n:
			right = minf(right, size.x - (n - from_bottom))
		if right > left:
			RenderingServer.canvas_item_add_line(canvas, origin + Vector2(left, y), origin + Vector2(right, y), color, 1.0)
		y += float(SCAN_STEP)


func _draw_glow(canvas: RID, rect: Rect2) -> void:
	# 內側光暈：往內三層漸淡的矩形線。
	var origin := rect.position.round()
	var size := rect.size.round()
	for i in 3:
		var inset := float(border_width + 1 + i)
		var c := Color(glow.r, glow.g, glow.b, glow.a * (1.0 - float(i) / 3.0))
		var r := Rect2(origin + Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		if r.size.x > 4.0 and r.size.y > 4.0:
			RenderingServer.canvas_item_add_polyline(canvas, PackedVector2Array([
				r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position,
			]), PackedColorArray([c]), 1.0)


func _draw_brackets(canvas: RID, rect: Rect2) -> void:
	var origin := rect.position.round()
	var size := rect.size.round()
	var l := float(BRACKET_LEN)
	var w := float(border_width) + 1.0
	var x0 := origin.x + 1.0
	var y0 := origin.y + 1.0
	var x1 := origin.x + size.x - 1.0
	var y1 := origin.y + size.y - 1.0
	var n := float(notch)
	# 括號沿著切角兩側的短邊畫，讓角落有「夾住」的感覺。
	if corners & Corner.TL:
		_bracket(canvas, Vector2(x0 + n, y0), Vector2(x0 + n + l, y0), w)
		_bracket(canvas, Vector2(x0, y0 + n), Vector2(x0, y0 + n + l), w)
	if corners & Corner.TR:
		_bracket(canvas, Vector2(x1 - n, y0), Vector2(x1 - n - l, y0), w)
		_bracket(canvas, Vector2(x1, y0 + n), Vector2(x1, y0 + n + l), w)
	if corners & Corner.BR:
		_bracket(canvas, Vector2(x1 - n, y1), Vector2(x1 - n - l, y1), w)
		_bracket(canvas, Vector2(x1, y1 - n), Vector2(x1, y1 - n - l), w)
	if corners & Corner.BL:
		_bracket(canvas, Vector2(x0 + n, y1), Vector2(x0 + n + l, y1), w)
		_bracket(canvas, Vector2(x0, y1 - n), Vector2(x0, y1 - n - l), w)


func _bracket(canvas: RID, a: Vector2, b: Vector2, width: float) -> void:
	RenderingServer.canvas_item_add_line(canvas, a, b, bracket, width)
