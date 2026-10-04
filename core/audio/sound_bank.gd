class_name SoundBank
extends RefCounted
## 音效庫：音效 id → 一或多個音訊檔（變體）。資料在 data/audio/sound_bank.json：
##   "sounds": { "<id>": { "files": ["res://audio/..."], "volume_db": 0.0, "pitch": [最小, 最大], "pack": "<授權包 id>" } }
## 檔案遺失或無法解碼時記錄「id 與路徑」並略過該檔；整個 id 都沒有可播的檔案時，呼叫端退回合成音。

const PATH := "res://data/audio/sound_bank.json"
const TAG := "SoundBank"
const KNOWN_FIELDS: PackedStringArray = ["files", "volume_db", "pitch", "pack", "note", "loop"]
const AUDIO_EXTENSIONS: PackedStringArray = ["ogg", "wav", "mp3"]

var path := PATH
var _defs: Dictionary = {}
## id → 載入成功的變體（Array[AudioStream]）。
var _streams: Dictionary = {}
## id → 載入失敗的路徑清單（給診斷與實驗室列出缺檔）。
var _failed: Dictionary = {}


func load_bank(p_path := PATH, fresh := false) -> void:
	path = p_path
	_defs = {}
	_streams = {}
	_failed = {}
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
	if not failed.is_empty():
		_failed[StringName(id)] = failed


## 這個 id 是否有至少一個可播放的檔案。
func has_files(id: StringName) -> bool:
	return _streams.has(id)


func variants(id: StringName) -> Array:
	return _streams.get(id, [])


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
