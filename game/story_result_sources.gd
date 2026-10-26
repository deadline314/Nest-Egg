extends RefCounted
## Finite authored producer contracts, independent of filesystem and live owners.
const SOURCE := "res://data/story/ch1_kasa.json"
const Supper := preload("res://game/story_result_supper.gd")
const Clinic := preload("res://game/story_result_clinic.gd")
const TERMINAL := "main_terminal_results_v1"
const CONTINUATION := "main_flags_continuation_v1"
const RESULT_CONTINUATION := "main_source_results_continuation_v1"
const CONTINUATION_POLICIES := [CONTINUATION, RESULT_CONTINUATION]
const VOICE_SOURCE := {
	"npc": "res://data/npcs/ch1_lamp_voice.tres",
	"levels": ["res://data/levels/ch1_booth_alley.tres"],
}
const ALI_SOURCE := {
	"npc": "res://data/npcs/ch1_ali_lounge.tres",
	"levels": ["res://data/levels/ch1_lounge.tres"],
}
const STALL_SOURCE := Supper.NPC_SOURCE
const PROLOGUE_SOURCE := {
	"npc": "res://data/npcs/ch1_old_k_counter.tres",
	"levels": ["res://data/levels/ch1_prologue.tres"],
}
const MAX_ROUTE_NODES := 64
const NPC_SOURCES := {
	"ch1_p05_service_fall": PROLOGUE_SOURCE,
	"ch1_p05_service_clean": PROLOGUE_SOURCE,
	"ch1_p06_call": PROLOGUE_SOURCE,

	"ch1_t_supper_choice_ordered": STALL_SOURCE,
	"ch1_t_supper_choice_none": STALL_SOURCE,
	"ch1_t_supper_leave_options": STALL_SOURCE,
	"ch1_t_supper_insufficient": STALL_SOURCE,
	"ch1_t_supper_tab_confirm": STALL_SOURCE,
	"ch1_t_supper_host_prompt": STALL_SOURCE,
	"ch1_t_supper_host_none_prompt": STALL_SOURCE,
	"ch1_t_supper_pay": STALL_SOURCE,
	"ch1_t_supper_paid_goodbye": STALL_SOURCE,
	"ch1_t_supper_tab": STALL_SOURCE,
	"ch1_t_supper_tab_goodbye": STALL_SOURCE,
	"ch1_t_supper_leave_none": STALL_SOURCE,
	"ch1_t_supper_return": STALL_SOURCE,
	"ch1_t_supper_stay_host": STALL_SOURCE,
	"ch1_t_supper_stay_host_none": STALL_SOURCE,
	"ch1_t_supper_stay_meal": STALL_SOURCE,
	"ch1_t_supper_stay_address": STALL_SOURCE,

	"ch1_t_label_watch": {
		"npc": "res://data/npcs/ch1_label_watch.tres",
		"levels": ["res://data/levels/ch1_pawnshop.tres", "res://data/levels/ch1_pawnshop_dawn.tres"],
	},
	"ch1_t_label_guitar": {
		"npc": "res://data/npcs/ch1_label_guitar.tres",
		"levels": ["res://data/levels/ch1_pawnshop.tres", "res://data/levels/ch1_pawnshop_dawn.tres"],
	},
	"ch1_t_label_raincoat": {
		"npc": "res://data/npcs/ch1_label_raincoat.tres",
		"levels": ["res://data/levels/ch1_pawnshop.tres", "res://data/levels/ch1_pawnshop_dawn.tres"],
	},
	"ch1_t_label_fare": {
		"npc": "res://data/npcs/ch1_label_fare.tres",
		"levels": ["res://data/levels/ch1_pawnshop.tres", "res://data/levels/ch1_pawnshop_dawn.tres"],
	},
	"ch1_t_egret_1": {
		"npc": "res://data/npcs/ch1_egret.tres",
		"levels": ["res://data/levels/ch1_rooftop.tres"],
	},
	"ch1_t_egret_sunday_prompt": {
		"npc": "res://data/npcs/ch1_egret.tres",
		"levels": ["res://data/levels/ch1_rooftop.tres"],
	},
	"ch1_t_egret_sunday": {
		"npc": "res://data/npcs/ch1_egret.tres",
		"levels": ["res://data/levels/ch1_rooftop.tres"],
	},
	"ch1_t_handoff_accept": {
		"npc": "res://data/npcs/ch1_handoff_cabinet.tres",
		"levels": ["res://data/levels/ch1_handoff.tres"],
	},
	"ch1_t_handoff_receipt": {
		"npc": "res://data/npcs/ch1_handoff_cabinet.tres",
		"levels": ["res://data/levels/ch1_handoff.tres"],
	},
	"ch1_t_handoff_summary": {
		"npc": "res://data/npcs/ch1_handoff_cabinet.tres",
		"levels": ["res://data/levels/ch1_handoff.tres"],
	},
	"ch1_t_ali_order": ALI_SOURCE,
	"ch1_t_ali_sit": ALI_SOURCE,
	"ch1_t_ali_name": ALI_SOURCE,
	"ch1_t_ali_2_ordered": ALI_SOURCE,
	"ch1_t_ali_2_sit": ALI_SOURCE,
	"ch1_t_ali_evening_close": ALI_SOURCE,
	"ch1_t_lamp_voice_prompt": VOICE_SOURCE,
	"ch1_t_lamp_voice_first": VOICE_SOURCE,
	"ch1_t_lamp_voice_second_prompt": VOICE_SOURCE,
	"ch1_t_lamp_voice_second": VOICE_SOURCE,
	"ch1_t_lamp_voice_later": VOICE_SOURCE,
}

