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


## 旗標表：{ 旗標: {"writes": [出處…], "reads": [出處…]} }。
## scenes：場景 id -> 場景；death_tables：章節 id -> death_scenes；text_files：路徑 -> 檔案內容（掃出入口與程式裡的讀寫）。
static func flag_table(scenes: Dictionary, death_tables: Dictionary, text_files: Dictionary) -> Dictionary:
	var table: Dictionary = {}
	for scene_id: String in scenes:
		var scene: Variant = scenes[scene_id]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var flags: Variant = (scene as Dictionary).get("set_flags", [])
		if typeof(flags) == TYPE_ARRAY:
			for flag: Variant in flags:
				_add(table, str(flag), "writes", "場景 %s 結束" % scene_id)
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
		if path.ends_with(".gd"):
			for match in _flag_write_re.search_all(text):
				_add(table, match.get_string(1), "writes", "%s 的 set_flag" % path)
			for match in _flag_read_re.search_all(text):
				_add(table, match.get_string(1), "reads", "%s 的 has_flag" % path)
	return table


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
