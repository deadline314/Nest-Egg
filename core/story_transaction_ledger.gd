class_name StoryTransactionLedger
extends RefCounted
## Progression 持有的有界一次交易收據；錢包仍只由 Progression 擁有。

const VERSION := 1
const MAX_RECEIPTS := 1024
const MESSAGES := {
	"ready": "這筆款項可以結算。", "applied": "這筆款項已結算。", "already_recorded": "這筆款項已經結算過。",
	"definition_changed": "這筆款項的記錄不同，請保留進度並更新遊戲。", "missing_requirement": "請先完成前一筆帳務。",
	"excluded": "這筆帳務已經採用另一種處理方式。", "insufficient_credits": "信用點不足，這筆款項尚未支付。",
	"wallet_limit": "信用點放不下，請先花用再領款。", "receipt_limit": "帳務記錄已滿，請保留進度。",
	"invalid_definition": "這筆帳務資料無法使用，進度仍保留。", "invalid_wallet": "信用點資料無法核對，這筆帳務尚未處理。",
	"ledger_locked": "帳務記錄無法核對，請保留進度並更新遊戲。", "busy": "前一筆帳務正在處理，請稍後再試。",
}

var _receipts: Dictionary = {}
var _locked := false
var _raw: Variant = null
var _raw_tree_safe := true


static func _invalid(where: String, reason: String, supported := true, tree_safe := true) -> Dictionary:
	var location := where if where.length() <= 256 else where.left(48) + "/…/" + where.right(205)
	var diagnostic := (location + ": " + reason.left(250)).left(512)
	return {"valid": false, "supported": supported, "tree_safe": tree_safe, "issues": PackedStringArray([diagnostic])}


## 純唯讀驗證；缺外層欄位是否為legacy由Progression判斷，null本身不是legacy。
static func validate_snapshot(raw: Variant, where: String = "run/progression/story_transactions") -> Dictionary:
	var tree_errors := RunSaveCodec.validate_tree(raw)
	if not tree_errors.is_empty():
		return _invalid(where, tree_errors[0], true, false)
	if not raw is Dictionary:
		return _invalid(where, "帳本必須是物件，原始證據保留")
	if not StoryTransactionData.integer_in(raw.get("version"), 1, int(RunSaveCodec.MAX_NUMBER)):
		return _invalid(where + "/version", "版本缺漏或不是有效整數")
	if raw["version"] != VERSION:
		return _invalid(where + "/version", "不支援的帳本版本，原始證據保留", false)
	if raw.size() != 2 or not raw.has("receipts") or not raw["receipts"] is Dictionary:
		return _invalid(where + "/receipts", "帳本欄位或收據清單無效")
	var receipts: Dictionary = raw["receipts"]
	if receipts.size() > MAX_RECEIPTS:
		return _invalid(where + "/receipts", "收據數量超過上限")
	for key: Variant in receipts:
		if not StoryTransactionData.valid_id(key):
			return _invalid(where + "/receipts", "收據事件編號無效")
		var path := where + "/receipts/" + String(key)
		var receipt: Variant = receipts[key]
		if not receipt is Dictionary or receipt.size() != 2:
			return _invalid(path, "收據必須包含指紋與金額")
		var fingerprint: Variant = receipt.get("definition_fingerprint")
		if not _valid_fingerprint(fingerprint):
			return _invalid(path + "/definition_fingerprint", "收據指紋無效")
		if not StoryTransactionData.integer_in(receipt.get("credits_delta"), -StoryTransactionData.MAX_DELTA, StoryTransactionData.MAX_DELTA):
			return _invalid(path + "/credits_delta", "收據金額不是有界整數")
	return {"valid": true, "supported": true, "tree_safe": true, "issues": PackedStringArray()}


static func _valid_fingerprint(raw: Variant) -> bool:
	if not raw is String or raw.length() != 64:
		return false
	var fingerprint: String = raw
	for i in 64:
		var code: int = fingerprint.unicode_at(i)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func reset() -> void:
	_receipts.clear()
	_locked = false
	_raw = null
	_raw_tree_safe = true


