class_name SoundBank
extends RefCounted
## 音效庫：音效 id → 一或多個音訊檔（變體）。資料在 data/audio/sound_bank.json：
##   "sounds": { "<id>": { "files": ["res://audio/..."], "volume_db": 0.0, "pitch": [最小, 最大], "pack": "<授權包 id>",
##                         "speed_files": { "1.5": ["res://audio/..._x150.ogg"] }, "choke_ms": 70 } }
## speed_files：加速變體（時間伸縮、音高不變），鍵是速度倍率；射速加快時依倍率選最接近的一級，沒有就退回原速。
## choke_ms：同一個音效在上一發還沒播完又響起時，上一發在這麼多毫秒內淡出（0 或沒寫 = 不收）。
## 檔案遺失或無法解碼時記錄「id 與路徑」並略過該檔；整個 id 都沒有可播的檔案時，呼叫端退回合成音。

const PATH := "res://data/audio/sound_bank.json"
const TAG := "SoundBank"
const KNOWN_FIELDS: PackedStringArray = ["files", "volume_db", "pitch", "pack", "note", "loop", "speed_files", "choke_ms"]
const MAX_CHOKE_MS := 500.0
const AUDIO_EXTENSIONS: PackedStringArray = ["ogg", "wav", "mp3"]

var path := PATH
var _defs: Dictionary = {}
## id → 載入成功的變體（Array[AudioStream]）。
var _streams: Dictionary = {}
## id → 載入失敗的路徑清單（給診斷與實驗室列出缺檔）。
var _failed: Dictionary = {}
## id → { 倍率（float）: 載入成功的加速變體（Array[AudioStream]） }。
var _speed_streams: Dictionary = {}


func load_bank(p_path := PATH, fresh := false) -> void:
	path = p_path
	_defs = {}
	_streams = {}
	_failed = {}
	_speed_streams = {}
	var root := AudioData.read_root(path, TAG, PackedStringArray(["sounds"]), fresh)
	if root.is_empty():
		return
	_defs = root["sounds"]
	for id: String in _defs.keys():
		_load_entry(id)


func _load_entry(id: String) -> void:
	var def: Variant = _defs[id]
	var files: Variant = (def as Dictionary).get("files") if typeof(def) == TYPE_DICTIONARY else null
	if typeof(files) != TYPE_ARRAY:
		AudioData.report("bank:%s:files" % id, "[%s] 音效「%s」沒有 files 陣列（%s）" % [TAG, id, path])
		return
	var loaded: Array[AudioStream] = []
	var failed := PackedStringArray()
	for file: Variant in files:
		var file_path := str(file)
		var stream := load(file_path) as AudioStream if ResourceLoader.exists(file_path) else null
		if stream == null:
			failed.append(file_path)
			AudioData.report("bank:%s:%s" % [id, file_path], "[%s] 音效「%s」的檔案無法載入：%s（%s），改用其他變體或合成音" % [TAG, id, file_path, path])
		else:
			loaded.append(stream)
	if not loaded.is_empty():
		_streams[StringName(id)] = loaded
	_load_speed_entry(id, failed)
	if not failed.is_empty():
		_failed[StringName(id)] = failed


