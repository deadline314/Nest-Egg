class_name StageFitAudit
extends RefCounted
## 過場舞台的尺寸與接觸檢查（ST-10）：以主角身高 H 當尺，檢查
##   stage_prop_proportion／stage_furniture_size——擺設與立繪裡的家具高度在比例表的範圍內（例如燈籠 0.15～0.35H、桌面 0.41～0.45H）；
##   stage_prop_unclassified——舞台上補的擺設沒有登記種類（新擺設要先分類，才知道合理大小）；
##   stage_furniture_floating——家具底邊不在舞台地面線上，又沒有標明支撐；
##   stage_sit_unsupported——演員坐著，但座位家具不在臀部下方，或腳底比座面還高；
##   stage_actor_overlap——站著的演員和同一層（plane: actor）的家具重疊；
##   stage_fit_invalid——比例表或家具資料本身寫錯。
## 比例表在 data/cutscene/stage_proportions.json；家具登記在舞台檔的 furniture。都是資料，新增擺設、家具、種類不用改程式。
## 回傳的問題格式同 SceneAudit（severity、code、where、message），where 指出場景、舞台與物件。

const PATH := "res://data/cutscene/stage_proportions.json"
## 讀不到比例表時用的身高（世界像素）與容許（H）。
const DEFAULT_ACTOR_HEIGHT := 58.0
const DEFAULT_TOLERANCE := 0.05
## 坐著的臀部可以超出座位左右邊緣多少（H）；站著的腳和家具邊緣重疊多少以內不算（H）。
const SEAT_MARGIN := 0.15
const OVERLAP_MARGIN := 0.1

static var _table: Dictionary = {}
static var _loaded := false


## 比例表（快取）；讀不到時記錄錯誤並回傳空表（只做不需要比例表的檢查）。
static func table() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("[StageFitAudit] 讀不到舞台比例表 %s，略過尺寸檢查" % PATH)
		else:
			_table = parsed
	return _table


## 測試用：換一份比例表（傳空字典則重新讀檔）。
static func use_table(value: Dictionary) -> void:
	_table = value
	_loaded = not value.is_empty()


static func actor_height() -> float:
	return float(table().get("actor_height", DEFAULT_ACTOR_HEIGHT))


## 比例表本身的檢查：每個種類是 [低, 高]、擺設登記的種類存在、body 是 0～1 的區間。
static func validate_table() -> PackedStringArray:
	var problems := PackedStringArray()
	var data := table()
	if data.is_empty():
		problems.append("%s 讀不到" % PATH)
		return problems
	var kinds: Variant = data.get("kinds")
	if typeof(kinds) != TYPE_DICTIONARY:
		problems.append("%s 缺少 kinds" % PATH)
		return problems
	for kind: String in kinds:
		var range_value: Variant = kinds[kind]
		if not _is_range(range_value):
			problems.append("%s 的種類 %s 要是 [最低, 最高]" % [PATH, kind])
	for kind: Variant in data.get("seat_kinds", []):
		if not (kinds as Dictionary).has(str(kind)):
			problems.append("%s 的 seat_kinds 有不存在的種類 %s" % [PATH, kind])
	var props: Variant = data.get("props", {})
	if typeof(props) != TYPE_DICTIONARY:
		problems.append("%s 的 props 要是物件" % PATH)
		return problems
	for id: String in props:
		var entry: Variant = props[id]
		if typeof(entry) != TYPE_DICTIONARY or not (kinds as Dictionary).has(str((entry as Dictionary).get("kind", ""))):
			problems.append("%s 的擺設 %s 沒有登記存在的種類" % [PATH, id])
			continue
		if (entry as Dictionary).has("body") and not _is_unit_range((entry as Dictionary)["body"]):
			problems.append("%s 的擺設 %s 的 body 要是 0～1 之間的 [上緣, 下緣]" % [PATH, id])
	return problems


## 舞台上補的場景擺設：種類與大小。prop_id 是擺設 id，height_world 是擺設的世界高度。
static func prop_issues(stage_id: String, prop_id: String, height_world: float) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var data := table()
	if data.is_empty():
		return issues
	var where := "%s／%s" % [stage_id, prop_id]
	var entry: Variant = (data.get("props", {}) as Dictionary).get(prop_id)
	if typeof(entry) != TYPE_DICTIONARY:
		_add(issues, "stage_prop_unclassified", where, "舞台擺設沒有在 %s 登記種類，無法判斷大小是否合理" % PATH)
		return issues
	if not str((entry as Dictionary).get("exempt", "")).strip_edges().is_empty():
		return issues
	var body: Array = (entry as Dictionary).get("body", [0.0, 1.0])
	var visible_height := height_world * (float(body[1]) - float(body[0])) if _is_unit_range(body) else height_world
	var problem := _size_problem(str((entry as Dictionary).get("kind", "")), visible_height / actor_height())
	if not problem.is_empty():
		_add(issues, "stage_prop_proportion", where, problem)
	return issues


