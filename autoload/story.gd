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
## 完成或取消的等待接點；取消不觸發 scene_finished，因而不寫完成旗標或發放獎勵。
signal request_settled(request: int, completed: bool)
signal presentation_cancelled(scene_id: StringName, context: Dictionary, reason: StringName, request: int)

const CHAPTER_PATHS: Array[String] = [
	"res://data/story/chapter_01.json",
	"res://data/story/chapter_02.json",
	# 新故事（傘）：第一章的章節資訊；台詞與過場由 ST-9 接上。
	"res://data/story/ch1_kasa.json",
	# 動畫過場（只有 scenes，用 for_chapter 指明屬於哪一章）。
	"res://data/story/cutscenes_ch1.json",
	"res://data/story/cutscenes_ch2.json",
]
const DEFAULT_CHAPTER := &"chapter_01"
const MODE_CINEMATIC := &"cinematic"
const MODE_RADIO := &"radio"
## 動畫過場（資料檔以 steps 描述，見 CutscenePlayer）：與過場一樣暫停遊戲並排隊。
const MODE_ANIMATED := &"animated"
## 場景人物對話（玩家主動觸發）：與過場一樣暫停遊戲、逐句推進，但句數上限較高，且不算「看過就不再播」。
const MODE_DIALOGUE := &"dialogue"
## 地圖上的對話氣泡（見 MapBubbles）：不暫停、不鎖操作，講者頭上冒出短句。沒有氣泡宿主（不在關卡裡）或講者不在地圖上時改用通訊。
const MODE_BUBBLES := &"bubbles"
## 分派：依 routes 的條件挑第一個成立的場景播放（人物或物件的入口），本身沒有台詞、不記觀看。
const MODE_DISPATCH := &"dispatch"
## 對話長度守則（見 design/04-story/STORY.md）：過場每段至多 6 句，通訊每段 1～2 句。
const MAX_CINEMATIC_LINES := 6
const MAX_RADIO_LINES := 2
const MAX_DIALOGUE_LINES := 8
## 氣泡守則（見 skill chapter-design）：一段 ≤ 4 句、每句 ≤ 30 字；戰鬥中的 bark ≤ 2 句、每句 ≤ 16 字。
const MAX_BUBBLE_LINES := 4
const MAX_BUBBLE_CHARS := 30
const MAX_BARK_LINES := 2
const MAX_BARK_CHARS := 16

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
## 地圖氣泡的宿主（Level 登記，離開關卡時清除）。
var _bubble_host: MapBubbles
var _respawn_scenes: Dictionary = {}
var _death_scenes: Dictionary = {}
var _death_sequences: Dictionary = {}
var _seen: Dictionary[StringName, bool] = {}
var _completed: Dictionary[StringName, bool] = {}
var _cinematic_queue: Array[Dictionary] = []
var _current_cinematic: StringName = &""
var _presentation_context: Dictionary = {}
var _framing_token := 0
var _presentation_generation := 0
var _request_serial := 0
var _current_request := 0
var _finished_request := 0
var _waiters: Dictionary[int, bool] = {}
var _request_results: Dictionary[int, bool] = {}
var _passive_requests: Dictionary[StringName, Array] = {}
var _resetting_presentation := false
## 選項選到的交付在場景播完才生效；取消、死亡或換區時丟棄（場景 id → 物品 id 清單）。
var _pending_transfers: Dictionary[StringName, Array] = {}
## 選項選到的接續場景（場景 id → 目標）；播完才接，取消時丟棄。
var _pending_next: Dictionary[StringName, StringName] = {}
## 段尾結果與章節事實表（見 StoryOutcomes）。
var outcomes := StoryOutcomes.new()
## 章節 → 一般復原時寫入的旗標（restoration_flag）。
var _restoration_flags: Dictionary[StringName, StringName] = {}
## 帶情境事實的演出鏈所屬請求；請求結束或取消時清除情境事實。
var _context_request := 0
var framing: CinematicFraming
var _layer: DialogueLayer
var _player: CutscenePlayer

class PreparedInstall extends RefCounted:
	var seen: Dictionary[StringName, bool] = {}
	var completed: Dictionary[StringName, bool] = {}


func _install_source() -> Dictionary:
	var waiters: Array = []
	var results: Array = []
	for request: int in _waiters:
		waiters.append([request, _waiters[request]])
	for request: int in _request_results:
		results.append([request, _request_results[request]])
	return {"seen": _seen, "completed": _completed, "generation": _presentation_generation,
		"request_serial": _request_serial, "current_request": _current_request, "finished_request": _finished_request,
		"cinematic": String(_current_cinematic), "context": _presentation_context, "queue": _cinematic_queue,
		"waiters": waiters, "results": results, "passive": _passive_requests, "resetting": _resetting_presentation,
		"scenes": _scenes}


