class_name QuestCatalog
extends RefCounted
## 唯讀任務檢視；來源是故事產生器輸出的 quests，絕不自行建立完成旗標。

var quests: Array[Dictionary] = []
var issues := PackedStringArray()


func load_story_sources(paths: Array[String] = Story.CHAPTER_PATHS) -> void:
	quests.clear()
	issues.clear()
	for path in paths:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			issues.append("%s: 無法讀取故事資料。" % path)
			continue
		read_source(json.data, path)


func read_source(source: Dictionary, path: String) -> void:
	var raw: Variant = source.get("quests", [])
	if not raw is Array:
		issues.append("%s.quests: 必須是陣列。" % path)
		return
	for i in raw.size():
		var at := "%s.quests[%d]" % [path, i]
		if not raw[i] is Dictionary:
			issues.append("%s: 必須是物件。" % at)
			continue
		var quest: Dictionary = raw[i].duplicate(true)
		var valid := true
		for key in ["id", "title", "background", "reward", "complete_flag"]:
			if not quest.get(key) is String or str(quest.get(key, "")).is_empty():
				issues.append("%s.%s: 必須是非空文字。" % [at, key])
				valid = false
		if quest.get("title") is String and quest["title"].length() > 16:
			issues.append("%s.title: 標題超過一行的 16 字預算。" % at)
			valid = false
		if not quest.get("kind", "main") in ["main", "side"]:
			issues.append("%s.kind: 必須是 main 或 side。" % at)
			valid = false
		for key in ["requires_flags", "visible_flags"]:
			if not quest.get(key, []) is Array or not (quest.get(key, []) as Array).all(func(f: Variant) -> bool: return f is String and not f.is_empty()):
				issues.append("%s.%s: 必須是旗標名稱陣列。" % [at, key])
				valid = false
		if quest.get("requires_flags", []) is Array and not quest.get("requires_flags", []).is_empty():
			for key in ["blocked_reason", "suggestion"]:
				if not quest.get(key) is String or str(quest.get(key, "")).is_empty():
					issues.append("%s.%s: 缺少阻塞說明。" % [at, key])
					valid = false
		if not quest.get("completion_requires_steps", false) is bool:
			issues.append("%s.completion_requires_steps: 必須是布林值。" % at)
			valid = false
		var steps: Variant = quest.get("steps")
		if not steps is Array or steps.is_empty():
			issues.append("%s.steps: 必須有至少一個步驟。" % at)
			valid = false
		else:
			for j in steps.size():
				var step: Variant = steps[j]
				if not step is Dictionary or not step.get("title") is String or str(step.get("title", "")).is_empty() or not step.get("complete_flag") is String or str(step.get("complete_flag", "")).is_empty():
					issues.append("%s.steps[%d]: 缺少目標或完成旗標。" % [at, j])
					valid = false
				elif step["title"].length() > 28:
					issues.append("%s.steps[%d].title: 目標超過一行的 28 字預算。" % [at, j])
					valid = false
				elif not valid_location(step.get("location")):
					issues.append("%s.steps[%d].location: 找不到真實區域或有效格座標。" % [at, j])
					valid = false
		if quests.any(func(q: Dictionary) -> bool: return q.get("id") == quest.get("id")):
			issues.append("%s.id: 任務編號重複。" % at)
			valid = false
		if valid:
			quest["chapter"] = str(source.get("chapter", {}).get("id", source.get("for_chapter", "")))
			quest["kind"] = quest.get("kind", "main")
			quest["source"] = at
			quests.append(quest)


static func valid_location(raw: Variant) -> bool:
	if not raw is Dictionary or not raw.get("level") is String or not raw.get("cell") is Array:
		return false
	var cell: Array = raw["cell"]
	if cell.size() != 2 or not cell.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and float(n) == floorf(float(n))):
		return false
	if not ResourceLoader.exists(raw["level"]):
		return false
	var data := load(raw["level"]) as LevelData
	if data == null:
		return false
	var layout := LevelBuilder.parse(data)
	return cell[0] >= 0 and cell[1] >= 0 and cell[0] < layout.width and cell[1] < layout.height and layout.cell(int(cell[0]), int(cell[1])) != "#"


func find(id: String) -> Dictionary:
	for quest in quests:
		if quest["id"] == id:
			return quest
	return {}


## 故事接受純量旗標；String 沒有 bool 建構子，使用語言的條件判定。
static func flag_set(flags: Dictionary, name: String) -> bool:
	return true if flags.get(name, false) else false


static func all_flags(names: Array, flags: Dictionary) -> bool:
	return names.all(func(flag: Variant) -> bool: return flag_set(flags, str(flag)))


static func status(quest: Dictionary, flags: Dictionary) -> String:
	if flag_set(flags, str(quest["complete_flag"])) and (not quest.get("completion_requires_steps", false) or current_step(quest, flags).is_empty()):
		return "completed"
	return "active" if all_flags(quest.get("requires_flags", []), flags) else "blocked"


func list_for(chapter: String, kind: String, completed: bool, flags: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest in quests:
		if quest["chapter"] != chapter or (kind != "all" and quest["kind"] != kind):
			continue
		if not all_flags(quest.get("visible_flags", []), flags):
			continue
		if (status(quest, flags) == "completed") == completed:
			result.append(quest)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["kind"] == "main" and b["kind"] != "main")
	return result


static func current_step(quest: Dictionary, flags: Dictionary) -> Dictionary:
	for step: Dictionary in quest.get("steps", []):
		if not flag_set(flags, str(step["complete_flag"])):
			return step
	return {}


## 交付檢查：定義與生產者由 Session 3 提供；沒有資料時回報缺口，不把模擬當成功。
## chapter 不為空時只檢查該章的任務；同一任務重複用到的旗標只報一次。
func validate_flags(known: Array, reachable: Array, chapter := "") -> PackedStringArray:
	var problems := PackedStringArray()
	for quest in quests:
		if not chapter.is_empty() and quest["chapter"] != chapter:
			continue
		var names: Array = [quest["complete_flag"]]
		names.append_array(quest.get("requires_flags", []))
		names.append_array(quest.get("visible_flags", []))
		for step: Dictionary in quest["steps"]:
			names.append(step["complete_flag"])
		var seen: Dictionary = {}
		for name in names:
			if seen.has(name):
				continue
			seen[name] = true
			if not known.has(name) or not reachable.has(name):
				problems.append("%s: 旗標 %s 未定義或不可達。" % [quest["source"], name])
	return problems
