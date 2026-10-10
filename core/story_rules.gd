class_name StoryRules
extends RefCounted
## 共用故事條件：選項、物件調查與演出分支沿用同一份旗標／道具來源。

## 物品條件分三種：requires_item 看「本輪曾取得」；requires_held_item／unless_held_item 看「目前手上有原件」；
## requires_transferred_item 看「原件已交出」。交出後歷史仍在，所以回顧與交付後的回訪要用後兩種。
const CUSTODY_KEYS: Array[String] = ["requires_held_item", "unless_held_item", "requires_transferred_item"]


static func eligible(entry: Dictionary, flag_reader: Callable, item_reader: Callable, custody_reader: Callable = Callable()) -> bool:
	var requires := StringName(str(entry.get("requires_flag", "")))
	var unless := StringName(str(entry.get("unless_flag", "")))
	var item := StringName(str(entry.get("requires_item", "")))
	return (requires == &"" or bool(flag_reader.call(requires))) \
		and (unless == &"" or not bool(flag_reader.call(unless))) \
		and (item == &"" or bool(item_reader.call(item))) \
		and custody_allows(entry, custody_reader)


## custody_reader(kind, id) -> bool，kind 為 &"held" 或 &"transferred"；未提供時讀 StoryItems（正式遊戲）。
static func custody_allows(entry: Dictionary, custody_reader: Callable = Callable()) -> bool:
	var reader := custody_reader if custody_reader.is_valid() else live_custody
	for key in CUSTODY_KEYS:
		var id := StringName(str(entry.get(key, "")))
		if id == &"":
			continue
		var kind := &"transferred" if key == "requires_transferred_item" else &"held"
		if bool(reader.call(kind, id)) == (key == "unless_held_item"):
			return false
	return true


static func live_custody(kind: StringName, id: StringName) -> bool:
	return StoryItems.was_transferred(id) if kind == &"transferred" else StoryItems.holds(id)


## 場景或選項宣告要交出的原件（transfer_items）；非清單時回空，由 validate 報告位置。
static func transfer_ids(entry: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw: Variant = entry.get("transfer_items", [])
	if raw is Array:
		for id: Variant in raw:
			if (id is String or id is StringName) and not str(id).is_empty() and not result.has(StringName(id)):
				result.append(StringName(id))
	return result


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
		problems.append_array(validate_transfers("%s 選項 %d" % [where, i + 1], option))
		if id == str(step.get("default", "")) and option.has("transfer_items"):
			problems.append("%s 的 default 不能交出原件：略過演出不等於玩家確認交付" % where)
	if not ids.has(str(step.get("default", ""))):
		problems.append("%s 的 default 必須指向一個選項" % where)
	return problems


## transfer_items 必須是物品目錄裡的 id 清單；catalog_reader(id) -> StoryItemData，測試可替換。
static func validate_transfers(where: String, entry: Dictionary, catalog_reader: Callable = Callable()) -> PackedStringArray:
	var problems := PackedStringArray()
	if not entry.has("transfer_items"):
		return problems
	var raw: Variant = entry["transfer_items"]
	if not raw is Array or (raw as Array).is_empty():
		problems.append("%s 的 transfer_items 必須是非空的物品 id 清單" % where)
		return problems
	var finder := catalog_reader if catalog_reader.is_valid() else StoryItems.find
	for id: Variant in raw:
		if not (id is String or id is StringName) or str(id).is_empty() or finder.call(StringName(id)) == null:
			problems.append("%s 的 transfer_items 有不存在的物品：%s" % [where, str(id)])
	return problems
