class_name HitFeedback
extends RefCounted
## 命中材質回饋（NE-140）：依命中物的材質查表（data/feel/materials.json），產生對應的火花、碎屑、塵土、閃光與聲音；
## 弱點與跳彈（被擋）疊上各自的特別回饋。材質標籤缺漏或不認得時退回 generic。
## 粒子數有預算（令牌桶）：短時間內大量命中（連發、霰彈）會依剩餘預算縮減數量，不會爆量。

const PATH := "res://data/feel/materials.json"
const FALLBACK := &"generic"

static var _data: Dictionary = {}
static var _loaded := false
static var _tokens := -1.0
static var _last_msec := 0
static var _reported: Dictionary = {}
## 診斷：累計播放次數與因預算縮減掉的粒子數。
static var played_count := 0
static var trimmed_particles := 0


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var json: JSON = load(PATH) as JSON if ResourceLoader.exists(PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("materials")) != TYPE_DICTIONARY:
		_report("load", "[HitFeedback] 無法讀取命中材質資料：%s（需要 materials 字典）" % PATH)
		return
	_data = json.data


static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


static func material_ids() -> Array:
	_ensure_loaded()
	return (_data.get("materials", {}) as Dictionary).keys()


## 某個命中材質（或 ricochet、weak）對應的聲音事件；沒有登記回傳空字串（實驗室試聽用）。
static func sound_event(material: StringName) -> StringName:
	_ensure_loaded()
	var def: Variant = _data.get(String(material)) if material == &"ricochet" or material == &"weak" else (_data.get("materials", {}) as Dictionary).get(String(material))
	return StringName(str((def as Dictionary).get("sound", ""))) if typeof(def) == TYPE_DICTIONARY else &""


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
static func validate() -> PackedStringArray:
	_ensure_loaded()
	var errors := PackedStringArray()
	var materials: Dictionary = _data.get("materials", {})
	if not materials.has(String(FALLBACK)):
		errors.append("%s 缺少預設材質「%s」" % [PATH, FALLBACK])
	var entries: Dictionary = materials.duplicate()
	entries["ricochet"] = _data.get("ricochet", {})
	entries["weak"] = _data.get("weak", {})
	for id: String in entries.keys():
		var def: Variant = entries[id]
		if typeof(def) != TYPE_DICTIONARY:
			errors.append("%s 的「%s」不是字典" % [PATH, id])
			continue
		var sound := StringName(str((def as Dictionary).get("sound", "")))
		if sound == &"" or not Sfx.has_event(sound):
			errors.append("%s 的「%s」引用不存在的聲音事件「%s」" % [PATH, id, sound])
		for kind in ["sparks", "shards", "dust"]:
			if (def as Dictionary).has(kind) and (typeof((def as Dictionary)[kind]) != TYPE_DICTIONARY or int(((def as Dictionary)[kind] as Dictionary).get("count", 0)) <= 0):
				errors.append("%s 的「%s」的 %s 要有大於 0 的 count" % [PATH, id, kind])
	return errors


## 在 position 播放材質回饋。normal 是命中面朝外的方向；color 是攻擊方的顏色（材質設定成 projectile 時用）。
## flags：weak（弱點）、ricochet（跳彈／被擋）。回傳實際使用的材質 id。
static func play(material: StringName, position: Vector2, normal: Vector2, color: Color, flags: Dictionary = {}) -> StringName:
	_ensure_loaded()
	var materials: Dictionary = _data.get("materials", {})
	var id := material
	if id == &"" or not materials.has(String(id)):
		if id != &"":
			_report("material:" + String(id), "[HitFeedback] 沒有這個命中材質「%s」（%s），改用 %s" % [id, PATH, FALLBACK])
		id = FALLBACK
	var def: Dictionary = {}
	if bool(flags.get("ricochet", false)):
		def = _data.get("ricochet", {})
	elif materials.has(String(id)):
		def = materials[String(id)]
	played_count += 1
	FeelRecord.capture("material", String(id), {"x": snappedf(position.x, 0.1), "y": snappedf(position.y, 0.1), "weak": bool(flags.get("weak", false)), "ricochet": bool(flags.get("ricochet", false))})
	Feel.record("材質", String(id) + (" 跳彈" if bool(flags.get("ricochet", false)) else (" 弱點" if bool(flags.get("weak", false)) else "")))
	_apply(def, position, normal, color)
	if bool(flags.get("weak", false)) and not bool(flags.get("ricochet", false)):
		_apply(_data.get("weak", {}), position, normal, color)
	return id


static func _apply(def: Dictionary, position: Vector2, normal: Vector2, color: Color) -> void:
	if def.is_empty():
		return
	var sparks: Variant = def.get("sparks")
	if typeof(sparks) == TYPE_DICTIONARY:
		var s := sparks as Dictionary
		var count := _spend(int(s.get("count", 0)))
		if count > 0:
			Fx.sparks(position, _color_of(s.get("color"), color), count, float(s.get("speed", 240.0)), float(s.get("life", 0.25)), normal, 1.5, 420.0)
	var shards: Variant = def.get("shards")
	if typeof(shards) == TYPE_DICTIONARY:
		var s := shards as Dictionary
		var count := _spend(int(s.get("count", 0)))
		if count > 0:
			Fx.shards(position, _color_of(s.get("color"), color), count, float(s.get("speed", 180.0)), 0.7, float(s.get("size", 5.0)))
	var dust: Variant = def.get("dust")
	if typeof(dust) == TYPE_DICTIONARY:
		var count := _spend(int((dust as Dictionary).get("count", 0)))
		if count > 0:
			Fx.dust(position, count, 30.0)
	var flare := float(def.get("flare", 0.0))
	if flare > 0.0 and _spend(1) > 0:
		Fx.flare(position, _color_of(null, color), flare, 0.07)
	var sound := StringName(str(def.get("sound", "")))
	if sound != &"":
		Sfx.play_event(sound)


static func _color_of(value: Variant, projectile_color: Color) -> Color:
	if typeof(value) == TYPE_STRING and String(value).begins_with("#"):
		return Color.html(String(value))
	return projectile_color


## 令牌桶：回傳這次實際能用的粒子數（預算不足時縮減，至少保留 1 顆讓每次命中都看得到）。
static func _spend(wanted: int) -> int:
	if wanted <= 0:
		return 0
	var budget: Dictionary = _data.get("budget", {})
	var capacity := float(budget.get("capacity", 60))
	var now := Time.get_ticks_msec()
	if _tokens < 0.0:
		_tokens = capacity
	else:
		_tokens = minf(capacity, _tokens + float(now - _last_msec) * 0.001 * float(budget.get("refill_per_second", 240)))
	_last_msec = now
	var granted := mini(wanted, maxi(1, int(_tokens)))
	_tokens = maxf(0.0, _tokens - float(granted))
	trimmed_particles += wanted - granted
	return granted


static func reset_budget() -> void:
	_tokens = -1.0
	played_count = 0
	trimmed_particles = 0


static func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(message)