func restore(raw: Variant, present: bool, where: String = "run/progression/story_transactions") -> void:
	reset()
	if not present:
		return
	var validation := validate_snapshot(raw, where)
	_raw_tree_safe = validation["tree_safe"]
	if not validation["valid"]:
		_locked = true
		# 先有限驗證才複製。unsafe原參照只供既有Codec拒寫，不能洗成空帳本。
		_raw = raw.duplicate(true) if _raw_tree_safe and (raw is Dictionary or raw is Array) else raw
		push_warning("[StoryTransaction] %s；故事交易已鎖定" % validation["issues"][0])
		return
	for key: Variant in raw["receipts"]:
		var receipt: Dictionary = raw["receipts"][key]
		_receipts[String(key)] = {"definition_fingerprint": receipt["definition_fingerprint"], "credits_delta": int(receipt["credits_delta"])}


func snapshot() -> Variant:
	if _locked:
		return _raw.duplicate(true) if _raw_tree_safe and (_raw is Dictionary or _raw is Array) else _raw
	return {"version": VERSION, "receipts": _receipts.duplicate(true)}


func receipt_status(id: StringName) -> Dictionary:
	if _locked or not StoryTransactionData.valid_id(id):
		return {"status": "untrusted"}
	if not _receipts.has(String(id)):
		return {"status": "missing"}
	return {"status": "recorded", "receipt": (_receipts[String(id)] as Dictionary).duplicate(true)}


static func result(status: String, id: String, before: int, delta := 0) -> Dictionary:
	return {"status": status, "id": id, "applied": status == "applied", "credits_delta": delta,
		"credits_before": before, "credits_after": before + delta, "message": MESSAGES.get(status, MESSAGES["invalid_definition"])}


func _proposal(transaction: StoryTransactionData, wallet: int, maximum: int) -> Dictionary:
	var id := String(transaction.id).left(64) if transaction != null else ""
	if _locked:
		return result("ledger_locked", id, wallet)
	if transaction == null:
		return result("invalid_definition", id, wallet)
	var description := transaction.descriptor()
	if description.has("error"):
		push_warning("[StoryTransaction] %s：%s" % [id, description["error"]])
		return result("invalid_definition", id, wallet)
	id = description["id"]
	if _receipts.has(id):
		var recorded: Dictionary = _receipts[id]
		var matches: bool = recorded["definition_fingerprint"] == description["fingerprint"] and recorded["credits_delta"] == description["credits_delta"]
		return result("already_recorded" if matches else "definition_changed", id, wallet)
	for key: String in description["required"]:
		if not _receipts.has(key):
			return result("missing_requirement", id, wallet)
	for key: String in description["excluded"]:
		if _receipts.has(key):
			return result("excluded", id, wallet)
	if _receipts.size() >= MAX_RECEIPTS:
		return result("receipt_limit", id, wallet)
	if wallet < 0 or wallet > maximum:
		return result("invalid_wallet", id, wallet)
	var delta: int = description["credits_delta"]
	if wallet + delta < 0:
		return result("insufficient_credits", id, wallet)
	if wallet + delta > maximum:
		return result("wallet_limit", id, wallet)
	var proposal := result("applied", id, wallet, delta)
	proposal["receipt"] = {"definition_fingerprint": description["fingerprint"], "credits_delta": delta}
	return proposal


func status(transaction: StoryTransactionData, wallet: int, maximum: int) -> Dictionary:
	var proposal := _proposal(transaction, wallet, maximum)
	proposal.erase("receipt")
	if proposal["applied"]:
		var ready := result("ready", proposal["id"], wallet)
		ready["planned_delta"] = proposal["credits_delta"]
		ready["planned_after"] = proposal["credits_after"]
		return ready
	return proposal


## 同步無回呼；Progression立即設定新錢包，兩者完成後才發通知。
func commit(transaction: StoryTransactionData, wallet: int, maximum: int) -> Dictionary:
	var proposal := _proposal(transaction, wallet, maximum)
	if proposal["applied"]:
		_receipts[proposal["id"]] = proposal["receipt"]
	proposal.erase("receipt")
	return proposal