const BOUNDARIES := {
	"ch1_p05_service_fall": {"policy": TERMINAL, "flag": "ch1_prologue_service_heard", "then": ""},
	"ch1_p05_service_clean": {"policy": TERMINAL, "flag": "ch1_prologue_service_heard", "then": ""},
	"ch1_p06_call": {"policy": TERMINAL, "then": "", "operations": [
		{"kind": "flag", "id": "ch1_prologue_done", "value": true},
		{"kind": "flag", "id": "ch1_prologue_exit", "value": true},
	]},

	"ch1_t_ali_order": {"policy": RESULT_CONTINUATION, "then": "ch1_t_ali_name", "operations": [
		{"kind": "transaction", "id": "ch1.revival_meal.order"},
		{"kind": "item_acquire", "id": "ch1_lounge_bill"},
		{"kind": "flag", "id": "ch1_ali_reception_selected", "value": true},
	]},
	"ch1_t_ali_sit": {"policy": CONTINUATION, "flag": "ch1_ali_reception_selected", "then": "ch1_t_ali_name"},
	"ch1_t_ali_name": {"policy": TERMINAL, "flag": "ch1_met_ali", "then": ""},
	"ch1_t_ali_2_ordered": {"policy": CONTINUATION, "flag": "ch1_ali_evening_talk_done", "then": "ch1_t_ali_evening_close"},
	"ch1_t_ali_2_sit": {"policy": CONTINUATION, "flag": "ch1_ali_evening_talk_done", "then": "ch1_t_ali_evening_close"},
	"ch1_t_ali_evening_close": {"policy": TERMINAL, "flag": "ch1_lounge_evening_done", "then": ""},
	"ch1_t_egret_sunday": {"policy": TERMINAL, "flag": "asked_egret_sunday", "then": ""},
	"ch1_t_lamp_voice_first": {"policy": CONTINUATION, "flag": "ch1_lamp_voice_asked", "then": "ch1_t_lamp_voice_second_prompt"},
	"ch1_t_lamp_voice_second": {"policy": TERMINAL, "flag": "sq5_lamp_voice_noticed", "then": ""},
	"ch1_t_lamp_voice_later": {"policy": TERMINAL, "flag": "", "then": "", "repeatable": true},
}
const CHOICES := {
	"ch1_t_egret_sunday_prompt": {
		"default": "return", "options": [
			{"id": "ask", "target": "ch1_t_egret_sunday", "flags": {"ch1_sunday_accepted": true}},
			{"id": "return", "target": "", "flags": {}},
		],
	},
	"ch1_t_lamp_voice_prompt": {
		"default": "return", "options": [
			{"id": "ask", "target": "ch1_t_lamp_voice_first", "flags": {"ch1_voice_accepted": true}},
			{"id": "return", "target": "", "flags": {}},
		],
	},
	"ch1_t_lamp_voice_second_prompt": {
		"default": "later", "options": [
			{"id": "ask", "target": "ch1_t_lamp_voice_second", "flags": {}},
			{"id": "later", "target": "ch1_t_lamp_voice_later", "flags": {}},
		],
	},
}


