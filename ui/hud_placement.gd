class_name HudPlacement
extends RefCounted
## 跟著主角的 HUD（彈帶、生命護盾標籤）共用的擺位規則（NE-264）。
## 平常放在主角背後（準星的反方向）；主角靠近畫面邊緣、背後放不下時，兩者一起移到頭頂上方
## （生命護盾在上、彈帶在下），不擋準星方向，也不蓋住頭和臉。兩個元件用同一個判斷，不會一個在背後、一個在頭上而疊在一起。
## 切換用連續的權重，由呼叫端平滑過渡，不在一格內跳位置。

## 離畫面左右邊緣至少留的距離（畫面像素）。
const EDGE_MARGIN := 4.0
## 背後至少要有這麼寬（畫面像素）才放得下最寬的元件（十顆子彈加備彈數字）。
const ROOM_NEEDED := 92.0
## 頭頂上方的間距（畫面像素）與兩列之間的間距。
const ABOVE_GAP := 5.0
const ROW_GAP := 3.0
## 頭頂相對於腳底的位置（世界座標）；與 VitalsTag.HEAD_OFFSET 相同。
const HEAD_OFFSET := Vector2(0, -56)
## 切換到頭頂、回到背後的速度（每秒權重變化）。
const BLEND_SPEED := 5.0


## 背後（side：-1 左、+1 右）從 anchor_x 往外還有多少畫面像素。
static func room_behind(anchor_x: float, side: float, gap: float, view_width: float) -> float:
	if side < 0.0:
		return anchor_x - gap - EDGE_MARGIN
	return view_width - EDGE_MARGIN - anchor_x - gap


## 目標權重：背後放得下是 0（放背後），放不下是 1（放頭上）。
static func above_target(anchor_x: float, side: float, gap: float, view_width: float) -> float:
	return 0.0 if room_behind(anchor_x, side, gap, view_width) >= ROOM_NEEDED else 1.0


## 讓 [left, left + width] 留在畫面裡，回傳需要的水平位移。
static func clamp_shift(left: float, width: float, view_width: float) -> float:
	if width >= view_width - EDGE_MARGIN * 2.0:
		return EDGE_MARGIN - left
	if left < EDGE_MARGIN:
		return EDGE_MARGIN - left
	if left + width > view_width - EDGE_MARGIN:
		return view_width - EDGE_MARGIN - (left + width)
	return 0.0