## Full restores require the caller to cancel presentation while the old run is intact.
## Story batches only replace progress, retaining current pending/queued reservations.
func prepare_install(raw: Variant, whole_run: bool) -> Dictionary:
	var errors := RunSaveCodec.validate_tree(raw)
	if not errors.is_empty():
		return {"error": errors[0]}
	if not raw is Array or raw.size() > _scenes.size():
		return {"error": "install/story/completed must be a bounded scene list"}
	if whole_run and (_current_cinematic != &"" or _current_request != 0 or _finished_request != 0 or not _cinematic_queue.is_empty() or not _passive_requests.is_empty() or not _waiters.is_empty() or _resetting_presentation):
		return {"error": "install/story/presentation must settle before whole-run preparation"}
	var prepared := PreparedInstall.new()
	if not whole_run:
		prepared.seen = _seen.duplicate()
	for value: Variant in raw:
		if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME] or not has_scene(StringName(value)) or prepared.completed.has(StringName(value)):
			return {"error": "install/story/completed unknown or repeated scene"}
		prepared.completed[StringName(value)] = true
		prepared.seen[StringName(value)] = true
	if not whole_run:
		for id: StringName in _completed:
			if not prepared.completed.has(id):
				return {"error": "install/story/batch cannot remove completed scenes"}
	return {"data": prepared}


## Never clears requests, callbacks, framing or queues, and emits nothing.
func _install_prepared(prepared: PreparedInstall) -> void:
	_seen = prepared.seen
	_completed = prepared.completed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	framing = CinematicFraming.new()
	add_child(framing)
	_layer = DialogueLayer.new()
	add_child(_layer)
	_layer.cinematic_finished.connect(_on_cinematic_finished)
	_layer.radio_finished.connect(_on_passive_finished)
	scene_finished.connect(func(id: StringName) -> void:
		_completed[id] = true
		GameState.request_story_save())
	EventBus.player_died.connect(func(_cause: StringName) -> void: reset_active_presentation(&"death"))
	EventBus.checkpoint_reached.connect(func(_position: Vector2) -> void:
		for scene in outcomes.scenes_for_event(&"checkpoint"):
			play(scene))
	load_all()
	if FileAccess.file_exists(GameState.STORY_SAVE_PATH):
		GameState.load_story_progress()
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
	_death_scenes.clear()
	_death_sequences.clear()
	_restoration_flags.clear()
	outcomes.clear()
	GameState.flag_defaults.clear()
	for path in CHAPTER_PATHS:
		load_chapter(path)


## 讀取一份章節劇本並合併進講者與場景表。講者 id 相同時後讀的覆蓋前者；場景 id 重複時略過後者並記錄錯誤。
func load_chapter(path: String) -> bool:
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[Story] 無法讀取劇本：%s" % path)
		return false
	var data: Dictionary = json.data
	if data.has("flag_defaults"):
		GameState.register_flag_defaults(data["flag_defaults"], path)
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
	if data.has("death_scenes"):
		_death_scenes[chapter_id] = data["death_scenes"]
	if data.has("death_sequences"):
		_death_sequences[chapter_id] = data["death_sequences"]
	outcomes.merge_chapter(data, path)
	if data.get("restoration_flag") is String:
		_restoration_flags[chapter_id] = StringName(data["restoration_flag"])
	return true


## 一般死亡後要從已登記的電話亭醒來（不是初次建檔的診間）時，寫下章節的「在亭子復原過」旗標。
## 由真正的死亡流程呼叫；不從死亡次數猜測。
func note_ordinary_restoration(chapter: StringName) -> void:
	var flag: StringName = _restoration_flags.get(chapter, &"")
	if flag != &"" and not GameState.has_flag(flag):
		GameState.set_flag(flag)


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


## 場景結束時套用結果：set_flags（旗標名稱清單，出入口的 requires_flag 與之後的劇情分支都看它）與
## transfer_items（交出原件；場景本身或玩家選到的選項宣告）。交付前先確認全部原件仍在手上，
## 任一件不在就整段結果不生效並記錄場景與物品，避免「旗標說交了、盤還在身上」的半套狀態。
## results（見 StoryOutcomes）與 set_flags／transfer_items 一起預檢、一起生效。回傳 {ok, failure_scene}：
## 交易被拒絕時改接 on_failure 指定的場景（例如現金不足），整段結果不生效。
func _apply_scene_results(id: StringName) -> Dictionary:
	var pending: Array = _pending_transfers.get(id, [])
	_pending_transfers.erase(id)
	var scene: Variant = _scenes.get(String(id), null)
	if typeof(scene) != TYPE_DICTIONARY:
		return {"ok": true, "failure_scene": ""}
	var transfers := StoryRules.transfer_ids(scene)
	for item: Variant in pending:
		if not transfers.has(StringName(item)):
			transfers.append(StringName(item))
	var checked := outcomes.preflight(id, scene, transfers)
	if not checked["ok"]:
		if str(checked["failure_scene"]).is_empty():
			push_error("[Story] %s：%s，這段結果（旗標、交付與交易）未生效" % [checked["where"], checked["reason"]])
		return checked
	if not outcomes.commit(id, scene, transfers):
		return {"ok": false, "failure_scene": ""}
	return {"ok": true, "failure_scene": ""}