## 舞台檔的 furniture（立繪裡畫好的家具）：資料格式、大小、落地。actor_scale 是這個舞台的演員縮放。
static func furniture_issues(stage_id: String, def: Dictionary, actor_scale: float) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var floor_y := float(def.get("floor", -1.0))
	var stage_h := actor_height() * actor_scale
	for item: Variant in def.get("furniture", []):
		var where := "%s／%s" % [stage_id, (item as Dictionary).get("id", "?") if item is Dictionary else "?"]
		var rect := furniture_rect(item)
		if rect == Rect2() or not (item as Dictionary).has("id"):
			_add(issues, "stage_fit_invalid", where, "家具要有 id、kind 與 rect [x, y, 寬, 高]（寬高大於 0）")
			continue
		var furniture := item as Dictionary
		var kind := str(furniture.get("kind", ""))
		if not (table().get("kinds", {}) as Dictionary).has(kind) and not table().is_empty():
			_add(issues, "stage_fit_invalid", where, "家具種類「%s」不在比例表 %s 裡" % [kind, PATH])
			continue
		if stage_h > 0.0 and str(furniture.get("exempt", "")).strip_edges().is_empty():
			var problem := _size_problem(kind, rect.size.y / stage_h)
			if not problem.is_empty():
				_add(issues, "stage_furniture_size", where, problem)
		if floor_y >= 0.0 and str(furniture.get("support", "")).is_empty() and absf(rect.end.y - floor_y) > SceneAudit.STAGE_FLOOR_TOLERANCE:
			_add(issues, "stage_furniture_floating", where, "底邊 y=%.0f，舞台地板在 %.0f（差 %.0f 像素），又沒有標明支撐" % [rect.end.y, floor_y, rect.end.y - floor_y])
	return issues


## 演員在某個姿勢、某個位置時，和家具的接觸：坐要有座位、站著不和同一層的家具重疊。
## feet 是演員原點（腳底）；actor_scale 是這個演員的縮放。
static func contact_issues(scene_id: String, stage_id: String, def: Dictionary, label: String, pose: String, feet: Vector2, actor_scale: float) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var floor_y := float(def.get("floor", -1.0))
	if floor_y < 0.0:
		return issues  # 舊式舞台沒有地面線，也沒有家具資料
	var stage_h := actor_height() * maxf(actor_scale, 0.01)
	var where := "%s／%s" % [scene_id, stage_id]
	var seat_kinds: Array = table().get("seat_kinds", [])
	if pose == "sit":
		var seated := false
		for item: Variant in def.get("furniture", []):
			var rect := furniture_rect(item)
			if rect == Rect2() or not seat_kinds.has(str((item as Dictionary).get("kind", ""))):
				continue
			var margin := SEAT_MARGIN * stage_h
			if feet.x >= rect.position.x - margin and feet.x <= rect.end.x + margin and feet.y > rect.position.y and feet.y <= floor_y + SceneAudit.STAGE_FLOOR_TOLERANCE:
				seated = true
				break
		if not seated:
			_add(issues, "stage_sit_unsupported", where, "%s 在 (%.0f, %.0f) 坐著，但臀部下方沒有登記的座位家具（舞台檔的 furniture，種類 %s）" % [label, feet.x, feet.y, ", ".join(PackedStringArray(seat_kinds))])
		return issues
	if SceneAudit.STAGE_FREE_POSES.has(pose):
		return issues
	for item: Variant in def.get("furniture", []):
		var rect := furniture_rect(item)
		if rect == Rect2() or str((item as Dictionary).get("plane", "back")) != "actor":
			continue
		var margin := OVERLAP_MARGIN * stage_h
		if feet.x > rect.position.x + margin and feet.x < rect.end.x - margin:
			_add(issues, "stage_actor_overlap", where, "%s 站在 x=%.0f，和同一層的家具 %s（x %.0f～%.0f）重疊" % [label, feet.x, (item as Dictionary)["id"], rect.position.x, rect.end.x])
	return issues


## 家具資料的 rect；格式不對回傳空的 Rect2。
static func furniture_rect(item: Variant) -> Rect2:
	if typeof(item) != TYPE_DICTIONARY:
		return Rect2()
	var raw: Variant = (item as Dictionary).get("rect")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 4:
		return Rect2()
	for value: Variant in raw:
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return Rect2()
	var rect := Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return rect if rect.size.x > 0.0 and rect.size.y > 0.0 else Rect2()


## 高度（H 的倍數）不在種類範圍時回傳說明，否則空字串。
static func _size_problem(kind: String, height_h: float) -> String:
	var kinds: Dictionary = table().get("kinds", {})
	if not kinds.has(kind) or not _is_range(kinds[kind]):
		return "種類「%s」不在比例表 %s 裡" % [kind, PATH]
	var low := float(kinds[kind][0])
	var high := float(kinds[kind][1])
	var tolerance := float(table().get("tolerance", DEFAULT_TOLERANCE))
	if height_h < low - tolerance or height_h > high + tolerance:
		return "%s 高 %.2fH，比例表是 %.2f～%.2fH（H＝主角身高）" % [kind, height_h, low, high]
	return ""


static func _is_range(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and (value as Array).size() == 2 and float(value[0]) <= float(value[1]) and float(value[0]) >= 0.0


static func _is_unit_range(value: Variant) -> bool:
	return _is_range(value) and float(value[1]) <= 1.0 and float(value[0]) < float(value[1])


static func _add(issues: Array[Dictionary], code: String, where: String, message: String) -> void:
	issues.append({"severity": SceneAudit.WARN, "code": code, "where": where, "message": message})
