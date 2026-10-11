extends Node
## NE-223：主線逐狀態檢查。用真實的故事資料與旗標生產者推進，每次旗標改變後都確認
## 「至少一個進行中的主線任務，而且目標列有一句非空的目標」。只讀任務與旗標，不寫故事資料。
## 用法：godot --path . res://tools/quest_mainline_trace.tscn -- --route=prologue|skip|stay|leave [--out=<絕對路徑資料夾>]
##   prologue／skip：新遊戲從序章開始，依序章關卡的練習旗標正常結束，或用序章的長按跳過旗標離開。
##   stay／leave：在旁邊跑故事組的第一章流程探針（tools/ch1_flow_probe.tscn，原封不動），本工具只旁聽旗標。
## 結束時印出 QUEST_TRACE 開頭的摘要；有任何一刻沒有主線或目標是空的，就以非零狀態結束。

const CHAPTER := "ch1_kasa"
const PROLOGUE_LEVEL := "res://data/levels/ch1_prologue.tres"
const FLOW_PROBE := "res://tools/ch1_flow_probe.tscn"

var _route := "prologue"
var _catalog := QuestCatalog.new()
var _dirty := false
var _states := 0
var _gaps: Array[String] = []
var _objectives: Array[String] = []
var _chapter_done := false
var _reported := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route="):
			_route = arg.trim_prefix("--route=")
	_catalog.load_story_sources()
	if _catalog.list_for(CHAPTER, "main", false, {}).is_empty() and _catalog.list_for(CHAPTER, "main", true, {}).is_empty():
		_finish("故事來源沒有第一章主線任務，無法做逐狀態檢查。")
		return
	GameState.flag_changed.connect(_on_flag_changed)
	match _route:
		"prologue", "skip":
			_run_prologue.call_deferred(_route == "skip")
		"stay", "leave":
			if not ResourceLoader.exists(FLOW_PROBE):
				_finish("找不到第一章流程探針 %s；這條路線要等故事組的探針合入。" % FLOW_PROBE)
				return
			GameState.start_new_run(GameState.difficulties[1])
			_evaluate("新遊戲")
			add_child((load(FLOW_PROBE) as PackedScene).instantiate())
		_:
			_finish("未知的路線：%s" % _route)


## 序章：新遊戲後先檢查一次，再依序章關卡記錄的旗標推進（正常結束：各練習完成；跳過：關卡的 skip_flags）。
func _run_prologue(skip: bool) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	if Story.has_method(&"reset_progress"):
		Story.reset_progress()
	_evaluate("新遊戲")
	var data := load(PROLOGUE_LEVEL) as LevelData
	if data == null:
		_finish("找不到序章關卡 %s。" % PROLOGUE_LEVEL)
		return
	var flags: Array = []
	if skip:
		flags = Array(data.get(&"skip_flags")) if data.get(&"skip_flags") != null else []
	else:
		# 序章任務的步驟本身就是序章的練習項目，依任務資料的順序完成。
		var prologue := _first_main()
		for step: Dictionary in prologue.get("steps", []):
			flags.append(_producer_for(str(step["complete_flag"])))
	for flag in flags:
		await get_tree().process_frame
		GameState.set_flag(StringName(str(flag)), true, false)
		if Story.get(&"outcomes") != null:
			Story.outcomes.refresh_derived()
		_evaluate("設定 %s" % flag)
	await get_tree().process_frame
	_finish()


## 衍生旗標（例如「序章結束或跳過或吃完晚飯」）不能直接寫，會被重算蓋掉；改寫條件裡列在最前面的那個實際旗標。
func _producer_for(flag: String) -> String:
	var outcomes: Variant = Story.get(&"outcomes")
	if outcomes == null or not (outcomes.derived_flags as Dictionary).has(flag):
		return flag
	var first := _first_condition_flag(outcomes.derived_flags[flag])
	return first if not first.is_empty() else flag


static func _first_condition_flag(tree: Variant) -> String:
	if tree is Dictionary:
		if (tree as Dictionary).has("flag"):
			return str(tree["flag"])
		for key in ["any", "all"]:
			if (tree as Dictionary).has(key):
				for child in tree[key]:
					var found := _first_condition_flag(child)
					if not found.is_empty():
						return found
	return ""


func _first_main() -> Dictionary:
	var mains := _catalog.list_for(CHAPTER, "main", false, GameState.world_flags)
	return mains[0] if not mains.is_empty() else {}


func _on_flag_changed(_flag: StringName, _value: Variant) -> void:
	if not _dirty:
		_dirty = true
		_evaluate_deferred.call_deferred(String(_flag))


func _evaluate_deferred(flag: String) -> void:
	_dirty = false
	_evaluate("旗標 %s" % flag)


## 一個狀態：有進行中的主線，而且追蹤目標（沒有釘選時跟著主線）的目前步驟是一句非空的話。
## 第一章主線全部完成時記為章末，不算缺口。
func _evaluate(moment: String) -> void:
	_states += 1
	var flags := GameState.world_flags
	var active := _catalog.list_for(CHAPTER, "main", false, flags)
	var finished := _catalog.list_for(CHAPTER, "main", true, flags)
	if active.is_empty() and not finished.is_empty():
		_chapter_done = true
		return
	var target := QuestMapState.for_run().target(_catalog, CHAPTER, flags)
	var step := QuestCatalog.current_step(target, flags)
	var title := str(step.get("title", "")).strip_edges()
	if active.is_empty() or title.is_empty():
		_gaps.append("%s：進行中主線 %d 項，目標「%s」" % [moment, active.size(), title])
		return
	if _objectives.is_empty() or _objectives.back() != title:
		_objectives.append(title)


func _exit_tree() -> void:
	_finish()


func _finish(error := "") -> void:
	if _reported:
		return
	_reported = true
	if not error.is_empty():
		_gaps.append(error)
	print("QUEST_TRACE route=%s states=%d gaps=%d chapter_done=%s objectives=%d" % [_route, _states, _gaps.size(), _chapter_done, _objectives.size()])
	for title in _objectives:
		print("QUEST_TRACE objective: %s" % title)
	for gap in _gaps:
		print("QUEST_TRACE gap: %s" % gap)
	if is_inside_tree() and (_route == "prologue" or _route == "skip" or not error.is_empty()):
		get_tree().quit(0 if _gaps.is_empty() else 1)
