extends RefCounted
## Finite first-clinic presentation family. No live services or persistence.
const SOURCE := "res://data/story/ch1_kasa.json"
const ROOT := "ch1_c09_wake"
const TRAY := "ch1_t_clinic_tray_prompt"
const LOOK := "ch1_t_clinic_cloth_look"
const DECIDE := "ch1_t_clinic_cloth_decide"
const TAKE := "ch1_t_clinic_cloth_take"
const LEAVE := "ch1_t_clinic_cloth_leave"
const REGISTERED := "ch1_t_clinic_backup_registered"
const MISSING := "ch1_t_clinic_backup_missing"
const DISPATCH := "ch1_dispatch_clinic_backup"
const PRESENTATIONS := [ROOT, TRAY, LOOK, DECIDE, TAKE, LEAVE, REGISTERED, MISSING]
const ACTIVE := {"flag":"ch1_first_clinic_active","equals":true}
const REGISTERED_BOOTH := {"flag":"ch1_booth_registered","equals":true}
const REAL := {"all":[ACTIVE,{"flag":"ch1_first_death_done","equals":true},{"not":{"item":"ch1_grey_cloth"}}]}
const EXAMINED := {"all":[REAL,{"flag":"ch1_grey_cloth_examined","equals":true}]}
const CONDITIONS := {
	ROOT:{"not":{"flag":"ch1_first_death_done","equals":true}},
	TRAY:REAL, LOOK:REAL, DECIDE:EXAMINED, TAKE:EXAMINED, LEAVE:ACTIVE,
	REGISTERED:{"all":[ACTIVE,REGISTERED_BOOTH]},
	MISSING:{"all":[ACTIVE,{"not":REGISTERED_BOOTH}]},
}
const BOUNDARIES := {
	ROOT:{"policy":"main_flags_continuation_v1","repeatable":true,"then":TRAY,"operations":[{"kind":"flag","id":"ch1_first_death_done","value":true}]},
	LOOK:{"policy":"main_flags_continuation_v1","repeatable":true,"then":DECIDE,"operations":[{"kind":"flag","id":"ch1_grey_cloth_examined","value":true}]},
	TAKE:{"policy":"main_terminal_results_v1","then":"","operations":[{"kind":"item_acquire","id":"ch1_grey_cloth"},{"kind":"flag","id":"has_grey_cloth","value":true}]},
	LEAVE:{"policy":"main_terminal_results_v1","repeatable":true,"then":"","operations":[]},
}
const CHOICES := {
	TRAY:{"default":"leave","options":[{"id":"look","target":LOOK},{"id":"backup","target":DISPATCH},{"id":"leave","target":LEAVE}]},
	DECIDE:{"default":"leave","options":[{"id":"take","target":TAKE},{"id":"leave","target":LEAVE}]},
}
const STEP_KINDS := ["scene","actor","say","camera","wait","fx","fade","reach","prop","prop_move","prop_hold","prop_release","prop_visible"]

static func owns(id: String) -> bool:
	return BOUNDARIES.has(id)

