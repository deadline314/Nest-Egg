extends RefCounted
## NE-231：測真錢包與完整快照；既有 EconomySuite 負責註冊及執行。


static func run(suite: TestSuite) -> void:
	var original := Progression.snapshot()
	_test_commit(suite)
	_test_meal(suite)
	_test_restore(suite)
	_test_bounds(suite)
	Progression.restore(original)


static func _definition(id: String, delta: int, requires: Array = [], excludes: Array = []) -> StoryTransactionData:
	var data := StoryTransactionData.new()
	data.id = StringName(id)
	data.credits_delta = delta
	data.requires_receipts = PackedStringArray(requires)
	data.excludes_receipts = PackedStringArray(excludes)
	return data


static func _load(name: String) -> StoryTransactionData:
	return load("res://data/story_transactions/%s.tres" % name) as StoryTransactionData


static func _test_commit(s: TestSuite) -> void:
	Progression.reset_run()
	var award := _load("ch1_commission_settled")
	s.check(award != null, "settlement has production transaction data")
	if award == null:
		return
	var ready := Progression.story_transaction_status(award)
	s.check(ready["status"] == "ready" and not ready["applied"] and ready["planned_after"] == 720 and Progression.credits == 0 and Progression.story_receipt_status(award.id)["status"] == "missing", "read-only preflight never claims a commit or writes a receipt")
	var observed: Array = []
	var callback := func(amount: int, delta: int) -> void:
		if delta != 720:
			return
		observed.append([amount, Progression.story_receipt_status(award.id)["status"]])
		observed.append(Progression.apply_story_transaction(award)["status"])
		Progression.spend(20)
	Progression.credits_changed.connect(callback)
	var result := Progression.apply_story_transaction(award)
	Progression.credits_changed.disconnect(callback)
	s.check(observed == [[720, "recorded"], "busy"], "wallet callback sees receipt and cannot reenter settlement")
	s.check(result["applied"] and result["credits_before"] == 0 and result["credits_after"] == 720 and result["credits_delta"] == 720, "commit result reports its own values before callback spending")
	s.check(Progression.credits == 700, "ordinary callback spending remains separate from settlement")
	s.check(Progression.apply_story_transaction(award)["status"] == "already_recorded" and Progression.credits == 700, "a repeated settlement cannot pay twice")
	var receipt := Progression.story_receipt_status(award.id)
	receipt["receipt"]["credits_delta"] = 999
	s.check(Progression.story_receipt_status(award.id)["receipt"]["credits_delta"] == 720, "returned receipt cannot mutate stored evidence")
	var drift := _definition("ch1.commission.settled", 721)
	s.check(Progression.apply_story_transaction(drift)["status"] == "definition_changed" and Progression.credits == 700, "same event with changed definition never tops up or pays again")
	drift.definition_version = 2
	s.check(Progression.apply_story_transaction(drift)["status"] == "invalid_definition" and Progression.credits == 700, "unsupported definition cannot replace recorded event")
	Progression.reset_run()
	Progression.add_credits(99500)
	var before := Progression.snapshot()
	s.check(Progression.apply_story_transaction(award)["status"] == "wallet_limit" and Progression.snapshot() == before, "overflow refuses entire reward and creates no receipt")
	Progression.spend(221)
	s.check(Progression.apply_story_transaction(award)["applied"] and Progression.credits == 99999, "exact remaining capacity accepts the entire reward")
	var notices: Array = []
	var notify := func(id: StringName) -> void: notices.append(id)
	Progression.story_transaction_committed.connect(notify)
	var free := _load("ch1_daily_dinner")
	s.check(Progression.apply_story_transaction(free)["applied"] and Progression.credits == 99999, "first daily dinner costs zero even at wallet capacity")
	Progression.apply_story_transaction(free)
	Progression.story_transaction_committed.disconnect(notify)
	s.check(notices == [free.id], "zero transaction emits exactly one commit notice without claiming autosave")
	Progression.reset_run()


