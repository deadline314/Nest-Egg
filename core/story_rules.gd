class_name StoryRules
extends RefCounted
## 共用故事條件：選項、物件調查與演出分支沿用同一份旗標／道具來源。

## 物品條件分三種：requires_item 看「本輪曾取得」；requires_held_item／unless_held_item 看「目前手上有原件」；
## requires_transferred_item 看「原件已交出」。交出後歷史仍在，所以回顧與交付後的回訪要用後兩種。
const CUSTODY_KEYS: Array[String] = ["requires_held_item", "unless_held_item", "requires_transferred_item"]
const CONDITION_OPERATORS: Array[String] = ["all", "any", "not"]


static func eligible(entry: Dictionary, flag_reader: Callable, item_reader: Callable, custody_reader: Callable = Callable()) -> bool:
	var requires := StringName(str(entry.get("requires_flag", "")))
	var unless := StringName(str(entry.get("unless_flag", "")))
	var item := StringName(str(entry.get("requires_item", "")))
	return (requires == &"" or bool(flag_reader.call(requires))) \
		and (unless == &"" or not bool(flag_reader.call(unless))) \
		and (item == &"" or bool(item_reader.call(item))) \
		and custody_allows(entry, custody_reader) \
		and (not entry.has("when") or holds(entry["when"]))


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


## 執行期條件樹：all／any／not、{flag, equals}、{item}（目前手上有原件）、
## {receipt, status}、{account, equals}。保留 flag 省略 equals=true 與原 facts reader；
## 不套用純 StoryConditionTree 的第一章帳務 ID／facts 快照政策。空物件代表沒有前置條件。
## facts(kind, id) 回傳事實：kind 為 &"flag"／&"held"／&"receipt"／&"account"；未提供時讀 Story（正式遊戲）。
## equals 的字面值不接受 null；facts 回傳 null 仍沿用 same_value 的預設值比較。
## 先完整驗一次結構才求值；not／短路分支不能把壞條件變成成功。
static func holds(condition: Variant, facts: Callable = Callable(), where: String = "$") -> bool:
	var problem := condition_error(condition, where)
	if not problem.is_empty():
		push_error("[StoryRules] " + problem)
		return false
	return _holds_valid(condition, facts if facts.is_valid() else Story.fact)


## 純結構檢查，不讀取任何事實。沿用共用條件樹的有界限制，但保留執行期葉節點契約。
static func condition_error(condition: Variant, where: String = "$") -> String:
	var problem := _condition_problem(condition, 1, [0])
	return (where.left(256) + problem).left(512) if not problem.is_empty() else ""


static func _condition_problem(raw: Variant, depth: int, budget: Array[int]) -> String:
	budget[0] += 1
	if depth > StoryConditionTree.MAX_DEPTH or budget[0] > StoryConditionTree.MAX_NODES:
		return ": 條件深度或節點數超過上限（含循環引用）"
	if not raw is Dictionary:
		return ": 條件必須是物件"
	if raw.is_empty():
		return ""
	for op in CONDITION_OPERATORS:
		if not raw.has(op):
			continue
		if raw.size() != 1:
			return _extra_condition_key(raw, op) + ": 條件不能混用運算或含額外欄位"
		if op == "not":
			var problem := _condition_problem(raw[op], depth + 1, budget)
			return ".not" + problem if not problem.is_empty() else ""
		var children: Variant = raw[op]
		if not children is Array or children.is_empty() or children.size() > StoryConditionTree.MAX_CHILDREN:
			return "." + op + ": 子條件必須是 1 到 %d 項的清單" % StoryConditionTree.MAX_CHILDREN
		for i in children.size():
			var problem := _condition_problem(children[i], depth + 1, budget)
			if not problem.is_empty():
				return ".%s[%d]" % [op, i] + problem
		return ""
	var op := ""
	if raw.has("flag"):
		op = "flag"
	elif raw.has("item"):
		op = "item"
	elif raw.has("receipt"):
		op = "receipt"
	elif raw.has("account"):
		op = "account"
	if op.is_empty():
		return _extra_condition_key(raw, "") + ": 未知條件運算"
	var companion := "status" if op == "receipt" else ("equals" if op != "item" else "")
	var expected_size := 1 + int(not companion.is_empty() and raw.has(companion))
	if raw.size() != expected_size:
		return _extra_condition_key(raw, op, companion) + ": 條件含額外欄位"
	if not _condition_id(raw[op]):
		return "." + op + ": 條件名稱必須是有效的非空文字 ID"
	if op == "flag":
		if raw.has("equals") and not _condition_scalar(raw["equals"]):
			return ".equals: 旗標比較值必須是有界的布林、文字或有限數字"
	elif op == "receipt":
		if not raw.has("status") or not (raw["status"] is String or raw["status"] is StringName) or String(raw["status"]) != "recorded":
			return ".status: 收據條件只接受 recorded"
	elif op == "account":
		if not raw.has("equals") or not (raw["equals"] is String or raw["equals"] is StringName) or String(raw["equals"]).is_empty() or String(raw["equals"]).length() > StoryConditionTree.MAX_TEXT_LENGTH:
			return ".equals: 帳務比較值必須是有界的非空文字"
	return ""


