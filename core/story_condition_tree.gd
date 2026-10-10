class_name StoryConditionTree
extends RefCounted
## 純條件合約；呼叫端提供可信服務快照，不讀 autoload、不寫入任何狀態。

const MAX_DEPTH := 16
const MAX_NODES := 256
const MAX_CHILDREN := 32
const MAX_ID_LENGTH := 64
const MAX_FACTS := 1024
const MAX_TEXT_LENGTH := 256
const MAX_NUMBER := 999999999
const MEAL_IDS := ["ch1.revival_meal.order", "ch1.revival_meal.paid", "ch1.revival_meal.tab", "ch1.revival_meal.gift", "ch1.revival_meal.later_pay"]
## 此階段受支援的正式資源 ID；金額與指紋只來自 current descriptor。
const TRANSACTION_IDS := ["ch1.daily_dinner", "ch1.commission.settled", "ch1.revival_meal.order", "ch1.revival_meal.paid", "ch1.revival_meal.tab", "ch1.revival_meal.gift", "ch1.revival_meal.later_pay"]
## 與作者 ACCOUNT_RECEIPTS 一致，mask 位元順序由 MEAL_IDS 定義。
const ACCOUNT_MASKS := {0: "none", 1: "open200", 3: "paid200", 5: "owed200", 9: "gifted200", 21: "paid200"}


static func _result(value: bool) -> Dictionary:
	return {"valid": true, "value": value, "error": ""}


static func _invalid(where: String, reason: String) -> Dictionary:
	return {"valid": false, "value": false, "error": (where.left(384) + ": " + reason).left(512)}


static func _id(raw: Variant) -> bool:
	if not raw is String or raw.is_empty() or raw.length() > MAX_ID_LENGTH:
		return false
	for i in raw.length():
		var code: int = raw.unicode_at(i)
		var letter := code >= 97 and code <= 122
		if (i == 0 and not letter) or (not letter and not (code >= 48 and code <= 57) and code not in [95, 46]):
			return false
	return true


static func _scalar(raw: Variant) -> bool:
	if raw is bool:
		return true
	if raw is String:
		return raw.length() <= MAX_TEXT_LENGTH
	return typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) and absf(float(raw)) <= MAX_NUMBER


static func _keys(raw: Dictionary, expected: Array) -> bool:
	if raw.size() != expected.size():
		return false
	for key: Variant in raw:
		if not key is String or not expected.has(key):
			return false
	return true


## 空物件是作者的無前置條件；空 all/any、未知欄位及型別一律無效。
static func validate(condition: Variant) -> Dictionary:
	return _validate(condition, "$", 1, {"nodes": 0})


static func _validate(raw: Variant, where: String, depth: int, budget: Dictionary) -> Dictionary:
	budget["nodes"] += 1
	if depth > MAX_DEPTH or budget["nodes"] > MAX_NODES:
		return _invalid(where, "條件深度或節點數超過上限（含循環引用）")
	if not raw is Dictionary:
		return _invalid(where, "條件必須是物件")
	if raw.is_empty():
		return _result(true)
	for op in ["all", "any", "not"]:
		if _keys(raw, [op]):
			if op == "not":
				return _validate(raw[op], where + ".not", depth + 1, budget)
			var children: Variant = raw[op]
			if not children is Array or children.is_empty() or children.size() > MAX_CHILDREN:
				return _invalid(where + "." + op, "子條件數量必須介於 1 與 %d" % MAX_CHILDREN)
			for i in children.size():
				var child := _validate(children[i], "%s.%s[%d]" % [where, op, i], depth + 1, budget)
				if not child["valid"]:
					return child
			return _result(true)
	if _keys(raw, ["flag", "equals"]) and _id(raw["flag"]) and _scalar(raw["equals"]):
		return _result(true)
	if _keys(raw, ["item"]) and _id(raw["item"]):
		return _result(true)
	if _keys(raw, ["receipt", "status"]) and raw["receipt"] is String and TRANSACTION_IDS.has(raw["receipt"]) and raw["status"] is String and raw["status"] == "recorded":
		return _result(true)
	if _keys(raw, ["account", "equals"]) and raw["account"] is String and raw["account"] == "ch1_lounge" and raw["equals"] is String and ACCOUNT_MASKS.values().has(raw["equals"]):
		return _result(true)
	return _invalid(where, "未知或格式錯誤的條件")


