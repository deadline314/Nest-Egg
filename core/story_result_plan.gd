class_name StoryResultPlan
extends RefCounted
## Pure, bounded proposal. The trusted coordinator owns registries and installation.
## This class never touches services, emits signals, saves, or calls author handlers.

const Conditions = preload("res://core/story_condition_tree.gd")
const MAX_RESULTS := 64
const MAX_ENTRIES := 1024
const MAX_TREE_NODES := 32768
const MAX_CREDITS := 99999
const KINDS := ["flag", "transaction", "item_acquire", "item_transfer"]


static func _fail(status: String, where: String, reason: String) -> Dictionary:
	return {"valid": false, "status": status, "error": (where.left(384) + ": " + reason).left(512)}


static func _keys(raw: Dictionary, keys: Array) -> bool:
	if raw.size() != keys.size():
		return false
	for key: Variant in raw:
		if not key is String or not keys.has(key):
			return false
	return true


static func _id(raw: Variant) -> bool:
	return raw is String and StoryTransactionData.valid_id(raw)


static func _scalar(raw: Variant) -> bool:
	return raw is bool or (raw is String and raw.length() <= 256) or (typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) and absf(float(raw)) <= 999999999)


static func _same_type(first: Variant, second: Variant) -> bool:
	return typeof(first) == typeof(second)


## snapshot is a service projection, not another save format:
## flags=GameState.world_flags; items=StoryItems.snapshot; credits/ledger=Progression;
## area_states=GameState.area_states; completed=Story.progress_snapshot.
static func plan(results: Variant, snapshot: Variant, context: Variant) -> Dictionary:
	for pair: Array in [[results, "results"], [snapshot, "snapshot"], [context, "context"]]:
		var errors := RunSaveCodec.validate_tree(pair[0], MAX_TREE_NODES)
		if not errors.is_empty():
			return _fail("invalid_tree", pair[1], errors[0])
	if not results is Array or results.size() > MAX_RESULTS:
		return _fail("invalid_results", "results", "expected a bounded result list")
	if not snapshot is Dictionary or not _keys(snapshot, ["flags", "items", "credits", "ledger", "area_states", "completed"]):
		return _fail("invalid_snapshot", "snapshot", "expected the complete service projection")
	if not context is Dictionary or not _keys(context, ["scene_id", "replay", "scenes", "flag_defaults", "item_definitions", "transaction_definitions", "producers", "ledger_locked"]):
		return _fail("invalid_context", "context", "expected the complete owner registry")
	if not _id(context["scene_id"]) or not context["replay"] is bool:
		return _fail("invalid_context", "context/scene_id", "invalid scene or replay mode")
	for key: String in ["scenes", "flag_defaults", "item_definitions", "transaction_definitions", "producers"]:
		if not context[key] is Dictionary or context[key].size() > MAX_ENTRIES:
			return _fail("invalid_context", "context/" + key, "expected a bounded registry")
	var scene_id: String = context["scene_id"]
	if not context["scenes"].has(scene_id):
		return _fail("unknown_scene", "context/scenes/" + scene_id, "scene is not registered")
	var scene: Variant = context["scenes"][scene_id]
	if not scene is Dictionary or not _keys(scene, ["once", "condition", "results"]) or not scene["once"] is bool or not scene["results"] is Array:
		return _fail("invalid_context", "context/scenes/" + scene_id, "invalid scene result contract")
	if results != scene["results"]:
		return _fail("unregistered_results", "results", "results differ from the loaded scene contract")
	var validation := _validate_state(snapshot, context)
	if not validation["valid"]:
		return validation
	var facts: Dictionary = validation["facts"]
	var condition_context := {"ledger_locked": context["ledger_locked"], "transaction_definitions": context["transaction_definitions"]}
	var ledger_proof := Conditions.verify_ledger(facts, condition_context)
	if not ledger_proof["valid"]:
		return _fail("invalid_ledger", "snapshot/ledger", ledger_proof["error"])
	if context["replay"]:
		return _fail("replay_forbidden", "context/replay", "memory presentation cannot produce results or completion")
	if snapshot["completed"].has(scene_id):
		return _fail("already_completed", "snapshot/completed/" + scene_id, "completed segments cannot be billed or produced again")
	if snapshot["completed"].size() >= MAX_ENTRIES:
		return _fail("completion_limit", "snapshot/completed", "completion history is full")
	# Admission is against the start facts only, never against the changed proposal.
	var admission := Conditions.evaluate(scene["condition"], facts, condition_context)
	if not admission["valid"]:
		return _fail("invalid_condition", "context/scenes/" + scene_id, admission["error"])
	if not admission["value"]:
		return _fail("condition_unmet", "context/scenes/" + scene_id, "start snapshot does not satisfy the scene condition")
	# The finite tree and service schemas have been checked before deep copying.
	var next: Dictionary = snapshot.duplicate(true)
	next["flags"] = facts["flags"].duplicate(true)
	var events: Array[Dictionary] = []
	var local_ledger := StoryTransactionLedger.new()
	local_ledger.restore(next["ledger"], true)
	for i in results.size():
		var where := "results/%d" % i
		var operation: Variant = results[i]
		var result := _apply(operation, next, context, local_ledger, events, where)
		if not result["valid"]:
			return result
	# The final receipt set also must remain a canonical, conflict-free set.
	var final_facts := {"flags": next["flags"], "items": facts["items"], "ledger": next["ledger"]}
	ledger_proof = Conditions.verify_ledger(final_facts, condition_context)
	if not ledger_proof["valid"]:
		return _fail("invalid_ledger", "next/ledger", ledger_proof["error"])
	next["completed"].append(scene_id)
	events.append({"kind": "scene_completed", "id": scene_id})
	return {"valid": true, "status": "planned", "error": "", "next": next, "events": events}