## 舊名稱：既有呼叫端與測試沿用，行為同 _apply_scene_results。
func _apply_scene_flags(id: StringName) -> void:
	_apply_scene_results(id)


## 場景宣告的交付原件是否都還在手上（沒有宣告時為 true）。
func can_transfer_for(id: StringName) -> bool:
	for item in StoryRules.transfer_ids(_scenes.get(String(id), {})):
		if not StoryItems.holds(item):
			return false
	return true


## 劇情條件讀取的事實（StoryRules.holds 的預設來源）。
func fact(kind: StringName, id: StringName) -> Variant:
	match kind:
		&"flag":
			return outcomes.flag_value(id)
		&"held":
			return StoryItems.holds(id)
		&"receipt":
			return outcomes.receipt_recorded(id)
		&"account":
			return outcomes.account_state(id)
	return null


## 場景的前置條件（when）是否成立；沒有條件時為 true。
func scene_available(id: StringName) -> bool:
	var scene: Dictionary = _scenes.get(String(id), {})
	return not scene.has("when") or StoryRules.holds(scene["when"])


## 分派場景目前會播哪一段（依 routes 順序第一個成立的）；不是分派場景時回傳自己，沒有可播的回傳空。
func resolve_dispatch(id: StringName) -> StringName:
	var scene: Dictionary = _scenes.get(String(id), {})
	if str(scene.get("mode", "")) != String(MODE_DISPATCH):
		return id if has_scene(id) else &""
	var routes: Variant = scene.get("routes", [])
	if routes is Array:
		for route: Variant in routes:
			if not route is Dictionary:
				continue
			var target := StringName(str((route as Dictionary).get("target", "")))
			if target != &"" and has_scene(target) and str((_scenes[String(target)] as Dictionary).get("mode", "")) != String(MODE_DISPATCH) \
					and StoryRules.holds(route.get("when", {})) and scene_available(target) and can_transfer_for(target):
				return target
	return &""


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
		if scene.has("set_flags") and (typeof(scene["set_flags"]) != TYPE_ARRAY or (scene["set_flags"] as Array).any(func(f: Variant) -> bool: return str(f).is_empty())):
			problems.append("場景 %s 的 set_flags 必須是非空的旗標名稱清單" % scene_id)
		problems.append_array(StoryRules.validate_transfers("場景 %s" % scene_id, scene))
		problems.append_array(outcomes.validate_scene(scene_id, scene, has_scene))
		problems.append_array(_validate_targets(scene_id, scene))
		if mode == String(MODE_DISPATCH):
			continue
		if scene.has("transfer_items") and mode not in [String(MODE_CINEMATIC), String(MODE_ANIMATED), String(MODE_DIALOGUE)]:
			problems.append("場景 %s（%s）不能交出原件：只有可取消回撤的過場與對話可以交付" % [scene_id, mode])
		if mode == String(MODE_ANIMATED):
			problems.append_array(CutsceneChecker.validate(scene_id, scene, _speakers))
			continue
		var lines: Array = scene.get("lines", [])
		var limit := _line_limit(mode, scene)
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
			if mode == String(MODE_BUBBLES):
				var cap := MAX_BARK_CHARS if bool(scene.get("bark", false)) else MAX_BUBBLE_CHARS
				if str(entry.get("text", "")).length() > cap:
					problems.append("場景 %s（氣泡%s）的句子超過 %d 字：%s" % [scene_id, "，戰鬥短句" if bool(scene.get("bark", false)) else "", cap, entry.get("text", "")])
	for scene_id: String in _scenes.keys():
		problems.append_array(_validate_chain(scene_id, _scenes[scene_id]))
	problems.append_array(outcomes.validate(has_scene))
	for chapter_id: StringName in _respawn_scenes:
		problems.append_array(StoryReactions.validate_respawns(String(chapter_id), _respawn_scenes[chapter_id], has_scene))
	for chapter_id: StringName in _death_scenes:
		problems.append_array(StoryReactions.validate_death_scenes(String(chapter_id), _death_scenes[chapter_id], has_scene, _scene_set_flags))
	for chapter_id: Variant in _death_sequences:
		problems.append_array(validate_death_sequences(str(chapter_id), _death_sequences[chapter_id]))
	if not _death_notes.is_empty():
		problems.append_array(StoryReactions.validate_notes("（全部）", _death_notes))
	for issue in StoryLint.errors_of(lint()):
		problems.append(StoryLint.format(issue))
	return problems