## facts: flags / items / ledger；context: ledger_locked / transaction_definitions。
## 不接受替代帳務旗標、函式回呼、狀態別名；所有輸入與內部 const 均唯讀。
static func evaluate(condition: Variant, facts: Variant, context: Variant = {}) -> Dictionary:
	var schema := validate(condition)
	if not schema["valid"]:
		return schema
	var checked := _validate_facts(facts, context)
	if not checked["valid"]:
		return checked
	return _evaluate(condition, facts, context, "$", {})


## 即使沒有帳務條件，也能驗證整份帳本；成功的 account 只供當次判定。
static func verify_ledger(facts: Variant, context: Variant) -> Dictionary:
	var checked := _validate_facts(facts, context)
	if not checked["valid"]:
		return checked
	return _verified_ledger(facts, context)


static func _validate_facts(facts: Variant, context: Variant) -> Dictionary:
	if not facts is Dictionary or not context is Dictionary:
		return _invalid("facts/context", "必須由可信呼叫端提供物件")
	if facts.size() > 3 or context.size() > 2:
		return _invalid("facts/context", "欄位數超過契約上限")
	for pair in [[facts, ["flags", "items", "ledger"], "facts"], [context, ["ledger_locked", "transaction_definitions"], "context"]]:
		for key: Variant in pair[0]:
			if not key is String or not pair[1].has(key):
				return _invalid(pair[2], "未知欄位或別名")
	for name in ["flags", "items"]:
		if facts.has(name):
			var values: Variant = facts[name]
			if not values is Dictionary or values.size() > MAX_FACTS:
				return _invalid("facts." + name, "事實必須是有界物件")
			for key: Variant in values:
				if not _id(key):
					return _invalid("facts." + name, "事實名稱無效")
				if (name == "flags" and not _scalar(values[key])) or (name == "items" and not values[key] is bool):
					return _invalid("facts." + name + "." + key, "事實型別無效")
	return _result(true)


static func _evaluate(raw: Dictionary, facts: Dictionary, context: Dictionary, where: String, cache: Dictionary) -> Dictionary:
	if raw.is_empty():
		return _result(true)
	if raw.has("not"):
		var child := _evaluate(raw["not"], facts, context, where + ".not", cache)
		return _result(not child["value"]) if child["valid"] else child
	for op in ["all", "any"]:
		if raw.has(op):
			var value: bool = op == "all"
			for i in raw[op].size():
				var child := _evaluate(raw[op][i], facts, context, "%s.%s[%d]" % [where, op, i], cache)
				if not child["valid"]:
					return child
				# 每支都已求值：false all / true any 不可隱藏壞事實。
				value = (value and child["value"]) if op == "all" else (value or child["value"])
			return _result(value)
	if raw.has("flag") or raw.has("item"):
		var op := "flag" if raw.has("flag") else "item"
		var name := "flags" if op == "flag" else "items"
		if not facts.has(name) or not facts[name].has(raw[op]):
			return _invalid(where, "尚未宣告的 %s 事實：%s" % [op, raw[op]])
		var actual: Variant = facts[name][raw[op]]
		if op == "item":
			return _result(actual)
		var expected: Variant = raw["equals"]
		var numeric := typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]
		return _result((numeric or typeof(actual) == typeof(expected)) and actual == expected)
	if not cache.has("ledger"):
		cache["ledger"] = _verified_ledger(facts, context)
	var ledger: Dictionary = cache["ledger"]
	if not ledger["valid"]:
		return _invalid(where, ledger["error"])
	if raw.has("receipt"):
		return _result(facts["ledger"]["receipts"].has(raw["receipt"]))
	return _result(ledger["account"] == raw["equals"])


static func _fingerprint(raw: Variant) -> bool:
	if not raw is String or raw.length() != 64:
		return false
	for i in 64:
		var code: int = raw.unicode_at(i)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