static func _test_meal(s: TestSuite) -> void:
	var order := _load("ch1_revival_meal_order")
	var paid := _load("ch1_revival_meal_paid")
	var gift := _load("ch1_revival_meal_gift")
	var tab := _load("ch1_revival_meal_tab")
	var later := _load("ch1_revival_meal_later_pay")
	Progression.reset_run()
	Progression.add_credits(720)
	for decision in [paid, gift, tab, later]:
		s.check(Progression.apply_story_transaction(decision)["status"] == "missing_requirement", "no order cannot create meal decision: %s" % decision.id)
	s.check(Progression.snapshot()["story_transactions"]["receipts"].is_empty() and Progression.credits == 720, "without order there is no 200 bill or money movement")
	Progression.apply_story_transaction(order)
	Progression.spend(521)
	var before := Progression.snapshot()
	s.check(Progression.apply_story_transaction(paid)["status"] == "insufficient_credits" and Progression.snapshot() == before, "199 cannot partially pay 200 or silently become a tab")
	Progression.add_credits(1)
	s.check(Progression.apply_story_transaction(paid)["applied"] and Progression.credits == 0, "paid meal charges exactly 200")
	for decision in [gift, tab, later]:
		s.check(not Progression.apply_story_transaction(decision)["applied"] and Progression.credits == 0, "paid meal cannot change into another result: %s" % decision.id)
	Progression.reset_run()
	Progression.apply_story_transaction(order)
	s.check(Progression.apply_story_transaction(gift)["applied"] and Progression.credits == 0, "meal gift waives bill and never invents a 200 refund")
	for decision in [paid, tab, later]:
		s.check(not Progression.apply_story_transaction(decision)["applied"], "gift blocks billing and later payment: %s" % decision.id)
	Progression.reset_run()
	Progression.apply_story_transaction(order)
	Progression.apply_story_transaction(tab)
	s.check(Progression.credits == 0 and not Progression.apply_story_transaction(later)["applied"], "tab adds no cash and cannot be paid without funds")
	Progression.apply_story_transaction(_load("ch1_commission_settled"))
	s.check(Progression.credits == 720, "tab does not automatically offset commission or charge forty")
	s.check(Progression.apply_story_transaction(later)["applied"] and Progression.credits == 520, "explicit later payment settles only the meal's 200")
	s.check(Progression.story_receipt_status(tab.id)["status"] == "recorded" and Progression.story_receipt_status(later.id)["status"] == "recorded", "settled tab retains both debt and payment history")
	s.check(not Progression.apply_story_transaction(later)["applied"] and Progression.credits == 520, "repeated debt payment cannot charge twice")
	s.check(not Progression.apply_story_transaction(paid)["applied"] and not Progression.apply_story_transaction(gift)["applied"], "tab history prevents switching to paid or gift after settlement")
	Progression.reset_run()