static func owns_choice(id: String) -> bool:
	return CHOICES.has(id) or Supper.CHOICES.has(id)

static func owns_boundary(id: String) -> bool:
	return BOUNDARIES.has(id) or Supper.BOUNDARIES.has(id) or Clinic.owns(id)

static func _choice_rule(id: String) -> Dictionary:
	return CHOICES.get(id, Supper.CHOICES.get(id, {}))

static func _boundary_rule(id: String) -> Dictionary:
	return BOUNDARIES.get(id, Supper.BOUNDARIES.get(id, {}))

static func _loaded(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	var scene: Variant = scenes.get(id)
	if not _text_equals(sources.get(id), SOURCE) or not scene is Dictionary or not RunSaveCodec.validate_tree(scene, 32768).is_empty():
		return {}
	return scene


static func _empty_array(data: Dictionary, key: String) -> bool:
	var value: Variant = data.get(key, [])
	return value is Array and value.is_empty()


static func _text_equals(raw: Variant, expected: String) -> bool:
	return typeof(raw) in [TYPE_STRING, TYPE_STRING_NAME] and String(raw) == expected


static func _value_equals(raw: Variant, expected: Variant) -> bool:
	return (raw is bool and raw == expected) if expected is bool else (expected is String and _text_equals(raw, expected))

static func _option_condition(raw: Variant, expected: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != expected.size():
		return false
	for key: String in expected:
		if not _value_equals(raw.get(key), expected[key]):
			return false
	return true

static func _flags_match(raw: Variant, expected: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != expected.size():
		return false
	for key: String in expected:
		if not raw.has(key) or not _value_equals(raw[key], expected[key]):
			return false
	return true


static func _operations_match(raw: Variant, expected: Array) -> bool:
	if not raw is Array or raw.size() != expected.size():
		return false
	for i in expected.size():
		var operation: Variant = raw[i]
		if not operation is Dictionary or operation.size() != expected[i].size():
			return false
		for key: String in expected[i]:
			if not _value_equals(operation.get(key), expected[i][key]):
				return false
	return true


static func boundary(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if Clinic.owns(id):
		return Clinic.boundary(id,scenes,sources)
	var rule := _boundary_rule(id)
	if rule.is_empty():
		return {}
	var scene := _loaded(id, scenes, sources)
	var operations: Array = rule.get("operations", []).duplicate(true)
	if not str(rule.get("flag", "")).is_empty():
		operations.append({"kind": "flag", "id": rule["flag"], "value": true})
	if not _text_equals(scene.get("completion_policy"), rule["policy"]) or not _text_equals(scene.get("then", ""), rule["then"]) or not _operations_match(scene.get("results", []), operations) or not _empty_array(scene, "set_flags") or not _empty_array(scene, "transfer_items"):
		return {}
	var steps: Variant = scene.get("steps", [])
	if not steps is Array:
		return {}
	for step: Variant in steps:
		if not step is Dictionary or step.get("do") in ["choice", "branch"]:
			return {}
	if rule.get("repeatable", false):
		var expected: Dictionary = rule.get("repeat_condition", {"flag": "ch1_lamp_voice_asked", "equals": true})
		if not _option_condition(scene.get("when"), expected):
			return {}
		if id == "ch1_t_lamp_voice_later" and not operations.is_empty():
			return {}
	if not _option_condition(scene.get("on_failure", {}), rule.get("failures", {})):
		return {}
	return rule


static func _option_matches(raw: Variant, expected: Dictionary) -> bool:
	return raw is Dictionary and _text_equals(raw.get("id"), expected["id"]) and _flags_match(raw.get("set_flags", {}), expected["flags"]) and _text_equals(raw.get("target", ""), expected["target"]) and _empty_array(raw, "steps") and _empty_array(raw, "transfer_items") and _option_condition(raw.get("when", {}), expected.get("when", {}))


static func _local_choice_step(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	var rule := _choice_rule(id)
	if rule.is_empty():
		return {}
	var scene := _loaded(id, scenes, sources)
	if scene.is_empty() or not str(scene.get("then", "")).is_empty() or not _empty_array(scene, "results") or not _empty_array(scene, "set_flags") or not _empty_array(scene, "transfer_items"):
		return {}
	var steps: Variant = scene.get("steps")
	if not steps is Array or steps.is_empty() or steps.size() > 64:
		return {}
	for i in steps.size():
		if not steps[i] is Dictionary:
			return {}
		if i < steps.size() - 1 and steps[i].get("do") not in ["scene", "actor", "say"]:
			var waits: Dictionary = rule.get("waits", {})
			var duration: Variant = steps[i].get("time")
			if steps[i].get("do") != "wait" or not waits.has(str(i)) or not typeof(duration) in [TYPE_INT, TYPE_FLOAT] or duration != waits[str(i)]:
				return {}
	var step: Dictionary = steps.back()
	var options: Variant = step.get("options")
	if not _text_equals(step.get("do"), "choice") or not _text_equals(step.get("default"), rule["default"]) or not options is Array or options.size() != rule["options"].size():
		return {}
	for i in options.size():
		var expected: Dictionary = rule["options"][i]
		if not _option_matches(options[i], expected):
			return {}
	return step


## One bounded, memoized authored graph; gray nodes reject cycles. Metadata is
## registered here rather than inferred from arbitrary loaded story payloads.
static func _route_valid(id: String, scenes: Dictionary, sources: Dictionary, visits: Dictionary) -> bool:
	if visits.has(id):
		return visits[id] == 2
	if visits.size() >= MAX_ROUTE_NODES or not NPC_SOURCES.has(id):
		return false
	visits[id] = 1
	var targets: Array = []
	if owns_choice(id):
		if _local_choice_step(id, scenes, sources).is_empty():
			return false
		for option: Dictionary in _choice_rule(id)["options"]:
			if not option["target"].is_empty():
				targets.append(option["target"])
	else:
		var rule := boundary(id, scenes, sources)
		if rule.is_empty():
			return false
		if not rule["then"].is_empty():
			targets.append(rule["then"])
		for target: String in rule.get("failures", {}).values():
			targets.append(target)
	for target: String in targets:
		if NPC_SOURCES.get(id, {}) != NPC_SOURCES.get(target, {}) or not _route_valid(target, scenes, sources, visits):
			return false
	visits[id] = 2
	return true

static func choice_step(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	return _local_choice_step(id, scenes, sources) if _route_valid(id, scenes, sources, {}) else {}

static func repeatable(id: String, scenes: Dictionary, sources: Dictionary) -> bool:
	return boundary(id, scenes, sources).get("repeatable", false)

static func failure(id: String, reason: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	var rule := boundary(id, scenes, sources)
	if not _route_valid(id, scenes, sources, {}):
		return &""
	return StringName(rule.get("failures", {}).get(reason, ""))

## Only two result-free goodbyes outlive their producer's dispatcher phase.
## The original data, same original talk entry and prior committed producer are
## required. Live source, spawn, index and eligibility remain caller checks.
static func pending_terminal(npc_path: String, entry: StringName, id: String, scenes: Dictionary, sources: Dictionary, completed: Dictionary) -> bool:
	if entry != &"ch1_dispatch_ali_stall" or npc_path != STALL_SOURCE["npc"] or completed.has(StringName(id)) or _loaded(String(entry), scenes, sources).is_empty():
		return false
	var rule := boundary(id, scenes, sources)
	var previous: String = rule.get("pending_after", "")
	return not previous.is_empty() and completed.has(StringName(previous)) and continuation(previous, scenes, sources) == StringName(id) and _route_valid(id, scenes, sources, {})

static func choice(id: String, option: Dictionary, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if not RunSaveCodec.validate_tree(option, 32768).is_empty():
		return {}
	var step := choice_step(id, scenes, sources)
	if step.is_empty():
		return {}
	var rule := _choice_rule(id)
	for i in rule["options"].size():
		var expected: Dictionary = rule["options"][i]
		if not _option_matches(option, expected):
			continue
		var operations: Array = []
		for flag: String in expected["flags"]:
			operations.append({"kind": "flag", "id": flag, "value": expected["flags"][flag]})
		return {"when": scenes[id].get("when", {}), "results": operations, "target": expected["target"], "option": step["options"][i], "return": expected["target"].is_empty()}
	return {}


static func continuation(id: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	if Clinic.owns(id):
		return Clinic.continuation(id,scenes,sources)
	var rule := boundary(id, scenes, sources)
	if rule.is_empty() or rule["policy"] not in CONTINUATION_POLICIES or not _route_valid(id, scenes, sources, {}):
		return &""
	return StringName(rule["then"])
