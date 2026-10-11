class_name MeleeSet
extends RefCounted
## 一組近戰招式：combo（連段順序）＋ attacks（招式表）。前搖、出招、收招、判定形狀、前衝、命中取消窗口都是資料。
## 預設那組是 data/feel/melee.json（MeleeData 轉接）；每把近戰武器各有一份 data/melee/<id>.json。
## 資料缺漏或損毀時記錄「檔案、招式、欄位」並退回內建的安全預設（單一輕斬），不崩潰。

const FIELDS: PackedStringArray = ["windup", "active", "recovery", "cancel_after", "damage", "range", "advance", "move_scale", "stagger", "impact", "knockback", "event", "trail", "sounds",
		"shape", "height", "arc_degrees", "min_range", "aim_follow", "sweep", "hitstop", "pose", "impact_fx", "guard_cost"]
## Broad authoring bounds, preserving every existing attack's balance values.
const COMBO_WINDOW_MAX := 2.0
const NUMERIC_LIMITS := {
	"windup": 5.0, "active": 5.0, "recovery": 5.0, "cancel_after": 5.0,
	"damage": 10000.0, "range": 512.0, "advance": 10000.0, "move_scale": 1.0,
	"stagger": 1000.0, "impact": 100.0, "height": 512.0, "arc_degrees": 360.0,
	"min_range": 512.0, "hitstop": 0.25, "guard_cost": 100.0,
}
const KNOCKBACK_COMPONENT_MAX := 10000.0
const TRAIL_NUMERIC_LIMITS := {"radius": 512.0, "arc": 360.0, "width": 64.0}
## 判定形狀：box＝面前的矩形（range 長 × height 高）；arc＝以身體為圓心、半徑 range 的扇形（arc_degrees 為總角度，360＝繞身一圈）。
const SHAPES: PackedStringArray = ["box", "arc"]
## 軌跡樣式：arc 弧形揮砍、thrust 沿揮擊方向的直線刺擊、lash 甩動的鞭痕；命中與揮擊特效種類見 MeleeFx.KINDS。
const TRAIL_STYLES: PackedStringArray = ["arc", "thrust", "lash"]
## 軌跡的限制：持續秒數範圍、峰值亮度上限（HDR 泛光下不過曝）、同時最多幾條。
const TRAIL_LIFE_RANGE := Vector2(0.08, 0.2)
const TRAIL_BRIGHTNESS_MAX := 2.2
## 判定框高度的預設值 0 ＝ 用角色身高。
const DEFAULT_ATTACK := {"windup": 0.05, "active": 0.06, "recovery": 0.16, "cancel_after": 0.05, "damage": 2, "range": 26.0, "advance": 0.0, "move_scale": 0.4, "stagger": 2, "impact": 6.0,
		"knockback": [180.0, -60.0], "event": "player_melee_hit", "trail": {"radius": 20.0, "arc": 130.0, "life": 0.09, "width": 3.0, "brightness": 1.7, "afterimage": true},
		"sounds": {"swing": "melee_swing", "hit": "melee_hit"},
		"shape": "box", "height": 0.0, "arc_degrees": 120.0, "min_range": 0.0, "aim_follow": false, "sweep": false, "hitstop": 0.0, "pose": "slash", "impact_fx": "slash", "guard_cost": 0.0}

var path := ""
var _data: Dictionary = {}
var _loaded := false
var _load_errors := PackedStringArray()


func _init(p_path: String) -> void:
	path = p_path


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	_load_errors = definition_problems(json.data if json != null else null, path)
	if not _load_errors.is_empty():
		for error in _load_errors:
			push_error("[MeleeSet] " + error + "; using safe default attack")
		_data = {"combo": ["light"], "combo_window": 0.5, "attacks": {"light": DEFAULT_ATTACK.duplicate(true)}}
		return
	_data = json.data


func reload() -> void:
	_loaded = false
	_data = {}
	_load_errors.clear()
	_ensure_loaded()