static func _same(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():
			return false
		for key: Variant in expected:
			if not actual.has(key) or not _same(actual[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():
			return false
		for i in expected.size():
			if not _same(actual[i], expected[i]):
				return false
		return true
	if expected is String:
		return typeof(actual) in [TYPE_STRING,TYPE_STRING_NAME] and String(actual) == expected
	return typeof(actual) == typeof(expected) and actual == expected

static func _loaded(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	var raw: Variant = scenes.get(id)
	if sources.get(id) != SOURCE or not raw is Dictionary or not RunSaveCodec.validate_tree(raw,32768).is_empty():
		return {}
	return raw

static func _choice(step: Dictionary, rule: Dictionary) -> bool:
	var options: Variant = step.get("options")
	if step.get("default") != rule["default"] or not options is Array or options.size() != rule["options"].size():
		return false
	for i in options.size():
		var actual: Variant = options[i]
		var expected: Dictionary = rule["options"][i]
		if not actual is Dictionary or actual.get("id") != expected["id"] or actual.get("target") != expected["target"]:
			return false
		for pair: Array in [["set_flags",{}],["when",{}],["steps",[]],["transfer_items",[]]]:
			if not _same(actual.get(pair[0],pair[1]),pair[1]):
				return false
	return true

## The authored backup loop is explicit and bounded; it is not an arbitrary NPC
## completion graph. Validate every member before accepting any family boundary.
static func valid(scenes: Dictionary, sources: Dictionary) -> bool:
	for id: String in PRESENTATIONS:
		var scene := _loaded(id,scenes,sources)
		var rule: Dictionary = BOUNDARIES.get(id,{})
		var next: String = rule.get("then",TRAY if id in [REGISTERED,MISSING] else "")
		if scene.get("mode") != "animated" or not _same(scene.get("when"),CONDITIONS[id]) or scene.get("then","") != next:
			return false
		if not _same(scene.get("results",[]),rule.get("operations",[])) or not _same(scene.get("set_flags",[]),[]) or not _same(scene.get("transfer_items",[]),[]) or not _same(scene.get("on_failure",{}),{}):
			return false
		if (not rule.is_empty() and scene.get("completion_policy") != rule["policy"]) or (rule.is_empty() and scene.has("completion_policy")):
			return false
		if not _same(scene.get("context_facts",[]),["first_clinic"] if id == ROOT else []):
			return false
		var steps: Variant = scene.get("steps")
		if not steps is Array or steps.is_empty() or steps.size() > 64:
			return false
		var choices := 0
		for i in steps.size():
			var step: Variant = steps[i]
			if not step is Dictionary:
				return false
			if step.get("do") == "choice":
				choices += 1
				if not CHOICES.has(id) or i != steps.size()-1 or not _choice(step,CHOICES[id]):
					return false
			elif not STEP_KINDS.has(step.get("do")):
				return false
		if choices != (1 if CHOICES.has(id) else 0):
			return false
	var dispatcher := _loaded(DISPATCH,scenes,sources)
	return dispatcher.get("mode") == "dispatch" and _same(dispatcher.get("routes"),[
		{"when":{"all":[ACTIVE,REGISTERED_BOOTH]},"target":REGISTERED},
		{"when":{"all":[ACTIVE,{"not":REGISTERED_BOOTH}]},"target":MISSING},
	]) and _same(dispatcher.get("results",[]),[]) and _same(dispatcher.get("set_flags",[]),[]) and _same(dispatcher.get("transfer_items",[]),[])

static func boundary(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	return BOUNDARIES.get(id,{}) if owns(id) and valid(scenes,sources) else {}

static func continuation(id: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	var rule := boundary(id,scenes,sources)
	return StringName(rule.get("then",""))


static func owns_episode(proof: Dictionary) -> bool:
	var raw: Variant = proof.get("entry")
	if not raw is Dictionary:
		return false
	var entry: Dictionary = raw
	return not proof.is_empty() and proof.get("chapter") == "ch1_kasa" and proof.get("root") == ROOT and _same(entry.get("scene"),ROOT) and _same(entry.get("free",true),true) and _same(entry.get("register_checkpoint",true),true) and _same(entry.get("unless_flag","ch1_first_death_done"),"ch1_first_death_done")

static func owns_source(proof: Dictionary) -> bool:
	var request: Variant = proof.get("request")
	var facts: Variant = proof.get("context_facts")
	return owns_episode(proof) and owns(proof.get("scene","")) and request is int and request > 0 and proof.get("context_request") == request and facts is Dictionary and _same(facts.get("first_clinic",false),true)

static func _read(history: Array, id: String) -> bool:
	return history.any(func(value: Variant) -> bool: return typeof(value) in [TYPE_STRING,TYPE_STRING_NAME] and String(value) == id)

## Existing flags/history prove a completed terminal, not a permission to take
## an unread item. Empty or stale legacy roots may finish the original retry.
static func resume(proof: Dictionary, pending: String, flags: Dictionary, history: Array, has_cloth: bool) -> Dictionary:
	if not owns_episode(proof) or history.size() > 1024:
		return {"valid":false}
	var registered: bool = _same(flags.get("ch1_first_death_done",false),true) and _read(history,ROOT)
	if _same(flags.get("ch1_first_death_done",false),true) and not registered:
		return {"valid":false}
	if pending.is_empty():
		return {"valid":true,"scene":"" if registered else ROOT}
	if not PRESENTATIONS.has(pending) or (pending != ROOT and not registered):
		return {"valid":false}
	if registered and (pending == ROOT or has_cloth or (pending in [TAKE,LEAVE] and _read(history,pending))):
		return {"valid":true,"scene":""}
	return {"valid":true,"scene":pending}
