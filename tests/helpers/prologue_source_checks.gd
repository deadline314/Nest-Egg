extends RefCounted
const Sources := preload("res://game/story_result_sources.gd")
const IDS := ["ch1_p05_service_fall","ch1_p05_service_clean","ch1_p06_call"]

static func run(s: TestSuite) -> void:
	var scenes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Sources.SOURCE))["scenes"]
	var locations := {}
	for id: String in scenes:
		locations[id] = Sources.SOURCE
	var before := var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot(),Story.progress_snapshot()])
	for id: String in IDS:
		s.check(not Sources.boundary(id,scenes,locations).is_empty(),"actual original prologue counter result has a finite contract: "+id)
		var changed := scenes.duplicate(true)
		changed[id]["results"][0]["value"] = false
		s.check(Sources.boundary(id,changed,locations).is_empty(),"counter contract cannot undo a different progression result: "+id)
		changed = scenes.duplicate(true)
		changed[id]["results"].append({"kind":"item_acquire","id":"ch1_grey_cloth"})
		s.check(Sources.boundary(id,changed,locations).is_empty(),"tutorial counter cannot add a clinic reward: "+id)
		changed = scenes.duplicate(true)
		changed[id]["then"] = "ch1_t_clinic_cloth_take"
		s.check(Sources.boundary(id,changed,locations).is_empty(),"terminal counter result cannot smuggle an unowned continuation: "+id)
		var foreign := locations.duplicate()
		foreign[id] = "res://data/story/ch2_heron.json"
		s.check(Sources.boundary(id,scenes,foreign).is_empty(),"foreign same-named scene cannot impersonate original prologue: "+id)
	s.check(before == var_to_bytes([GameState.world_flags,Progression.snapshot(),StoryItems.snapshot(),Story.progress_snapshot()]),"prologue producer preflight is read-only")