func combo(extended := false) -> Array:
	_ensure_loaded()
	var list: Variant = _data.get("combo", [])
	var result: Array = (list as Array).duplicate() if typeof(list) == TYPE_ARRAY and not (list as Array).is_empty() else ["light_1"]
	var extension: Variant = _data.get("extension", {})
	if extended and extension is Dictionary and not extension_upgrade().is_empty():
		var id := str(extension.get("attack", ""))
		var tail := live_attack(id)
		var problems := _attack_problems(tail, "%s/attacks/%s" % [path, id])
		problems.append_array(_tail_role_problems(tail, "%s/attacks/%s" % [path, id]))
		for problem in problems:
			push_error("[MeleeSet] " + problem + "; refusing unsafe extension")
		if problems.is_empty() and not tail.is_empty() and not result.has(id):
			result.append(id)
	return result


func extension_upgrade() -> StringName:
	_ensure_loaded()
	var extension: Variant = _data.get("extension", {})
	return StringName(str(extension.get("upgrade", ""))) if extension is Dictionary else &""


func extension_attack() -> String:
	_ensure_loaded()
	var extension: Variant = _data.get("extension", {})
	return str(extension.get("attack", "")) if extension is Dictionary else ""


## 這把武器拿在手上時的待機聲（音效庫的 id；沒有就回傳空字串）。
func idle_sound() -> StringName:
	_ensure_loaded()
	return StringName(str(_data.get("idle_sound", "")))


func combo_window() -> float:
	_ensure_loaded()
	var value: Variant = _data.get("combo_window", 0.5)
	if not _number(value) or float(value) <= 0.0 or float(value) > COMBO_WINDOW_MAX:
		push_error("[MeleeSet] %s/combo_window outside finite (0,%s]; using 0.5" % [path, COMBO_WINDOW_MAX])
		return 0.5
	return float(value)


## 某一招的即時資料（實驗室直接改這份就會影響下一次出招）；不存在回傳空字典。
func live_attack(id: String) -> Dictionary:
	_ensure_loaded()
	var attacks: Dictionary = _data.get("attacks", {})
	return attacks[id] if attacks.has(id) and typeof(attacks[id]) == TYPE_DICTIONARY else {}


## 某一招的資料（缺欄位補預設）；招式不存在時回傳預設並記錄。
func attack(id: String, frozen_paid_tail := false) -> Dictionary:
	_ensure_loaded()
	var attacks: Dictionary = _data.get("attacks", {})
	var result := DEFAULT_ATTACK.duplicate(true)
	var paid_tail := frozen_paid_tail or (not extension_attack().is_empty() and id == extension_attack())
	if not attacks.has(id) or typeof(attacks[id]) != TYPE_DICTIONARY:
		if paid_tail:
			push_error("[MeleeSet] %s/attacks/%s paid tail missing; refusing swing, no free fallback" % [path, id])
			return {}
		push_error("[MeleeSet] %s 沒有招式「%s」，改用預設" % [path, id])
		return result
	var problems := _attack_problems(attacks[id], "%s/attacks/%s" % [path, id])
	if paid_tail:
		problems.append_array(_tail_role_problems(attacks[id], "%s/attacks/%s" % [path, id]))
	if not problems.is_empty():
		for problem in problems:
			push_error("[MeleeSet] " + problem + ("; refusing paid tail, no free fallback" if paid_tail else "; using safe default attack"))
		return {} if paid_tail else result
	for key: String in (attacks[id] as Dictionary).keys():
		if not key.begins_with("_"):
			result[key] = (attacks[id] as Dictionary)[key]
	return result


## 整組的一次完整連段秒數與平均傷害率（說明與平衡檢查用）。
func damage_per_second() -> float:
	var total_damage := 0.0
	var total_time := 0.0
	for id: Variant in combo():
		var def := attack(str(id))
		total_damage += float(def["damage"])
		total_time += float(def["windup"]) + float(def["active"]) + float(def["recovery"])
	return total_damage / maxf(0.01, total_time)


## 這組裡最遠的攻擊距離。
func max_range() -> float:
	var best := 0.0
	for id: Variant in combo():
		best = maxf(best, float(attack(str(id))["range"]))
	return best