## 載入加速變體；缺檔或格式不對時記錄 id、倍率與路徑，那一級退回原速（其他級照常）。
func _load_speed_entry(id: String, failed: PackedStringArray) -> void:
	var table: Variant = (_defs[id] as Dictionary).get("speed_files")
	if table == null:
		return
	if typeof(table) != TYPE_DICTIONARY:
		AudioData.report("bank:%s:speed_files" % id, "[%s] 音效「%s」的 speed_files 要是 {倍率: [檔案]}（%s）" % [TAG, id, path])
		return
	var levels := {}
	for key: Variant in (table as Dictionary).keys():
		var speed := str(key).to_float()
		var list: Variant = (table as Dictionary)[key]
		if speed <= 1.0 or typeof(list) != TYPE_ARRAY:
			AudioData.report("bank:%s:speed:%s" % [id, key], "[%s] 音效「%s」的 speed_files「%s」要是大於 1 的倍率加檔案陣列（%s），略過" % [TAG, id, key, path])
			continue
		var loaded: Array[AudioStream] = []
		for file: Variant in list:
			var file_path := str(file)
			var stream := load(file_path) as AudioStream if ResourceLoader.exists(file_path) else null
			if stream == null:
				failed.append(file_path)
				AudioData.report("bank:%s:%s" % [id, file_path], "[%s] 音效「%s」的 %s 倍加速檔無法載入：%s（%s），這一級退回原速" % [TAG, id, key, file_path, path])
			else:
				loaded.append(stream)
		if loaded.size() == (list as Array).size() and not loaded.is_empty():
			levels[speed] = loaded
	if not levels.is_empty():
		_speed_streams[StringName(id)] = levels


## 這個 id 是否有至少一個可播放的檔案。
func has_files(id: StringName) -> bool:
	return _streams.has(id)


func variants(id: StringName) -> Array:
	return _streams.get(id, [])


## 這個音效依射速倍率要用的那一級：回傳 1.0（原速）或有檔案的加速倍率。
## 倍率不大於 1 或沒有加速變體 = 原速；有的話選對數距離最近的一級（原速也算一級）。
func speed_level(id: StringName, speed: float) -> float:
	var levels: Dictionary = _speed_streams.get(id, {})
	if speed <= 1.0 or levels.is_empty():
		return 1.0
	var best := 1.0
	var best_distance := absf(log(speed))
	for level: float in levels.keys():
		var distance := absf(log(speed) - log(level))
		if distance < best_distance:
			best = level
			best_distance = distance
	return best


## 某一級的變體（level 是 speed_level 的結果）；1.0 或不存在的級回傳原速變體。
func variants_at(id: StringName, level: float) -> Array:
	var levels: Dictionary = _speed_streams.get(id, {})
	return levels.get(level, variants(id)) if level > 1.0 else variants(id)


## 載入成功的加速倍率（由小到大）。
func speed_levels(id: StringName) -> Array:
	var keys: Array = (_speed_streams.get(id, {}) as Dictionary).keys()
	keys.sort()
	return keys


## 上一發尾音的淡出時間（毫秒）；0 = 不收。
func choke_ms(id: StringName) -> float:
	return clampf(float((_defs.get(String(id), {}) as Dictionary).get("choke_ms", 0.0)), 0.0, MAX_CHOKE_MS)


func ids() -> Array:
	return _defs.keys()


func volume_db(id: StringName) -> float:
	return float((_defs.get(String(id), {}) as Dictionary).get("volume_db", 0.0))


func pitch_range(id: StringName) -> Vector2:
	return AudioData.read_range((_defs.get(String(id), {}) as Dictionary).get("pitch"))


## 這個音效用到的授權包 id（pack 欄位可以是一個字串或字串陣列）。
func packs_of(id: StringName) -> PackedStringArray:
	var value: Variant = (_defs.get(String(id), {}) as Dictionary).get("pack", "")
	var result := PackedStringArray()
	for item: Variant in (value if typeof(value) == TYPE_ARRAY else [value]):
		if not str(item).is_empty():
			result.append(str(item))
	return result


