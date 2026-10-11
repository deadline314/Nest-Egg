class_name LampFlicker
extends RefCounted
## 場景燈的閃法（BG-35）：穩定、接觸不良、快壞了。資料在 data/environment/lamp_flicker.json：每個狀態有幾條閃法
## （一個字母一步，a 全暗、m 正常亮度），以及「減少閃光」打開時改用的緩慢明暗起伏；區域的供電狀況決定這一區亮著的燈
## 依序輪到哪個狀態。新增閃法或供電狀況只改資料。
## 光敏安全在載入時檢查：任何一秒內亮度明顯變化超過上限的閃法不採用（記錄是哪一條），那個狀態沒有可用的閃法時當成穩定。

const DATA_PATH := "res://data/environment/lamp_flicker.json"
const STABLE: StringName = &"stable"
## 任何一秒內亮度明顯變化的次數上限（WCAG 2.3.1：一秒內不超過三次閃光）。資料可以訂得更嚴，不能更鬆。
const MAX_CHANGES_PER_SECOND := 3
## 字母 m 是正常亮度；a 到 m 共 12 級。
const LETTER_STEPS := 12.0
## 亮度上限：閃法裡比正常亮的字母不超過這個倍數。
const PEAK := 1.3
## 「減少閃光」的起伏一個來回最短幾秒。
const MIN_CALM_PERIOD := 2.0

static var _step_hz := 10.0
static var _threshold := 0.2
static var _limit := MAX_CHANGES_PER_SECOND
## 狀態 → {patterns: Array[PackedFloat32Array], calm_low, calm_high, calm_period, buzz, sparks}
static var _states: Dictionary = {}
## 供電狀況 → Array[StringName]（輪到的狀態）
static var _supply: Dictionary = {}
static var _problems := PackedStringArray()
static var _reported: Dictionary[String, bool] = {}
static var _loaded := false
static var _reduced := false
static var _reduced_known := false
static var _reduced_hooked := false


static func step_hz() -> float:
	_load()
	return _step_hz


static func change_threshold() -> float:
	_load()
	return _threshold


static func change_limit() -> int:
	_load()
	return _limit


static func states() -> Array[StringName]:
	_load()
	var result: Array[StringName] = []
	for id: StringName in _states:
		result.append(id)
	return result


static func has_supply(id: StringName) -> bool:
	_load()
	return _supply.has(id)


## 供電狀況 supply 的區域裡，第 ordinal 盞亮著的燈是什麼狀態。不認得的供電狀況當成穩定並回報一次。
static func state_for(supply: StringName, ordinal: int) -> StringName:
	_load()
	if supply == &"" or supply == STABLE:
		return STABLE
	var cycle: Array = _supply.get(supply, [])
	if cycle.is_empty():
		_report("supply:" + String(supply), "[LampFlicker] 沒有「%s」這種供電狀況（%s），當成穩定" % [supply, DATA_PATH])
		return STABLE
	var state: StringName = cycle[posmod(ordinal, cycle.size())]
	return state if state == STABLE or pattern_count(state) > 0 else STABLE


static func pattern_count(state: StringName) -> int:
	_load()
	return (_states.get(state, {}).get("patterns", []) as Array).size()


## 這個狀態的第 index 條閃法（每一步的亮度比例）；沒有回傳空的。
static func pattern(state: StringName, index: int) -> PackedFloat32Array:
	_load()
	var patterns: Array = _states.get(state, {}).get("patterns", [])
	return patterns[posmod(index, patterns.size())] if not patterns.is_empty() else PackedFloat32Array()


## 閃法在時間 time（秒）的亮度比例。offset 是從第幾步開始。
static func level_at(values: PackedFloat32Array, time: float, offset: int) -> float:
	if values.is_empty():
		return 1.0
	return values[posmod(int(time * _step_hz) + offset, values.size())]


## 「減少閃光」打開時的亮度比例：在 low～high 之間緩慢起伏，沒有突然的變化。
static func calm_level(state: StringName, time: float, phase: float) -> float:
	_load()
	var entry: Dictionary = _states.get(state, {})
	if entry.is_empty():
		return 1.0
	var wave := 0.5 + 0.5 * sin((time / float(entry["calm_period"]) + phase) * TAU)
	return lerpf(float(entry["calm_low"]), float(entry["calm_high"]), wave)


## 這個狀態最暗的時候的亮度比例（量測「燈暗下來的那一刻」用）。
static func darkest(state: StringName) -> float:
	_load()
	var lowest := 1.0
	for values: PackedFloat32Array in _states.get(state, {}).get("patterns", []):
		for value in values:
			lowest = minf(lowest, value)
	return lowest


## 電流聲的音量比例（0＝這個狀態沒有聲音）。
static func buzz(state: StringName) -> float:
	_load()
	return float(_states.get(state, {}).get("buzz", 0.0))


## 這個狀態的燈突然亮起來時會不會掉火花。
static func sparks(state: StringName) -> bool:
	_load()
	return bool(_states.get(state, {}).get("sparks", false))


## 設定的「減少閃光」有沒有打開。只在設定改變後重讀一次，不是每盞燈每影格都去讀設定檔。
static func reduced() -> bool:
	if not _reduced_known:
		if not _reduced_hooked:
			_reduced_hooked = true
			Settings.display_changed.connect(_forget_reduced)
		_reduced = Settings.get_reduce_flashes()
		_reduced_known = true
	return _reduced


