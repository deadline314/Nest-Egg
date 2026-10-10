class_name StoryTransactionData
extends Resource
## 一次故事款項的定義；不含任意回呼、物品或故事旗標。

const MAX_ID_LENGTH := 64
const MAX_DEPENDENCIES := 32
const MAX_DELTA := 99999
const VERSION := 1

@export var id: StringName = &""
@export var definition_version: int = VERSION
@export var credits_delta: int = 0
@export var requires_receipts: PackedStringArray = []
@export var excludes_receipts: PackedStringArray = []


static func valid_id(raw: Variant) -> bool:
	if typeof(raw) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := String(raw)
	if text.is_empty() or text.length() > MAX_ID_LENGTH:
		return false
	for i in text.length():
		var code := text.unicode_at(i)
		var letter := code >= 97 and code <= 122
		if i == 0 and not letter:
			return false
		if not letter and not (code >= 48 and code <= 57) and code not in [95, 46]:
			return false
	return true


static func integer_in(raw: Variant, minimum: int, maximum: int) -> bool:
	return typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) \
		and float(raw) >= minimum and float(raw) <= maximum and floorf(float(raw)) == float(raw)


## 驗證後的獨立純資料；指紋不受資源路徑或條件排列順序影響。
func descriptor() -> Dictionary:
	if not valid_id(id):
		return {"error": "definition/id：事件編號格式無效"}
	if definition_version != VERSION:
		return {"error": "definition/definition_version：不支援的定義版本"}
	if not integer_in(credits_delta, -MAX_DELTA, MAX_DELTA):
		return {"error": "definition/credits_delta：金額超過上限"}
	if requires_receipts.size() > MAX_DEPENDENCIES or excludes_receipts.size() > MAX_DEPENDENCIES:
		return {"error": "definition/receipts：條件數量超過上限"}
	var required: Array[String] = []
	var excluded: Array[String] = []
	for key in requires_receipts:
		if not valid_id(key) or key == String(id) or required.has(key):
			return {"error": "definition/requires_receipts：無效、自我引用或重複條件"}
		required.append(key)
	for key in excludes_receipts:
		if not valid_id(key) or key == String(id) or excluded.has(key) or required.has(key):
			return {"error": "definition/excludes_receipts：無效、自我引用、重複或衝突條件"}
		excluded.append(key)
	required.sort()
	excluded.sort()
	var canonical := [String(id), definition_version, credits_delta, required, excluded]
	return {"id": String(id), "credits_delta": credits_delta, "required": required,
		"excluded": excluded, "fingerprint": JSON.stringify(canonical).sha256_text()}


func validate() -> PackedStringArray:
	var description := descriptor()
	return PackedStringArray([description["error"]]) if description.has("error") else PackedStringArray()
