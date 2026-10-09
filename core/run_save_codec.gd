class_name RunSaveCodec
extends RefCounted
## 有界 JSON 邊界；只接受純資料，資源引用另按欄位白名單核對。

const VERSION := 1
const MAX_BYTES := 4 * 1024 * 1024
const MAX_DEPTH := 16
const MAX_NODES := 200000
const MAX_CONTAINER := 65536
const MAX_TEXT := 1024
const MAX_DIAGNOSTIC_PATH := 512
const MAX_NUMBER := 1000000000.0


static func encode(data: Dictionary) -> String:
	if not validate_tree(data).is_empty():
		return ""
	var payload := JSON.stringify(data)
	return JSON.stringify({"version": VERSION, "checksum": payload.sha256_text(), "payload": payload})


static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES or not nesting_safe(text):
		return {"error": "檔案超過大小或巢狀上限"}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": "JSON 損毀，第%d行：%s" % [json.get_error_line(), json.get_error_message()]}
	var envelope: Dictionary = json.data
	if not valid_version(envelope.get("version")):
		return {"error": "存檔版本缺漏或格式損毀"}
	if envelope.get("version") != VERSION:
		return {"error": "未知存檔版本", "unknown_version": true}
	var payload: Variant = envelope.get("payload")
	if not payload is String or not envelope.get("checksum") is String or payload.sha256_text() != envelope["checksum"]:
		return {"error": "存檔完整性校驗失敗"}
	if not nesting_safe(payload):
		return {"error": "資料巢狀超過上限"}
	if json.parse(payload) != OK or not json.data is Dictionary:
		return {"error": "整輪資料不是有效物件"}
	var errors := validate_tree(json.data)
	if not errors.is_empty():
		return {"error": errors[0]}
	return {"data": json.data}


static func valid_version(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 1 and float(value) <= MAX_NUMBER and floorf(float(value)) == float(value)


## 在 JSON.parse 前檢查容器深度；忽略字串內括號及跳脫字元。
static func nesting_safe(text: String) -> bool:
	var depth := 0
	var quoted := false
	var escaped := false
	for i in text.length():
		var c := text[i]
		if quoted:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				quoted = false
		elif c == "\"":
			quoted = true
		elif c == "{" or c == "[":
			depth += 1
			if depth > MAX_DEPTH:
				return false
		elif c == "}" or c == "]":
			depth -= 1
			if depth < 0:
				return false
	return depth == 0 and not quoted


static func validate_tree(raw: Variant, node_limit := MAX_NODES) -> PackedStringArray:
	# 呼叫端可收緊預算，但不能放寬正式上限；測試不必配置20萬節點。
	node_limit = clampi(node_limit, 1, MAX_NODES)
	var errors := PackedStringArray()
	var pending: Array = [[raw, 0, "run"]]
	var count := 0
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		count += 1
		if count > node_limit or int(entry[1]) > MAX_DEPTH:
			errors.append("%s：資料數量或深度超過上限" % entry[2])
			break
		var value: Variant = entry[0]
		var where: String = entry[2]
		match typeof(value):
			TYPE_NIL, TYPE_BOOL:
				pass
			TYPE_INT, TYPE_FLOAT:
				if not is_finite(float(value)) or absf(float(value)) > MAX_NUMBER:
					errors.append("%s：數值不是有界有限值" % where)
			TYPE_STRING, TYPE_STRING_NAME:
				# 既有故事物品使用 StringName；JSON 將它寫為普通字串。
				if String(value).length() > MAX_TEXT:
					errors.append("%s：文字超過上限" % where)
			TYPE_ARRAY, TYPE_DICTIONARY:
				if value.size() > MAX_CONTAINER:
					errors.append("%s：容器超過上限" % where)
					break
				if count + pending.size() + value.size() > node_limit:
					errors.append("%s：資料數量超過上限" % where)
					break
				for key: Variant in value.size() if value is Array else value:
					if value is Dictionary and (typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or String(key).length() > MAX_TEXT):
						errors.append("%s：無效欄位名稱" % where)
						break
					pending.append([value[key], int(entry[1]) + 1, _diagnostic_path(where, str(key))])
			_:
				errors.append("%s：不接受物件或引擎型別" % where)
		if not errors.is_empty():
			break
	return errors


static func _diagnostic_path(parent: String, key: String) -> String:
	var path := parent + "/" + key
	if path.length() <= MAX_DIAGNOSTIC_PATH:
		return path
	# 保留根與最新欄位尾端；每個待驗節點最多持有512字元。
	return path.left(96) + "/…/" + path.right(MAX_DIAGNOSTIC_PATH - 99)


static func number(raw: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
		return fallback
	return clampf(float(raw), minimum, maximum)


static func vector(raw: Variant, fallback := Vector2.ZERO) -> Vector2:
	if not raw is Array or raw.size() != 2:
		return fallback
	if typeof(raw[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return fallback
	var result := Vector2(float(raw[0]), float(raw[1]))
	return result if result.is_finite() else fallback


static func resource(path: Variant, type: String, folder: String) -> Resource:
	if not path is String or not path.begins_with(folder) or ".." in path or "::" in path or path.get_extension() != "tres":
		return null
	if not ResourceLoader.exists(path):
		return null
	var value: Resource = load(path)
	match type:
		"level": return value if value is LevelData else null
		"weapon": return value if value is WeaponData else null
		"difficulty": return value if value is DifficultyData else null
		"enemy": return value if value is EnemyData else null
		"consumable": return value if value is ConsumableData else null
	return null
