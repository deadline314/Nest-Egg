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
