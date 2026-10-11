extends Node
## NE-223：任務與地圖的靜態接線診斷。用真實的故事與關卡資料檢查一章：
## - 每個任務用到的旗標都有人寫，而且從章節入口照出入口、劇情與衍生旗標推得到；
## - 每道鎖門、閘門都有遊戲內說明。
## 只讀故事與關卡資料，不寫。逐狀態的主線模擬由 tools/quest_mainline_trace.tscn 負責（序章、跳過、留下、離開）。
## 用法：godot --headless --path . res://tools/quest_map_audit.tscn -- [--chapter=ch1_kasa] [--start=res://data/levels/x.tres] [--out=<絕對路徑>]
##   --start 可給多個（逗號分隔）；不給時取上一章 next_level 進入本章的區域，沒有就取本章沒有其他區域通往的區域。
## 有問題時以非零狀態結束。

const DEFAULT_CHAPTER := "ch1_kasa"
## 衍生旗標的固定點迴圈上限：每輪至少多拿到一個旗標才繼續，正常兩三輪就收斂。
const MAX_ROUNDS := 16
const TRACE_TOOL := "res://tools/quest_mainline_trace.tscn"
const LEVEL_DIR := "res://data/levels"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var chapter := DEFAULT_CHAPTER
	var starts: Array = []
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chapter="):
			chapter = arg.trim_prefix("--chapter=")
		elif arg.begins_with("--start="):
			starts = Array(arg.trim_prefix("--start=").split(",", false))
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var report := audit(chapter, starts)
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			push_error("[QuestMapAudit] 無法寫入 %s（%s）" % [out, error_string(FileAccess.get_open_error())])
		else:
			file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report, "\t"))
	get_tree().quit(0 if (report["issues"] as Array).is_empty() else 1)


func audit(chapter: String, starts: Array) -> Dictionary:
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var maps := QuestMapIndex.new()
	maps.load_chapter(StringName(chapter))
	var issues: Array = Array(catalog.issues)
	if maps.areas.is_empty():
		issues.append("章節 %s 沒有任何區域（res://data/levels 裡 chapter = %s 的 LevelData）。" % [chapter, chapter])
		return {"chapter": chapter, "delivery_ready": false, "issues": issues}
	var datas: Dictionary = {}
	var layouts: Dictionary = {}
	for path: String in maps.areas:
		datas[path] = maps.areas[path]["data"]
		layouts[path] = maps.areas[path]["layout"]
	if starts.is_empty():
		starts = chapter_handoff_levels(datas.keys())
	if starts.is_empty():
		starts = entry_levels(datas, layouts)
	var story: Dictionary = get_tree().root.get_node("Story").audit_data()
	var table := ContinuityAudit.flag_table(story["scenes"], story["death"], ContinuityAudit.read_text_files())
	var code_flags: Array = []
	for flag: String in table:
		for writer: String in table[flag]["writes"]:
			if writer.contains("set_flag"):
				code_flags.append(flag)
	var reachable := _reach_with_derived(datas, layouts, story["scenes"], code_flags, _event_scenes(maps), starts)
	issues.append_array(catalog.validate_flags(table.keys(), reachable["flags"].keys(), chapter))
	if catalog.list_for(chapter, "main", false, {}).is_empty() and catalog.list_for(chapter, "main", true, {}).is_empty():
		issues.append("%s 的故事來源沒有主線任務；新遊戲沒有可追蹤的目標。" % chapter)
	var locks := lock_sources(maps)
	for lock: Dictionary in locks:
		if str(lock["text"]).is_empty():
			issues.append("%s.%s: 鎖門或閘門缺少遊戲內說明。" % [lock["level"], lock["id"]])
	for path: String in datas:
		if not reachable["levels"].has(path):
			issues.append("%s: 從章節入口走不到這一區。" % path)
	return {
		"chapter": chapter,
		"delivery_ready": issues.is_empty(),
		"start_levels": starts,
		"area_count": maps.areas.size(),
		"quest_count": catalog.quests.filter(func(quest: Dictionary) -> bool: return quest["chapter"] == chapter).size(),
		"reachable_level_count": reachable["levels"].size(),
		"ordered_simulation": "逐狀態主線請跑 %s（--route=prologue|skip|stay|leave）。" % TRACE_TOOL,
		"locks_using_existing_game_text": locks,
		"issues": issues,
	}


