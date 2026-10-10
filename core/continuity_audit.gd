class_name ContinuityAudit
extends RefCounted
## 劇情與流程的連續性檢查（NE-217，見 .claude/skills/continuity-qa）。純靜態、不依賴全域單例，資料由呼叫端傳入，所以可以用假資料測試。
##
## 旗標表：誰寫（場景的 set_flags、程式的 set_flag）、誰讀（出入口的 requires_flag、死亡場景的 unless_flag／requires_flag、程式的 has_flag）。
##   錯誤：只讀不寫（永遠不會成立）、拼字相近（多半是打錯字）。
##   警告：只寫不讀（可能是留給之後章節的伏筆，但要有人知道）。
## 孤兒場景：沒有任何地方引用（關卡、NPC、道具、then、重生與死亡場景表、程式）的場景。列為警告。

const MAX_NEAR_DISTANCE := 2
## 太短的旗標名（例如 a1、a2）差一兩個字是正常的，不比拼字。
const MIN_NEAR_LENGTH := 6
const SCAN_ROOTS: Array[String] = ["res://data", "res://game", "res://autoload", "res://ui", "res://core"]
const SCAN_EXTENSIONS: Array[String] = ["tres", "tscn", "gd", "json"]

static var _flag_write_re := RegEx.create_from_string("set_flag\\(\\s*&?\"([^\"]+)\"")
static var _flag_read_re := RegEx.create_from_string("has_flag\\(\\s*&?\"([^\"]+)\"")
static var _portal_read_re := RegEx.create_from_string("requires_flag = &\"([^\"]+)\"")
static var _spawn_read_re := RegEx.create_from_string("spawn_(?:requires|unless)_flag = &\"([^\"]+)\"")
static var _acquire_write_re := RegEx.create_from_string("acquire_flag = &\"([^\"]+)\"")
static var _channel_write_re := RegEx.create_from_string("channel_(?:done|cleared)_flags = Dictionary\\[StringName, StringName\\]\\(\\{([^\\n]*)\\}\\)")
static var _dict_value_re := RegEx.create_from_string(": &\"([^\"]+)\"")


## 旗標表：{ 旗標: {"writes": [出處…], "reads": [出處…]} }。
## scenes：場景 id -> 場景；death_tables：章節 id -> death_scenes；text_files：路徑 -> 檔案內容（掃出入口與程式裡的讀寫）。
static func flag_table(scenes: Dictionary, death_tables: Dictionary, text_files: Dictionary) -> Dictionary:
	var table: Dictionary = {}
	for scene_id: String in scenes:
		var scene: Variant = scenes[scene_id]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		for entry in StoryRules.entries(scene):
			for flag: Variant in StoryRules.flag_names(entry.get("set_flags", [])):
				_add(table, str(flag), "writes", "場景 %s 的故事分支／結束" % scene_id)
			for key in ["requires_flag", "unless_flag"]:
				_add(table, str(entry.get(key, "")), "reads", "場景 %s 的 %s" % [scene_id, key])
			for flag in condition_flags(entry.get("when", {})):
				_add(table, flag, "reads", "場景 %s 的條件" % scene_id)
		for op in StoryOutcomes.operations(scene):
			if str(op.get("kind", "")) == "flag":
				_add(table, str(op.get("id", "")), "writes", "場景 %s 的段尾結果" % scene_id)
		for route: Variant in (scene as Dictionary).get("routes", []):
			if route is Dictionary:
				for flag in condition_flags((route as Dictionary).get("when", {})):
					_add(table, flag, "reads", "分派場景 %s 的路線條件" % scene_id)
	for chapter: String in death_tables:
		var entries: Variant = death_tables[chapter]
		if typeof(entries) != TYPE_ARRAY:
			continue
		for entry: Variant in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			for key in ["unless_flag", "requires_flag"]:
				var flag := str((entry as Dictionary).get(key, ""))
				if not flag.is_empty():
					_add(table, flag, "reads", "章節 %s 死亡場景 %s 的 %s" % [chapter, (entry as Dictionary).get("scene", "?"), key])
	for path: String in text_files:
		var text: String = text_files[path]
		for match in _portal_read_re.search_all(text):
			_add(table, match.get_string(1), "reads", "%s 的 requires_flag" % path)
		for match in _spawn_read_re.search_all(text):
			_add(table, match.get_string(1), "reads", "%s 的人物出現條件" % path)
		for match in _acquire_write_re.search_all(text):
			_add(table, match.get_string(1), "writes", "%s 取得物品時" % path)
		for match in _channel_write_re.search_all(text):
			for value in _dict_value_re.search_all(match.get_string(1)):
				_add(table, value.get_string(1), "writes", "%s 的機關頻道" % path)
		if path.ends_with(".json"):
			_add_chapter_rules(table, path, text)
		if path.ends_with(".gd"):
			for match in _flag_write_re.search_all(text):
				_add(table, match.get_string(1), "writes", "%s 的 set_flag" % path)
			for match in _flag_read_re.search_all(text):
				_add(table, match.get_string(1), "reads", "%s 的 has_flag" % path)
	return table