## 分派路線、選項接續（target）與條件（when）都要指向存在的場景、格式正確。
func _validate_targets(scene_id: String, scene: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if str(scene.get("mode", "")) == String(MODE_DISPATCH):
		var routes: Variant = scene.get("routes", [])
		if not routes is Array or (routes as Array).is_empty():
			problems.append("分派場景 %s 需要非空的 routes" % scene_id)
			return problems
		for i in (routes as Array).size():
			var route: Variant = routes[i]
			var target := str((route as Dictionary).get("target", "")) if route is Dictionary else ""
			if not _scenes.has(target) or str((_scenes[target] as Dictionary).get("mode", "")) == String(MODE_DISPATCH):
				problems.append("分派場景 %s 的 routes[%d] 指向不存在或另一個分派場景：%s" % [scene_id, i, target])
			elif not StoryConditionTree.validate((route as Dictionary).get("when", {}))["valid"]:
				problems.append("分派場景 %s 的 routes[%d] 條件無效" % [scene_id, i])
		return problems
	for entry in StoryRules.entries(scene.get("steps", [])):
		if entry.has("target") and not _scenes.has(str(entry["target"])):
			problems.append("場景 %s 的選項 %s 接續不存在的場景：%s" % [scene_id, entry.get("id", ""), entry["target"]])
		if entry.has("when") and not StoryConditionTree.validate(entry["when"])["valid"]:
			problems.append("場景 %s 的選項或分支 %s 條件無效：%s" % [scene_id, entry.get("id", ""), StoryConditionTree.validate(entry["when"])["error"]])
	return problems


## 接續場景（then）：只能接在過場／動畫過場之後，目標必須存在，且不能形成迴圈。
func _validate_chain(scene_id: String, scene: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(scene) != TYPE_DICTIONARY or not (scene as Dictionary).has("then"):
		return problems
	var mode := str((scene as Dictionary).get("mode", "radio"))
	var family := _chain_family(mode)
	var first := str((scene as Dictionary)["then"])
	if family == "":
		problems.append("場景 %s（%s）不能設定 then" % [scene_id, mode])
		return problems
	if family == "passive" and _scenes.has(first) and _chain_family(str((_scenes[first] as Dictionary).get("mode", "radio"))) != "passive":
		problems.append("場景 %s（%s）不能設定 then 接到「%s」：通訊與氣泡只能接通訊或氣泡" % [scene_id, mode, first])
		return problems
	var seen: Dictionary = {scene_id: true}
	var next := first
	while next != "":
		if not _scenes.has(next):
			problems.append("場景 %s 的接續場景「%s」不存在" % [scene_id, next])
			break
		if seen.has(next):
			problems.append("場景 %s 的接續形成迴圈（%s）" % [scene_id, next])
			break
		var next_mode := str((_scenes[next] as Dictionary).get("mode", "radio"))
		if _chain_family(next_mode) != family:
			problems.append("場景 %s 的接續場景「%s」是 %s，%s" % [scene_id, next, next_mode, "只能接過場、動畫過場或對話" if family == "presentation" else "只能接通訊或氣泡"])
		seen[next] = true
		next = str((_scenes[next] as Dictionary).get("then", ""))
	return problems


## 接續只在同一類演出之間：過場／動畫過場／對話接成同一段鎖操作的演出；通訊／氣泡各自排隊、不鎖操作。
static func _chain_family(mode: String) -> String:
	if mode in [String(MODE_CINEMATIC), String(MODE_ANIMATED), String(MODE_DIALOGUE)]:
		return "presentation"
	if mode in [String(MODE_RADIO), String(MODE_BUBBLES)]:
		return "passive"
	return ""


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
		var text_lines := _scene_text_lines(_scenes[scene_id])
		for line: Dictionary in text_lines:
			line["mode"] = str(_scenes[scene_id].get("mode", "text"))
			line["bark"] = bool(_scenes[scene_id].get("bark", false))
		units.append({"id": scene_id, "lines": text_lines})
		for variant in StoryReactions.variants_of(_scenes[scene_id]):
			units.append({"id": "%s（死亡 %d 次起）" % [scene_id, StoryReactions.threshold(variant)], "lines": variant["lines"]})
	var card: Array = []
	var info: Dictionary = _chapters.get(chapter_id, {})
	for key in ["title", "subtitle", "end_title", "teaser"]:
		if info.has(key):
			card.append({"speaker": "", "text": str(info[key]), "kind": "label"})
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
		for step: Variant in StoryRules.entries(steps):
			if typeof(step) != TYPE_DICTIONARY:
				continue
			match str(step.get("do", "")):
				"choice":
					for option: Variant in step.get("options", []):
						if option is Dictionary:
							result.append({"speaker": "rin", "text": str(option.get("text", ""))})
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
		for line: Variant in lines:
			result.append(line.duplicate() if line is Dictionary else line)
	return result


func _line_limit(mode: String, scene: Dictionary = {}) -> int:
	match mode:
		String(MODE_BUBBLES):
			return MAX_BARK_LINES if bool(scene.get("bark", false)) else MAX_BUBBLE_LINES
		String(MODE_CINEMATIC):
			return MAX_CINEMATIC_LINES
		String(MODE_DIALOGUE):
			return MAX_DIALOGUE_LINES
	return MAX_RADIO_LINES


func has_scene(id: StringName) -> bool:
	return _scenes.has(String(id))


func scene_ids() -> Array:
	return _scenes.keys()


## 劇情資料的唯讀檢視（連續性檢查用，見 ContinuityAudit）：場景表、各章節的重生場景表與死亡場景表。不要修改回傳的內容。
func audit_data() -> Dictionary:
	return {"scenes": _scenes, "respawn": _respawn_scenes, "death": _death_scenes}


## 場景的台詞。分派入口回傳所有路線段落的台詞（整條人物線完整走一遍的份量，節奏估計用）；動畫段落取其中的 say。
func scene_lines(id: StringName) -> Array:
	var scene: Dictionary = _scenes.get(String(id), {})
	if str(scene.get("mode", "")) != String(MODE_DISPATCH):
		return scene.get("lines", [])
	var result: Array = []
	for route: Variant in scene.get("routes", []):
		var target: Dictionary = _scenes.get(str((route as Dictionary).get("target", "")) if route is Dictionary else "", {})
		if target.has("lines"):
			result.append_array(target["lines"])
		else:
			for step in StoryRules.entries(target.get("steps", [])):
				if step.get("do") == "say":
					result.append(step)
	return result


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


## 這個章節在這次死亡（死因 cause）後、重生前要播的特殊過場（例如第一次死亡的診間）；沒有符合的回傳空字典。
## 條件、旗標與演出選項的寫法見 StoryReactions。
func death_scene_entry(chapter: StringName, cause: StringName, deaths := -1) -> Dictionary:
	return StoryReactions.pick_death_scene(_death_scenes.get(chapter, []), GameState.deaths if deaths < 0 else deaths, cause, GameState.has_flag)


## 場景結束時會寫入的旗標清單（資料檢查用）。
func _scene_set_flags(id: StringName) -> Array:
	var scene: Variant = _scenes.get(String(id), {})
	var flags: Variant = (scene as Dictionary).get("set_flags", []) if typeof(scene) == TYPE_DICTIONARY else []
	var result: Array = []
	if typeof(flags) == TYPE_ARRAY:
		for flag: Variant in flags:
			result.append(str(flag))
	if typeof(scene) == TYPE_DICTIONARY:
		for op in StoryOutcomes.operations(scene):
			var value: Variant = op.get("value", true)
			if str(op.get("kind", "")) == "flag" and value is bool and value:
				result.append(str(op.get("id", "")))
	return result


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
	reset_active_presentation(&"new_run")
	_seen.clear()
	_completed.clear()
	_cinematic_queue.clear()


func is_cinematic_active() -> bool:
	return _current_cinematic != &""


## 可保存的入隊來源，不包含畫幅位置、Node、token 或 Tween。
static func presentation_context(raw: Dictionary) -> Dictionary:
	var source := str(raw.get("framing_source", ""))
	if source not in ["person", "object", "entry"]:
		return {}
	var result := {"framing_source": source, "source_id": str(raw.get("source_id", ""))}
	var index: Variant = raw.get("talk_index")
	if source in ["person", "object"] and raw.has("talk_index") and not (typeof(index) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(index)) and float(index) == floorf(float(index)) and index >= 0 and index < 256):
		return {}
	if source in ["person", "object"] and typeof(index) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(index)) and float(index) == floorf(float(index)) and index >= 0 and index < 256:
		result["talk_index"] = int(index)
	return result