## 章節入口（優先）：別章關卡的 next_level 指向本章的區域，也就是玩家從上一章真正進來的地方。
## 只讀關卡資料；讀不到的檔案記錄位置後略過。
static func chapter_handoff_levels(chapter_paths: Array) -> Array:
	var inside: Dictionary = {}
	for path: String in chapter_paths:
		inside[path] = true
	var roots: Array = []
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		push_error("[QuestMapAudit] 無法開啟 %s（%s），改用本章結構判斷入口。" % [LEVEL_DIR, error_string(DirAccess.get_open_error())])
		return roots
	for file in dir.get_files():
		var path := LEVEL_DIR.path_join(file.trim_suffix(".remap"))
		if not path.ends_with(".tres") or inside.has(path):
			continue
		var data := ResourceLoader.load(path) as LevelData
		if data == null:
			push_warning("[QuestMapAudit] %s 不是可讀的 LevelData，略過。" % path)
			continue
		if inside.has(data.next_level) and not roots.has(data.next_level):
			roots.append(data.next_level)
	roots.sort()
	return roots


## 章節入口：本章裡沒有其他區域（出入口或 next_level）通往的區域；全都有人通往時退回全部區域。
static func entry_levels(datas: Dictionary, layouts: Dictionary) -> Array:
	var targeted: Dictionary = {}
	for path: String in datas:
		var data := datas[path] as LevelData
		if not data.next_level.is_empty():
			targeted[data.next_level] = true
		for spawn in (layouts[path] as LevelLayout).spawns:
			var portal := spawn["resource"] as PortalData
			if portal != null and not portal.target_level.is_empty() and portal.target_level != path:
				targeted[portal.target_level] = true
	var roots: Array = datas.keys().filter(func(path: String) -> bool: return not targeted.has(path))
	roots.sort()
	return roots if not roots.is_empty() else datas.keys()


## 可達性加上衍生旗標：衍生旗標的條件在目前拿得到的旗標下有可能成立，就當作拿得到，再推一次，直到不再增加。
func _reach_with_derived(datas: Dictionary, layouts: Dictionary, scenes: Dictionary, code_flags: Array, always: Array, starts: Array) -> Dictionary:
	var outcomes: Variant = get_tree().root.get_node("Story").get(&"outcomes")
	var derived: Dictionary = outcomes.derived_flags if outcomes != null else {}
	var known := code_flags.duplicate()
	var model := ContinuityAudit.level_model(datas, layouts, scenes, always, known)
	var reachable := ContinuityAudit.reachability(model, starts)
	for round in MAX_ROUNDS:
		var added := false
		for flag: String in derived:
			if not reachable["flags"].has(flag) and may_hold(derived[flag], reachable["flags"]):
				known.append(flag)
				added = true
		if not added:
			break
		model["code_flags"] = known
		reachable = ContinuityAudit.reachability(model, starts)
	return reachable


## 世界事件第一次發生時播放的場景（章節的 event_scenes）：復原點事件要本章真的有復原點才算播得出。
func _event_scenes(maps: QuestMapIndex) -> Array:
	var outcomes: Variant = get_tree().root.get_node("Story").get(&"outcomes")
	if outcomes == null or outcomes.get(&"event_scenes") == null:
		return []
	var result: Array = []
	for entry: Dictionary in outcomes.event_scenes:
		if str(entry.get("event", "")) != "checkpoint" or not maps.checkpoint_keys.is_empty():
			result.append(str(entry.get("scene", "")))
	return result


## 條件樹「有沒有可能成立」：旗標要拿得到；物品、收據與帳的狀態不在旗標圖裡，視為可能；not 也視為可能。
static func may_hold(condition: Variant, flags: Dictionary) -> bool:
	if not condition is Dictionary:
		return false
	var raw: Dictionary = condition
	if raw.has("all") or raw.has("any"):
		var all := raw.has("all")
		var children: Variant = raw["all"] if all else raw["any"]
		if not children is Array or (children as Array).is_empty():
			return false
		for child: Variant in children:
			if may_hold(child, flags) != all:
				return not all
		return all
	if raw.has("flag"):
		# 要求旗標「沒設定」的條件（equals 為 false、空字串、0 或 unset）在新遊戲就成立。
		return flags.has(str(raw["flag"])) or raw.get("equals", true) in [false, "", 0, 0.0, "unset"]
	return true


static func lock_sources(maps: QuestMapIndex) -> Array:
	var result: Array = []
	for path: String in maps.areas:
		for marker: Dictionary in maps.areas[path]["markers"]:
			var resource: Resource = marker.get("resource")
			if resource is PortalData and (resource.is_locked_door() or resource.requires_flag != &""):
				result.append({"level": path, "id": String(resource.id), "requires_flag": String(resource.requires_flag), "text": resource.locked_text})
			elif resource is MechanismData and resource.kind == MechanismData.Kind.GATE and not resource.is_retired_arena_gate():
				result.append({"level": path, "id": String(resource.id), "channel": String(resource.channel), "text": resource.hint})
	return result
