class_name WorldText
extends RefCounted
## 錨在世界、大小在螢幕（NE-493）：位置跟著世界裡的人或物（世界座標），字級、最大寬度與行數是螢幕空間的，
## 由字體系統的角色決定，不隨鏡頭倍率、區域取景或拉近拉遠的脈衝變大變小。
## 用法（見 design/22-living-scenes/TYPOGRAPHY.md「世界裡的文字」）：
## - 整個節點都是文字（提示、看板上的字）：每格呼叫 WorldText.fit(節點)，節點的本地座標就是畫面像素，照畫面像素排版與繪製。
## - 一個節點畫很多塊（氣泡）：unit(節點) 是一個畫面像素等於多少世界像素；排版矩形乘上它換到世界，繪製時 draw_set_transform 縮放。
## 畫面像素是 640×360 的設計畫布（720p 乘 2、1080p 乘 3），和 HUD、選單的字級同一套單位。

const CANVAS_WIDTH := 640.0
## 每一類世界文字：字體角色、最大寬度（畫面寬度的比例）、最多幾行（文字大小 1.2 倍時也要放得下）。
const KINDS := {
	## 互動提示（按鍵邀請）：一句話講重點。
	&"prompt": {"role": &"body", "width": 0.36, "lines": 2},
	## 拾取物的名稱與說明（物品說明較長：文字 1.2 倍時最長的五件要四行）。
	&"pickup": {"role": &"body", "width": 0.36, "lines": 4},
	## 對凜說的話。
	&"addressed": {"role": &"body", "width": 0.36, "lines": 3},
	## 路人閒聊：更小、更窄，可以不讀。
	&"ambient": {"role": &"caption", "width": 0.28, "lines": 2},
}


static func spec(kind: StringName) -> Dictionary:
	return KINDS.get(kind, KINDS[&"prompt"])


static func role(kind: StringName) -> StringName:
	return spec(kind)["role"]


## 這一類文字的字級（畫面像素，已乘上文字大小設定）。
static func font_size(kind: StringName) -> int:
	return roundi(Typography.base_size(role(kind)) * Settings.get_ui_text_scale())


static func font(kind: StringName) -> Font:
	return Typography.font(role(kind))


## 最大寬度（畫面像素，不含內距）。
static func max_width(kind: StringName) -> float:
	return CANVAS_WIDTH * float(spec(kind)["width"])


static func max_lines(kind: StringName) -> int:
	return int(spec(kind)["lines"])


## item 所在的座標系裡，一個畫面像素等於多少單位（鏡頭倍率 1.92 時約 0.52）。不在場景樹或縮放異常時是 1。
static func unit(item: CanvasItem) -> float:
	if item == null or not item.is_inside_tree():
		return 1.0
	var parent := item.get_parent() as CanvasItem
	var frame := item.get_canvas_transform() if parent == null else parent.get_global_transform_with_canvas()
	var scale := frame.get_scale().abs()
	var per_pixel := maxf(scale.x, scale.y)
	if not is_finite(per_pixel) or per_pixel <= 0.0001:
		return 1.0
	return 1.0 / per_pixel


## 縮放 node，讓它的本地座標就是畫面像素（字在螢幕上的大小固定）；回傳一個畫面像素等於多少父節點單位。
static func fit(node: Node2D) -> float:
	var value := unit(node)
	var target := Vector2.ONE * value
	if not node.scale.is_equal_approx(target):
		node.scale = target
	return value


## 排好的段落（畫面像素）。width 是可用寬度；回傳的段落行數可能超過 max_lines（由資料檢查負責）。
static func paragraph(text: String, kind: StringName, width := -1.0) -> TextParagraph:
	var limit := max_width(kind) if width <= 0.0 else minf(width, max_width(kind))
	var face := font(kind)
	var size := font_size(kind)
	var result := TextParagraph.new()
	result.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	result.width = minf(limit, maxf(1.0, face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x))
	result.add_string(text, face, size)
	return result