static func _extra_condition_key(raw: Dictionary, op: String, companion: String = "") -> String:
	for key: Variant in raw:
		if not (key is String or key is StringName):
			return "[非文字鍵]"
		if String(key) != op and String(key) != companion:
			return "." + String(key).left(64)
	return ""


static func _condition_id(raw: Variant) -> bool:
	if not (raw is String or raw is StringName):
		return false
	var text := String(raw)
	if text.is_empty() or text.length() > StoryConditionTree.MAX_ID_LENGTH:
		return false
	for i in text.length():
		var code := text.unicode_at(i)
		var letter := code >= 97 and code <= 122
		if (i == 0 and not letter) or (not letter and not (code >= 48 and code <= 57) and code != 95 and code != 46):
			return false
	return true


static func _condition_scalar(raw: Variant) -> bool:
	if raw is bool:
		return true
	if raw is String or raw is StringName:
		return String(raw).length() <= StoryConditionTree.MAX_TEXT_LENGTH
	return (raw is int or raw is float) and is_finite(float(raw)) and absf(float(raw)) <= StoryConditionTree.MAX_NUMBER


static func _holds_valid(raw: Dictionary, reader: Callable) -> bool:
	if raw.is_empty():
		return true
	if raw.has("all") or raw.has("any"):
		var all := raw.has("all")
		var children: Variant = raw["all"] if all else raw["any"]
		if not children is Array or (children as Array).is_empty():
			return false
		for child: Variant in children:
			if _holds_valid(child, reader) != all:
				return not all
		return all
	if raw.has("not"):
		return not _holds_valid(raw["not"], reader)
	if raw.has("flag"):
		return same_value(reader.call(&"flag", StringName(str(raw["flag"]))), raw.get("equals", true))
	if raw.has("item"):
		return bool(reader.call(&"held", StringName(str(raw["item"]))))
	if raw.has("receipt"):
		return str(raw.get("status", "")) == "recorded" and bool(reader.call(&"receipt", StringName(str(raw["receipt"]))))
	if raw.has("account"):
		return str(reader.call(&"account", StringName(str(raw["account"])))) == str(raw.get("equals", ""))
	return false


## 旗標比對：數字以數值比、其他型別必須相同；未設定（null）只等於 false、""、0 與 "unset"。
static func same_value(actual: Variant, expected: Variant) -> bool:
	if actual == null:
		return expected in [false, "", 0, 0.0, "unset"]
	var numeric := typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]
	if numeric:
		return float(actual) == float(expected)
	if (actual is String or actual is StringName) and (expected is String or expected is StringName):
		return str(actual) == str(expected)
	return typeof(actual) == typeof(expected) and actual == expected


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