static func _test_restore(s: TestSuite) -> void:
	Progression.reset_run()
	var award := _load("ch1_commission_settled")
	Progression.apply_story_transaction(award)
	var checkpoint := Progression.snapshot()
	var copied := Progression.snapshot()
	copied["story_transactions"]["receipts"][String(award.id)]["credits_delta"] = 0
	s.check(Progression.story_receipt_status(award.id)["receipt"]["credits_delta"] == 720, "snapshot receipt map is a deep copy of live evidence")
	Progression.apply_story_transaction(_definition("test.after_checkpoint", 100))
	Progression.restore(JSON.parse_string(JSON.stringify(checkpoint)))
	s.check(Progression.credits == 720 and Progression.story_receipt_status(&"test.after_checkpoint")["status"] == "missing", "checkpoint rollback restores money and receipt together through JSON")
	s.check(not Progression.apply_story_transaction(award)["applied"] and Progression.credits == 720, "pre-checkpoint reward remains paid after retry")
	Progression.apply_story_transaction(_definition("test.after_checkpoint", 100))
	s.check(Progression.credits == 820, "repeating a rolled-back event produces the same total, no extra income")
	var unknown := Progression.snapshot()
	Progression.restore(unknown)
	s.check(not Progression.apply_story_transaction(_definition("test.after_checkpoint", 100))["applied"], "valid receipt with no catalog definition still protects its stable ID")
	var conflicting: Dictionary = checkpoint.duplicate(true)
	conflicting["story_transactions"]["receipts"][String(award.id)]["credits_delta"] = 719
	Progression.restore(conflicting)
	var before_conflict := Progression.snapshot()
	var conflict_status := Progression.story_transaction_status(award)
	s.check(conflict_status["status"] == "definition_changed" and not conflict_status["applied"] and Progression.snapshot() == before_conflict, "same fingerprint with corrupted receipt amount refuses preflight without mutation")
	var conflict_apply := Progression.apply_story_transaction(award)
	s.check(conflict_apply["status"] == "definition_changed" and not conflict_apply["applied"] and Progression.snapshot() == before_conflict and Progression.credits == 720 and Progression.story_receipt_status(award.id)["receipt"]["credits_delta"] == 719, "same fingerprint with corrupted receipt amount refuses commit and preserves wallet and evidence")
	var legacy := checkpoint.duplicate(true)
	legacy.erase("story_transactions")
	Progression.restore(legacy)
	s.check(Progression.story_receipt_status(award.id)["status"] == "missing", "only absent ledger field is legacy empty")
	var future := {"version": 2, "receipts": {"old.event": {"definition_fingerprint": "a".repeat(64), "credits_delta": 720}}}
	var validated := StoryTransactionLedger.validate_snapshot(future, "test/future")
	s.check(not validated["valid"] and not validated["supported"] and validated["issues"].size() == 1, "unsupported numeric version is explicitly invalid and unsupported")
	Progression.restore({"credits": 100, "story_transactions": future})
	future["receipts"]["old.event"]["credits_delta"] = 0
	var protected_copy := Progression.snapshot()
	protected_copy["story_transactions"]["version"] = 1
	protected_copy["story_transactions"]["receipts"].clear()
	s.check(Progression.snapshot()["story_transactions"]["version"] == 2 and Progression.snapshot()["story_transactions"]["receipts"]["old.event"]["credits_delta"] == 720, "unsupported raw evidence owns a bounded copy and returns independent snapshots")
	s.check(Progression.apply_story_transaction(award)["status"] == "ledger_locked", "mutating source or returned future snapshot cannot unlock transactions")
	for raw: Variant in [null, "bad", {}, {"version": null, "receipts": {}}, {"version": "1", "receipts": {}}, {"version": 1.5, "receipts": {}}, {"version": 2, "receipts": {}}, {"version": 1, "receipts": {"ch1.commission.settled": {"credits_delta": 720}}}]:
		Progression.restore({"credits": 100, "story_transactions": raw})
		s.check(Progression.apply_story_transaction(award)["status"] == "ledger_locked" and Progression.credits == 100, "malformed/present ledger never becomes a fresh claim: %s" % [raw])
		s.check(Progression.snapshot()["story_transactions"] == raw, "failed restore preserves bounded raw receipt evidence")
		s.check(Progression.spend(60), "locked story ledger does not prevent normal purchases")
		var med := ConsumableBag.find(&"med_injector")
		s.check(Progression.pawn(med) == 30 and Progression.redeem(med) and Progression.credits == 34, "locked ledger keeps ordinary pawn and redeem safe")
		Progression.restore(Progression.snapshot())
		s.check(Progression.apply_story_transaction(award)["status"] == "ledger_locked", "saving a bad ledger cannot reopen reward claims")
	Progression.reset_run()
	s.check(Progression.apply_story_transaction(award)["applied"], "explicit new run resets prior receipts and corruption lock")
	var malformed: Dictionary = checkpoint["story_transactions"].duplicate(true)
	for value: Variant in [true, "720", null, NAN, INF, 720.5, 100000]:
		malformed["receipts"][String(award.id)]["credits_delta"] = value
		s.check(not StoryTransactionLedger.validate_snapshot(malformed, "test/ledger")["valid"], "nonintegral or out-of-range receipt amount is rejected")
	malformed["receipts"][String(award.id)]["credits_delta"] = 720
	for fingerprint in ["-" + "a".repeat(63), "A".repeat(64), "g".repeat(64), "a".repeat(63)]:
		malformed["receipts"][String(award.id)]["definition_fingerprint"] = fingerprint
		s.check(not StoryTransactionLedger.validate_snapshot(malformed, "test/ledger")["valid"], "fingerprint must be exactly lowercase hexadecimal, without sign")
	var reordered_a := _definition("test.canonical", 0, ["test.one", "test.two"])
	var reordered_b := _definition("test.canonical", 0, ["test.two", "test.one"])
	Progression.reset_run()
	Progression.apply_story_transaction(_definition("test.one", 0))
	Progression.apply_story_transaction(_definition("test.two", 0))
	Progression.apply_story_transaction(reordered_a)
	s.check(Progression.apply_story_transaction(reordered_b)["status"] == "already_recorded", "dependency ordering does not drift a definition fingerprint")
	Progression.reset_run()


