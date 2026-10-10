extends RefCounted
## Existing EconomySuite exercises pure proposals; fixtures are not production bindings.

const Planner = preload("res://core/story_result_plan.gd")
const ORDER := "ch1.revival_meal.order"
const PAID := "ch1.revival_meal.paid"
const GIFT := "ch1.revival_meal.gift"
const DISK := "ch1_data_disk"
const CLOTH := "ch1_grey_cloth"
const SCENE := "test_result_scene"


static func _context(operations: Array, condition: Dictionary = {}) -> Dictionary:
	var definitions := {}
	for name: String in ["ch1_daily_dinner", "ch1_commission_settled", "ch1_revival_meal_order", "ch1_revival_meal_paid", "ch1_revival_meal_tab", "ch1_revival_meal_gift", "ch1_revival_meal_later_pay"]:
		var resource := load("res://data/story_transactions/%s.tres" % name) as StoryTransactionData
		if resource != null:
			definitions[String(resource.id)] = resource.descriptor()
	var items := {}
	for id: String in [DISK, CLOTH]:
		var resource := load("res://data/story_items/%s.tres" % id) as StoryItemData
		if resource != null:
			items[id] = {"trigger": resource.trigger}
	var producers := {}
	for operation: Dictionary in operations:
		var capability := "scene_completion"
		if operation["kind"] == "item_acquire":
			capability = "scene_manual_item"
		elif operation["kind"] == "item_transfer":
			capability = "item_transfer"
		var producer := {"scene_id": SCENE, "source": "res://tests/helpers/story_result_plan_checks.gd", "capability": capability}
		if operation["kind"] == "item_transfer":
			producer["destination"] = "test_cabinet"
		producers[operation["kind"] + ":" + operation["id"]] = [producer]
	return {"scene_id": SCENE, "replay": false, "scenes": {SCENE: {"once": true, "condition": condition, "results": operations}, "test_earlier_segment": {"once": true, "condition": {}, "results": []}},
		"flag_defaults": {"test_done": false, "test_route": "unset"}, "item_definitions": items,
		"transaction_definitions": definitions, "producers": producers, "ledger_locked": false}


static func _snapshot(credits: int = 200) -> Dictionary:
	return {"flags": {}, "items": {"custody_version": 1, "owned": [], "unseen": [], "held": [], "transferred": []},
		"credits": credits, "ledger": {"version": 1, "receipts": {}}, "area_states": {"test_area": {"consumed": {}, "damage": {}, "world": {}}}, "completed": ["test_earlier_segment"]}


static func _tx(id: String) -> Dictionary:
	return {"kind": "transaction", "id": id}


static func _flag() -> Dictionary:
	return {"kind": "flag", "id": "test_done", "value": true}


static func _receipt(state: Dictionary, context: Dictionary, id: String) -> void:
	var definition: Dictionary = context["transaction_definitions"][id]
	state["ledger"]["receipts"][id] = {"definition_fingerprint": definition["fingerprint"], "credits_delta": definition["credits_delta"]}


static func _refused(suite: TestSuite, operations: Array, state: Dictionary, context: Dictionary, status: String, description: String) -> void:
	var before := JSON.stringify([operations, state, context])
	var proposal := Planner.plan(operations, state, context)
	suite.check(not proposal["valid"] and proposal["status"] == status and proposal["error"].contains(":"), description + " refuses precisely: " + str(proposal))
	suite.check(not proposal.has("next") and not proposal.has("events") and JSON.stringify([operations, state, context]) == before, description + " has no partial proposal and leaves every input byte unchanged")


static func run(suite: TestSuite) -> void:
	_test_atomic_money(suite)
	_test_custody(suite)
	_test_world(suite)
	_test_rejections(suite)
	_test_aliases(suite)