## 章節劇本的旗標規則：執行期事實與一般復原旗標由真實服務寫入；衍生旗標由條件重算（寫）並讀它的條件。
static func _add_chapter_rules(table: Dictionary, path: String, text: String) -> void:
	if not text.contains("\"runtime_facts\"") and not text.contains("\"derived_flags\"") and not text.contains("\"restoration_flag\""):
		return
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return
	var facts: Variant = (data as Dictionary).get("runtime_facts", {})
	for name: Variant in (facts as Dictionary if facts is Dictionary else {}):
		_add(table, str(name), "writes", "%s 的執行期事實" % path)
	var derived: Variant = (data as Dictionary).get("derived_flags", {})
	for name: Variant in (derived as Dictionary if derived is Dictionary else {}):
		_add(table, str(name), "writes", "%s 的衍生旗標" % path)
		for flag in condition_flags(derived[name]):
			_add(table, flag, "reads", "%s 的衍生旗標 %s" % [path, name])
	if (data as Dictionary).get("restoration_flag") is String:
		_add(table, str(data["restoration_flag"]), "writes", "%s 的一般復原" % path)


## 條件樹裡讀到的旗標名稱（all／any／not 遞迴）。
static func condition_flags(condition: Variant) -> Array[String]:
	var result: Array[String] = []
	if not condition is Dictionary:
		return result
	var raw: Dictionary = condition
	if raw.has("flag"):
		result.append(str(raw["flag"]))
	for key in ["all", "any"]:
		if raw.get(key) is Array:
			for child: Variant in raw[key]:
				result.append_array(condition_flags(child))
	if raw.has("not"):
		result.append_array(condition_flags(raw["not"]))
	return result


static func _add(table: Dictionary, flag: String, kind: String, where: String) -> void:
	if flag.is_empty():
		return
	if not table.has(flag):
		table[flag] = {"writes": [], "reads": []}
	(table[flag][kind] as Array).append(where)


