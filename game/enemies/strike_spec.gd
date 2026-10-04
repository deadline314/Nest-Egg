class_name StrikeSpec
extends RefCounted
## 貼身與鎖鏈類敵人攻擊（StrikeEnemy）的參數：寫在 EnemyData.strike 這個字典裡，沒寫的欄位用預設，不認得的欄位會被資料檢查指出。
## 判定框用「離腳底的高度帶」描述（band），所以「跳過低的、蹲下躲高的」是資料而不是程式。長度單位都是像素、時間是秒。
##
## 共用：reach 攻擊長度、reach_from 判定框離身體中心多遠開始、band [低, 高] 離腳底的高度、active 出招區間、hits 出招區間內判定幾次（電鋸連割）、
##       advance 出招時往前衝的速度、knockback 擊退、start_range 離目標多近開始預兆（0＝reach 的 85%）、damage 每次判定的傷害（0＝ability_damage）、source_id 死因。
## 預兆秒數用 EnemyData.telegraph_time、收招用 ability_time、冷卻用 attack_cooldown。
## 電漿鞭：bands 清單，每次出招預兆會顯示其中一條（高處要蹲、低處要跳）。
## 鎖鏈鐵鉤：throw_range 鉤子射程、throw_speed 飛行速度、reel_speed 把玩家拉近的速度、reel_time 最長拉扯秒數、chain_health 鎖鏈耐久（打斷即解除）、stab_damage 拉到面前的一擊。

const DEFAULTS := {
	"reach": 36.0, "reach_from": 6.0, "band": [0.0, 40.0], "active": 0.2, "hits": 1, "advance": 0.0, "knockback": [160.0, -80.0],
	"start_range": 0.0, "damage": 0, "source_id": "",
}
const EXTRA_KEYS: PackedStringArray = ["bands", "throw_range", "throw_speed", "reel_speed", "reel_time", "chain_health", "stab_damage"]
const NUMERIC := ["reach", "reach_from", "active", "hits", "advance", "start_range", "damage"]
const MIN_TELEGRAPH := 0.4


## 合併預設與敵人資料，補上衍生欄位；回傳一份新字典。
static func resolve(data: EnemyData) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	if data == null:
		return result
	for key: String in data.strike.keys():
		result[key] = data.strike[key]
	if int(result["damage"]) <= 0:
		result["damage"] = data.ability_damage
	if float(result["start_range"]) <= 0.0:
		result["start_range"] = float(result["reach"]) * 0.85
	if str(result["source_id"]).is_empty():
		result["source_id"] = str(data.contact_source_id)
	return result


## 資料檢查：回傳錯誤清單（空＝沒問題）。
static func validate(data: EnemyData) -> PackedStringArray:
	var errors := PackedStringArray()
	if data == null:
		return errors
	var id := str(data.id)
	for key: String in data.strike.keys():
		if not DEFAULTS.has(key) and not EXTRA_KEYS.has(key):
			errors.append("%s 的 strike 有不認得的欄位「%s」" % [id, key])
	var spec := resolve(data)
	for key: String in NUMERIC:
		if float(spec[key]) < 0.0:
			errors.append("%s 的 strike.%s 不能是負的" % [id, key])
	if float(spec["reach"]) <= 0.0 or float(spec["active"]) <= 0.0 or int(spec["hits"]) < 1:
		errors.append("%s 的 strike.reach、active、hits 要大於 0" % id)
	if not _valid_band(spec["band"]):
		errors.append("%s 的 strike.band 要是 [低, 高] 且低於高" % id)
	if spec.has("bands"):
		if typeof(spec["bands"]) != TYPE_ARRAY or (spec["bands"] as Array).is_empty():
			errors.append("%s 的 strike.bands 要是不為空的清單" % id)
		else:
			for band: Variant in spec["bands"]:
				if not _valid_band(band):
					errors.append("%s 的 strike.bands 有無效的高度帶：%s" % [id, str(band)])
	if data.telegraph_time < MIN_TELEGRAPH:
		errors.append("%s 的預兆 %.2f 秒短於最短的 %.1f 秒" % [id, data.telegraph_time, MIN_TELEGRAPH])
	if int(spec["damage"]) >= 3:
		errors.append("%s 的單次傷害不能到 3（不能一擊必殺）" % id)
	return errors


static func band_of(spec: Dictionary, variant := -1) -> Vector2:
	var raw: Variant = spec["band"]
	if variant >= 0 and spec.has("bands") and typeof(spec["bands"]) == TYPE_ARRAY and variant < (spec["bands"] as Array).size():
		raw = (spec["bands"] as Array)[variant]
	return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))


static func _valid_band(raw: Variant) -> bool:
	return typeof(raw) == TYPE_ARRAY and (raw as Array).size() == 2 and float((raw as Array)[0]) < float((raw as Array)[1])
