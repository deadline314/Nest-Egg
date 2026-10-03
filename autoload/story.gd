extends Node
## 劇情服務：載入章節劇本（data/story/*.json）、播放過場／通訊對話、記錄本輪已看過的場景。
##   過場（cinematic）：暫停遊戲，一次一段，依序排隊。
##   通訊（radio）：不暫停遊戲，排隊自動播放。
##   對話（dialogue）：場景人物，玩家主動觸發，暫停遊戲逐句推進（見 NpcActor）。
## 場景可以帶 variants，依累計死亡次數改用不同的台詞（見 StoryReactions）；劇本品質檢查見 StoryLint。
## 台詞全部在資料檔，修改不需改程式；死亡重來時已看過的場景不會重播。
## 多章節：CHAPTER_PATHS 列出的劇本會合併成同一份講者與場景表（場景 id 全域唯一，慣例以 c2_ 等前綴區分章節），
## 關卡以 LevelData.chapter 指定自己屬於哪一章（章節標題、結尾卡、預告取自該章）。

signal scene_started(scene_id: StringName, mode: StringName)
signal scene_finished(scene_id: StringName)

const CHAPTER_PATHS: Array[String] = [
	"res://data/story/chapter_01.json",
	"res://data/story/chapter_02.json",
	# 動畫過場（只有 scenes，用 for_chapter 指明屬於哪一章）。
	"res://data/story/cutscenes_ch1.json",
]
const DEFAULT_CHAPTER := &"chapter_01"
const MODE_CINEMATIC := &"cinematic"
const MODE_RADIO := &"radio"
## 動畫過場（資料檔以 steps 描述，見 CutscenePlayer）：與過場一樣暫停遊戲並排隊。
const MODE_ANIMATED := &"animated"
## 場景人物對話（玩家主動觸發）：與過場一樣暫停遊戲、逐句推進，但句數上限較高，且不算「看過就不再播」。
const MODE_DIALOGUE := &"dialogue"
## 對話長度守則（見 design/04-story/STORY.md）：過場每段至多 6 句，通訊每段 1～2 句。
const MAX_CINEMATIC_LINES := 6
const MAX_RADIO_LINES := 2
const MAX_DIALOGUE_LINES := 8

## 測試用：過場立即結束（仍會發出開始／結束訊號）。
var auto_skip := false

## 章節 id -> 章節資訊（標題、副標、結尾卡、預告）。
var _chapters: Dictionary[StringName, Dictionary] = {}
var _speakers: Dictionary = {}
var _scenes: Dictionary = {}
## 場景 id -> 所屬章節 id（劇本品質檢查依章節加總）。
var _scene_chapter: Dictionary[String, StringName] = {}
## 死亡畫面的小字（各章節合併）與各章節的重生通訊（章節 id -> 清單），見 StoryReactions。
var _death_notes: Array = []
var _respawn_scenes: Dictionary = {}
var _seen: Dictionary[StringName, bool] = {}
var _cinematic_queue: Array[StringName] = []
var _current_cinematic: StringName = &""
## 剛結束的場景 -> 因 then 而自動接上的場景（play_and_wait 據此一路等到最後一段）。
var _chained: Dictionary[StringName, StringName] = {}
var _layer: DialogueLayer
var _player: CutscenePlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = DialogueLayer.new()
	add_child(_layer)
	_layer.cinematic_finished.connect(_on_cinematic_finished)
	_layer.radio_finished.connect(func(id: StringName) -> void: scene_finished.emit(id))
	load_all()
	for problem in validate():
		push_error("[Story] %s" % problem)
	for issue in lint_warnings():
		push_warning("[Story] %s" % StoryLint.format(issue))