## 旗標表的問題：{"errors": PackedStringArray, "warnings": PackedStringArray}。
static func flag_problems(table: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var names: Array = table.keys()
	names.sort()
	for flag: String in names:
		var entry: Dictionary = table[flag]
		if (entry["writes"] as Array).is_empty():
			errors.append("旗標「%s」只有人讀、沒有人寫，永遠不會成立：%s" % [flag, "、".join(entry["reads"])])
		elif (entry["reads"] as Array).is_empty():
			warnings.append("旗標「%s」只有人寫、沒有人讀（%s）：伏筆還是漏接？" % [flag, "、".join(entry["writes"])])
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			if a.length() >= MIN_NEAR_LENGTH and b.length() >= MIN_NEAR_LENGTH and distance(a, b) <= MAX_NEAR_DISTANCE:
				errors.append("旗標「%s」和「%s」拼字太接近，可能打錯字" % [a, b])
	return {"errors": errors, "warnings": warnings}


## 編輯距離（Levenshtein）。
static func distance(a: String, b: String) -> int:
	var previous: Array[int] = []
	for j in b.length() + 1:
		previous.append(j)
	for i in range(1, a.length() + 1):
		var current: Array[int] = [i]
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			current.append(mini(mini(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost))
		previous = current
	return previous[b.length()]


## 場景被引用的出處：{ 場景 id: [出處…] }。引用來自：場景的 then、重生與死亡場景表、其他檔案裡出現的場景 id 字串。
## text_files：路徑 -> 內容（劇本檔本身不要放進來，場景定義裡的 id 不算引用）。
static func scene_references(scenes: Dictionary, respawn_tables: Dictionary, death_tables: Dictionary, text_files: Dictionary) -> Dictionary:
	var refs: Dictionary = {}
	for scene_id: String in scenes:
		refs[scene_id] = []
	for scene_id: String in scenes:
		var scene: Variant = scenes[scene_id]
		if typeof(scene) == TYPE_DICTIONARY:
			var next := str((scene as Dictionary).get("then", ""))
			if refs.has(next):
				(refs[next] as Array).append("場景 %s 的 then" % scene_id)
			for target in _scene_targets(scene):
				if refs.has(target):
					(refs[target] as Array).append("場景 %s 的選項、分派或失敗接續" % scene_id)
	for tables: Dictionary in [respawn_tables, death_tables]:
		for chapter: String in tables:
			if typeof(tables[chapter]) != TYPE_ARRAY:
				continue
			for entry: Variant in tables[chapter]:
				if typeof(entry) == TYPE_DICTIONARY and refs.has(str((entry as Dictionary).get("scene", ""))):
					(refs[str((entry as Dictionary)["scene"])] as Array).append("章節 %s 的重生／死亡場景表" % chapter)
	for path: String in text_files:
		var text: String = text_files[path]
		for scene_id: String in refs:
			if text.contains("\"%s\"" % scene_id):
				(refs[scene_id] as Array).append(path)
	return refs


## 沒有任何引用的場景 id（排序）。
static func orphan_scenes(refs: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for scene_id: String in refs:
		if (refs[scene_id] as Array).is_empty():
			result.append(scene_id)
	result.sort()
	return result


# ---------------------------------------------------------------------------
# 不可達內容（旗標圖模擬）
# ---------------------------------------------------------------------------

## 從 starts（起點關卡）出發，反覆推進直到沒有新東西：到得了的關卡 → 裡面播得出的場景 → 場景設定的旗標 → 旗標打開的出入口 → 到得了的關卡…
## model：{ "levels": { 關卡: {"scenes": [{"id": 場景, "after": 前置場景（空＝不限）}…], "portals": [{"to": 關卡, "requires": 旗標（空＝不限）}…]} },
##          "scenes": { 場景: 場景資料（用 set_flags 與 then） }, "always": [一開始就播得出的場景（死亡與重生場景表）], "code_flags": [程式會設定的旗標] }。
## 回傳 { "levels": 到得了的關卡, "scenes": 播得出的場景, "flags": 拿得到的旗標 }（都是 Dictionary 當集合用）。
static func reachability(model: Dictionary, starts: Array) -> Dictionary:
	var levels: Dictionary = {}
	var scenes: Dictionary = {}
	var flags: Dictionary = {}
	for flag: Variant in model.get("code_flags", []):
		flags[str(flag)] = true
	for scene: Variant in model.get("always", []):
		_play(model, str(scene), scenes, flags)
	for start: Variant in starts:
		levels[str(start)] = true
	var size_before := -1
	while size_before != levels.size() + scenes.size() + flags.size():
		size_before = levels.size() + scenes.size() + flags.size()
		for level_id: String in levels.keys():
			var level: Dictionary = (model.get("levels", {}) as Dictionary).get(level_id, {})
			for flag: Variant in level.get("flags", []):
				flags[str(flag)] = true
			for entry: Variant in level.get("scenes", []):
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var scene_id := str((entry as Dictionary).get("id", ""))
				var after := str((entry as Dictionary).get("after", ""))
				if scene_id.is_empty() or scenes.has(scene_id) or (not after.is_empty() and not scenes.has(after)):
					continue
				_play(model, scene_id, scenes, flags)
			for portal: Variant in level.get("portals", []):
				if typeof(portal) != TYPE_DICTIONARY:
					continue
				var to := str((portal as Dictionary).get("to", ""))
				var requires := str((portal as Dictionary).get("requires", ""))
				if not to.is_empty() and not levels.has(to) and (requires.is_empty() or flags.has(requires)):
					levels[to] = true
	return {"levels": levels, "scenes": scenes, "flags": flags}


## 播放一個場景（與它的 then 串）：記下場景、設定的旗標。
static func _play(model: Dictionary, scene_id: String, scenes: Dictionary, flags: Dictionary) -> void:
	var guard := 0
	var current := scene_id
	while not current.is_empty() and not scenes.has(current) and guard < 64:
		guard += 1
		scenes[current] = true
		var scene: Variant = (model.get("scenes", {}) as Dictionary).get(current, {})
		if typeof(scene) != TYPE_DICTIONARY:
			return
		# Static potential reachability: enumerate every branch, not simultaneous runtime choices.
		for entry in StoryRules.entries(scene):
			for flag: Variant in StoryRules.flag_names(entry.get("set_flags", [])):
				flags[str(flag)] = true
		for op in StoryOutcomes.operations(scene):
			if str(op.get("kind", "")) == "flag":
				flags[str(op.get("id", ""))] = true
		for target in _scene_targets(scene):
			_play(model, target, scenes, flags)
		current = str((scene as Dictionary).get("then", ""))


## 一個場景可能接到的其他場景：選項的 target、分派路線、交易失敗的 on_failure（靜態列舉全部分支）。
static func _scene_targets(scene: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for entry in StoryRules.entries(scene.get("steps", [])):
		if entry.has("target"):
			result.append(str(entry["target"]))
	for route: Variant in scene.get("routes", []):
		if route is Dictionary:
			result.append(str((route as Dictionary).get("target", "")))
	var failures: Variant = scene.get("on_failure", {})
	if failures is Dictionary:
		for reason: Variant in failures:
			result.append(str(failures[reason]))
	return result


## 不可達內容的問題：{"errors", "warnings"}。
##   錯誤：到不了的關卡（除了 allowed_unreachable）；出入口要的旗標在整張圖裡拿不到（永遠打不開）。
##   警告：有定義、被引用、卻因為前置場景或旗標而永遠播不出的場景。
static func unreachable_problems(model: Dictionary, starts: Array, allowed_unreachable: Array = []) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var result := reachability(model, starts)
	var levels: Dictionary = result["levels"]
	var level_ids: Array = (model.get("levels", {}) as Dictionary).keys()
	level_ids.sort()
	for level_id: String in level_ids:
		if not levels.has(level_id) and not allowed_unreachable.has(level_id):
			errors.append("關卡「%s」從起點走不到（出入口的旗標拿不到，或沒有任何出入口通往它）" % level_id)
	for level_id: String in level_ids:
		for portal: Variant in (model["levels"][level_id] as Dictionary).get("portals", []):
			var requires := str((portal as Dictionary).get("requires", ""))
			if not requires.is_empty() and not (result["flags"] as Dictionary).has(requires) and levels.has(level_id):
				errors.append("關卡「%s」通往「%s」的出入口要旗標「%s」，但整張圖裡沒有一個播得出的場景會設定它" % [level_id, (portal as Dictionary).get("to", "?"), requires])
	var referenced: Dictionary = {}
	for level_id: String in level_ids:
		for entry: Variant in (model["levels"][level_id] as Dictionary).get("scenes", []):
			referenced[str((entry as Dictionary).get("id", ""))] = level_id
	var unplayable: Array = []
	for scene_id: String in referenced:
		if not (result["scenes"] as Dictionary).has(scene_id) and levels.has(referenced[scene_id]):
			unplayable.append(scene_id)
	unplayable.sort()
	for scene_id: String in unplayable:
		warnings.append("場景「%s」在關卡「%s」裡被引用，但它的前置場景永遠播不出來" % [scene_id, referenced[scene_id]])
	return {"errors": errors, "warnings": warnings}


## 從真實的關卡資料建 model：datas 與 layouts 都以關卡路徑為鍵（LevelData、LevelLayout）。
static func level_model(datas: Dictionary, layouts: Dictionary, scenes: Dictionary, always: Array, code_flags: Array) -> Dictionary:
	var levels: Dictionary = {}
	for path: String in datas:
		var data := datas[path] as LevelData
		var layout := layouts[path] as LevelLayout
		var scene_entries: Array = []
		for id in [data.intro_scene, data.boss_scene, data.outro_scene]:
			if id != &"":
				scene_entries.append({"id": str(id), "after": ""})
		for id: Variant in data.channel_scenes.values():
			scene_entries.append({"id": str(id), "after": ""})
		for id in data.story_triggers:
			scene_entries.append({"id": str(id), "after": ""})
		for entry in data.cinematic_entries:
			if entry != null:
				scene_entries.append({"id": str(entry.scene), "after": ""})
		var level_flags: Array = []
		for flag: Variant in data.channel_done_flags.values() + data.channel_cleared_flags.values():
			level_flags.append(str(flag))
		var portals: Array = []
		if not data.next_level.is_empty():
			portals.append({"to": data.next_level, "requires": ""})
		for spawn in layout.spawns:
			var res := spawn["resource"] as Resource
			if res is PortalData and not (res as PortalData).is_locked_door():
				portals.append({"to": (res as PortalData).target_level, "requires": str((res as PortalData).requires_flag)})
			elif res is NpcData:
				for talk in (res as NpcData).talks:
					if talk != null:
						scene_entries.append({"id": str(talk.scene), "after": str(talk.after_scene)})
			elif res is MechanismData and (res as MechanismData).start_scene != &"":
				scene_entries.append({"id": str((res as MechanismData).start_scene), "after": ""})
			elif res is StoryItemData and (res as StoryItemData).acquire_flag != &"":
				level_flags.append(str((res as StoryItemData).acquire_flag))
		levels[path] = {"scenes": scene_entries, "portals": portals, "flags": level_flags}
	return {"levels": levels, "scenes": scenes, "always": always, "code_flags": code_flags}


## 讀出資料夾下（遞迴）所有指定副檔名的文字檔：路徑 -> 內容。exclude：路徑包含這些字串的略過。
static func read_text_files(roots: Array[String] = SCAN_ROOTS, exclude: Array[String] = []) -> Dictionary:
	var result: Dictionary = {}
	for root in roots:
		_collect(root, exclude, result)
	return result


static func _collect(dir: String, exclude: Array[String], result: Dictionary) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect("%s/%s" % [dir, sub], exclude, result)
	for file in DirAccess.get_files_at(dir):
		var path := "%s/%s" % [dir, file]
		if not SCAN_EXTENSIONS.has(file.get_extension()):
			continue
		if exclude.any(func(part: String) -> bool: return path.contains(part)):
			continue
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			result[path] = text