## Validate raw JSON before casts or indexing; errors retain source/attack/field.
static func definition_problems(raw: Variant, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not raw is Dictionary or not raw.get("attacks") is Dictionary:
		return PackedStringArray([source + "/attacks must be an object"])
	for key: Variant in raw:
		if not key is String or (key not in ["combo", "combo_window", "attacks", "extension", "idle_sound"] and not key.begins_with("_")):
			errors.append("%s/%s unknown field" % [source, key])
	var attacks: Dictionary = raw.attacks
	var combo: Variant = raw.get("combo")
	if not combo is Array or combo.is_empty():
		errors.append(source + "/combo must be a nonempty array")
	else:
		for id: Variant in combo:
			if not id is String or id.is_empty() or not attacks.has(id):
				errors.append("%s/combo unknown attack: %s" % [source, id])
	if not _number(raw.get("combo_window", 0.5)) or float(raw.get("combo_window", 0.5)) <= 0.0 or float(raw.get("combo_window", 0.5)) > COMBO_WINDOW_MAX:
		errors.append(source + "/combo_window must be finite in (0,%s]" % COMBO_WINDOW_MAX)
	for id: Variant in attacks:
		if not id is String or id.is_empty():
			errors.append("%s/attacks invalid id: %s" % [source, id])
			continue
		errors.append_array(_attack_problems(attacks[id], "%s/attacks/%s" % [source, id]))
	if raw.has("extension"):
		var extension: Variant = raw.extension
		if not extension is Dictionary:
			errors.append(source + "/extension must be an object")
		else:
			for key: Variant in extension:
				if key not in ["upgrade", "attack"]:
					errors.append("%s/extension/%s unknown field" % [source, key])
			var upgrade: Variant = extension.get("upgrade")
			var id: Variant = extension.get("attack")
			if not upgrade is String or upgrade.is_empty():
				errors.append(source + "/extension/upgrade must name an upgrade")
			if not id is String or not attacks.get(id) is Dictionary or (combo is Array and combo.has(id)):
				errors.append(source + "/extension/attack must name a distinct tail")
			else:
				errors.append_array(_tail_role_problems(attacks[id], "%s/attacks/%s" % [source, id]))
	return errors


## The same role constraints apply to initial validation and every live swing.
## Missing ordinary moves retain their fallback; a paid commitment never does.
static func _tail_role_problems(raw: Variant, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not raw is Dictionary:
		return PackedStringArray([source + " paid tail must be an object"])
	if not _number(raw.get("guard_cost")) or float(raw.guard_cost) <= 0.0 or float(raw.guard_cost) > NUMERIC_LIMITS.guard_cost:
		errors.append(source + "/guard_cost tail must have a positive cost within the supported bound")
	if not _number(raw.get("cancel_after")) or not _number(raw.get("recovery")) or raw.cancel_after != raw.recovery:
		errors.append(source + "/cancel_after tail must pay full recovery")
	return errors


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _attack_problems(raw: Variant, source: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not raw is Dictionary:
		return PackedStringArray([source + " must be an object"])
	for key: Variant in raw:
		if not key is String or (not FIELDS.has(key) and not key.begins_with("_")):
			errors.append("%s/%s unknown field" % [source, key])
	var d := DEFAULT_ATTACK.duplicate(true)
	d.merge(raw, true)
	for field: String in ["windup", "active", "recovery", "cancel_after", "damage", "range", "advance", "move_scale", "stagger", "impact", "height", "arc_degrees", "min_range", "hitstop", "guard_cost"]:
		if not _number(d[field]):
			errors.append("%s/%s must be a finite number" % [source, field])
	for field: String in NUMERIC_LIMITS:
		if _number(d[field]) and absf(float(d[field])) > float(NUMERIC_LIMITS[field]):
			errors.append("%s/%s exceeds supported magnitude %s" % [source, field, NUMERIC_LIMITS[field]])
	# Stop before arithmetic/coercion on invalid values.
	if not errors.is_empty():
		return errors
	for field: String in ["windup", "active", "recovery", "damage", "range"]:
		if not raw.has(field) or float(d[field]) <= 0.0:
			errors.append("%s/%s must be positive" % [source, field])
	for field: String in ["cancel_after", "stagger", "impact", "height", "min_range", "hitstop", "guard_cost"]:
		if float(d[field]) < 0.0:
			errors.append("%s/%s cannot be negative" % [source, field])
	for field: String in ["damage", "stagger"]:
		if float(d[field]) != floorf(float(d[field])) or float(d[field]) >= 9223372036854775808.0:
			errors.append("%s/%s must be a representable integer" % [source, field])
	if not is_finite(float(d.windup) + float(d.active) + float(d.recovery)):
		errors.append(source + "/recovery total duration must be finite")
	if float(d.cancel_after) > float(d.recovery):
		errors.append(source + "/cancel_after exceeds recovery")
	if float(d.min_range) >= float(d.range):
		errors.append(source + "/min_range must be below range")
	if float(d.guard_cost) > 100.0:
		errors.append(source + "/guard_cost exceeds 100")
	if float(d.move_scale) < 0.0 or float(d.move_scale) > 1.0:
		errors.append(source + "/move_scale must be in 0–1")
	if float(d.arc_degrees) <= 0.0 or float(d.arc_degrees) > 360.0:
		errors.append(source + "/arc_degrees must be in (0,360]")
	if not d.knockback is Array or d.knockback.size() != 2 or not _number(d.knockback[0]) or not _number(d.knockback[1]):
		errors.append(source + "/knockback must have two finite numbers")
	elif absf(float(d.knockback[0])) > KNOCKBACK_COMPONENT_MAX or absf(float(d.knockback[1])) > KNOCKBACK_COMPONENT_MAX:
		errors.append("%s/knockback exceeds component magnitude %s" % [source, KNOCKBACK_COMPONENT_MAX])
	for field: String in ["aim_follow", "sweep"]:
		if not d[field] is bool:
			errors.append("%s/%s must be boolean" % [source, field])
	for field: String in ["pose", "shape", "impact_fx", "event"]:
		if not d[field] is String:
			errors.append("%s/%s must be a string" % [source, field])
	if not errors.is_empty():
		return errors
	if not SHAPES.has(d.shape):
		errors.append(source + "/shape unknown shape")
	if not MeleeFx.KINDS.has(d.impact_fx):
		errors.append(source + "/impact_fx unknown effect")
	if d.event is String and not d.event.is_empty() and not Feel.has_event(StringName(d.event)):
		errors.append(source + "/event unknown feedback: " + d.event)
	if not d.sounds is Dictionary:
		errors.append(source + "/sounds must be an object")
	else:
		for key: Variant in d.sounds:
			if key not in ["swing", "hit"] or not d.sounds[key] is String or not Sfx.has_named(StringName(d.sounds[key])):
				errors.append("%s/sounds/%s unknown sound" % [source, key])
	if not raw.get("trail") is Dictionary:
		errors.append(source + "/trail must be an object")
	else:
		var trail: Dictionary = raw.trail
		for key: Variant in trail:
			if key not in ["radius", "arc", "life", "width", "brightness", "afterimage", "color", "style"]:
				errors.append("%s/trail/%s unknown field" % [source, key])
		for field: String in ["radius", "arc", "life", "width", "brightness"]:
			if not _number(trail.get(field)) or float(trail[field]) <= 0.0:
				errors.append("%s/trail/%s must be finite and positive" % [source, field])
		for field: String in TRAIL_NUMERIC_LIMITS:
			if _number(trail.get(field)) and absf(float(trail[field])) > float(TRAIL_NUMERIC_LIMITS[field]):
				errors.append("%s/trail/%s exceeds supported magnitude %s" % [source, field, TRAIL_NUMERIC_LIMITS[field]])
		if _number(trail.get("life")) and (float(trail.life) < TRAIL_LIFE_RANGE.x - 0.0001 or float(trail.life) > TRAIL_LIFE_RANGE.y + 0.0001):
			errors.append(source + "/trail/life outside supported range")
		if _number(trail.get("brightness")) and float(trail.brightness) > TRAIL_BRIGHTNESS_MAX:
			errors.append(source + "/trail/brightness exceeds supported maximum")
		if not trail.get("afterimage", false) is bool:
			errors.append(source + "/trail/afterimage must be boolean")
		if not trail.get("color", "#35e0ff") is String or not str(trail.get("color", "#35e0ff")).is_valid_html_color():
			errors.append(source + "/trail/color must be an HTML color")
		if not trail.get("style", "arc") is String or not TRAIL_STYLES.has(trail.get("style", "arc")):
			errors.append(source + "/trail/style unknown style")
	return errors


func validate() -> PackedStringArray:
	_ensure_loaded()
	var errors := _load_errors.duplicate()
	errors.append_array(definition_problems(_data, path))
	if not idle_sound().is_empty() and not Sfx.has_sound(idle_sound()):
		errors.append("%s 的 idle_sound 引用不存在的聲音「%s」" % [path, idle_sound()])
	return errors
