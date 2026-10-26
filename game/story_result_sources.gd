extends RefCounted
## Finite authored producer contracts, independent of filesystem and live owners.
const SOURCE := "res://data/story/ch1_kasa.json"
const TERMINAL := "main_terminal_results_v1"
const CONTINUATION := "main_flags_continuation_v1"
const VOICE_SOURCE := {
	"npc": "res://data/npcs/ch1_lamp_voice.tres",
	"levels": ["res://data/levels/ch1_booth_alley.tres"],
}
const NPC_SOURCES := {
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
	"ch1_t_lamp_voice_prompt": VOICE_SOURCE,
	"ch1_t_lamp_voice_first": VOICE_SOURCE,
	"ch1_t_lamp_voice_second_prompt": VOICE_SOURCE,
	"ch1_t_lamp_voice_second": VOICE_SOURCE,
	"ch1_t_lamp_voice_later": VOICE_SOURCE,
}

const BOUNDARIES := {
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


static func _flags_match(raw: Variant, expected: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != expected.size():
		return false
	for key: String in expected:
		if not raw.has(key) or not raw[key] is bool or raw[key] != expected[key]:
			return false
	return true


static func _operations_match(raw: Variant, expected: Array) -> bool:
	if not raw is Array or raw.size() != expected.size():
		return false
	for i in expected.size():
		var operation: Variant = raw[i]
		if not operation is Dictionary or operation.size() != expected[i].size():
			return false
		if not _text_equals(operation.get("kind"), "flag") or not _text_equals(operation.get("id"), expected[i]["id"]) or not operation.get("value") is bool or operation["value"] != true:
			return false
	return true


static func boundary(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if not BOUNDARIES.has(id):
		return {}
	var rule: Dictionary = BOUNDARIES[id]
	var scene := _loaded(id, scenes, sources)
	var operations: Array = []
	if not rule["flag"].is_empty():
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
		var condition: Variant = scene.get("when")
		if not condition is Dictionary or condition.size() != 2 or not _text_equals(condition.get("flag"), "ch1_lamp_voice_asked") or not condition.get("equals") is bool or condition["equals"] != true or not operations.is_empty():
			return {}
	return rule


static func _option_matches(raw: Variant, expected: Dictionary) -> bool:
	return raw is Dictionary and _text_equals(raw.get("id"), expected["id"]) and _flags_match(raw.get("set_flags", {}), expected["flags"]) and _text_equals(raw.get("target", ""), expected["target"]) and _empty_array(raw, "steps") and _empty_array(raw, "transfer_items")


static func choice_step(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if not CHOICES.has(id):
		return {}
	var rule: Dictionary = CHOICES[id]
	var scene := _loaded(id, scenes, sources)
	if scene.is_empty() or not str(scene.get("then", "")).is_empty() or not _empty_array(scene, "results") or not _empty_array(scene, "set_flags") or not _empty_array(scene, "transfer_items"):
		return {}
	var steps: Variant = scene.get("steps")
	if not steps is Array or steps.is_empty() or steps.size() > 64:
		return {}
	for i in steps.size():
		if not steps[i] is Dictionary or (i < steps.size() - 1 and steps[i].get("do") not in ["scene", "actor", "say"]):
			return {}
	var step: Dictionary = steps.back()
	var options: Variant = step.get("options")
	if not _text_equals(step.get("do"), "choice") or not _text_equals(step.get("default"), rule["default"]) or not options is Array or options.size() != rule["options"].size():
		return {}
	for i in options.size():
		var expected: Dictionary = rule["options"][i]
		if not _option_matches(options[i], expected):
			return {}
		if not expected["target"].is_empty() and boundary(expected["target"], scenes, sources).is_empty():
			return {}
	return step


static func choice(id: String, option: Dictionary, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if not RunSaveCodec.validate_tree(option, 32768).is_empty():
		return {}
	var step := choice_step(id, scenes, sources)
	if step.is_empty():
		return {}
	for i in CHOICES[id]["options"].size():
		var expected: Dictionary = CHOICES[id]["options"][i]
		if not _option_matches(option, expected):
			continue
		var operations: Array = []
		for flag: String in expected["flags"]:
			operations.append({"kind": "flag", "id": flag, "value": expected["flags"][flag]})
		return {"when": scenes[id].get("when", {}), "results": operations, "target": expected["target"], "option": step["options"][i], "return": expected["target"].is_empty()}
	return {}


static func continuation(id: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	var rule := boundary(id, scenes, sources)
	if rule.is_empty() or rule["policy"] != CONTINUATION or choice_step(rule["then"], scenes, sources).is_empty():
		return &""
	return StringName(rule["then"])
