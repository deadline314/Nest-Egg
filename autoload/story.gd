extends Node
## 劇情服務：載入章節劇本（data/story/*.json）、播放過場／通訊對話、記錄本輪已看過的場景。
##   過場（cinematic）：暫停遊戲，一次一段，依序排隊。
##   通訊（radio）：不暫停遊戲，排隊自動播放。
## 台詞全部在資料檔，修改不需改程式；死亡重來時已看過的場景不會重播。
## 多章節：CHAPTER_PATHS 列出的劇本會合併成同一份講者與場景表（場景 id 全域唯一，慣例以 c2_ 等前綴區分章節），
## 關卡以 LevelData.chapter 指定自己屬於哪一章（章節標題、結尾卡、預告取自該章）。

signal scene_started(scene_id: StringName, mode: StringName)
signal scene_finished(scene_id: StringName)

const CHAPTER_PATHS: Array[String] = [
	"res://data/story/chapter_01.json",
	"res://data/story/chapter_02.json",
]
const DEFAULT_CHAPTER := &"chapter_01"
const MODE_CINEMATIC := &"cinematic"
const MODE_RADIO := &"radio"
## 對話長度守則（見 design/04-story/STORY.md）：過場每段至多 6 句，通訊每段 1～2 句。
const MAX_CINEMATIC_LINES := 6
const MAX_RADIO_LINES := 2

## 測試用：過場立即結束（仍會發出開始／結束訊號）。
var auto_skip := false

## 章節 id -> 章節資訊（標題、副標、結尾卡、預告）。
var _chapters: Dictionary[StringName, Dictionary] = {}
var _speakers: Dictionary = {}
var _scenes: Dictionary = {}
var _seen: Dictionary[StringName, bool] = {}
var _cinematic_queue: Array[StringName] = []
var _current_cinematic: StringName = &""
var _layer: DialogueLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = DialogueLayer.new()
	add_child(_layer)
	_layer.cinematic_finished.connect(_on_cinematic_finished)
	_layer.radio_finished.connect(func(id: StringName) -> void: scene_finished.emit(id))
	load_all()
	for problem in validate():
		push_error("[Story] %s" % problem)


## 載入 CHAPTER_PATHS 的所有章節（先清空）。單一章節壞掉只記錄錯誤，不影響其他章節。
func load_all() -> void:
	_chapters.clear()
	_speakers.clear()
	_scenes.clear()
	for path in CHAPTER_PATHS:
		load_chapter(path)


## 讀取一份章節劇本並合併進講者與場景表。講者 id 相同時後讀的覆蓋前者；場景 id 重複時略過後者並記錄錯誤。
func load_chapter(path: String) -> bool:
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[Story] 無法讀取劇本：%s" % path)
		return false
	var data: Dictionary = json.data
	var info: Dictionary = data.get("chapter", {})
	var chapter_id := StringName(str(info.get("id", path.get_file().get_basename())))
	_chapters[chapter_id] = info
	var speakers: Variant = data.get("speakers", {})
	if typeof(speakers) == TYPE_DICTIONARY:
		_speakers.merge(speakers, true)
	var scenes: Variant = data.get("scenes", {})
	if typeof(scenes) == TYPE_DICTIONARY:
		for scene_id: String in scenes.keys():
			if _scenes.has(scene_id):
				push_error("[Story] 場景 id「%s」重複（%s），已略過後者" % [scene_id, path])
				continue
			_scenes[scene_id] = scenes[scene_id]
	return true


## 章節資訊。chapter 留空代表預設章節（第一章）。找不到時回傳空字典。
func chapter_info(chapter: StringName = DEFAULT_CHAPTER) -> Dictionary:
	if not _chapters.has(chapter):
		push_warning("[Story] 找不到章節：%s" % chapter)
		return {}
	return _chapters[chapter]


func chapter_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _chapters:
		ids.append(id)
	return ids


