extends RefCounted
const Sources := preload("res://game/story_result_sources.gd")

static func run(s: TestSuite) -> void:
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Sources.SOURCE))
	var scenes: Dictionary = chapter["scenes"]
	var locations := {}
	for id: String in scenes:
		locations[id] = Sources.SOURCE
	for id: String in ["ch1_t_ali_name", "ch1_t_ali_2_ordered", "ch1_t_ali_2_sit", "ch1_t_ali_evening_close"]:
		s.check(not Sources.boundary(id, scenes, locations).is_empty(), "authored Ali boundary owns exactly its original flag: " + id)
	for id: String in ["ch1_t_ali_2_ordered", "ch1_t_ali_2_sit"]:
		s.check(Sources.continuation(id, scenes, locations) == &"ch1_t_ali_evening_close", "both real account states preserve the same original closing continuation: " + id)
	var changed := scenes.duplicate(true)
	changed["ch1_t_ali_evening_close"]["results"].append({"kind": "transaction", "id": "ch1.revival_meal.paid"})
	s.check(Sources.continuation("ch1_t_ali_2_ordered", changed, locations) == &"", "a flag continuation cannot lead to an unvalidated money-producing terminal")
	changed = scenes.duplicate(true)
	changed["ch1_t_ali_evening_close"]["then"] = "ch1_t_ali_2_sit"
	s.check(Sources.continuation("ch1_t_ali_2_sit", changed, locations) == &"", "an outgoing terminal cycle invalidates the incoming finite continuation")
	var foreign := locations.duplicate()
	foreign["ch1_t_ali_evening_close"] = "res://data/story/ch2_heron.json"
	s.check(Sources.continuation("ch1_t_ali_2_sit", scenes, foreign) == &"", "another loaded source cannot impersonate Ali's authored closing boundary")

	for id: String in ["ch1_t_ali_order", "ch1_t_ali_sit"]:
		s.check(Sources.continuation(id, scenes, locations) == &"ch1_t_ali_name", "actual reception preserves its unread same-person name: " + id)
		s.check(Story.outcomes.result_contract_problem(StringName(id), scenes[id]).is_empty(), "canonical reception admits its limited result strategy: " + id)
	for key: String in ["kind", "id"]:
		for malformed: Variant in [false, 1, {}, [], "wrong"]:
			changed = scenes.duplicate(true)
			changed["ch1_t_ali_order"]["results"][0][key] = malformed
			s.check(Sources.continuation("ch1_t_ali_order", changed, locations) == &"", "receipt contract rejects untyped or changed transaction " + key)
	changed = scenes.duplicate(true)
	changed["ch1_t_ali_order"]["results"][0]["credits_delta"] = 200
	s.check(Sources.continuation("ch1_t_ali_order", changed, locations) == &"", "finite order cannot add an unregistered amount override")
	changed = scenes.duplicate(true)
	changed["ch1_t_ali_order"]["results"][1]["id"] = "ch1_data_disk"
	s.check(Sources.continuation("ch1_t_ali_order", changed, locations) == &"", "finite order cannot grant another item")
	changed = scenes.duplicate(true)
	changed["ch1_t_ali_order"]["results"].reverse()
	s.check(Sources.continuation("ch1_t_ali_order", changed, locations) == &"", "finite result order stays authored")
	changed = scenes.duplicate(true)
	changed["ch1_t_ali_order"]["results"][2]["value"] = {}
	s.check(Sources.continuation("ch1_t_ali_order", changed, locations) == &"", "flag payload remains strictly boolean before comparing")
	changed = scenes.duplicate(true)
	changed["ch1_t_ali_order"]["completion_policy"] = Sources.CONTINUATION
	s.check(Sources.continuation("ch1_t_ali_order", changed, locations) == &"" and not Story.outcomes.result_contract_problem(&"ch1_t_ali_order", changed["ch1_t_ali_order"]).is_empty(), "flag-only policy still refuses the order's money and item operations")
	foreign = locations.duplicate()
	foreign["ch1_t_ali_name"] = "res://data/story/ch2_heron.json"
	s.check(Sources.continuation("ch1_t_ali_order", scenes, foreign) == &"", "reception must retain the same authored name source")