static func _integer(raw: Variant, maximum: int) -> bool:
	return typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) and absf(float(raw)) <= maximum and floorf(float(raw)) == float(raw)


static func _verified_ledger(facts: Dictionary, context: Dictionary) -> Dictionary:
	if not context.has("ledger_locked") or not context["ledger_locked"] is bool or context["ledger_locked"]:
		return _invalid("context.ledger_locked", "帳本鎖定或信任狀態不明")
	var definitions: Variant = context.get("transaction_definitions")
	if not definitions is Dictionary or not _keys(definitions, TRANSACTION_IDS):
		return _invalid("context.transaction_definitions", "七個現行資源定義必須全部提供")
	for id: String in TRANSACTION_IDS:
		var definition: Variant = definitions[id]
		if not definition is Dictionary or not _keys(definition, ["id", "credits_delta", "required", "excluded", "fingerprint"]):
			return _invalid("definitions." + id, "現行定義描述無效")
		if not definition["id"] is String or definition["id"] != id or not _integer(definition["credits_delta"], 99999):
			return _invalid("definitions." + id, "現行資源編號或金額無效")
		var required: Variant = definition["required"]
		var excluded: Variant = definition["excluded"]
		if not required is Array or not excluded is Array or required.size() > MAX_CHILDREN or excluded.size() > MAX_CHILDREN:
			return _invalid("definitions." + id, "現行資源條件清單無效")
		var used := {}
		for pair in [[required, "required"], [excluded, "excluded"]]:
			var previous := ""
			for dependency: Variant in pair[0]:
				if not _id(dependency) or not TRANSACTION_IDS.has(dependency) or dependency == id or used.has(dependency) or String(dependency) < previous:
					return _invalid("definitions." + id + "." + pair[1], "條件編號未知、重複、自我引用、互斥或未排序")
				used[dependency] = true
				previous = dependency
		var fingerprint := JSON.stringify([id, 1, int(definition["credits_delta"]), required, excluded]).sha256_text()
		if not _fingerprint(definition["fingerprint"]) or definition["fingerprint"] != fingerprint:
			return _invalid("definitions." + id, "現行資源指紋與其描述不一致")
	var snapshot: Variant = facts.get("ledger")
	if not snapshot is Dictionary or not _keys(snapshot, ["version", "receipts"]) or not _integer(snapshot["version"], 1) or snapshot["version"] != 1:
		return _invalid("facts.ledger", "帳本版本或格式不可信")
	var receipts: Variant = snapshot["receipts"]
	if not receipts is Dictionary or receipts.size() > MAX_FACTS:
		return _invalid("facts.ledger.receipts", "收據清單無效")
	for id: Variant in receipts:
		if not id is String or not TRANSACTION_IDS.has(id):
			return _invalid("facts.ledger.receipts", "收據沒有受支援的現行資源")
		var receipt: Variant = receipts[id]
		if not receipt is Dictionary or not _keys(receipt, ["definition_fingerprint", "credits_delta"]):
			return _invalid("receipts." + id, "收據格式不可信")
		if not _fingerprint(receipt["definition_fingerprint"]) or receipt["definition_fingerprint"] != definitions[id]["fingerprint"] or not _integer(receipt["credits_delta"], 99999) or receipt["credits_delta"] != definitions[id]["credits_delta"]:
			return _invalid("receipts." + id, "收據指紋或金額與現行資源不一致")
		for required: String in definitions[id]["required"]:
			if not receipts.has(required):
				return _invalid("receipts." + id, "收據前置條件遺失：" + required)
		for excluded: String in definitions[id]["excluded"]:
			if receipts.has(excluded):
				return _invalid("receipts." + id, "收據互斥條件衝突：" + excluded)
	var mask := 0
	for i in MEAL_IDS.size():
		if receipts.has(MEAL_IDS[i]):
			mask |= 1 << i
	if not ACCOUNT_MASKS.has(mask):
		return _invalid("facts.ledger.receipts", "餐費收據集合沒有唯一合法帳務狀態")
	var result := _result(true)
	result["account"] = ACCOUNT_MASKS[mask]
	return result
