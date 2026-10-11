class_name MeleeMove
extends RefCounted
## 一招的完整資料（NE-277）：MeleeSet 的招式表裡每一招除了時間、判定、傷害之外，還自己帶齊下面這些欄位。
## 這裡只放「讀」與「檢查」，不存狀態；招式資料仍是 JSON 的字典，舊欄位照舊由 MeleeSet 讀。
##
##   follow    跟隨段的秒數（收招的前段：武器甩過頭、身體還在往前，之後才是真正的收回）。四段＝前搖、出招、跟隨、收招。
##   hits      判定：[{at 出招後幾秒開始, length 持續幾秒, damage 這一段的傷害（可省略＝招式的 damage）}]，多段攻擊寫多筆；
##             每一段開始時同一個目標可以再被打一次（同一段裡只算一次）。
##   body      身體怎麼動：step 出手時骨盆往前移幾像素（踏步）、drop 往下壓幾像素、twist 胸口轉多少（弧度，正的是往前傾）。
##   path      武器走的路徑：[{t 招式進度 0～1, angle 握把在肩膀的哪個方向（朝右空間的弧度，0＝正前方、正的往下）,
##             reach 握把離肩膀多遠（骨架單位，主角手臂全長約 14）, tilt 武器相對這個方向再轉多少（可省略＝0，順著手臂）}]，
##             4～6 個關鍵點；手去握武器（前手的掌心追著這條路徑），不是武器跟著手臂。
##   grip      握法：hands 1＝單手、2＝雙手（另一隻手握在桿上，位置由武器外觀資料的 second 決定）。
##   feedback  命中回饋：reaction 敵人的反應輕重（light／heavy，要和 stagger 一致）、low 低頻的悶擊聲、high 高頻的切割或撞擊聲。
##
## 動作進度（角色姿勢與 path 的 t）：前搖 0～0.4、出招 0.4～0.7、收招 0.7～1（跟隨段在收招的最前面）。

const FIELDS: PackedStringArray = ["follow", "hits", "body", "path", "grip", "feedback"]
const REACTIONS: PackedStringArray = ["light", "heavy"]
const MAX_HITS := 6
const PATH_KEYS := Vector2i(4, 6)
const BODY_LIMITS := {"step": Vector2(-16.0, 24.0), "drop": Vector2(-4.0, 14.0), "twist": Vector2(-0.8, 0.8)}
const REACH_LIMITS := Vector2(2.0, 14.0)
const TILT_LIMIT := PI
## 姿勢的關鍵點數量（art/rigs/action_poses.json 的 rin.melee_<pose>）：每一招 4～6 個。
const POSE_KEYS := Vector2i(4, 6)
const POSE_PREFIX := "rin.melee_"
const POSES_PATH := "res://art/rigs/action_poses.json"
const EPSILON := 0.0001


## 跟隨段秒數；沒寫用收招的四成。
static func follow(def: Dictionary) -> float:
	var value: Variant = def.get("follow")
	return float(value) if _number(value) else float(def.get("recovery", 0.0)) * 0.4


## 判定的各段；沒寫就是「出招開始一次，持續整個出招」（搬到新格式之前的行為）。
static func hits(def: Dictionary) -> Array:
	var value: Variant = def.get("hits")
	if value is Array and not (value as Array).is_empty():
		return value
	return [{"at": 0.0, "length": float(def.get("active", 0.0))}]


## 第 i 段的傷害。
static func hit_damage(def: Dictionary, i: int) -> int:
	var list := hits(def)
	if i >= 0 and i < list.size() and _number((list[i] as Dictionary).get("damage")):
		return int((list[i] as Dictionary)["damage"])
	return int(def.get("damage", 0))


## 身體的位移在這個動作進度的值：前搖時往後縮一點（預兆）、出手時到最前、跟隨段留在那裡、收招回到原位。
## 回傳 (骨盆前後, 骨盆上下, 胸口轉角)。
static func body_at(def: Dictionary, progress: float) -> Vector3:
	var body: Variant = def.get("body")
	if not body is Dictionary or progress < 0.0:
		return Vector3.ZERO
	var step := float((body as Dictionary).get("step", 0.0))
	var drop := float((body as Dictionary).get("drop", 0.0))
	var twist := float((body as Dictionary).get("twist", 0.0))
	var follow_end := 0.7 + 0.3 * clampf(follow(def) / maxf(EPSILON, float(def.get("recovery", 1.0))), 0.0, 1.0)
	var lead: float
	var low: float
	if progress < 0.4:
		var u := progress / 0.4
		lead = lerpf(0.0, -0.25, smoothstep(0.0, 0.6, u)) if u < 0.6 else lerpf(-0.25, 1.0, smoothstep(0.6, 1.0, u))
		low = smoothstep(0.0, 1.0, u)
	elif progress < follow_end:
		lead = 1.0
		low = 1.0
	else:
		var v := smoothstep(follow_end, 1.0, progress)
		lead = 1.0 - v
		low = 1.0 - v
	return Vector3(step * lead, drop * low, twist * lead)


