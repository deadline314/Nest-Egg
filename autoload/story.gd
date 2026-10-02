extends Node
## 劇情服務：載入章節劇本（data/story/*.json）、播放過場／通訊對話、記錄本輪已看過的場景。
##   過場（cinematic）：暫停遊戲，一次一段，依序排隊。
##   通訊（radio）：不暫停遊戲，排隊自動播放。
## 台詞全部在資料檔，修改不需改程式；死亡重來時已看過的場景不會重播。

signal scene_started(scene_id: StringName, mode: StringName)
signal scene_finished(scene_id: StringName)

const DEFAULT_CHAPTER := "res://data/story/chapter_01.json"
const MODE_CINEMATIC := &"cinematic"
const MODE_RADIO := &"radio"

## 測試用：過場立即結束（仍會發出開始／結束訊號）。
var auto_skip := false

var _chapter: Dictionary = {}
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
	load_chapter(DEFAULT_CHAPTER)


func load_chapter(path: String) -> bool:
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[Story] 無法讀取劇本：%s" % path)
		return false
	_chapter = (json.data as Dictionary).get("chapter", {})
	_speakers = (json.data as Dictionary).get("speakers", {})
	_scenes = (json.data as Dictionary).get("scenes", {})
	return true


func chapter_info() -> Dictionary:
	return _chapter


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