static func _test_atomic_money(s: TestSuite) -> void:
	var operations := [_flag(), _tx(ORDER), _tx(PAID)]
	var context := _context(operations, {"account": "ch1_lounge", "equals": "none"})
	var state := _snapshot(199)
	_refused(s, operations, state, context, "insufficient_credits", "199 cannot partially write flags, order, or a 200 payment")
	state["credits"] = 200
	var before := JSON.stringify([operations, state, context])
	var proposal := Planner.plan(operations, state, context)
	s.check(proposal["valid"] and proposal["next"]["credits"] == 0 and proposal["next"]["ledger"]["receipts"].has(PAID) and proposal["next"]["flags"]["test_done"], "in-list order then paid uses canonical resource guards and plans all results")
	s.check(proposal["next"]["completed"] == ["test_earlier_segment", SCENE] and JSON.stringify([operations, state, context]) == before, "start none condition is not rerun after order; earlier completion and every input remain intact")
	_refused(s, operations, proposal["next"], context, "already_completed", "completed scene cannot rebill even though its original condition changed")
	operations = [_tx("ch1.daily_dinner"), _flag()]
	context = _context(operations)
	state = _snapshot(99999)
	proposal = Planner.plan(operations, state, context)
	s.check(proposal["valid"] and proposal["next"]["credits"] == 99999 and proposal["next"]["ledger"]["receipts"].has("ch1.daily_dinner") and proposal["events"][0]["credits_delta"] == 0, "free daily dinner still plans a real zero receipt and completion event")
	state = proposal["next"].duplicate(true)
	state["completed"].erase(SCENE)
	proposal = Planner.plan(operations, state, context)
	s.check(proposal["valid"] and proposal["events"].size() == 2 and proposal["next"]["credits"] == 99999, "same canonical receipt resumes incomplete segment without charging or re-notifying that transaction")
	operations = [_tx(PAID), _tx(ORDER)]
	_refused(s, operations, _snapshot(), _context(operations), "missing_requirement", "paid before order fails without reordering authored effects")
	operations = [_tx(ORDER), _tx(PAID), _tx(GIFT)]
	_refused(s, operations, _snapshot(), _context(operations), "excluded", "paid plus gift rejects the whole batch")
	operations = [_tx("ch1.commission.settled")]
	_refused(s, operations, _snapshot(99999), _context(operations), "wallet_limit", "whole canonical reward cannot overflow the wallet")
	operations = [_flag()]
	context = _context(operations)
	for corruption: String in ["fingerprint", "delta", "dual", "missing", "unknown", "version", "locked"]:
		state = _snapshot()
		var changed := context.duplicate(true)
		_receipt(state, changed, ORDER)
		_receipt(state, changed, PAID)
		match corruption:
			"fingerprint": state["ledger"]["receipts"][PAID]["definition_fingerprint"] = "0".repeat(64)
			"delta": state["ledger"]["receipts"][PAID]["credits_delta"] = 0
			"dual": _receipt(state, changed, GIFT)
			"missing": state["ledger"]["receipts"].erase(ORDER)
			"unknown": state["ledger"]["receipts"]["test.unknown"] = state["ledger"]["receipts"][PAID].duplicate(true)
			"version": state["ledger"]["version"] = 2
			"locked": changed["ledger_locked"] = true
		_refused(s, operations, state, changed, "invalid_ledger", "existing receipt evidence " + corruption)
	state = _snapshot()
	_receipt(state, context, ORDER)
	var drifted := context.duplicate(true)
	var description: Dictionary = drifted["transaction_definitions"][ORDER]
	description["credits_delta"] += 1
	description["fingerprint"] = JSON.stringify([ORDER, 1, description["credits_delta"], description["required"], description["excluded"]]).sha256_text()
	_refused(s, operations, state, drifted, "invalid_ledger", "valid changed current definition cannot overwrite an earlier canonical receipt")


