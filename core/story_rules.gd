class_name StoryRules
extends RefCounted
## 共用故事條件：選項、物件調查與演出分支沿用同一份旗標／道具來源。

static func eligible(entry: Dictionary, flag_reader: Callable, item_reader: Callable) -> bool:
	var requires := StringName(str(entry.get("requires_flag", "")))
	var unless := StringName(str(entry.get("unless_flag", "")))
	var item := StringName(str(entry.get("requires_item", "")))
	return (requires == &"" or bool(flag_reader.call(requires))) \
		and (unless == &"" or not bool(flag_reader.call(unless))) \
		and (item == &"" or bool(item_reader.call(item)))


static func options(step: Dictionary, flag_reader: Callable, item_reader: Callable) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = step.get("options", [])
	if raw is Array:
		for option: Variant in raw:
			if option is Dictionary and eligible(option, flag_reader, item_reader):
				result.append(option)
	return result


static func default_option(step: Dictionary, available: Array[Dictionary]) -> Dictionary:
	for option in available:
		if str(option.get("id", "")) == str(step.get("default", "")):
			return option
	return available[0] if not available.is_empty() else {}


## 掃描所有分支；審核端可辨識選項旗標與場景引用，不把它們當作孤兒。
static func entries(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Dictionary:
		result.append(value)
		for key: Variant in value:
			if key in ["steps", "options", "else_steps"]:
				result.append_array(entries(value[key]))
	elif value is Array:
		for entry: Variant in value:
			result.append_array(entries(entry))
	return result


static func flag_names(value: Variant) -> Array:
	return value.keys() if value is Dictionary else (value if value is Array else [])


static func validate_choice(where: String, step: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var raw: Variant = step.get("options", [])
	if not raw is Array or raw.size() < 2 or raw.size() > 4:
		problems.append("%s 的選項必須有 2 到 4 項" % where)
		return problems
	var ids := {}
	for i in raw.size():
		var option: Variant = raw[i]
		if not option is Dictionary:
			problems.append("%s 選項 %d 不是物件" % [where, i + 1])
			continue
		var id := str(option.get("id", ""))
		if id.is_empty() or ids.has(id):
			problems.append("%s 選項 %d 的 id 遺失或重複" % [where, i + 1])
		ids[id] = true
		if str(option.get("text", "")).strip_edges().is_empty():
			problems.append("%s 選項 %d 沒有文字" % [where, i + 1])
		var flags: Variant = option.get("set_flags", {})
		if not flags is Dictionary and not flags is Array:
			problems.append("%s 選項 %d 的 set_flags 必須是物件或清單" % [where, i + 1])
	if not ids.has(str(step.get("default", ""))):
		problems.append("%s 的 default 必須指向一個選項" % where)
	return problems
