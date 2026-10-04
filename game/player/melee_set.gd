class_name MeleeSet
extends RefCounted
## 一組近戰招式：combo（連段順序）＋ attacks（招式表）。前搖、出招、收招、判定形狀、前衝、命中取消窗口都是資料。
## 預設那組是 data/feel/melee.json（MeleeData 轉接）；每把近戰武器各有一份 data/melee/<id>.json。
## 資料缺漏或損毀時記錄「檔案、招式、欄位」並退回內建的安全預設（單一輕斬），不崩潰。

const FIELDS: PackedStringArray = ["windup", "active", "recovery", "cancel_after", "damage", "range", "advance", "move_scale", "stagger", "impact", "knockback", "event", "trail", "sounds",
		"shape", "height", "arc_degrees", "min_range", "aim_follow", "sweep", "hitstop", "pose"]
## 判定形狀：box＝面前的矩形（range 長 × height 高）；arc＝以身體為圓心、半徑 range 的扇形（arc_degrees 為總角度，360＝繞身一圈）。
const SHAPES: PackedStringArray = ["box", "arc"]
## 軌跡的限制：持續秒數範圍、峰值亮度上限（HDR 泛光下不過曝）、同時最多幾條。
const TRAIL_LIFE_RANGE := Vector2(0.08, 0.2)
const TRAIL_BRIGHTNESS_MAX := 2.2
## 判定框高度的預設值 0 ＝ 用角色身高。
const DEFAULT_ATTACK := {"windup": 0.05, "active": 0.06, "recovery": 0.16, "cancel_after": 0.05, "damage": 2, "range": 26.0, "advance": 0.0, "move_scale": 0.4, "stagger": 2, "impact": 6.0,
		"knockback": [180.0, -60.0], "event": "player_melee_hit", "trail": {"radius": 20.0, "arc": 130.0, "life": 0.09, "width": 3.0, "brightness": 1.7, "afterimage": true},
		"sounds": {"swing": "melee_swing", "hit": "melee_hit"},
		"shape": "box", "height": 0.0, "arc_degrees": 120.0, "min_range": 0.0, "aim_follow": false, "sweep": false, "hitstop": 0.0, "pose": "slash"}

var path := ""
var _data: Dictionary = {}
var _loaded := false


func _init(p_path: String) -> void:
	path = p_path


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("attacks")) != TYPE_DICTIONARY:
		push_error("[MeleeSet] 無法讀取近戰資料：%s（需要 attacks 字典），改用內建預設" % path)
		_data = {"combo": ["light"], "combo_window": 0.5, "attacks": {"light": DEFAULT_ATTACK}}
		return
	_data = json.data


func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


func combo() -> Array:
	_ensure_loaded()
	var list: Variant = _data.get("combo", [])
	return list if typeof(list) == TYPE_ARRAY and not (list as Array).is_empty() else ["light_1"]


func combo_window() -> float:
	_ensure_loaded()
	return float(_data.get("combo_window", 0.5))


## 某一招的即時資料（實驗室直接改這份就會影響下一次出招）；不存在回傳空字典。
func live_attack(id: String) -> Dictionary:
	_ensure_loaded()
	var attacks: Dictionary = _data.get("attacks", {})
	return attacks[id] if attacks.has(id) and typeof(attacks[id]) == TYPE_DICTIONARY else {}


## 某一招的資料（缺欄位補預設）；招式不存在時回傳預設並記錄。
func attack(id: String) -> Dictionary:
	_ensure_loaded()
	var attacks: Dictionary = _data.get("attacks", {})
	var result := DEFAULT_ATTACK.duplicate(true)
	if not attacks.has(id) or typeof(attacks[id]) != TYPE_DICTIONARY:
		push_error("[MeleeSet] %s 沒有招式「%s」，改用預設" % [path, id])
		return result
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


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
func validate() -> PackedStringArray:
	_ensure_loaded()
	var errors := PackedStringArray()
	var attacks: Dictionary = _data.get("attacks", {})
	for id: Variant in combo():
		if not attacks.has(str(id)):
			errors.append("%s 的 combo 引用不存在的招式「%s」" % [path, id])
	for id: String in attacks.keys():
		var def: Variant = attacks[id]
		if typeof(def) != TYPE_DICTIONARY:
			errors.append("%s 的招式「%s」不是字典" % [path, id])
			continue
		var d := def as Dictionary
		for field in ["windup", "active", "recovery", "damage", "range"]:
			if float(d.get(field, 0.0)) <= 0.0:
				errors.append("%s 的招式「%s」的 %s 要大於 0" % [path, id, field])
		if float(d.get("cancel_after", 0.0)) > float(d.get("recovery", 0.0)):
			errors.append("%s 的招式「%s」的 cancel_after 不能大於 recovery" % [path, id])
		if float(d.get("min_range", 0.0)) >= float(d.get("range", 1.0)):
			errors.append("%s 的招式「%s」的 min_range 要小於 range" % [path, id])
		if d.has("shape") and not SHAPES.has(str(d["shape"])):
			errors.append("%s 的招式「%s」的 shape「%s」不認得（可用：%s）" % [path, id, d["shape"], ", ".join(SHAPES)])
		for key: String in d.keys():
			if not FIELDS.has(key) and not key.begins_with("_"):
				errors.append("%s 的招式「%s」有不認得的欄位「%s」" % [path, id, key])
		var trail: Variant = d.get("trail")
		if typeof(trail) != TYPE_DICTIONARY:
			errors.append("%s 的招式「%s」沒有 trail" % [path, id])
		else:
			var life := float((trail as Dictionary).get("life", 0.0))
			if life < TRAIL_LIFE_RANGE.x - 0.0001 or life > TRAIL_LIFE_RANGE.y + 0.0001:
				errors.append("%s 的招式「%s」的 trail.life 要在 %s 秒之間" % [path, id, TRAIL_LIFE_RANGE])
			if float((trail as Dictionary).get("brightness", 0.0)) > TRAIL_BRIGHTNESS_MAX:
				errors.append("%s 的招式「%s」的 trail.brightness 不能超過 %s（過曝）" % [path, id, TRAIL_BRIGHTNESS_MAX])
		var sounds: Variant = d.get("sounds", {})
		if typeof(sounds) != TYPE_DICTIONARY:
			errors.append("%s 的招式「%s」的 sounds 要是字典（swing、hit）" % [path, id])
		else:
			for key: String in (sounds as Dictionary).keys():
				if key != "swing" and key != "hit":
					errors.append("%s 的招式「%s」的 sounds 有不認得的欄位「%s」（可用：swing、hit）" % [path, id, key])
				elif not Sfx.has_named(StringName(str((sounds as Dictionary)[key]))):
					errors.append("%s 的招式「%s」的 sounds.%s 引用不存在的聲音「%s」" % [path, id, key, (sounds as Dictionary)[key]])
		var event := StringName(str(d.get("event", "")))
		if event != &"" and not Feel.has_event(event):
			errors.append("%s 的招式「%s」引用不存在的回饋事件「%s」" % [path, id, event])
	return errors