static func _test_bounds(s: TestSuite) -> void:
	Progression.reset_run()
	for i in 1024:
		Progression.apply_story_transaction(_definition("test.capacity_%d" % i, 0))
	var before := Progression.snapshot()
	s.check(Progression.apply_story_transaction(_definition("test.capacity_extra", 10))["status"] == "receipt_limit" and Progression.snapshot() == before, "full ledger refuses new payment without evicting receipts")
	s.check(Progression.apply_story_transaction(_definition("test.capacity_0", 0))["status"] == "already_recorded", "capacity cannot erase oldest duplicate protection")
	var over: Dictionary = before["story_transactions"].duplicate(true)
	over["receipts"]["test.extra"] = {"definition_fingerprint": "a".repeat(64), "credits_delta": 0}
	s.check(not StoryTransactionLedger.validate_snapshot(over, "test/ledger")["valid"], "oversized receipt map fails closed")
	Progression.reset_run()
	for invalid in [_definition("bad-id", 1), _definition("a".repeat(65), 1), _definition("test.self", 1, ["test.self"]), _definition("test.overlap", 1, ["test.one"], ["test.one"]), _definition("test.duplicate_required", 1, ["test.one", "test.one"]), _definition("test.duplicate_excluded", 1, [], ["test.one", "test.one"])]:
		s.check(Progression.apply_story_transaction(invalid)["status"] == "invalid_definition" and Progression.credits == 0, "invalid definition cannot move credits")
	for broken_wallet in [-1, 100000]:
		Progression.credits = broken_wallet
		s.check(Progression.apply_story_transaction(_definition("test.bad_wallet", 720))["status"] == "invalid_wallet" and Progression.credits == broken_wallet and Progression.story_receipt_status(&"test.bad_wallet")["status"] == "missing", "invalid wallet rejects story payment without a receipt or partial mutation")
	Progression.reset_run()
	var many := _definition("test.many", 720)
	for i in 33:
		many.requires_receipts.append("test.dependency_%d" % i)
	s.check(Progression.apply_story_transaction(many)["status"] == "invalid_definition" and Progression.credits == 0, "excess dependency fanout rejects before creating a payment")
	var unsafe: Dictionary = {}
	var cursor := unsafe
	for i in 18:
		cursor["child"] = {}
		cursor = cursor["child"]
	var validation := StoryTransactionLedger.validate_snapshot(unsafe, "test/ledger")
	s.check(not validation["valid"] and validation["issues"].size() == 1 and validation["issues"][0].length() <= 512, "unsafe raw tree returns one bounded diagnostic")
	Progression.restore({"credits": 100, "story_transactions": unsafe})
	var saved := Progression.snapshot()
	s.check(is_same(saved["story_transactions"], unsafe), "tree-unsafe evidence is retained by reference without deep copy")
	s.check(RunSaveCodec.encode(saved).is_empty(), "unsafe ledger stays unsavable so existing store cannot overwrite old slot")
	s.check(Progression.apply_story_transaction(_definition("test.unsafe_claim", 720))["status"] == "ledger_locked" and Progression.spend(60), "unsafe evidence blocks regrant but not normal spending")
	Progression.reset_run()
