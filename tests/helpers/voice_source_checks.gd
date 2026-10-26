extends RefCounted
const Sources := preload("res://game/story_result_sources.gd")


static func run(s: TestSuite) -> void:
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Sources.SOURCE))
	var scenes: Dictionary = chapter["scenes"]
	var locations := {}
	for id: String in scenes:
		locations[id] = Sources.SOURCE
	var before := var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])
	for id: String in Sources.CHOICES:
		s.check(not Sources.choice_step(id, scenes, locations).is_empty(), "authored optional question validates every finite target: " + id)
	var first := "ch1_t_lamp_voice_first"
	var prompt := "ch1_t_lamp_voice_prompt"
	var second := "ch1_t_lamp_voice_second_prompt"
	s.check(Sources.continuation(first, scenes, locations) == StringName(second), "flag-only first reading owns exactly its authored next question")
	s.check(Story.outcomes.result_contract_problem(StringName(first), scenes[first]).is_empty(), "canonical first reading satisfies the flag-only continuation policy")
	var illegal: Dictionary = scenes[first].duplicate(true)
	illegal["results"].append({"kind": "item_acquire", "id": "ch1_grey_cloth"})
	s.check(not Story.outcomes.result_contract_problem(StringName(first), illegal).is_empty(), "flag continuation cannot grant an item through a broader result kind")
	illegal = scenes[first].duplicate(true)
	illegal["completion_policy"] = "unadvertised_atomic_policy"
	s.check(not Story.outcomes.result_contract_problem(StringName(first), illegal).is_empty(), "adding a flag continuation never advertises arbitrary atomic policies")
	var option: Dictionary = scenes[prompt]["steps"].back()["options"][0].duplicate(true)
	var foreign := locations.duplicate()
	foreign[prompt] = "res://data/story/ch2_heron.json"
	s.check(Sources.choice(prompt, option, scenes, foreign).is_empty(), "another chapter cannot impersonate the authored headset source")
	var forged := option.duplicate(true)
	forged["set_flags"] = {"sq5_lamp_voice_noticed": true}
	s.check(Sources.choice(prompt, forged, scenes, locations).is_empty(), "an accepted first question cannot smuggle the unread final answer")
	forged = option.duplicate(true)
	forged["set_flags"] = 7
	s.check(Sources.choice(prompt, forged, scenes, locations).is_empty(), "malformed choice flags reject without calling collection methods on a scalar")
	var changed := scenes.duplicate(true)
	changed[second]["steps"].back()["default"] = "ask"
	s.check(Sources.choice_step(second, changed, locations).is_empty() and Sources.continuation(first, changed, locations) == &"", "a changed material default invalidates both question and incoming continuation")
	changed = scenes.duplicate(true)
	changed["ch1_t_lamp_voice_later"]["results"] = [{"kind": "flag", "id": "sq5_lamp_voice_noticed", "value": true}]
	s.check(Sources.boundary("ch1_t_lamp_voice_later", changed, locations).is_empty(), "the repeatable later reply must remain result-free")
	s.check(before == var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()]), "source preflight has no live owner mutations")
