extends Node
## 從實際故事與關卡輸出接線診斷；缺相依資料時以非零狀態結束。


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var maps := QuestMapIndex.new()
	maps.load_chapter(&"ch1_kasa")
	var datas: Dictionary = {}
	var layouts: Dictionary = {}
	var lock_sources: Array[Dictionary] = []
	for path: String in maps.areas:
		datas[path] = maps.areas[path]["data"]
		layouts[path] = maps.areas[path]["layout"]
		for marker: Dictionary in maps.areas[path]["markers"]:
			var resource: Resource = marker.get("resource")
			if resource is PortalData and (resource.is_locked_door() or resource.requires_flag != &""):
				lock_sources.append({"level": path, "id": String(resource.id), "requires_flag": String(resource.requires_flag), "text": resource.locked_text})
			elif resource is MechanismData and resource.kind == MechanismData.Kind.GATE and not resource.is_retired_arena_gate():
				lock_sources.append({"level": path, "id": String(resource.id), "channel": String(resource.channel), "text": resource.hint})
	var story: Dictionary = get_tree().root.get_node("Story").audit_data()
	var table := ContinuityAudit.flag_table(story["scenes"], story["death"], ContinuityAudit.read_text_files())
	var code_flags: Array = []
	for flag: String in table:
		for writer: String in table[flag]["writes"]:
			if writer.contains("set_flag"):
				code_flags.append(flag)
	var model := ContinuityAudit.level_model(datas, layouts, story["scenes"], [], code_flags)
	var reachable := ContinuityAudit.reachability(model, ["res://data/levels/ch1_pawnshop.tres"])
	var issues := catalog.issues.duplicate()
	issues.append_array(catalog.validate_flags(table.keys(), reachable["flags"].keys()))
	if catalog.list_for("ch1_kasa", "main", false, {}).is_empty():
		issues.append("第一章故事來源沒有任務語義；新遊戲沒有可追蹤主線，不能宣稱主線模擬通過。")
	for lock in lock_sources:
		if str(lock["text"]).is_empty():
			issues.append("%s.%s.hint: 缺少遊戲內鎖門說明。" % [lock["level"], lock["id"]])
	issues.append("逐狀態主線模擬、整輪讀檔與序章兩條路線尚未接線；靜態可達性不能代替本票驗收。")
	var report := {"delivery_ready": false, "ordered_simulation_verified": false, "real_area_count": maps.areas.size(), "quest_count": catalog.quests.size(), "reachable_level_count": reachable["levels"].size(), "reachable_flags": reachable["flags"].keys(), "locks_using_existing_game_text": lock_sources, "issues": Array(issues)}
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report, "\t"))
	get_tree().quit(0 if issues.is_empty() else 1)