## 武器路徑在這個動作進度的 (握把方向, 握把離肩膀的距離, 武器的傾角)；沒有路徑回傳空陣列。關鍵點之間用 smoothstep 內插。
static func path_at(def: Dictionary, progress: float) -> PackedFloat32Array:
	var path: Variant = def.get("path")
	if not path is Array or (path as Array).size() < 2 or progress < 0.0:
		return PackedFloat32Array()
	var keys: Array = path
	var first: Dictionary = keys[0]
	if progress <= float(first["t"]):
		return PackedFloat32Array([float(first["angle"]), float(first["reach"]), float(first.get("tilt", 0.0))])
	for i in range(keys.size() - 1):
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if progress <= float(b["t"]):
			var w := smoothstep(0.0, 1.0, (progress - float(a["t"])) / maxf(EPSILON, float(b["t"]) - float(a["t"])))
			return PackedFloat32Array([lerpf(float(a["angle"]), float(b["angle"]), w), lerpf(float(a["reach"]), float(b["reach"]), w),
					lerpf(float(a.get("tilt", 0.0)), float(b.get("tilt", 0.0)), w)])
	var last: Dictionary = keys[keys.size() - 1]
	return PackedFloat32Array([float(last["angle"]), float(last["reach"]), float(last.get("tilt", 0.0))])


static func hands(def: Dictionary) -> int:
	var grip: Variant = def.get("grip")
	return int((grip as Dictionary).get("hands", 1)) if grip is Dictionary else 1


static func reaction(def: Dictionary) -> String:
	var feedback: Variant = def.get("feedback")
	if feedback is Dictionary and (feedback as Dictionary).get("reaction") is String:
		return str(feedback["reaction"])
	return "heavy" if int(def.get("stagger", 0)) >= 3 else "light"


## 命中聲的兩層：low 低頻悶擊、high 高頻（沒寫用招式的 sounds.hit）。
static func hit_layers(def: Dictionary) -> Array[StringName]:
	var feedback: Variant = def.get("feedback")
	var layers: Array[StringName] = []
	var high := StringName(str(MeleeModule.sounds_of(def)["hit"]))
	if feedback is Dictionary:
		if str((feedback as Dictionary).get("high", "")) != "":
			high = StringName(str(feedback["high"]))
		if str((feedback as Dictionary).get("low", "")) != "":
			layers.append(StringName(str(feedback["low"])))
	layers.append(high)
	return layers


# ---------------------------------------------------------------------------
# 資料檢查
# ---------------------------------------------------------------------------

