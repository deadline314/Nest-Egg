class_name MeleeData
extends RefCounted
## 近戰三段資料（data/feel/melee.json）：前搖、出招、收招、判定、前衝、命中取消窗口與連段。
## 資料缺漏或損毀時記錄「檔案、招式、欄位」並退回內建的安全預設（單一輕斬），不崩潰。

const PATH := "res://data/feel/melee.json"
const FIELDS: PackedStringArray = ["windup", "active", "recovery", "cancel_after", "damage", "range", "advance", "move_scale", "stagger", "impact", "knockback", "event", "trail", "sounds"]
## 軌跡的限制：持續秒數範圍、峰值亮度上限（HDR 泛光下不過曝）、同時最多幾條。
const TRAIL_LIFE_RANGE := Vector2(0.08, 0.12)
const TRAIL_BRIGHTNESS_MAX := 2.2
const MAX_TRAILS := 2
const DEFAULT_ATTACK := {"windup": 0.05, "active": 0.06, "recovery": 0.16, "cancel_after": 0.05, "damage": 2, "range": 26.0, "advance": 0.0, "move_scale": 0.4, "stagger": 2, "impact": 6.0, "knockback": [180.0, -60.0], "event": "player_melee_hit", "trail": {"radius": 20.0, "arc": 130.0, "life": 0.09, "width": 3.0, "brightness": 1.7, "afterimage": true}, "sounds": {"swing": "melee_swing", "hit": "melee_hit"}}

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var json: JSON = load(PATH) as JSON if ResourceLoader.exists(PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("attacks")) != TYPE_DICTIONARY:
		push_error("[MeleeData] 無法讀取近戰資料：%s（需要 attacks 字典），改用內建預設" % PATH)
		_data = {"combo": ["light"], "combo_window": 0.5, "buffer": 0.2, "attacks": {"light": DEFAULT_ATTACK}}
		return
	_data = json.data


static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


static func combo() -> Array:
	_ensure_loaded()
	var list: Variant = _data.get("combo", [])
	return list if typeof(list) == TYPE_ARRAY and not (list as Array).is_empty() else ["light_1"]


static func combo_window() -> float:
	_ensure_loaded()
	return float(_data.get("combo_window", 0.5))


static func buffer_time() -> float:
	return InputFeel.window("melee_buffer", 0.2)


## 某一招的即時資料（實驗室直接改這份就會影響下一次出招）；不存在回傳空字典。
static func live_attack(id: String) -> Dictionary:
	_ensure_loaded()
	var attacks: Dictionary = _data.get("attacks", {})
	return attacks[id] if attacks.has(id) and typeof(attacks[id]) == TYPE_DICTIONARY else {}


## 某一招的資料（缺欄位補預設）；招式不存在時回傳預設並記錄一次。
static func attack(id: String) -> Dictionary:
	_ensure_loaded()
	var attacks: Dictionary = _data.get("attacks", {})
	var result := DEFAULT_ATTACK.duplicate(true)
	if not attacks.has(id) or typeof(attacks[id]) != TYPE_DICTIONARY:
		push_error("[MeleeData] %s 沒有招式「%s」，改用預設" % [PATH, id])
		return result
	for key: String in (attacks[id] as Dictionary).keys():
		if not key.begins_with("_"):
			result[key] = (attacks[id] as Dictionary)[key]
	return result


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
static func validate() -> PackedStringArray:
	_ensure_loaded()
	var errors := PackedStringArray()
	var attacks: Dictionary = _data.get("attacks", {})
	for id: Variant in combo():
		if not attacks.has(str(id)):
			errors.append("%s 的 combo 引用不存在的招式「%s」" % [PATH, id])
	for id: String in attacks.keys():
		var def: Variant = attacks[id]
		if typeof(def) != TYPE_DICTIONARY:
			errors.append("%s 的招式「%s」不是字典" % [PATH, id])
			continue
		for field in ["windup", "active", "recovery", "damage", "range"]:
			if float((def as Dictionary).get(field, 0.0)) <= 0.0:
				errors.append("%s 的招式「%s」的 %s 要大於 0" % [PATH, id, field])
		if float((def as Dictionary).get("cancel_after", 0.0)) > float((def as Dictionary).get("recovery", 0.0)):
			errors.append("%s 的招式「%s」的 cancel_after 不能大於 recovery" % [PATH, id])
		for key: String in (def as Dictionary).keys():
			if not FIELDS.has(key) and not key.begins_with("_"):
				errors.append("%s 的招式「%s」有不認得的欄位「%s」" % [PATH, id, key])
		var trail: Variant = (def as Dictionary).get("trail")
		if typeof(trail) != TYPE_DICTIONARY:
			errors.append("%s 的招式「%s」沒有 trail" % [PATH, id])
		else:
			var life := float((trail as Dictionary).get("life", 0.0))
			if life < TRAIL_LIFE_RANGE.x - 0.0001 or life > TRAIL_LIFE_RANGE.y + 0.0001:
				errors.append("%s 的招式「%s」的 trail.life 要在 %s 秒之間" % [PATH, id, TRAIL_LIFE_RANGE])
			if float((trail as Dictionary).get("brightness", 0.0)) > TRAIL_BRIGHTNESS_MAX:
				errors.append("%s 的招式「%s」的 trail.brightness 不能超過 %s（過曝）" % [PATH, id, TRAIL_BRIGHTNESS_MAX])
		var sounds: Variant = (def as Dictionary).get("sounds", {})
		if typeof(sounds) != TYPE_DICTIONARY:
			errors.append("%s 的招式「%s」的 sounds 要是字典（swing、hit）" % [PATH, id])
		else:
			for key: String in (sounds as Dictionary).keys():
				if key != "swing" and key != "hit":
					errors.append("%s 的招式「%s」的 sounds 有不認得的欄位「%s」（可用：swing、hit）" % [PATH, id, key])
				elif not Sfx.has_named(StringName(str((sounds as Dictionary)[key]))):
					errors.append("%s 的招式「%s」的 sounds.%s 引用不存在的聲音「%s」" % [PATH, id, key, (sounds as Dictionary)[key]])
		var event := StringName(str((def as Dictionary).get("event", "")))
		if event != &"" and not Feel.has_event(event):
			errors.append("%s 的招式「%s」引用不存在的回饋事件「%s」" % [PATH, id, event])
	return errors
