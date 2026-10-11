class_name LampFixtures
extends RefCounted
## 場景燈具的款式表（BG-36）：每一款是一張畫出來的燈具圖（和擺設同一套流程）加上安裝方式與光的比例。
## 資料在 data/environment/lamp_fixtures.json；圖與大小在 data/environment/scene_props/lamps/lamps__<款式>.tres。
## 新增一款只要加圖與一筆資料。資料或圖遺失時回報是哪一款，改用同安裝方式的備用款；連備用款都沒有就回傳空的，
## 燈照樣會亮，只是沒有燈具圖。

## 安裝方式：吊在天花板、裝在牆上、立桿（桿子接到地面）、直接站在地上。
const MOUNTS: Array[StringName] = [&"ceiling", &"wall", &"pole", &"ground"]
## 原本不是立桿的款式掛到桿子上的方式：arm＝掛在橫臂下，post＝鎖在桿子上。
const POLE_STYLES: Array[StringName] = [&"arm", &"post"]
const DATA_PATH := "res://data/environment/lamp_fixtures.json"
const PROP_PATH := "res://data/environment/scene_props/lamps/lamps__%s.tres"
## 沒有任何指定款式可用時，依這個順序找備用的安裝方式。
const FALLBACK_ORDER: Array[StringName] = [&"ceiling", &"wall", &"pole", &"ground"]

static var _table: Dictionary = {}
static var _fallback: Dictionary = {}
static var _props: Dictionary[StringName, PropData] = {}
static var _reported: Dictionary[String, bool] = {}
static var _loaded := false


## 一款燈具的資料：{id, mount, shaft, radius, energy, pole_at, emit, aim_x, pole}；沒有這一款回傳空的。
static func fixture(id: StringName) -> Dictionary:
	_load()
	return _table.get(id, {})


static func ids() -> Array[StringName]:
	_load()
	var result: Array[StringName] = []
	for id: StringName in _table:
		result.append(id)
	return result


## 這一款的圖與大小（PropData）；缺檔回傳 null 並回報一次。
static func prop(id: StringName) -> PropData:
	if _props.has(id):
		return _props[id]
	var path := PROP_PATH % id
	var data := load(path) as PropData if ResourceLoader.exists(path) else null
	if data == null or not ResourceLoader.exists(data.texture):
		_report("prop:" + String(id), "[LampFixtures] 燈具「%s」的圖或資料不存在：%s" % [id, path])
		data = null
	_props[id] = data
	return data


## 從 wanted 裡挑一款 supports 允許的安裝方式（supports＝{ceiling, wall, pole, ground: bool}）。
## ordinal 是這盞燈在關卡裡的序號：相鄰的燈輪流用不同款；seed_value 讓每一區的起點不同。
## wanted 裡沒有可用的就改用備用款；都沒有回傳 &""。
static func pick(wanted: PackedStringArray, supports: Dictionary, ordinal: int, seed_value: int) -> StringName:
	_load()
	if supports.is_empty():
		return &""
	var usable: Array[StringName] = []
	for name: String in wanted:
		var entry: Dictionary = _table.get(StringName(name), {})
		if not entry.is_empty() and mount_for(entry, supports) != &"" and prop(StringName(name)) != null:
			usable.append(StringName(name))
	if not usable.is_empty():
		return usable[posmod(ordinal + seed_value, usable.size())]
	for mount: StringName in FALLBACK_ORDER:
		var spare := StringName(str(_fallback.get(mount, "")))
		if bool(supports.get(mount, false)) and _table.has(spare) and prop(spare) != null:
			return spare
	return &""


## 這一款在 supports 允許的安裝方式裡實際怎麼裝：原本的裝得上就用原本的；裝不上、但這一款可以掛在桿子上
## （pole＝arm 掛在橫臂下、post 鎖在桿子上）而且立得了桿子，就用 pole；都不行回傳 &""。supports 是空的代表不檢查。
static func mount_for(entry: Dictionary, supports: Dictionary) -> StringName:
	if entry.is_empty():
		return &""
	var native: StringName = entry["mount"]
	if supports.is_empty() or bool(supports.get(native, false)):
		return native
	if POLE_STYLES.has(entry.get("pole", &"")) and bool(supports.get(&"pole", false)):
		return &"pole"
	return &""


## 資料檢查：每一款的安裝方式合法、比例在範圍內、圖存在；備用款存在。
static func problems() -> PackedStringArray:
	_load()
	var result := PackedStringArray()
	if _table.is_empty():
		result.append("%s 沒有任何燈具款式" % DATA_PATH)
	for id: StringName in _table:
		var entry: Dictionary = _table[id]
		if not MOUNTS.has(entry["mount"]):
			result.append("燈具「%s」的安裝方式不合法：%s" % [id, entry["mount"]])
		if float(entry["radius"]) <= 0.0 or float(entry["energy"]) <= 0.0 or float(entry["shaft"]) < 0.0:
			result.append("燈具「%s」的光池、亮度比例要大於 0，光錐比例不能是負的" % id)
		if entry["pole"] != &"" and not POLE_STYLES.has(entry["pole"]):
			result.append("燈具「%s」掛在桿子上的方式不合法：%s" % [id, entry["pole"]])
		if prop(id) == null:
			result.append("燈具「%s」沒有圖或資料（%s）" % [id, PROP_PATH % id])
	for mount: StringName in MOUNTS:
		if not _table.has(StringName(str(_fallback.get(mount, "")))):
			result.append("安裝方式「%s」沒有備用款" % mount)
	return result


static func clear_cache() -> void:
	_table.clear()
	_fallback.clear()
	_props.clear()
	_reported.clear()
	_loaded = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if not raw is Dictionary or not (raw as Dictionary).get("fixtures") is Dictionary:
		_report("data", "[LampFixtures] 讀不到燈具款式表：%s" % DATA_PATH)
		return
	var fixtures: Dictionary = raw["fixtures"]
	for name: String in fixtures:
		var entry: Variant = fixtures[name]
		if not entry is Dictionary:
			_report("entry:" + name, "[LampFixtures] 燈具「%s」的資料不是物件，略過" % name)
			continue
		_table[StringName(name)] = {
			"id": StringName(name),
			"mount": StringName(str(entry.get("mount", "ceiling"))),
			"shaft": float(entry.get("shaft", 1.0)),
			"radius": float(entry.get("radius", 1.0)),
			"energy": float(entry.get("energy", 1.0)),
			"pole_at": float(entry.get("pole_at", 0.5)),
			"emit": clampf(float(entry.get("emit", 0.0)), 0.0, 1.0),
			"aim_x": clampf(float(entry.get("aim_x", 0.0)), -1.0, 1.0),
			"pole": StringName(str(entry.get("pole", ""))),
		}
	var fallback: Variant = raw.get("fallback", {})
	if fallback is Dictionary:
		_fallback = fallback


static func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(message)
