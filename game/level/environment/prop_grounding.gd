class_name PropGrounding
extends ChunkedDrawer
## 擺設的接地陰影（BG-63）：站在地面上的擺設，在實際接觸地面的範圍底下畫一道柔邊陰影。
## 一半落在地板面、一半壓住擺設底緣，同時當「接觸陰影」與「底部遮蔽」，擺設才不像貼在畫面上。
## 只收以地面為支撐的擺設（由關卡在擺放時交進來）；關卡建立時畫一次，沒有每影格成本。
## 投到背牆上的影子是另一套（WallShadows），角色腳下的是 ContactShadow；這裡只管不會動的擺設。

## 地形之上、拾取物與角色（含角色的接觸陰影）之下。
const Z := WorldLayers.TERRAIN + 1
## 看得到的部分比這個矮（地面貼花、踏墊）就不畫：本來就是平的東西沒有東西可以遮。
const MIN_VISIBLE_HEIGHT := 6.0
## 陰影的高 ÷ 寬與高度上限（像素）：側視的地板只有頂面那一條，和角色的接觸陰影用同一組比例。
const FLATTEN := 0.3
const MAX_HEIGHT := 7.0
## 陰影頂端比接觸面高多少：這一段壓在擺設底緣上。
const LIFT := 2.5
## 淡影比接觸範圍左右各多出多少（占寬度的比例與像素上限）。
const SPREAD := 0.12
const MAX_SPREAD := 6.0
## 淡影（整件）與深色核心（每個實際接觸段）的不透明度；矮的擺設用 LOW、到 TALL_HEIGHT 以上用 HIGH。
const BODY_ALPHA_LOW := 0.45
const BODY_ALPHA_HIGH := 0.6
const CORE_ALPHA := 0.5
const TALL_HEIGHT := 64.0

## 每筆 { "rect": Rect2（世界座標）, "alpha": float }。
var _shadows: Array[Dictionary] = []


## 這件擺設該不該有接地陰影：前景擺設、水窪與太扁的東西不畫，資料也可以個別關掉。
static func wants_shadow(prop: PropData, rect: Rect2) -> bool:
	if prop == null or not prop.ground_shadow or prop.ripple or prop.layer == PropData.Layer.FRONT:
		return false
	return ScenerySupport.visible_rect(rect, prop.id).size.y >= MIN_VISIBLE_HEIGHT


## 一件站在地上的擺設要畫的陰影（世界座標，由下層到上層）。rect 是擺設的擺放範圍；不該有陰影時回傳空陣列。
## 純計算，不碰場景樹，測試直接呼叫。
static func footprints(prop: PropData, rect: Rect2, flip := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not wants_shadow(prop, rect) or not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0:
		return result
	var surface := rect.end.y - ScenerySupport.ground_offset(prop.id, rect.size.y)
	var visible := ScenerySupport.visible_rect(rect, prop.id, flip)
	# 淡影只蓋住接觸段的外包範圍：路燈的燈臂、樹冠這些懸在半空的部分不會在地上拖出一大片。
	var hull_from := INF
	var hull_to := -INF
	var cores: Array[Dictionary] = []
	for span in ScenerySupport.ground_spans(prop.id, flip):
		var from := rect.position.x + rect.size.x * span.x
		var to := rect.position.x + rect.size.x * span.y
		if to - from < 1.0:
			continue
		hull_from = minf(hull_from, from)
		hull_to = maxf(hull_to, to)
		cores.append({"rect": _strip(from, to, surface), "alpha": CORE_ALPHA})
	if cores.is_empty():
		return result
	var spread := minf((hull_to - hull_from) * SPREAD, MAX_SPREAD)
	var body_alpha := lerpf(BODY_ALPHA_LOW, BODY_ALPHA_HIGH, clampf(visible.size.y / TALL_HEIGHT, 0.0, 1.0))
	result.append({"rect": _strip(hull_from - spread, hull_to + spread, surface), "alpha": body_alpha})
	result.append_array(cores)
	return result


static func _strip(from_x: float, to_x: float, surface: float) -> Rect2:
	var width := to_x - from_x
	return Rect2(from_x, surface - LIFT, width, minf(maxf(width * FLATTEN, LIFT * 2.0), MAX_HEIGHT))


func _init() -> void:
	name = "PropGrounding"
	z_as_relative = false
	z_index = Z


## 登記一件站在地上的擺設；回傳有沒有加上陰影。要在 build_chunks 之前呼叫。
func add_prop(prop: PropData, rect: Rect2, flip := false) -> bool:
	if prop != null and not (rect.position.is_finite() and rect.size.is_finite()):
		push_warning("[PropGrounding] 擺設 %s 的擺放範圍無效，不畫接地陰影" % prop.id)
		return false
	var prints := footprints(prop, rect, flip)
	_shadows.append_array(prints)
	return not prints.is_empty()


func shadow_count() -> int:
	return _shadows.size()


## 所有陰影的世界範圍（測試與量測用）。
func shadow_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for shadow in _shadows:
		rects.append(shadow["rect"])
	return rects


func _draw_chunk(canvas: CanvasItem, rect: Rect2) -> void:
	var soft := LightKit.soft_texture()
	for shadow in _shadows:
		var area: Rect2 = shadow["rect"]
		# 跨區塊的陰影只由中心所在的那一塊畫，不會重疊成兩倍深。
		var center := area.get_center().x
		if center < rect.position.x or center >= rect.end.x:
			continue
		canvas.draw_texture_rect(soft, area, false, Color(0.0, 0.0, 0.0, float(shadow["alpha"])))