## 載入 CHAPTER_PATHS 的所有章節（先清空）。單一章節壞掉只記錄錯誤，不影響其他章節。
func load_all() -> void:
	_chapters.clear()
	_speakers.clear()
	_scenes.clear()
	_scene_chapter.clear()
	_death_notes.clear()
	_respawn_scenes.clear()
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
	# 沒有 chapter 區塊的檔案只提供場景，並以 for_chapter 指定所屬章節（不覆蓋章節資訊）。
	var chapter_id := StringName(str(info.get("id", data.get("for_chapter", path.get_file().get_basename()))))
	if data.has("chapter") or not data.has("for_chapter"):
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
			_scene_chapter[scene_id] = chapter_id
	var notes: Variant = data.get("death_notes", [])
	if typeof(notes) == TYPE_ARRAY:
		_death_notes.append_array(notes)
	elif data.has("death_notes"):
		push_error("[Story] %s 的 death_notes 必須是陣列" % path)
	if data.has("respawn_scenes"):
		_respawn_scenes[chapter_id] = data["respawn_scenes"]
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
		if mode == String(MODE_ANIMATED):
			problems.append_array(CutsceneChecker.validate(scene_id, scene, _speakers))
			continue
		var lines: Array = scene.get("lines", [])
		var limit := _line_limit(mode)
		problems.append_array(StoryReactions.validate_variants(scene_id, scene, limit, _speakers))
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
	for scene_id: String in _scenes.keys():
		problems.append_array(_validate_chain(scene_id, _scenes[scene_id]))
	for chapter_id: StringName in _respawn_scenes:
		problems.append_array(StoryReactions.validate_respawns(String(chapter_id), _respawn_scenes[chapter_id], has_scene))
	if not _death_notes.is_empty():
		problems.append_array(StoryReactions.validate_notes("（全部）", _death_notes))
	for issue in StoryLint.errors_of(lint()):
		problems.append(StoryLint.format(issue))
	return problems