## 新欄位的格式與數值（有寫才檢查；舊格式的招式照舊可以讀）。錯誤訊息帶「檔案/attacks/招式/欄位」。
static func problems(raw: Dictionary, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var active := float(raw.get("active", 0.0)) if _number(raw.get("active")) else 0.0
	var recovery := float(raw.get("recovery", 0.0)) if _number(raw.get("recovery")) else 0.0
	if raw.has("follow"):
		if not _number(raw.follow) or float(raw.follow) <= 0.0 or float(raw.follow) > recovery + EPSILON:
			errors.append(source + "/follow must be a positive number no longer than recovery")
	if raw.has("hits"):
		errors.append_array(_hits_problems(raw.hits, active, source + "/hits"))
	if raw.has("body"):
		errors.append_array(_body_problems(raw.body, source + "/body"))
	if raw.has("path"):
		errors.append_array(_path_problems(raw.path, source + "/path"))
	if raw.has("grip"):
		var grip: Variant = raw.grip
		if not grip is Dictionary or not _number((grip as Dictionary).get("hands")) or int(grip.hands) not in [1, 2] or float(grip.hands) != floorf(float(grip.hands)):
			errors.append(source + "/grip/hands must be 1 or 2")
		elif (grip as Dictionary).size() != 1:
			errors.append(source + "/grip has unknown fields")
	if raw.has("feedback"):
		errors.append_array(_feedback_problems(raw.feedback, raw, source + "/feedback"))
	return errors


## 完整格式（出貨的招式資料都要有）：六個欄位都要寫，姿勢要有 4～6 個關鍵點。
## 空手／拿槍時的預設近戰沒有近戰武器可握（手上是槍），不寫武器路徑（needs_path＝false）。
static func completeness_problems(raw: Dictionary, source: String, needs_path := true) -> PackedStringArray:
	var errors := PackedStringArray()
	for field in FIELDS:
		if field == "path" and not needs_path:
			continue
		if not raw.has(field):
			errors.append("%s/%s missing (every move carries follow, hits, body, path, grip and feedback)" % [source, field])
	var pose := str(raw.get("pose", "slash"))
	var actions: Variant = (load(POSES_PATH) as JSON).data.get("actions", {}) if ResourceLoader.exists(POSES_PATH) and load(POSES_PATH) is JSON else {}
	var action: Variant = (actions as Dictionary).get(POSE_PREFIX + pose) if actions is Dictionary else null
	if not action is Dictionary:
		errors.append("%s/pose %s%s not found in %s" % [source, POSE_PREFIX, pose, POSES_PATH])
	else:
		var count := ((action as Dictionary).get("keys", []) as Array).size()
		if count < POSE_KEYS.x or count > POSE_KEYS.y:
			errors.append("%s/pose %s%s has %d key poses; a move needs %d–%d" % [source, POSE_PREFIX, pose, count, POSE_KEYS.x, POSE_KEYS.y])
	return errors


static func _hits_problems(value: Variant, active: float, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Array or (value as Array).is_empty() or (value as Array).size() > MAX_HITS:
		return PackedStringArray([source + " must list 1–%d hit windows" % MAX_HITS])
	var previous_end := -1.0
	for i in (value as Array).size():
		var hit: Variant = value[i]
		var where := "%s/%d" % [source, i]
		if not hit is Dictionary:
			errors.append(where + " must be an object")
			continue
		for key: Variant in hit:
			if key not in ["at", "length", "damage"]:
				errors.append("%s/%s unknown field" % [where, key])
		if not _number(hit.get("at")) or not _number(hit.get("length")) or float(hit.at) < 0.0 or float(hit.length) <= 0.0:
			errors.append(where + " needs at ≥ 0 and length > 0")
			continue
		if float(hit.at) + float(hit.length) > active + EPSILON:
			errors.append(where + " ends after the active phase")
		if float(hit.at) < previous_end - EPSILON:
			errors.append(where + " overlaps or precedes the previous window")
		previous_end = float(hit.at) + float(hit.length)
		if hit.has("damage") and (not _number(hit.damage) or float(hit.damage) <= 0.0 or float(hit.damage) != floorf(float(hit.damage)) or float(hit.damage) > 10000.0):
			errors.append(where + "/damage must be a positive integer")
	return errors


static func _body_problems(value: Variant, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		return PackedStringArray([source + " must be an object"])
	for key: Variant in value:
		if not BODY_LIMITS.has(key):
			errors.append("%s/%s unknown field" % [source, key])
		elif not _number(value[key]) or float(value[key]) < (BODY_LIMITS[key] as Vector2).x or float(value[key]) > (BODY_LIMITS[key] as Vector2).y:
			errors.append("%s/%s must be within %s" % [source, key, BODY_LIMITS[key]])
	return errors


static func _path_problems(value: Variant, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Array or (value as Array).size() < PATH_KEYS.x or (value as Array).size() > PATH_KEYS.y:
		return PackedStringArray([source + " must have %d–%d keys" % [PATH_KEYS.x, PATH_KEYS.y]])
	var previous := -1.0
	for i in (value as Array).size():
		var key: Variant = value[i]
		var where := "%s/%d" % [source, i]
		if not key is Dictionary or not _number(key.get("t")) or not _number(key.get("angle")) or not _number(key.get("reach")):
			errors.append(where + " needs numeric t, angle and reach")
			continue
		for field: Variant in key:
			if field not in ["t", "angle", "reach", "tilt"]:
				errors.append("%s/%s unknown field" % [where, field])
		if float(key.t) <= previous or float(key.t) < 0.0 or float(key.t) > 1.0:
			errors.append(where + "/t must increase within 0–1")
		previous = float(key.t)
		if absf(float(key.angle)) > TAU:
			errors.append(where + "/angle must be within ±2π")
		if float(key.reach) < REACH_LIMITS.x or float(key.reach) > REACH_LIMITS.y:
			errors.append(where + "/reach must be within %s (the arm is about 14 rig units long)" % REACH_LIMITS)
		if key.has("tilt") and (not _number(key.tilt) or absf(float(key.tilt)) > TILT_LIMIT):
			errors.append(where + "/tilt must be a number within ±π")
	if errors.is_empty() and (absf(float(value[0].t)) > EPSILON or absf(float(value[-1].t) - 1.0) > EPSILON):
		errors.append(source + " must start at t 0 and end at t 1")
	return errors


static func _feedback_problems(value: Variant, raw: Dictionary, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		return PackedStringArray([source + " must be an object"])
	for key: Variant in value:
		if key not in ["reaction", "low", "high"]:
			errors.append("%s/%s unknown field" % [source, key])
	var react: Variant = value.get("reaction")
	if not react is String or not REACTIONS.has(react):
		errors.append(source + "/reaction must be light or heavy")
	elif _number(raw.get("stagger", 2)) and ((react == "heavy") != (int(raw.get("stagger", 2)) >= 3)):
		errors.append(source + "/reaction must match stagger (heavy ⇔ stagger ≥ 3)")
	for key: String in ["low", "high"]:
		if value.has(key) and (not value[key] is String or not Sfx.has_named(StringName(value[key]))):
			errors.append("%s/%s unknown sound" % [source, key])
	return errors


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