func current_presentation_context() -> Dictionary:
	return _presentation_context.duplicate(true)


## runtime 關聯用，不能存檔；讀檔重新入隊會得到新handle。
func current_presentation_request() -> int:
	return _current_request


func finished_presentation_request() -> int:
	return _finished_request


## 續玩NPC後續segment只接受原talk的then鏈，不將任意同來源scene當成獎勵入口。
func is_chained_scene(origin: StringName, segment: StringName) -> bool:
	var visited: Dictionary[StringName, bool] = {}
	for i in 64:
		if origin == segment:
			return has_scene(origin)
		if not has_scene(origin) or visited.has(origin):
			return false
		visited[origin] = true
		origin = StringName(str((_scenes[String(origin)] as Dictionary).get("then", "")))
	return false


## 節奏估計用（PacingEstimate.along_path）：場景的台詞行數、實際模式與宣告的電影秒數。
func pacing_info(id: StringName) -> Dictionary:
	var scene: Dictionary = _scenes.get(String(id), {})
	return {"lines": scene_lines(id).size(), "mode": scene_mode(id), "budget": float(scene.get("budget", 0.0))}


func scene_mode(id: StringName) -> StringName:
	var mode := StringName(str((_scenes.get(String(id), {}) as Dictionary).get("mode", "radio")))
	if mode == MODE_DISPATCH:
		var target := resolve_dispatch(id)
		return scene_mode(target) if target != &"" else MODE_DISPATCH
	return mode


