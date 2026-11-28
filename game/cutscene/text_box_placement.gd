class_name TextBoxPlacement
extends RefCounted
## 過場的文字框不蓋住講者（NE-492）：對話框與選擇框擺在不蓋住任何在場演員臉與上半身的位置；
## 每個位置都蓋到時，鏡頭讓位（往旁邊平移一點或拉遠一點）而不是蓋上去。
## 播放器（CutscenePlayer）與靜態檢查（CutsceneChecker.text_box_problems）共用同一套算法，檢查結果就是玩家看到的結果。
## 座標：舞台座標經鏡頭（中心 cam、倍率 zoom）換到畫面：畫面中心 + (舞台點 − cam) × zoom。

## 臉與上半身：頭頂往下佔身高的這個比例；寬度是身高的這個比例（含頭髮與手臂）。
const BODY_SHARE := 0.55
const BODY_WIDTH := 0.42
## 文字框和上半身之間至少留的距離（畫面像素）。
const MARGIN := 4.0
## 讓位時鏡頭依序試著拉遠到原本倍率的這些比例（先小幅、再大一點）。
const ROOM_ZOOMS: Array[float] = [1.0, 0.85, 0.72]
## 舞台的畫面範圍：多數舞台的背景圖是 768×432，從 (-64, -36) 開始（比 640×360 的取景多出一圈）。讓位時鏡頭不能拍到背景圖以外。
const DEFAULT_ART := Rect2(-64.0, -36.0, 768.0, 432.0)


## 一個演員的臉與上半身在畫面上的範圍；tall 是舞台上的身高（已含縮放與姿勢）。
static func upper_body(feet: Vector2, tall: float, cam: Vector2, zoom: float, screen: Vector2) -> Rect2:
	var foot := screen * 0.5 + (feet - cam) * zoom
	var height := tall * zoom
	return Rect2(foot.x - height * BODY_WIDTH * 0.5, foot.y - height, height * BODY_WIDTH, height * BODY_SHARE).grow(MARGIN)