static func _test_custody(s: TestSuite) -> void:
	var operations := [{"kind": "item_transfer", "id": DISK, "destination": "test_cabinet"}, _flag()]
	var context := _context(operations, {"item": DISK})
	var state := _snapshot()
	for key: String in ["owned", "held", "unseen"]:
		state["items"][key].append(DISK)
	var proposal := Planner.plan(operations, state, context)
	s.check(proposal["valid"] and proposal["next"]["items"]["held"].is_empty() and proposal["next"]["items"]["owned"] == [DISK] and proposal["next"]["items"]["transferred"] == [DISK] and proposal["next"]["items"]["unseen"] == [DISK], "transfer plans only custody change; acquisition history and NEW remain")
	state = proposal["next"].duplicate(true)
	state["completed"].erase(SCENE)
	_refused(s, operations, state, context, "condition_unmet", "history does not satisfy current-holds condition after delivery")
	context["scenes"][SCENE]["condition"] = {}
	_refused(s, operations, state, context, "item_not_held", "original cannot transfer twice")
	operations = [{"kind": "item_acquire", "id": DISK}]
	_refused(s, operations, state, _context(operations), "item_already_acquired", "transferred original cannot regenerate from history")
	state = _snapshot()
	operations = [{"kind": "item_acquire", "id": CLOTH}, {"kind": "item_acquire", "id": CLOTH}]
	_refused(s, operations, state, _context(operations), "item_already_acquired", "two manual grants are all-or-nothing")
	operations = [{"kind": "item_acquire", "id": CLOTH}]
	context = _context(operations)
	proposal = Planner.plan(operations, state, context)
	s.check(proposal["valid"] and proposal["next"]["items"]["owned"] == [CLOTH] and proposal["next"]["items"]["held"] == [CLOTH] and proposal["next"]["items"]["unseen"] == [CLOTH], "registered manual grant plans all three custody lists")
	context["item_definitions"][CLOTH]["trigger"] = StoryItemData.Trigger.SCENE_FINISHED
	_refused(s, operations, state, context, "automatic_item", "automatic item grants stay outside the result planner")
	state["items"]["held"] = [DISK]
	_refused(s, operations, state, _context(operations), "invalid_snapshot", "held item outside acquisition history preserves corrupt evidence")


static func _pickup_context(operations: Array) -> Dictionary:
	var context := _context(operations)
	context["producers"]["item_acquire:" + DISK] = [{"scene_id": SCENE, "source": "res://game/level/level.gd", "capability": "consumed_pickup", "binding": "test_actual_pickup", "area_id": "test_area", "slot": "ch1_data_disk@40,16"}]
	return context


static func _test_world(s: TestSuite) -> void:
	var operations := [{"kind": "item_acquire", "id": DISK, "source_binding": "test_actual_pickup"}, _flag()]
	var state := _snapshot()
	var context := _pickup_context(operations)
	var proposal := Planner.plan(operations, state, context)
	s.check(proposal["valid"] and proposal["next"]["area_states"]["test_area"]["consumed"]["ch1_data_disk@40,16"] and proposal["next"]["items"]["held"] == [DISK], "actual registered pickup plans world consumed marker and original custody together")
	state["area_states"]["test_area"]["consumed"]["ch1_data_disk@40,16"] = true
	_refused(s, operations, state, context, "world_item_consumed", "consumed slot cannot mint an item")
	state = _snapshot()
	context["producers"]["item_acquire:" + DISK][0]["binding"] = "test_other_pickup"
	_refused(s, operations, state, context, "invalid_producer", "author source binding cannot select a different actual object")
	context = _pickup_context(operations)
	context["producers"]["item_acquire:" + DISK][0]["capability"] = "stage_tray"
	_refused(s, operations, state, context, "unsupported_capability", "stage tray has no installed persistent-world boundary")
	context = _pickup_context(operations)
	context["producers"]["item_acquire:" + DISK][0]["area_id"] = "test_absent_area"
	_refused(s, operations, state, context, "invalid_producer", "missing real area is not synthesized")
	context = _pickup_context(operations)
	context["producers"]["item_acquire:" + DISK][0]["slot"] = "ch1_grey_cloth@40,16"
	_refused(s, operations, state, context, "invalid_producer", "registered world key must belong to the original being produced")
	operations.append(_tx(PAID))
	context = _pickup_context(operations)
	_refused(s, operations, state, context, "missing_requirement", "later result failure discards staged world consumption and item grant")


