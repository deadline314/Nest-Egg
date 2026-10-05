class_name GaitShape
extends RefCounted
## 跑步循環的形狀（純函式，不碰骨架）：身體高度隨步伐起伏、腳掌隨相位滾動。
## 相位 c／p 都是 0~1：c＝一個步伐週期（左右腳各一步），p＝某一隻腳自己的週期（0＝著地、duty＝蹬地離地、之後是前擺）。
## 所有參數來自角色的動作資料（art/motion/<角色>.json），預設值＝不啟用，等於舊的走路式落腳。


## 身體下沉量（骨架空間，往下為正）。跑步的重心在「踩地中段最低（膝蓋壓縮）、騰空中段最高」，一個週期兩次起伏。
## compress＝踩地中段下沉多少像素，rise＝騰空時上升多少像素；兩者都是 0 時回傳 NAN（呼叫端改用舊的固定下限）。
static func body_sag(c: float, duty: float, compress: float, rise: float) -> float:
	if compress <= 0.0 and rise <= 0.0:
		return NAN
	var mid_stance := duty * 0.5
	var k := 0.5 + 0.5 * cos(TAU * 2.0 * (c - mid_stance))
	return lerpf(-rise, compress, k)


## 腳掌的絕對角度（0＝放平，正＝腳尖下壓）。
## 著地段：先以腳跟著地（heel，負值＝腳尖翹），踩穩放平，蹬地時腳尖下壓（toe_off）；
## 前擺段：離地時還帶著蹬地的腳尖下壓、抬腳時依抬高比例下垂（droop，舊行為），快落地前再翹起準備腳跟著地。
## lift_ratio：目前抬腳高度占最大抬腳高度的比例（0~1）。
static func foot_angle(p: float, duty: float, lift_ratio: float, foot: Dictionary) -> float:
	var heel := float(foot["heel"])
	var toe_off := float(foot["toe_off"])
	if p < duty:
		var s := p / maxf(0.01, duty)
		return heel * (1.0 - smoothstep(0.0, 0.35, s)) + toe_off * smoothstep(0.6, 1.0, s)
	var t := (p - duty) / maxf(0.01, 1.0 - duty)
	return float(foot["droop"]) * lift_ratio + toe_off * (1.0 - smoothstep(0.0, 0.5, t)) + heel * smoothstep(0.6, 1.0, t)