static func _validate_state(snapshot: Dictionary, context: Dictionary) -> Dictionary:
	if not snapshot["flags"] is Dictionary or snapshot["flags"].size() > MAX_ENTRIES:
		return _fail("invalid_snapshot", "snapshot/flags", "expected bounded flags")
	var flags: Dictionary = {}
	for id: Variant in context["flag_defaults"]:
		if not _id(id) or not _scalar(context["flag_defaults"][id]):
			return _fail("invalid_context", "context/flag_defaults", "invalid declared flag or default")
		flags[id] = context["flag_defaults"][id]
	for id: Variant in snapshot["flags"]:
		if not _id(id) or not flags.has(id) or not _scalar(snapshot["flags"][id]) or not _same_type(snapshot["flags"][id], flags[id]):
			return _fail("invalid_snapshot", "snapshot/flags/" + str(id), "flag is undeclared or has the wrong declared type")
		flags[id] = snapshot["flags"][id]
	var items: Variant = snapshot["items"]
	if not items is Dictionary or not _keys(items, ["owned", "unseen", "custody_version", "held", "transferred"]) or not StoryTransactionData.integer_in(items.get("custody_version"), 1, 1):
		return _fail("invalid_snapshot", "snapshot/items", "expected current custody version 1; migrate legacy through the owner first")
	var holds := {}
	for id: Variant in context["item_definitions"]:
		var definition: Variant = context["item_definitions"][id]
		if not _id(id) or not definition is Dictionary or not _keys(definition, ["trigger"]) or not StoryTransactionData.integer_in(definition["trigger"], 0, 3):
			return _fail("invalid_context", "context/item_definitions", "invalid canonical item projection")
		holds[id] = false
	var sets := {}
	for key: String in ["owned", "unseen", "held", "transferred"]:
		if not items[key] is Array or items[key].size() > holds.size():
			return _fail("invalid_snapshot", "snapshot/items/" + key, "expected a bounded custody array")
		var ids := {}
		for raw: Variant in items[key]:
			if typeof(raw) not in [TYPE_STRING, TYPE_STRING_NAME] or not holds.has(String(raw)) or ids.has(String(raw)):
				return _fail("invalid_snapshot", "snapshot/items/" + key, "unknown or duplicate item")
			ids[String(raw)] = true
		sets[key] = ids
	for key: String in ["unseen", "held", "transferred"]:
		for id: String in sets[key]:
			if not sets["owned"].has(id):
				return _fail("invalid_snapshot", "snapshot/items/" + key + "/" + id, "custody is outside acquisition history")
	for id: String in sets["owned"]:
		if sets["held"].has(id) == sets["transferred"].has(id):
			return _fail("invalid_snapshot", "snapshot/items/" + id, "history must be held or transferred, exclusively")
		holds[id] = sets["held"].has(id)
	if not StoryTransactionData.integer_in(snapshot["credits"], 0, MAX_CREDITS):
		return _fail("invalid_wallet", "snapshot/credits", "expected the bounded Progression wallet")
	if not snapshot["completed"] is Array or snapshot["completed"].size() > MAX_ENTRIES:
		return _fail("invalid_snapshot", "snapshot/completed", "expected bounded completion history")
	var completed := {}
	for raw: Variant in snapshot["completed"]:
		if typeof(raw) not in [TYPE_STRING, TYPE_STRING_NAME] or not context["scenes"].has(String(raw)) or completed.has(String(raw)):
			return _fail("invalid_snapshot", "snapshot/completed", "unknown or duplicate completed scene")
		completed[String(raw)] = true
	if not snapshot["area_states"] is Dictionary or snapshot["area_states"].size() > MAX_ENTRIES:
		return _fail("invalid_snapshot", "snapshot/area_states", "expected bounded actual area states")
	for area_id: Variant in snapshot["area_states"]:
		var area: Variant = snapshot["area_states"][area_id]
		if not _id(area_id) or not area is Dictionary or not _keys(area, ["consumed", "damage", "world"]):
			return _fail("invalid_snapshot", "snapshot/area_states", "invalid area service shape")
		for key: String in ["consumed", "damage", "world"]:
			if not area[key] is Dictionary or area[key].size() > MAX_ENTRIES:
				return _fail("invalid_snapshot", "snapshot/area_states/" + area_id + "/" + key, "invalid bounded area map")
		for slot: Variant in area["consumed"]:
			if not slot is String or slot.is_empty() or slot.length() > 128 or area["consumed"][slot] != true or not area["consumed"][slot] is bool:
				return _fail("invalid_snapshot", "snapshot/area_states/" + area_id + "/consumed", "consumed slots must contain true markers")
	return {"valid": true, "facts": {"flags": flags, "items": holds, "ledger": snapshot["ledger"]}}


