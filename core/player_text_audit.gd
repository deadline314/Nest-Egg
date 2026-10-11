class_name PlayerTextAudit
extends RefCounted
## 玩家文字盤點：全部故事 JSON、data 的說明／提示及 UI／遊戲訊息來源。
## 用來源位置回報，對白嚴格檢查；名稱／按鈕／數值是標籤，不套用句子短片段限制。

const TEXT_FIELDS := ["text", "ja", "en", "description", "body", "hint", "tooltip", "locked_text", "prompt", "hints", "message", "action_hint", "tooltip_text", "placeholder_text", "help", "background", "reward", "blocked_reason", "suggestion"]
const LABEL_FIELDS := ["name", "display_name", "title", "subtitle", "sub", "end_title", "teaser", "label"]
# Player-facing map text is produced here; the other navigation core strings
# are developer validation diagnostics, not rendered messages.
const SCRIPT_SOURCES := ["core/navigation/quest_map_index.gd"]

static func catalog(source_root := "res://") -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for path in _files(source_root.path_join("data")):
		if path.ends_with(".json"):
			_json(JSON.parse_string(FileAccess.get_file_as_string(path)), path, "", entries)
		elif path.ends_with(".tres"):
			_tres(path, entries)
	for root in [source_root.path_join("ui"), source_root.path_join("game"), source_root.path_join("autoload")]:
		for path in _files(root):
			if path.ends_with(".gd"):
				_script(path, entries)
			elif path.ends_with(".tscn"):
				_tres(path, entries)
	for relative_path in SCRIPT_SOURCES:
		var path: String = source_root.path_join(relative_path)
		if FileAccess.file_exists(path):
			_script(path, entries)
	if source_root != "res://":
		for entry in entries:
			entry.id = "res://" + str(entry.id).trim_prefix(source_root.trim_suffix("/") + "/")
	return entries


static func lint(entries: Array[Dictionary]) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for entry in entries:
		if entry["kind"] == "label":
			continue
		issues.append_array(StoryLint.readability(entry["text"], entry["id"], entry.get("mode", "text"), entry.get("bark", false), _language_of(str(entry["id"]))))
	return issues


## 譯文欄位（ST-2）：路徑最後一段是 ja／en 或 <欄位>_ja／<欄位>_en。
static func _language_of(id: String) -> String:
	var last := id.get_slice("/", id.get_slice_count("/") - 1)
	for language in ["ja", "en"]:
		if last == language or last.ends_with("_" + language):
			return language
	return "zh"


static func _json(value: Variant, path: String, key: String, entries: Array[Dictionary], mode := "text", bark := false) -> void:
	if value is Dictionary:
		mode = str(value.get("mode", mode))
		# 只有布林值才是「氣泡對白」標記；同名的資料鍵（例如頭目招式 bark）不能讓盤點崩潰。
		var bark_flag: Variant = value.get("bark", bark)
		bark = bark_flag if bark_flag is bool else bark
		for field: String in value:
			var item: Variant = value[field]
			var location := path + "/" + field
			if item is String and (TEXT_FIELDS.has(field) or LABEL_FIELDS.has(field)):
				# Quest/step titles are action objectives, unlike chapter/item names.
				var quest_title := field == "title" and path.contains("/quests/")
				var is_label: bool = (LABEL_FIELDS.has(field) and not quest_title) or str(value.get("do", "")) == "title"
				_add(entries, location, item, "label" if is_label else "text", mode, bark)
			elif field == "lines" and item is Array:
				for i in item.size():
					if item[i] is String:
						_add(entries, "%s/%d" % [location, i + 1], item[i], "text", mode, bark)
					else:
						_json(item[i], "%s/%d" % [location, i + 1], field, entries, mode, bark)
			elif item is Dictionary or item is Array:
				_json(item, location, field, entries, mode, bark)
	elif value is Array:
		for i in value.size():
			if value[i] is String and TEXT_FIELDS.has(key):
				_add(entries, "%s/%d" % [path, i + 1], value[i], "text", mode, bark)
			else:
				_json(value[i], "%s/%d" % [path, i + 1], key, entries, mode, bark)


static func _tres(path: String, entries: Array[Dictionary]) -> void:
	var field := ""
	var strings := RegEx.create_from_string('"((?:[^"\\\\]|\\\\.)*)"')
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var line := lines[i]
		if line.contains(" = "):
			field = line.split(" = ")[0].strip_edges()
		if not TEXT_FIELDS.has(field) and not LABEL_FIELDS.has(field):
			continue
		for match_value in strings.search_all(line):
			var text := _decode(match_value.get_string(1))
			_add(entries, "%s:%d/%s" % [path, i + 1, field], text, "label" if LABEL_FIELDS.has(field) else "text")


static func _script(path: String, entries: Array[Dictionary]) -> void:
	var strings := RegEx.create_from_string('"((?:[^"\\\\]|\\\\.)*)"')
	var han := RegEx.create_from_string("[\\p{Han}]")
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.begins_with("#") or line.contains("push_error(") or line.contains("push_warning("):
			continue
		for match_value in strings.search_all(line):
			# A trailing source comment is not rendered text.
			if line.substr(0, match_value.get_start()).contains("#"):
				break
			var text := _decode(match_value.get_string(1))
			if han.search(text) == null:
				continue
			var kind := "text"
			if not text.contains("。") and not text.contains("，") and not text.contains("？") and not text.contains("；") and not text.contains("\n") and text.length() <= 4:
				kind = "label"
			# Dictionary keys, explicit titles and concatenation prefixes are labels.
			if line.substr(match_value.get_end()).strip_edges().begins_with(":") or text.ends_with("：") or line.contains(".title =") or line.contains(".subtitle =") or _button_caption(line, match_value.get_start()):
				kind = "label"
			# This is a field caption plus separately catalogued quest prose.
			if text == "獎勵：%s" and line.contains('_wrapped(_details,'):
				kind = "label"
			_add(entries, "%s:%d@%d" % [path, i + 1, match_value.get_start()], text, kind)


## Only the first button argument is a caption. Nested get()/str() defaults count;
## the tooltip argument stays prose even when it is on the same source line.
static func _button_caption(line: String, literal_start: int) -> bool:
	var call := line.rfind("UiKit.button(", literal_start)
	if call < 0:
		return false
	var depth := 1
	var quote := ""
	var escaped := false
	for i in range(call + "UiKit.button(".length(), literal_start):
		var character := line[i]
		if escaped:
			escaped = false
			continue
		if not quote.is_empty():
			if character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
			continue
		if character == '"' or character == "'":
			quote = character
		elif character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
			if depth == 0:
				return false
		elif character == "," and depth == 1:
			return false
	return true


static func _add(entries: Array[Dictionary], id: String, text: String, kind: String, mode := "text", bark := false) -> void:
	if not text.is_empty():
		entries.append({"id": id, "text": text, "kind": kind, "mode": mode, "bark": bark})


static func _decode(text: String) -> String:
	var decoded: Variant = JSON.parse_string('"' + text + '"')
	return str(decoded) if decoded is String else text


static func _files(root: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(root):
		files.append(root.path_join(file))
	for dir in DirAccess.get_directories_at(root):
		files.append_array(_files(root.path_join(dir)))
	files.sort()
	return files
