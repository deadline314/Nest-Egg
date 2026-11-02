extends RefCounted
## Independent authored identity for terminal flag-only intros.
const SOURCE := "res://data/story/ch1_kasa.json"
const HOME := "ch1_c14_home"
const LEVEL := "res://data/levels/ch1_pawnshop_dawn.tres"
const CONTRACT := {
	"mode": "animated",
	"completion_policy": "main_flags_v1",
	"then": "",
	"when": {"all": [
		{"flag": "ch1_supper_done", "equals": true},
		{"flag": "ch1_handoff_done", "equals": true},
		{"not": {"flag": "ch1_home_done", "equals": true}},
	]},
	"results": [
		{"kind": "flag", "id": "ch1_home_done", "value": true},
		{"kind": "flag", "id": "ch1_complete", "value": true},
	],
	"set_flags": [],
	"transfer_items": [],
}


static func owns(id: String) -> bool:
	return id == HOME


static func valid(id: String, scenes: Dictionary, sources: Dictionary) -> bool:
	var scene: Variant = scenes.get(id)
	if not owns(id) or not _matches(sources.get(id), SOURCE) or not scene is Dictionary or not RunSaveCodec.validate_tree(scene, 32768).is_empty():
		return false
	for key: String in CONTRACT:
		if not _matches(scene.get(key, CONTRACT[key] if key in ["then", "set_flags", "transfer_items"] else null), CONTRACT[key]):
			return false
	return not Story.offers_choice(scene)


static func _matches(actual: Variant, expected: Variant, depth := 0) -> bool:
	if depth > 16 or typeof(actual) != typeof(expected):
		return false
	if expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not _matches(actual[key], expected[key], depth + 1): return false
		return true
	if expected is Array:
		if actual.size() != expected.size(): return false
		for index in expected.size():
			if not _matches(actual[index], expected[index], depth + 1): return false
		return true
	return actual == expected