static func _producer(operation: Dictionary, context: Dictionary, where: String) -> Dictionary:
	var key: String = operation["kind"] + ":" + operation["id"]
	var candidates: Variant = context["producers"].get(key)
	if not candidates is Array or candidates.is_empty() or candidates.size() > 16:
		return _fail("missing_producer", where, "no actual producer registry entry for " + key)
	var selected: Dictionary = {}
	for entry: Variant in candidates:
		if not entry is Dictionary or not entry.get("scene_id") is String or not entry.get("source") is String or not entry.get("capability") is String:
			return _fail("invalid_producer", where, "malformed producer evidence")
		if entry["scene_id"] != context["scene_id"]:
			continue
		if not selected.is_empty():
			return _fail("invalid_producer", where, "ambiguous producer evidence")
		if not entry["source"].begins_with("res://") or entry["source"].length() > 256 or ".." in entry["source"]:
			return _fail("invalid_producer", where, "producer source is not an owner supplied project source")
		selected = entry
	if selected.is_empty():
		return _fail("missing_producer", where, "no actual producer for this scene")
	return {"valid": true, "producer": selected}


static func _apply(raw: Variant, next: Dictionary, context: Dictionary, ledger: StoryTransactionLedger, events: Array[Dictionary], where: String) -> Dictionary:
	if not raw is Dictionary or not raw.get("kind") is String or not KINDS.has(raw["kind"]) or not _id(raw.get("id")):
		return _fail("unsupported_result", where, "unknown action or invalid result id")
	var kind: String = raw["kind"]
	var id: String = raw["id"]
	var keys: Array = ["kind", "id"]
	if kind == "flag":
		keys.append("value")
	elif kind == "item_transfer":
		keys.append("destination")
	elif kind == "item_acquire" and raw.has("source_binding"):
		keys.append("source_binding")
	if not _keys(raw, keys):
		return _fail("unsupported_result", where, "unknown result fields")
	var proof := _producer(raw, context, where)
	if not proof["valid"]:
		return proof
	var producer: Dictionary = proof["producer"]
	var capability: String = producer["capability"]
	if kind in ["flag", "transaction"]:
		if capability != "scene_completion" or not _keys(producer, ["scene_id", "source", "capability"]):
			return _fail("unsupported_capability", where, "result needs a real scene completion producer")
	if kind == "flag":
		if not context["flag_defaults"].has(id) or not _scalar(raw["value"]) or not _same_type(raw["value"], context["flag_defaults"][id]):
			return _fail("invalid_flag", where, "flag or value does not match its declared default type")
		next["flags"][id] = raw["value"]
		events.append({"kind": "flag_changed", "id": id, "value": raw["value"]})
	elif kind == "transaction":
		if not context["transaction_definitions"].has(id):
			return _fail("unknown_transaction", where, "canonical transaction is missing")
		var definition: Dictionary = context["transaction_definitions"][id]
		var transaction := StoryTransactionData.new()
		transaction.id = StringName(id)
		transaction.credits_delta = int(definition["credits_delta"])
		transaction.requires_receipts = PackedStringArray(definition["required"])
		transaction.excludes_receipts = PackedStringArray(definition["excluded"])
		var committed := ledger.commit(transaction, int(next["credits"]), MAX_CREDITS)
		if not committed["status"] in ["applied", "already_recorded"]:
			return _fail(committed["status"], where, committed["message"])
		if committed["applied"]:
			next["credits"] = committed["credits_after"]
			next["ledger"] = ledger.snapshot()
			events.append({"kind": "transaction_committed", "id": id, "credits_delta": committed["credits_delta"]})
	else:
		if not context["item_definitions"].has(id):
			return _fail("unknown_item", where, "canonical item is missing")
		if context["item_definitions"][id]["trigger"] != StoryItemData.Trigger.MANUAL:
			return _fail("automatic_item", where, "result planner only produces manual items")
		var items: Dictionary = next["items"]
		if kind == "item_transfer":
			if capability != "item_transfer" or not _keys(producer, ["scene_id", "source", "capability", "destination"]) or not _id(raw["destination"]) or raw["destination"] != producer["destination"]:
				return _fail("unsupported_capability", where, "destination is not an actual registered transfer binding")
			if not items["held"].has(id) or items["transferred"].has(id):
				return _fail("item_not_held", where, "only a currently held original may transfer once")
			items["held"].erase(id)
			items["transferred"].append(id)
		else:
			if items["owned"].has(id):
				return _fail("item_already_acquired", where, "acquisition history prevents regeneration")
			if capability == "scene_manual_item":
				if raw.has("source_binding") or not _keys(producer, ["scene_id", "source", "capability"]):
					return _fail("unsupported_capability", where, "bound world items need actual persistent world evidence")
			elif capability == "consumed_pickup":
				if not _keys(producer, ["scene_id", "source", "capability", "binding", "area_id", "slot"]) or not raw.has("source_binding") or not _id(raw["source_binding"]) or raw["source_binding"] != producer["binding"]:
					return _fail("invalid_producer", where, "pickup binding is missing or mismatched")
				var area_id: Variant = producer["area_id"]
				var slot: Variant = producer["slot"]
				if not _id(area_id) or not slot is String or not slot.begins_with(id + "@") or slot.length() > 128 or not next["area_states"].has(area_id):
					return _fail("invalid_producer", where, "actual area or generated slot is unavailable")
				var consumed: Dictionary = next["area_states"][area_id]["consumed"]
				if consumed.has(slot):
					return _fail("world_item_consumed", where, "actual world slot has already been consumed")
				if consumed.size() >= MAX_ENTRIES:
					return _fail("world_limit", where, "consumed marker capacity is full")
				consumed[slot] = true
				events.append({"kind": "world_consumed", "area_id": area_id, "slot": slot})
			else:
				return _fail("unsupported_capability", where, "world, stage, or companion capability is not installed")
			items["owned"].append(id)
			items["held"].append(id)
			items["unseen"].append(id)
		events.append({"kind": kind, "id": id})
	return {"valid": true}