## 對外 scene_started 的 dialogue→cinematic 別名是存檔契約；資格判斷必須讀實際資料模式。
func uses_cinematic_framing(id: StringName, context: Dictionary = {}) -> bool:
	var mode := scene_mode(id)
	if mode == MODE_DIALOGUE:
		return str(context.get("framing_source", "")) == "person"
	if mode == MODE_CINEMATIC:
		return true
	return mode == MODE_ANIMATED and not bool((_scenes.get(String(id), {}) as Dictionary).get("overlay", false))


## 換區、死亡、新局或讀檔時中止演出。不當作看完，不套用跳過預設選項或完成旗標。
func reset_active_presentation(reason: StringName = &"leave") -> void:
	if _resetting_presentation:
		return
	_resetting_presentation = true
	_presentation_generation += 1
	var interrupted := _current_cinematic
	var interrupted_request := _current_request
	if interrupted != &"":
		presentation_cancelled.emit(interrupted, current_presentation_context(), reason, interrupted_request)
	_current_cinematic = &""
	_current_request = 0
	_presentation_context = {}
	if is_instance_valid(_player):
		_player.cancel()
		_player = null
	if is_instance_valid(_layer):
		_layer.cancel_cinematic()
	if is_instance_valid(framing):
		framing.reset()
	_framing_token = 0
	var pending := _cinematic_queue
	_cinematic_queue = []
	_pending_transfers.clear()
	_pending_next.clear()
	outcomes.context_facts.clear()
	_context_request = 0
	if interrupted != &"":
		if not _completed.has(interrupted):
			_seen.erase(interrupted)
		_complete_request(interrupted_request, false)
	for queued in pending:
		if not _completed.has(queued.id):
			_seen.erase(queued.id)
		_complete_request(queued.request, false)
	for id: StringName in _passive_requests:
		if not _completed.has(id):
			_seen.erase(id)
		var requests: Array = _passive_requests[id]
		for request in requests:
			_complete_request(request, false)
	_passive_requests.clear()
	if is_instance_valid(_layer):
		_layer.cancel_radio()
	_resetting_presentation = false


## 播放場景。once = true 時同一輪只播一次。回傳是否有開始（或排入佇列）。
## 登記或清除氣泡宿主（Level 進入關卡時登記自己的 MapBubbles；宿主離開場景樹時自動清除）。
func set_bubble_host(host: MapBubbles) -> void:
	if is_instance_valid(_bubble_host) and _bubble_host.scene_finished.is_connected(_on_bubbles_finished):
		_bubble_host.scene_finished.disconnect(_on_bubbles_finished)
	_bubble_host = host
	if host != null:
		host.scene_finished.connect(_on_bubbles_finished)
		host.tree_exiting.connect(func() -> void:
			if _bubble_host == host:
				_bubble_host = null
				reset_active_presentation(), CONNECT_ONE_SHOT)


func _on_bubbles_finished(id: StringName) -> void:
	_on_passive_finished(id)


func _on_passive_finished(id: StringName, expected_request := 0) -> void:
	var requests: Array = _passive_requests.get(id, [])
	if requests.is_empty():
		return  # 已取消或舊宿主的延遲回呼，不再寫完成旗標。
	if expected_request != 0 and int(requests[0]) != expected_request:
		return  # auto-skip 舊請求的延遲回呼不能完成取消後新入隊的同名場景。
	var request := int(requests.pop_front())
	if requests.is_empty():
		_passive_requests.erase(id)
	var applied := _apply_scene_results(id)
	_finished_request = request
	scene_finished.emit(id)
	_finished_request = 0
	_complete_request(request, true)
	var next := StringName(str(applied["failure_scene"])) if not applied["ok"] else StringName(str((_scenes.get(String(id), {}) as Dictionary).get("then", "")))
	if next != &"" and has_scene(next):
		play(next, applied["ok"])


func play(id: StringName, once := true, context: Dictionary = {}) -> bool:
	return _enqueue_request(id, once, context) != 0


func _enqueue_request(id: StringName, once: bool, context: Dictionary, waiting := false) -> int:
	if id == &"" or not has_scene(id):
		if id != &"":
			push_warning("[Story] 找不到劇情場景：%s" % id)
		return 0
	if str((_scenes[String(id)] as Dictionary).get("mode", "")) == String(MODE_DISPATCH):
		var target := resolve_dispatch(id)
		return 0 if target == &"" else _enqueue_request(target, false, context, waiting)
	if once and _seen.has(id):
		return 0
	if not scene_available(id):
		return 0
	if not can_transfer_for(id):
		push_warning("[Story] 場景 %s 要交出的原件不在手上，未開始播放" % id)
		return 0
	_request_serial += 1
	var request := _request_serial
	if waiting:
		_waiters[request] = true
	_seen[id] = true
	var scene: Dictionary = _scenes[String(id)]
	var mode := StringName(str(scene.get("mode", "radio")))
	if mode == MODE_CINEMATIC or mode == MODE_ANIMATED or mode == MODE_DIALOGUE:
		if is_cinematic_active():
			_cinematic_queue.append({"id": id, "context": presentation_context(context), "request": request})
		else:
			_start_cinematic(id, context, request)
	else:
		if not _passive_requests.has(id):
			_passive_requests[id] = []
		_passive_requests[id].append(request)
		if mode != MODE_BUBBLES or not _play_bubbles(id, request):
			scene_started.emit(id, MODE_RADIO)
			_layer.enqueue_radio(id, resolved_lines(id))
	return request


