class_name AudioData
extends RefCounted
## 音訊資料（data/audio/*.json）共用的讀取器：檔案遺失、格式錯誤、缺少必要欄位都只記錄一次錯誤並回傳空字典，
## 呼叫端退回安全預設（合成音、靜音），遊戲不會因為資料壞掉而崩潰。

static var _reported: Dictionary = {}


## 讀取 JSON 並回傳最上層字典；fresh 為 true 時略過資源快取（實驗室寫回資料後重新讀取用）。
## required 是必須存在且為字典的欄位名稱，缺少時視為損毀。
static func read_root(path: String, tag: String, required: PackedStringArray = PackedStringArray(), fresh := false) -> Dictionary:
	if not ResourceLoader.exists(path):
		report(path + ":missing", "[%s] 找不到資料檔：%s" % [tag, path])
		return {}
	var json := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE if fresh else ResourceLoader.CACHE_MODE_REUSE) as JSON
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		report(path + ":format", "[%s] 資料檔格式錯誤（最上層要是字典）：%s" % [tag, path])
		return {}
	var root: Dictionary = json.data
	for key in required:
		if typeof(root.get(key)) != TYPE_DICTIONARY:
			report(path + ":" + key, "[%s] 資料檔缺少「%s」字典：%s" % [tag, key, path])
			return {}
	return root


## 同一個問題只記錄一次，避免每次播放都洗版。
static func report(key: String, message: String, as_error := true) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	if as_error:
		push_error(message)
	else:
		push_warning(message)


## 清掉已回報紀錄（測試與實驗室重新載入時用）。
static func reset_reports() -> void:
	_reported.clear()


## 把 [最小, 最大] 欄位讀成 Vector2；格式不對時回傳 fallback。
static func read_range(value: Variant, fallback := Vector2.ONE) -> Vector2:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return fallback
	var low := float(value[0])
	var high := float(value[1])
	if low <= 0.0 or high < low:
		return fallback
	return Vector2(low, high)