static func _test_rejections(s: TestSuite) -> void:
	var operations := [_flag()]
	var state := _snapshot()
	var context := _context(operations)
	context["replay"] = true
	_refused(s, operations, state, context, "replay_forbidden", "memory replay cannot produce irreversible effects")
	context = _context(operations)
	context["scenes"][SCENE]["condition"] = {"not": {"flag": "undeclared", "equals": true}}
	_refused(s, operations, state, context, "invalid_condition", "negated missing flag is invalid rather than eligible")
	context = _context(operations)
	context["producers"].clear()
	_refused(s, operations, state, context, "missing_producer", "result has no actual producer")
	context = _context(operations)
	context["producers"]["flag:test_done"][0]["trusted"] = true
	_refused(s, operations, state, context, "unsupported_capability", "arbitrary trusted boolean cannot authorize a producer")
	context = _context(operations)
	context["producers"]["flag:test_done"][0]["scene_id"] = "test_other_scene"
	_refused(s, operations, state, context, "missing_producer", "other scene producer cannot write this result")
	context = _context(operations)
	context["producers"]["flag:test_done"].append(context["producers"]["flag:test_done"][0].duplicate(true))
	_refused(s, operations, state, context, "invalid_producer", "ambiguous actual producer evidence is refused")
	for operation: Dictionary in [{"kind": "companion_join", "id": "test_friend"}, {"kind": "world", "id": "test_gate"}, {"kind": "item_acquire", "id": "test_missing"}, {"kind": "transaction", "id": "test.unknown"}, {"kind": "flag", "id": "test_done", "value": "yes"}, {"kind": "flag", "id": "test_missing", "value": true}]:
		operations = [operation]
		var expected := "unsupported_result"
		match operation["kind"]:
			"item_acquire": expected = "unknown_item"
			"transaction": expected = "unknown_transaction"
			"flag": expected = "invalid_flag"
		_refused(s, operations, state, _context(operations), expected, "unknown action, definition, or typed flag " + str(operation))
	operations = [_flag()]
	context = _context(operations)
	context["scenes"][SCENE]["results"] = []
	_refused(s, operations, state, context, "unregistered_results", "caller cannot substitute an author result list")
	context = _context(operations)
	state["flags"]["test_route"] = true
	_refused(s, operations, state, context, "invalid_snapshot", "declared string default cannot become boolean")
	state = _snapshot()
	state["credits"] = -1
	_refused(s, operations, state, context, "invalid_wallet", "negative wallet is never normalized into money")
	state = _snapshot()
	state["items"].erase("held")
	_refused(s, operations, state, context, "invalid_snapshot", "partial custody is not migrated as legacy")
	operations = []
	for i in Planner.MAX_RESULTS + 1:
		operations.append(_flag())
	_refused(s, operations, _snapshot(), _context(operations), "invalid_results", "result count is bounded before duplication")
	var unsafe := _snapshot()
	unsafe["area_states"]["test_area"]["world"]["handler"] = RefCounted.new()
	var proposal := Planner.plan([], unsafe, _context([]))
	s.check(not proposal["valid"] and proposal["status"] == "invalid_tree" and unsafe["area_states"]["test_area"]["world"]["handler"] is RefCounted, "object trees are rejected before copying or invoking handlers")
	var cycle := {}
	cycle["self"] = cycle
	proposal = Planner.plan([], cycle, _context([]))
	s.check(not proposal["valid"] and proposal["status"] == "invalid_tree" and is_same(cycle["self"], cycle), "cyclic input is bounded and remains intact")
	cycle.clear()


static func _test_aliases(s: TestSuite) -> void:
	var operations := [{"kind": "item_acquire", "id": DISK, "source_binding": "test_actual_pickup"}, _tx(ORDER), _flag()]
	var context := _pickup_context(operations)
	var state := _snapshot()
	var before := JSON.stringify([operations, state, context])
	var first := Planner.plan(operations, state, context)
	var second := Planner.plan(operations, state, context)
	s.check(first["valid"] and second["valid"], "independent proposals are repeatable before installation")
	if not first["valid"] or not second["valid"]:
		return
	var second_before := JSON.stringify(second)
	first["next"]["flags"]["test_done"] = false
	first["next"]["items"]["held"].clear()
	first["next"]["ledger"]["receipts"][ORDER]["credits_delta"] = 100
	first["next"]["area_states"]["test_area"]["consumed"].clear()
	first["next"]["completed"].clear()
	first["events"][0]["slot"] = "changed"
	first["events"].clear()
	s.check(JSON.stringify([operations, state, context]) == before and JSON.stringify(second) == second_before, "mutating every returned branch and event never aliases inputs or another proposal")