func files_of(id: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	for file: Variant in (_defs.get(String(id), {}) as Dictionary).get("files", []):
		result.append(str(file))
	return result


## 原速與所有加速變體的檔案（檢查有沒有沒被引用的音訊檔用）。
func all_files_of(id: StringName) -> PackedStringArray:
	var result := files_of(id)
	var table: Variant = (_defs.get(String(id), {}) as Dictionary).get("speed_files")
	if typeof(table) == TYPE_DICTIONARY:
		for list: Variant in (table as Dictionary).values():
			if typeof(list) == TYPE_ARRAY:
				for file: Variant in list:
					result.append(str(file))
	return result


## 載入失敗的檔案路徑（id → PackedStringArray）。
func failed_files() -> Dictionary:
	return _failed


func def(id: StringName) -> Dictionary:
	return _defs.get(String(id), {})


## 目前記憶體中的全部定義（實驗室調整後寫回用）。
func all_defs() -> Dictionary:
	return _defs


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。known_pack 不為空時，pack 欄位必須在清單內。
func validate(known_packs: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var errors := PackedStringArray()
	for id: String in _defs.keys():
		var entry: Variant = _defs[id]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s 的音效「%s」不是字典" % [path, id])
			continue
		var d := entry as Dictionary
		for field: String in d.keys():
			if not KNOWN_FIELDS.has(field):
				errors.append("%s 的音效「%s」有不認得的欄位「%s」" % [path, id, field])
		var files: Variant = d.get("files")
		if typeof(files) != TYPE_ARRAY or (files as Array).is_empty():
			errors.append("%s 的音效「%s」要有非空的 files 陣列" % [path, id])
		else:
			for file: Variant in files:
				var file_path := str(file)
				if not AUDIO_EXTENSIONS.has(file_path.get_extension().to_lower()):
					errors.append("%s 的音效「%s」的檔案副檔名不是音訊格式：%s" % [path, id, file_path])
				elif not ResourceLoader.exists(file_path):
					errors.append("%s 的音效「%s」引用不存在的檔案：%s" % [path, id, file_path])
		if d.has("speed_files"):
			if typeof(d["speed_files"]) != TYPE_DICTIONARY:
				errors.append("%s 的音效「%s」的 speed_files 要是 {倍率: [檔案]}" % [path, id])
			else:
				for key: Variant in (d["speed_files"] as Dictionary).keys():
					var list: Variant = (d["speed_files"] as Dictionary)[key]
					if str(key).to_float() <= 1.0:
						errors.append("%s 的音效「%s」的 speed_files 倍率「%s」要大於 1" % [path, id, key])
					if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
						errors.append("%s 的音效「%s」的 speed_files「%s」要有非空的檔案陣列" % [path, id, key])
					elif typeof(files) == TYPE_ARRAY and (list as Array).size() != (files as Array).size():
						errors.append("%s 的音效「%s」的 speed_files「%s」要和 files 一樣多個（%d 對 %d），變體才對得上" % [path, id, key, (list as Array).size(), (files as Array).size()])
					elif typeof(list) == TYPE_ARRAY:
						for file: Variant in list:
							if not ResourceLoader.exists(str(file)):
								errors.append("%s 的音效「%s」的 speed_files「%s」引用不存在的檔案：%s" % [path, id, key, file])
		if d.has("choke_ms") and (not (typeof(d["choke_ms"]) in [TYPE_INT, TYPE_FLOAT]) or float(d["choke_ms"]) < 0.0 or float(d["choke_ms"]) > MAX_CHOKE_MS):
			errors.append("%s 的音效「%s」的 choke_ms 要是 0 到 %d 的數字（毫秒）" % [path, id, int(MAX_CHOKE_MS)])
		if d.has("pitch") and AudioData.read_range(d["pitch"], Vector2.ZERO) == Vector2.ZERO:
			errors.append("%s 的音效「%s」的 pitch 要是 [最小, 最大]，且大於 0" % [path, id])
		if d.has("volume_db") and typeof(d["volume_db"]) != TYPE_FLOAT and typeof(d["volume_db"]) != TYPE_INT:
			errors.append("%s 的音效「%s」的 volume_db 要是數字" % [path, id])
		if not known_packs.is_empty():
			var packs := packs_of(StringName(id))
			if packs.is_empty():
				errors.append("%s 的音效「%s」沒有 pack（授權包 id）" % [path, id])
			for pack in packs:
				if not known_packs.has(pack):
					errors.append("%s 的音效「%s」的 pack「%s」不在授權登記裡" % [path, id, pack])
	return errors