## 氣泡場景：有宿主、講者全都在地圖上才用氣泡；測試的 auto_skip 立即結束。回傳 false 代表改用通訊。
func _play_bubbles(id: StringName, request: int) -> bool:
	var lines := resolved_lines(id)
	if auto_skip:
		scene_started.emit(id, MODE_BUBBLES)
		_on_passive_finished.call_deferred(id, request)
		return true
	if not is_instance_valid(_bubble_host) or not _bubble_host.can_show_all(lines):
		return false
	scene_started.emit(id, MODE_BUBBLES)
	_bubble_host.show_lines(id, lines)
	return true


## 播放並等待該場景結束，包含接在後面的 then 場景（場景不存在，或 once 為 true 且已看過時立即返回）。
func play_and_wait(id: StringName, once := true, context: Dictionary = {}) -> bool:
	var request := _enqueue_request(id, once, context, true)
	if request == 0:
		return false
	while not _request_results.has(request):
		await request_settled
	var completed := _request_results[request]
	_request_results.erase(request)
	_waiters.erase(request)
	return completed


func _complete_request(request: int, completed: bool) -> void:
	if request == 0:
		return
	if request == _context_request:
		outcomes.context_facts.clear()
		_context_request = 0
	if _waiters.has(request):
		_request_results[request] = completed
	request_settled.emit(request, completed)


## 跳過目前的過場（與按 Esc 相同）。
func skip_cinematic() -> void:
	if not is_cinematic_active():
		return
	if is_instance_valid(_player) and _player.is_running():
		_player.skip()
	else:
		_layer.finish_cinematic()


func _start_cinematic(id: StringName, context: Dictionary = {}, request := 0) -> void:
	_presentation_generation += 1
	_current_cinematic = id
	_current_request = request
	_presentation_context = presentation_context(context)
	var scene: Dictionary = _scenes.get(String(id), {})
	var animated := str(scene.get("mode", "")) == String(MODE_ANIMATED)
	var facts: Variant = scene.get("context_facts", [])
	if facts is Array and not (facts as Array).is_empty():
		for key: Variant in facts:
			outcomes.context_facts[str(key)] = true
		_context_request = request
	scene_started.emit(id, MODE_ANIMATED if animated else MODE_CINEMATIC)
	if auto_skip or Settings.get_skip_cutscenes():
		apply_default_choices(scene)
		_finish_auto_skip.call_deferred(id, _presentation_generation)
		return
	if not animated and uses_cinematic_framing(id, _presentation_context):
		_framing_token = framing.acquire(self)
	elif not uses_cinematic_framing(id, _presentation_context):
		framing.clear_preview()
	if animated:
		_player = CutscenePlayer.new()
		add_child(_player)
		_player.finished.connect(_on_cinematic_finished)
		_player.play(id, scene)
		return
	_layer.start_cinematic(id, resolved_lines(id))


func _finish_auto_skip(id: StringName, generation: int) -> void:
	if generation == _presentation_generation:
		_on_cinematic_finished(id)


func _on_cinematic_finished(id: StringName) -> void:
	if _current_cinematic != id:
		return
	_current_cinematic = &""
	var completed_request := _current_request
	_current_request = 0
	framing.release(_framing_token)
	_framing_token = 0
	var applied := _apply_scene_results(id)
	var chosen: StringName = _pending_next.get(id, &"")
	_pending_next.erase(id)
	var chained := false
	if not applied["ok"]:
		chained = _queue_dynamic_scene(StringName(str(applied["failure_scene"])), completed_request)
	elif chosen != &"":
		chained = _queue_dynamic_scene(chosen, completed_request)
	else:
		chained = _queue_chained_scene(id, completed_request)
	_presentation_context = {}
	_finished_request = completed_request
	scene_finished.emit(id)
	_finished_request = 0
	if not chained:
		_complete_request(completed_request, true)
	if not _cinematic_queue.is_empty():
		var queued: Dictionary = _cinematic_queue.pop_front()
		_start_cinematic(queued.id, queued.context, queued.request)


## 選項或交易失敗指定的接續場景：不論是否看過都接著播（可回到上一個選擇），條件不成立時不接。
func _queue_dynamic_scene(next: StringName, request: int) -> bool:
	if next == &"" or not has_scene(next):
		return false
	var target := resolve_dispatch(next)
	if target == &"" or not scene_available(target) or not can_transfer_for(target):
		return false
	_seen[target] = true
	_cinematic_queue.push_front({"id": target, "context": _presentation_context.duplicate(true), "request": request})
	return true