## 檢查劇本是否符合守則，回傳問題清單（空代表沒問題）：講者存在且有頭像、過場／通訊的句數、每句有文字。
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for speaker_id: String in _speakers.keys():
		var portrait := str((_speakers[speaker_id] as Dictionary).get("portrait", ""))
		if portrait.is_empty() or not ResourceLoader.exists(portrait):
			problems.append("講者 %s 的頭像不存在：%s" % [speaker_id, portrait])
	for scene_id: String in _scenes.keys():
		var scene: Dictionary = _scenes[scene_id]
		var mode := str(scene.get("mode", "radio"))
		var lines: Array = scene.get("lines", [])
		var limit := MAX_CINEMATIC_LINES if mode == String(MODE_CINEMATIC) else MAX_RADIO_LINES
		if lines.is_empty():
			problems.append("場景 %s 沒有任何台詞" % scene_id)
		elif lines.size() > limit:
			problems.append("場景 %s（%s）有 %d 句，上限 %d 句" % [scene_id, mode, lines.size(), limit])
		for entry: Variant in lines:
			if typeof(entry) != TYPE_DICTIONARY:
				problems.append("場景 %s 有一句不是物件" % scene_id)
				continue
			if not _speakers.has(str(entry.get("speaker", ""))):
				problems.append("場景 %s 的講者「%s」未定義" % [scene_id, entry.get("speaker", "")])
			if str(entry.get("text", "")).is_empty():
				problems.append("場景 %s 有一句沒有文字" % scene_id)
	return problems


func has_scene(id: StringName) -> bool:
	return _scenes.has(String(id))


func scene_ids() -> Array:
	return _scenes.keys()


func scene_lines(id: StringName) -> Array:
	return (_scenes.get(String(id), {}) as Dictionary).get("lines", [])


func speaker(id: String) -> Dictionary:
	return _speakers.get(id, {"name": id, "color": "#ffffff", "portrait": ""})


func speaker_ids() -> Array:
	return _speakers.keys()


func was_seen(id: StringName) -> bool:
	return _seen.has(id)


## 新的一輪遊戲開始時清除觀看紀錄。
func reset_progress() -> void:
	_seen.clear()
	_cinematic_queue.clear()


func is_cinematic_active() -> bool:
	return _current_cinematic != &""


## 播放場景。once = true 時同一輪只播一次。回傳是否有開始（或排入佇列）。
func play(id: StringName, once := true) -> bool:
	if id == &"" or not has_scene(id):
		if id != &"":
			push_warning("[Story] 找不到劇情場景：%s" % id)
		return false
	if once and _seen.has(id):
		return false
	_seen[id] = true
	var scene: Dictionary = _scenes[String(id)]
	var mode := StringName(str(scene.get("mode", "radio")))
	if mode == MODE_CINEMATIC:
		if is_cinematic_active():
			_cinematic_queue.append(id)
		else:
			_start_cinematic(id)
	else:
		scene_started.emit(id, MODE_RADIO)
		_layer.enqueue_radio(id, _resolve_lines(scene.get("lines", [])))
	return true


## 播放並等待該場景結束（場景不存在或已看過時立即返回）。
func play_and_wait(id: StringName) -> void:
	if not play(id):
		return
	while true:
		var finished: StringName = await scene_finished
		if finished == id:
			return


## 跳過目前的過場（與按 Esc 相同）。
func skip_cinematic() -> void:
	if is_cinematic_active():
		_layer.finish_cinematic()


func _start_cinematic(id: StringName) -> void:
	_current_cinematic = id
	scene_started.emit(id, MODE_CINEMATIC)
	if auto_skip:
		_on_cinematic_finished.call_deferred(id)
		return
	_layer.start_cinematic(id, _resolve_lines(scene_lines(id)))


func _on_cinematic_finished(id: StringName) -> void:
	if _current_cinematic != id:
		return
	_current_cinematic = &""
	scene_finished.emit(id)
	if not _cinematic_queue.is_empty():
		_start_cinematic(_cinematic_queue.pop_front())


## 把台詞的講者 id 換成顯示資料（名字、顏色、頭像）。
func _resolve_lines(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var info := speaker(str(entry.get("speaker", "")))
		result.append({
			"name": str(info.get("name", "")),
			"color": Color(str(info.get("color", "#ffffff"))),
			"portrait": str(info.get("portrait", "")),
			"text": str(entry.get("text", "")),
		})
	return result