## 接續場景（then）：只能接在過場／動畫過場之後，目標必須存在，且不能形成迴圈。
func _validate_chain(scene_id: String, scene: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(scene) != TYPE_DICTIONARY or not (scene as Dictionary).has("then"):
		return problems
	var mode := str((scene as Dictionary).get("mode", "radio"))
	if mode != String(MODE_CINEMATIC) and mode != String(MODE_ANIMATED):
		problems.append("場景 %s（%s）不能設定 then，只有過場與動畫過場可以接續" % [scene_id, mode])
	var seen: Dictionary = {scene_id: true}
	var next := str((scene as Dictionary)["then"])
	while next != "":
		if not _scenes.has(next):
			problems.append("場景 %s 的接續場景「%s」不存在" % [scene_id, next])
			break
		if seen.has(next):
			problems.append("場景 %s 的接續形成迴圈（%s）" % [scene_id, next])
			break
		var next_mode := str((_scenes[next] as Dictionary).get("mode", "radio"))
		if next_mode != String(MODE_CINEMATIC) and next_mode != String(MODE_ANIMATED):
			problems.append("場景 %s 的接續場景「%s」是 %s，只能接過場或動畫過場" % [scene_id, next, next_mode])
		seen[next] = true
		next = str((_scenes[next] as Dictionary).get("then", ""))
	return problems


## 劇本品質檢查（文本風格指南的自動檢查，見 StoryLint）：掃描所有場景台詞與章節卡文字，回傳錯誤與警告。
func lint() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for chapter_id in _chapters:
		issues.append_array(StoryLint.check_chapter(String(chapter_id), text_units(chapter_id), _speakers))
	return issues


func lint_warnings() -> Array[Dictionary]:
	return StoryLint.warnings_of(lint())


## 某一章所有要檢查的文本單元：每個場景的台詞，加上章節卡文字。動畫場景取其中的 say 與 narrate 步驟。
func text_units(chapter_id: StringName) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for scene_id: String in _scenes.keys():
		if _scene_chapter.get(scene_id, &"") != chapter_id:
			continue
		units.append({"id": scene_id, "lines": _scene_text_lines(_scenes[scene_id])})
		for variant in StoryReactions.variants_of(_scenes[scene_id]):
			units.append({"id": "%s（死亡 %d 次起）" % [scene_id, StoryReactions.threshold(variant)], "lines": variant["lines"]})
	var card: Array = []
	var info: Dictionary = _chapters.get(chapter_id, {})
	for key in ["title", "subtitle", "end_title", "teaser"]:
		if info.has(key):
			card.append({"speaker": "", "text": str(info[key])})
	units.append({"id": "%s 章節卡" % chapter_id, "lines": card})
	return units


func _scene_text_lines(scene: Variant) -> Array:
	if typeof(scene) != TYPE_DICTIONARY:
		return []
	var result: Array = []
	if str((scene as Dictionary).get("mode", "radio")) == String(MODE_ANIMATED):
		var steps: Variant = (scene as Dictionary).get("steps", [])
		if typeof(steps) != TYPE_ARRAY:
			return result
		for step: Variant in steps:
			if typeof(step) != TYPE_DICTIONARY:
				continue
			match str(step.get("do", "")):
				"say":
					result.append({"speaker": str(step.get("speaker", "")), "text": str(step.get("text", ""))})
				"narrate":
					var narration: Variant = step.get("lines", [])
					if typeof(narration) == TYPE_ARRAY:
						for text: Variant in narration:
							result.append({"speaker": "system", "text": str(text)})
		return result
	var lines: Variant = (scene as Dictionary).get("lines", [])
	if typeof(lines) == TYPE_ARRAY:
		result.append_array(lines)
	return result


func _line_limit(mode: String) -> int:
	match mode:
		String(MODE_CINEMATIC):
			return MAX_CINEMATIC_LINES
		String(MODE_DIALOGUE):
			return MAX_DIALOGUE_LINES
	return MAX_RADIO_LINES


func has_scene(id: StringName) -> bool:
	return _scenes.has(String(id))


func scene_ids() -> Array:
	return _scenes.keys()


func scene_lines(id: StringName) -> Array:
	return (_scenes.get(String(id), {}) as Dictionary).get("lines", [])


## 場景現在要念的台詞：累計死亡達到某個變化的門檻就改用那一組，否則用正常台詞。deaths < 0 代表用本輪的累計死亡。
func lines_for(id: StringName, deaths := -1) -> Array:
	var scene: Variant = _scenes.get(String(id), null)
	if typeof(scene) != TYPE_DICTIONARY:
		return []
	var variant := StoryReactions.variant_lines(scene, GameState.deaths if deaths < 0 else deaths)
	if not variant.is_empty():
		return variant
	var base: Variant = (scene as Dictionary).get("lines", [])
	return base if typeof(base) == TYPE_ARRAY else []


## lines_for 的結果換成顯示資料（名字、顏色、頭像，{death_time} 已填入）。
func resolved_lines(id: StringName, deaths := -1) -> Array[Dictionary]:
	return _resolve_lines(lines_for(id, deaths))


## 死亡畫面的小字：累計死亡達到次數後才有，沒有回傳空字串。
func death_note(deaths := -1) -> String:
	return StoryReactions.pick_note(_death_notes, GameState.deaths if deaths < 0 else deaths)


## 某章節在累計死亡 deaths 次時，重生後要播的通訊。
func respawn_scene_ids(chapter: StringName, deaths := -1) -> Array[StringName]:
	var ids: Array[StringName] = []
	var entries: Variant = _respawn_scenes.get(chapter, [])
	if typeof(entries) != TYPE_ARRAY:
		return ids
	for entry in StoryReactions.eligible_respawns(entries, GameState.deaths if deaths < 0 else deaths):
		ids.append(StringName(str(entry["scene"])))
	return ids


## 死亡重生後播出該章節的反應通訊（repeat 的每次重生都播，其餘一輪只播一次）。回傳開始播的場景數。
func play_respawn_reactions(chapter: StringName, deaths := -1) -> int:
	var started := 0
	var entries: Variant = _respawn_scenes.get(chapter, [])
	if typeof(entries) != TYPE_ARRAY:
		return started
	for entry in StoryReactions.eligible_respawns(entries, GameState.deaths if deaths < 0 else deaths):
		if play(StringName(str(entry["scene"])), not bool(entry.get("repeat", false))):
			started += 1
	return started


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
	if mode == MODE_CINEMATIC or mode == MODE_ANIMATED or mode == MODE_DIALOGUE:
		if is_cinematic_active():
			_cinematic_queue.append(id)
		else:
			_start_cinematic(id)
	else:
		scene_started.emit(id, MODE_RADIO)
		_layer.enqueue_radio(id, resolved_lines(id))
	return true


## 播放並等待該場景結束，包含接在後面的 then 場景（場景不存在，或 once 為 true 且已看過時立即返回）。
func play_and_wait(id: StringName, once := true) -> void:
	if not play(id, once):
		return
	var current := id
	while current != &"":
		var finished: StringName = await scene_finished
		if finished == current:
			current = _chained.get(current, &"")
			_chained.erase(finished)


## 跳過目前的過場（與按 Esc 相同）。
func skip_cinematic() -> void:
	if not is_cinematic_active():
		return
	if is_instance_valid(_player) and _player.is_running():
		_player.skip()
	else:
		_layer.finish_cinematic()


func _start_cinematic(id: StringName) -> void:
	_current_cinematic = id
	var scene: Dictionary = _scenes.get(String(id), {})
	var animated := str(scene.get("mode", "")) == String(MODE_ANIMATED)
	scene_started.emit(id, MODE_ANIMATED if animated else MODE_CINEMATIC)
	if auto_skip or Settings.get_skip_cutscenes():
		_on_cinematic_finished.call_deferred(id)
		return
	if animated:
		_player = CutscenePlayer.new()
		add_child(_player)
		_player.finished.connect(_on_cinematic_finished)
		_player.play(id, scene)
		return
	_layer.start_cinematic(id, resolved_lines(id))


func _on_cinematic_finished(id: StringName) -> void:
	if _current_cinematic != id:
		return
	_current_cinematic = &""
	_queue_chained_scene(id)
	scene_finished.emit(id)
	if not _cinematic_queue.is_empty():
		_start_cinematic(_cinematic_queue.pop_front())


## 場景設定了 then 時，結束後立刻接著播（排在佇列最前面）；玩家按 Esc 略過時整串都略過，已看過的場景不重播。
func _queue_chained_scene(id: StringName) -> void:
	var next := StringName(str((_scenes.get(String(id), {}) as Dictionary).get("then", "")))
	if next == &"" or not has_scene(next) or _seen.has(next):
		return
	if is_instance_valid(_player) and _player.user_skipped:
		return
	_seen[next] = true
	_cinematic_queue.push_front(next)
	_chained[id] = next


## 把台詞的講者 id 換成顯示資料（名字、顏色、頭像），填入 {death_time}，帶上顯示前的沉默秒數 delay。
func _resolve_lines(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var info := speaker(str(entry.get("speaker", "")))
		var resolved := {
			"name": str(info.get("name", "")),
			"color": Color(str(info.get("color", "#ffffff"))),
			"portrait": str(info.get("portrait", "")),
			"text": StoryReactions.fill_placeholders(str(entry.get("text", "")), _death_clock()),
		}
		var delay := StoryReactions.line_delay(entry)
		if delay > 0.0:
			resolved["delay"] = delay
		result.append(resolved)
	return result


## {death_time} 要填的世界時間：剛剛死亡的時間；還沒死過就用現在的。
func _death_clock() -> String:
	return GameState.last_death_clock if not GameState.last_death_clock.is_empty() else GameState.world_clock_text()