## 場景設定了 then 時，結束後立刻接著播（排在佇列最前面）；玩家按 Esc 略過時整串都略過，已看過的場景不重播。
func _queue_chained_scene(id: StringName, request: int) -> bool:
	var next := StringName(str((_scenes.get(String(id), {}) as Dictionary).get("then", "")))
	if next == &"" or not has_scene(next) or _seen.has(next) or not scene_available(next):
		return false
	if is_instance_valid(_player) and _player.user_skipped:
		return false
	_seen[next] = true
	_cinematic_queue.push_front({"id": next, "context": _presentation_context.duplicate(true), "request": request})
	return true


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
			"speaker": str(entry.get("speaker", "")),
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


func progress_snapshot() -> Array:
	return _completed.keys()


func restore_progress(raw: Variant, where := "story/seen", cancel_presentation := true) -> void:
	if cancel_presentation:
		reset_active_presentation(&"load")
	_seen.clear()
	_completed.clear()
	if not raw is Array:
		push_warning("[Story] %s 不是清單，退回空觀看紀錄" % where)
		return
	for entry: Variant in raw:
		var id := StringName(str(entry))
		if has_scene(id):
			_seen[id] = true
			_completed[id] = true
		else:
			push_warning("[Story] %s/%s 場景不存在，已略過" % [where, id])


func apply_choice(option: Dictionary) -> void:
	var flags: Variant = option.get("set_flags", {})
	for flag: Variant in StoryRules.flag_names(flags):
		GameState.set_flag(StringName(str(flag)), flags[flag] if flags is Dictionary else true)
	var target := StringName(str(option.get("target", "")))
	if target != &"" and _current_cinematic != &"":
		_pending_next[_current_cinematic] = target
	var transfers := StoryRules.transfer_ids(option)
	if transfers.is_empty():
		return
	if _current_cinematic == &"":
		push_warning("[Story] 選項 %s 要交出原件，但沒有進行中的場景可以承接，已忽略" % option.get("id", ""))
		return
	var queued: Array = _pending_transfers.get(_current_cinematic, [])
	queued.append_array(transfers)
	_pending_transfers[_current_cinematic] = queued


## Skip uses explicit defaults, so gates cannot depend on an unanswered question.
func apply_default_choices(scene: Dictionary) -> void:
	_resolve_skipped_steps(scene.get("steps", []))


func _resolve_skipped_steps(raw: Variant) -> void:
	if not raw is Array:
		return
	for step: Variant in raw:
		if not step is Dictionary:
			continue
		if step.get("do") == "choice":
			var option := StoryRules.default_option(step, StoryRules.options(step, GameState.has_flag, StoryItems.owns))
			apply_choice(option)
			_resolve_skipped_steps(option.get("steps", []))
		elif step.get("do") == "branch":
			_resolve_skipped_steps(step.get("steps", []) if StoryRules.eligible(step, GameState.has_flag, StoryItems.owns) else step.get("else_steps", []))


func death_sequence(chapter: StringName, count := -1) -> Dictionary:
	var result := {}
	var threshold := -1
	var raw: Variant = _death_sequences.get(chapter, [])
	if not raw is Array:
		return result
	var actual := GameState.deaths if count < 0 else count
	for entry: Variant in raw:
		if not entry is Dictionary:
			continue
		var minimum_raw: Variant = entry.get("min_deaths", 1)
		if not (minimum_raw is int or minimum_raw is float):
			continue
		var minimum := int(minimum_raw)
		if minimum <= actual and minimum >= threshold:
			result = entry
			threshold = minimum
	return result


func validate_death_sequences(chapter: String, raw: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if not raw is Array:
		return PackedStringArray(["章節 %s 的 death_sequences 必須是清單" % chapter])
	for i in raw.size():
		var entry: Variant = raw[i]
		var where := "章節 %s/death_sequences/%d" % [chapter, i]
		if not entry is Dictionary or not entry.get("steps") is Array:
			problems.append("%s 必須是有 steps 清單的物件" % where)
			continue
		var steps: Array = entry.steps
		if steps.is_empty() or steps.size() > 8:
			problems.append("%s/steps 必須有 1 到 8 步" % where)
		for j in steps.size():
			var step: Variant = steps[j]
			if not step is Dictionary:
				problems.append("%s/steps/%d 不是物件" % [where, j])
				continue
			var kind := str(step.get("kind", "line"))
			if not kind in ["line", "status", "card"]:
				problems.append("%s/steps/%d 未知種類 %s" % [where, j, kind])
			if kind != "card" and str(step.get("text", "")).strip_edges().is_empty():
				problems.append("%s/steps/%d 缺少文字" % [where, j])
			if kind == "line" and not _speakers.has(str(step.get("speaker", ""))):
				problems.append("%s/steps/%d 講者未定義" % [where, j])
			var seconds: Variant = step.get("time", 0.6)
			if not (seconds is int or seconds is float) or float(seconds) < 0.0 or float(seconds) > 3.0:
				problems.append("%s/steps/%d/time 必須在 0 到 3 秒" % [where, j])
	return problems
