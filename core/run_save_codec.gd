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

# Alternating branches are disjoint. Possessive runs keep quote matching linear.
static var _json_strings := RegEx.create_from_string(r'(?s)"(?:[^"\\]++|\\.)*+"')


static func encode(data: Dictionary) -> String:
	if not validate_tree(data).is_empty():
		return ""
	return _wrap_payload(JSON.stringify(data))


static func _wrap_payload(payload: String) -> String:
	return JSON.stringify({"version": VERSION, "checksum": payload.sha256_text(), "payload": payload})


## Use the same JSON types and byte budget for a freshly captured run.
## The envelope is generated here, so only external text goes through envelope parsing.
static func round_trip(data: Dictionary) -> Dictionary:
	var errors := validate_tree(data)
	if not errors.is_empty():
		return {"error": errors[0]}
	var payload := JSON.stringify(data)
	if _wrap_payload(payload).to_utf8_buffer().size() > MAX_BYTES:
		return {"error": "檔案超過大小或巢狀上限"}
	return _decode_payload(payload, JSON.new())


static func decode(text: String) -> Dictionary:
	if not _bounded_envelope(text):
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
	return _decode_payload(payload, json)


static func _decode_payload(payload: String, json: JSON) -> Dictionary:
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
	var stripped := _json_strings.sub(text, "", true) if _json_strings != null else text
	# An unmatched quote or a failed substitution can require the original scan.
	if stripped.is_empty() or stripped.contains('"'):
		return _nesting_bytes_safe(text.to_utf8_buffer())
	return _nesting_bytes_safe(stripped.to_utf8_buffer())


static func _bounded_envelope(text: String) -> bool:
	return text.to_utf8_buffer().size() <= MAX_BYTES and nesting_safe(text)


## JSON delimiters and escapes are ASCII; UTF-8 continuation bytes cannot match them.
static func _nesting_bytes_safe(bytes: PackedByteArray) -> bool:
	const QUOTE := 34
	const ESCAPE := 92
	const ARRAY_OPEN := 91
	const ARRAY_CLOSE := 93
	const OBJECT_OPEN := 123
	const OBJECT_CLOSE := 125
	var depth := 0
	var quoted := false
	var escaped := false
	for byte in bytes:
		if quoted:
			if escaped:
				escaped = false
			elif byte == ESCAPE:
				escaped = true
			elif byte == QUOTE:
				quoted = false
		elif byte == QUOTE:
			quoted = true
		elif byte == OBJECT_OPEN or byte == ARRAY_OPEN:
			depth += 1
			if depth > MAX_DEPTH:
				return false
		elif byte == OBJECT_CLOSE or byte == ARRAY_CLOSE:
			depth -= 1
			if depth < 0:
				return false
	return depth == 0 and not quoted


## Callers handling saved data keep the file-format depth. An internal caller
## may set a different bound for its own type of tree.
static func validate_tree(raw: Variant, node_limit := MAX_NODES, depth_limit := MAX_DEPTH) -> PackedStringArray:
	var validator := _TreeValidator.new()
	validator.limit = clampi(node_limit, 1, MAX_NODES)
	validator.depth_limit = depth_limit
	if validator.visit(raw, 0):
		return PackedStringArray()
	var where := "run"
	for i in range(validator.path.size() - 1, -1, -1):
		where = _diagnostic_path(where, str(validator.path[i]))
	return PackedStringArray(["%s：%s" % [where, validator.message]])


## Save trees have a small fixed depth. Produce the path while unwinding a failure.
class _TreeValidator:
	var limit := 0
	var depth_limit := RunSaveCodec.MAX_DEPTH
	var count := 0
	var path: Array = []
	var message := ""

	func fail(reason: String) -> bool:
		message = reason
		return false

	func visit(value: Variant, depth: int) -> bool:
		count += 1
		if count > limit or depth > depth_limit:
			return fail("資料數量或深度超過上限")
		match typeof(value):
			TYPE_NIL, TYPE_BOOL:
				return true
			TYPE_INT, TYPE_FLOAT:
				return (is_finite(float(value)) and absf(float(value)) <= RunSaveCodec.MAX_NUMBER) or fail("數值不是有界有限值")
			TYPE_STRING, TYPE_STRING_NAME:
				return String(value).length() <= RunSaveCodec.MAX_TEXT or fail("文字超過上限")
			TYPE_ARRAY, TYPE_DICTIONARY:
				return visit_container(value, depth)
		return fail("不接受物件或引擎型別")

	func visit_container(value: Variant, depth: int) -> bool:
		var size: int = value.size()
		if size > RunSaveCodec.MAX_CONTAINER:
			return fail("容器超過上限")
		if count + size > limit:
			return fail("資料數量超過上限")
		if value is Dictionary:
			for key: Variant in value:
				if (not key is String and not key is StringName) or String(key).length() > RunSaveCodec.MAX_TEXT:
					return fail("無效欄位名稱")
				if not visit(value[key], depth + 1):
					path.append(key)
					return false
		else:
			for i in size:
				if not visit(value[i], depth + 1):
					path.append(i)
					return false
		return true


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