## 在場演員（{feet, tall}）在畫面上要保護的範圍；鏡頭外與沒有身高的演員不算。
static func protected_rects(actors: Array[Dictionary], cam: Vector2, zoom: float, screen: Vector2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var view := Rect2(Vector2.ZERO, screen)
	for actor in actors:
		var tall := float(actor.get("tall", 0.0))
		if tall <= 0.0:
			continue
		var rect := upper_body(actor["feet"], tall, cam, zoom, screen)
		if rect.intersects(view):
			result.append(rect)
	return result


## 對話框的候選位置：下方（預設），蓋到人時改到上方。
static func dialogue_candidates(safe: Rect2, box_size: Vector2, side_margin: float, bottom_gap: float, top_gap: float) -> Array[Rect2]:
	var x := safe.position.x + side_margin
	return [Rect2(Vector2(x, safe.end.y - bottom_gap), box_size), Rect2(Vector2(x, safe.position.y + top_gap), box_size)]


## 選擇框擠不下時改用的較窄寬度（畫面像素）；變窄時高度依文字區按比例變高。
const CHOICE_NARROW: Array[float] = [236.0, 208.0]


## 選擇框所有的候選：原本寬度的四個角，再來是較窄寬度的四個角。第 i 個候選的寬度是 choice_width_index(i)。
static func choice_candidate_set(safe: Rect2, base_size: Vector2, inset: float, bottom_gap: float, padding_y: float) -> Array[Rect2]:
	var result: Array[Rect2] = choice_candidates(safe, base_size, inset, bottom_gap)
	for width in CHOICE_NARROW:
		if width >= base_size.x:
			continue
		var text_height := maxf(0.0, base_size.y - padding_y) * base_size.x / width
		result.append_array(choice_candidates(safe, Vector2(width, padding_y + text_height), inset, bottom_gap))
	return result


## 選擇框的候選位置：右上（預設）、左上、右下、左下；下方的位置在對話框區域之上。
static func choice_candidates(safe: Rect2, panel_size: Vector2, inset: float, bottom_gap: float) -> Array[Rect2]:
	var top := ceilf(safe.position.y + inset)
	var bottom := floorf(safe.end.y - bottom_gap - panel_size.y)
	var right := floorf(safe.end.x - inset - panel_size.x)
	var left := ceilf(safe.position.x + inset)
	return [Rect2(Vector2(right, top), panel_size), Rect2(Vector2(left, top), panel_size),
		Rect2(Vector2(right, bottom), panel_size), Rect2(Vector2(left, bottom), panel_size)]


## 第一個不蓋到任何保護範圍、也不超出安全範圍的候選；preferred 仍然可用時優先保留（不跳來跳去）。都不行回傳 -1。
static func first_free(candidates: Array[Rect2], protected: Array[Rect2], safe: Rect2, preferred := -1) -> int:
	if preferred >= 0 and preferred < candidates.size() and _free(candidates[preferred], protected, safe):
		return preferred
	for i in candidates.size():
		if _free(candidates[i], protected, safe):
			return i
	return -1


static func _free(rect: Rect2, protected: Array[Rect2], safe: Rect2) -> bool:
	if not safe.grow(1.0).encloses(rect):
		return false
	for body in protected:
		if body.intersects(rect):
			return false
	return true


## 每個位置都蓋到人時鏡頭怎麼讓位：先左右平移（文字框那一側讓出來），再拉遠一點、再拉遠一點並平移。
## 回傳 {ok, cam, zoom, index}：讓位後的鏡頭與用哪一個候選位置。
static func make_room(actors: Array[Dictionary], cam: Vector2, zoom: float, screen: Vector2, safe: Rect2, candidates: Array[Rect2], art := DEFAULT_ART) -> Dictionary:
	var width := candidates[0].size.x if not candidates.is_empty() else 0.0
	# 讓位後看到的範圍要在背景圖裡（或原本鏡頭已經看到的範圍裡），不能拍到舞台的邊。
	var allowed := art.merge(view_rect(cam, zoom, screen)).grow(0.5)
	var tries: Array[Array] = []
	for scale_factor: float in ROOM_ZOOMS:
		var next_zoom := zoom * scale_factor
		for share: float in [0.0, 0.5, -0.5, 1.0, -1.0]:
			if scale_factor == 1.0 and share == 0.0:
				continue
			tries.append([cam + Vector2(width / next_zoom * share, 0.0), next_zoom])
	for attempt in tries:
		# 拉遠或平移後超出背景圖時，把鏡頭推回背景圖裡再試；整個畫面比背景圖還大就放棄這一個。
		attempt[0] = clamp_cam(attempt[0], attempt[1], screen, allowed)
		if not allowed.encloses(view_rect(attempt[0], attempt[1], screen)):
			continue
		var rects := protected_rects(actors, attempt[0], attempt[1], screen)
		# 讓位不能把人推出畫面：原本在畫面裡的演員讓位後仍要完整在畫面裡。
		if rects.size() < protected_rects(actors, cam, zoom, screen).size():
			continue
		var index := first_free(candidates, rects, safe)
		if index >= 0:
			return {"ok": true, "cam": attempt[0], "zoom": attempt[1], "index": index}
	return {"ok": false, "cam": cam, "zoom": zoom, "index": -1}

## 鏡頭在舞台座標裡看到的範圍。
static func view_rect(cam: Vector2, zoom: float, screen: Vector2) -> Rect2:
	return Rect2(cam - screen * 0.5 / zoom, screen / zoom)


## 舞台背景圖（art/environment/scenes/ 的那一層）在舞台座標的範圍；讀不到時用多數舞台的大小。
static func stage_art(definition: Dictionary) -> Rect2:
	var layers: Variant = definition.get("layers", [])
	if layers is Array:
		for layer: Variant in layers:
			if not layer is Dictionary or str(layer.get("kind", "")) != "sprite":
				continue
			var path := str(layer.get("path", ""))
			if not path.begins_with("res://art/environment/scenes/"):
				continue
			var native := RigLibrary.texture_size(path)
			if native == Vector2.ZERO:
				continue
			return Rect2(StageLayers.vec2_of(layer.get("pos", [0, 0])), native * float(layer.get("scale", 1.0)))
	return DEFAULT_ART

## 把鏡頭推到看到的範圍完全在 allowed 裡（看得到的範圍比 allowed 大時置中）。
static func clamp_cam(cam: Vector2, zoom: float, screen: Vector2, allowed: Rect2) -> Vector2:
	var half := screen * 0.5 / zoom
	var result := cam
	for axis in 2:
		var low := allowed.position[axis] + half[axis]
		var high := allowed.end[axis] - half[axis]
		result[axis] = (low + high) * 0.5 if low > high else clampf(cam[axis], low, high)
	return result
