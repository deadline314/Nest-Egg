class_name FeelParams
extends RefCounted
## 回饋參數面板的資料層（NE-134）：從事件資料自動列出可調的數值參數（路徑、範圍），不必為新參數改面板程式；
## 手感預設組合（data/feel/presets.json）；反向索引：每個事件被哪些檔案使用、哪些事件完全沒被使用。

const PRESETS_PATH := "res://data/feel/presets.json"
## 參數名稱（路徑最後一段）→ [最小, 最大, 步進]。事件資料新增數值欄位時，在這裡補範圍即可。
const RANGES := {
	"px": [0.0, 12.0, 0.2], "time": [0.02, 1.0, 0.01], "hitstop": [0.0, 0.2, 0.005], "freeze": [0.0, 0.2, 0.005],
	"scale": [0.1, 1.0, 0.05], "amount": [0.0, 0.08, 0.002], "max_enemies": [0.0, 20.0, 1.0],
}
const SOURCE_DIRS: PackedStringArray = ["res://game", "res://ui", "res://autoload", "res://core"]
const EXTRA_SOURCES: PackedStringArray = ["res://data/feel/melee.json"]

static var _presets: Dictionary = {}
static var _usage: Dictionary = {}
static var _usage_built := false


## 事件的可調數值參數：回傳 [{path: ["shake","px"], name: "shake.px", value: 3.2, min, max, step}]。
static func parameters(event: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect(event, [], result)
	return result


static func _collect(node: Dictionary, path: Array, out: Array[Dictionary]) -> void:
	for key: String in node.keys():
		var value: Variant = node[key]
		var here := path + [key]
		if typeof(value) == TYPE_DICTIONARY:
			_collect(value as Dictionary, here, out)
		elif typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			var range_def: Array = RANGES.get(key, [0.0, maxf(10.0, absf(float(value)) * 2.0), 0.1])
			out.append({"path": here, "name": ".".join(here), "value": float(value), "min": range_def[0], "max": range_def[1], "step": range_def[2], "known": RANGES.has(key)})


## 寫入事件裡某個參數（路徑逐層走下去；路徑不存在就不動並回傳 false）。
static func set_value(event: Dictionary, path: Array, value: float) -> bool:
	var node: Dictionary = event
	for i in path.size() - 1:
		if typeof(node.get(path[i])) != TYPE_DICTIONARY:
			return false
		node = node[path[i]]
	if not node.has(path[path.size() - 1]):
		return false
	node[path[path.size() - 1]] = value
	return true


# ---------------------------------------------------------------------------
# 預設組合
# ---------------------------------------------------------------------------

static func presets() -> Dictionary:
	if _presets.is_empty():
		var json: JSON = load(PRESETS_PATH) as JSON if ResourceLoader.exists(PRESETS_PATH) else null
		if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("presets")) != TYPE_DICTIONARY:
			push_error("[FeelParams] 無法讀取預設組合：%s（需要 presets 字典），只有 standard" % PRESETS_PATH)
			_presets = {"standard": {"label": "標準", "shake": 1.0, "hitstop": 1.0, "zoom": 1.0}}
		else:
			_presets = (json.data as Dictionary)["presets"]
	return _presets


static func validate_presets() -> PackedStringArray:
	var errors := PackedStringArray()
	var all := presets()
	if not all.has("standard"):
		errors.append("%s 缺少 standard 預設" % PRESETS_PATH)
	for id: String in all.keys():
		for key in ["shake", "hitstop", "zoom"]:
			if typeof((all[id] as Dictionary).get(key)) not in [TYPE_FLOAT, TYPE_INT] or float((all[id] as Dictionary)[key]) < 0.0:
				errors.append("%s 的預設「%s」的 %s 要是不小於 0 的數字" % [PRESETS_PATH, id, key])
	return errors


# ---------------------------------------------------------------------------
# 反向索引
# ---------------------------------------------------------------------------

## 事件 id → 使用它的檔案清單（掃描程式碼與資料檔裡的 Feel.play(&"…") 與招式的 event 欄位）。
static func usage(rebuild := false) -> Dictionary:
	if _usage_built and not rebuild:
		return _usage
	_usage = {}
	for id: Variant in Feel.event_ids():
		_usage[String(id)] = []
	var play_re := RegEx.create_from_string("Feel\\.play(?:\\.call_deferred)?\\(&\"([a-z0-9_]+)\"")
	var field_re := RegEx.create_from_string("\"event\"\\s*:\\s*\"([a-z0-9_]+)\"")
	var files := PackedStringArray()
	for dir in SOURCE_DIRS:
		_gd_files(dir, files)
	files.append_array(EXTRA_SOURCES)
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for regex in [play_re, field_re]:
			for m in (regex as RegEx).search_all(text):
				var id := m.get_string(1)
				if _usage.has(id) and not (_usage[id] as Array).has(path):
					(_usage[id] as Array).append(path)
	_usage_built = true
	return _usage


static func _gd_files(dir: String, into: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_gd_files(dir.path_join(sub), into)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			into.append(dir.path_join(file))


static func users_of(event_id: String) -> Array:
	return usage().get(event_id, [])


## 完全沒有被任何程式或資料使用的事件。
static func unused_events() -> PackedStringArray:
	var result := PackedStringArray()
	for id: String in usage().keys():
		if (usage()[id] as Array).is_empty():
			result.append(id)
	return result