static func _forget_reduced() -> void:
	_reduced_known = false


## 一條閃法在任何一秒內（頭尾相接）亮度明顯變化的最多次數。
static func worst_window(values: PackedFloat32Array) -> int:
	_load()
	var count := values.size()
	var window := int(_step_hz)
	var worst := 0
	for start in count:
		var changes := 0
		for step in window:
			var at := (start + step) % count
			if absf(values[(at + 1) % count] - values[at]) >= _threshold:
				changes += 1
		worst = maxi(worst, changes)
	return worst


## 資料檢查：載入時發現的問題（讀不到檔、閃法不合法或超過光敏安全上限、起伏太快、供電狀況用了不存在的狀態）。
static func problems() -> PackedStringArray:
	_load()
	return _problems


static func clear_cache() -> void:
	_states.clear()
	_supply.clear()
	_problems = PackedStringArray()
	_reported.clear()
	_loaded = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if not raw is Dictionary or not (raw as Dictionary).get("states") is Dictionary:
		_fail("data", "讀不到燈的閃法：%s（所有的燈當成穩定）" % DATA_PATH)
		return
	_step_hz = clampf(float(raw.get("step_hz", 10.0)), 2.0, 30.0)
	_threshold = clampf(float(raw.get("change_threshold", 0.2)), 0.05, 1.0)
	_limit = mini(int(raw.get("max_changes_per_second", MAX_CHANGES_PER_SECOND)), MAX_CHANGES_PER_SECOND)
	if int(raw.get("max_changes_per_second", MAX_CHANGES_PER_SECOND)) > MAX_CHANGES_PER_SECOND:
		_fail("limit", "max_changes_per_second 不能超過 %d，已改用 %d" % [MAX_CHANGES_PER_SECOND, MAX_CHANGES_PER_SECOND])
	var states_raw: Dictionary = raw["states"]
	for name: String in states_raw:
		var entry: Variant = states_raw[name]
		if not entry is Dictionary:
			_fail("state:" + name, "狀態「%s」的資料不是物件，略過" % name)
			continue
		_states[StringName(name)] = _parse_state(name, entry)
	var supply_raw: Variant = raw.get("supply", {})
	if supply_raw is Dictionary:
		for name: String in supply_raw:
			_supply[StringName(name)] = _parse_cycle(name, supply_raw[name])


static func _parse_state(name: String, entry: Dictionary) -> Dictionary:
	var patterns: Array[PackedFloat32Array] = []
	var listed: Variant = entry.get("patterns", [])
	for index in (listed as Array).size() if listed is Array else 0:
		var values := _parse_pattern(str(listed[index]))
		if values.is_empty():
			_fail("pattern:%s:%d" % [name, index], "狀態「%s」的第 %d 條閃法只能用小寫字母而且不能是空的，略過" % [name, index])
			continue
		var worst := worst_window(values)
		if worst > _limit:
			_fail("flash:%s:%d" % [name, index], "狀態「%s」的第 %d 條閃法一秒內亮度變化 %d 次，超過上限 %d，略過" % [name, index, worst, _limit])
			continue
		patterns.append(values)
	if patterns.is_empty():
		_fail("empty:" + name, "狀態「%s」沒有可用的閃法，當成穩定" % name)
	var calm: Dictionary = entry.get("calm", {}) if entry.get("calm") is Dictionary else {}
	var period := float(calm.get("period", 4.0))
	if period < MIN_CALM_PERIOD:
		_fail("calm:" + name, "狀態「%s」的緩慢起伏一個來回要 %.0f 秒以上，已改用 %.0f 秒" % [name, MIN_CALM_PERIOD, MIN_CALM_PERIOD])
		period = MIN_CALM_PERIOD
	return {
		"patterns": patterns,
		"calm_low": clampf(float(calm.get("low", 0.7)), 0.0, PEAK),
		"calm_high": clampf(float(calm.get("high", 1.0)), 0.0, PEAK),
		"calm_period": period,
		"buzz": clampf(float(entry.get("buzz", 0.0)), 0.0, 1.0),
		"sparks": bool(entry.get("sparks", false)),
	}


static func _parse_pattern(text: String) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for index in text.length():
		var code := text.unicode_at(index)
		if code < 97 or code > 122:
			return PackedFloat32Array()
		values.append(minf(float(code - 97) / LETTER_STEPS, PEAK))
	return values


static func _parse_cycle(name: String, entry: Variant) -> Array[StringName]:
	var cycle: Array[StringName] = []
	var listed: Variant = entry.get("cycle", []) if entry is Dictionary else []
	for item: Variant in listed if listed is Array else []:
		var state := StringName(str(item))
		if state != STABLE and not _states.has(state):
			_fail("cycle:%s:%s" % [name, state], "供電狀況「%s」用了不存在的狀態「%s」，當成穩定" % [name, state])
			state = STABLE
		cycle.append(state)
	if cycle.is_empty():
		_fail("cycle:" + name, "供電狀況「%s」沒有任何狀態，當成穩定" % name)
		cycle.append(STABLE)
	return cycle


static func _fail(key: String, message: String) -> void:
	_problems.append(message)
	_report(key, "[LampFlicker] " + message)


static func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(message)
