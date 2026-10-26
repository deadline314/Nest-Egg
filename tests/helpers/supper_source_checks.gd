extends RefCounted
const Sources := preload("res://game/story_result_sources.gd")
const Supper := preload("res://game/story_result_supper.gd")

static func run(s: TestSuite) -> void:
	var scenes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Sources.SOURCE))["scenes"]
	var locations := {}
	for id: String in scenes:
		locations[id] = Sources.SOURCE
	var before := var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])
	for id: String in Supper.BOUNDARIES:
		s.check(not Sources.boundary(id, scenes, locations).is_empty(), "actual supper result has a finite contract: " + id)
		if not Supper.BOUNDARIES[id]["then"].is_empty():
			s.check(String(Sources.continuation(id, scenes, locations)) == Supper.BOUNDARIES[id]["then"], "same original stall source retains its actual unread segment: " + id)
	for id: String in Supper.CHOICES:
		s.check(not Sources.choice_step(id, scenes, locations).is_empty(), "all original menu/default/condition paths validate: " + id)
	var root := "ch1_t_supper_choice_ordered"
	var leaf := "ch1_t_supper_stay_address"
	var changed := scenes.duplicate(true)
	changed[leaf]["results"].append({"kind":"item_acquire","id":"ch1_data_disk"})
	s.check(Sources.choice_step(root, changed, locations).is_empty(), "a distant altered terminal cannot smuggle an item through an earlier choice")
	changed = scenes.duplicate(true)
	changed["ch1_t_supper_stay_meal"]["then"] = "ch1_t_supper_host_prompt"
	s.check(Sources.choice_step(root, changed, locations).is_empty(), "an outgoing cycle rejects the incoming original menu")
	var foreign := locations.duplicate()
	foreign[leaf] = "res://data/story/ch2_heron.json"
	s.check(Sources.choice_step(root, scenes, foreign).is_empty(), "same-named foreign descendant cannot impersonate the stall family")
	var option: Dictionary = scenes[root]["steps"].back()["options"][0].duplicate(true)
	for malformed: Variant in [true, false, 1, {}, [], "unknown"]:
		var forged := option.duplicate(true)
		forged["set_flags"]["ch1_supper_choice"] = malformed
		s.check(Sources.choice(root, forged, scenes, locations).is_empty(), "material enum choice rejects malformed or undeclared value")
	var menu := "ch1_t_supper_leave_options"
	changed = scenes.duplicate(true)
	changed[menu]["steps"].back()["options"][2].erase("when")
	s.check(Sources.choice_step(menu, changed, locations).is_empty(), "rechoose cannot remove its irreversibility condition")
	changed = scenes.duplicate(true)
	changed[root]["steps"][6]["time"] = 99.0
	s.check(Sources.choice_step(root, changed, locations).is_empty(), "the one registered short authored pause cannot become unbounded waiting")
	s.check(Sources.failure("ch1_t_supper_pay", "insufficient_credits", scenes, locations) == &"ch1_t_supper_insufficient", "actual insufficient money keeps the original unpaid options")
	for reason: String in ["io_error", "already_completed", "invalid_definition"]:
		s.check(Sources.failure("ch1_t_supper_pay", reason, scenes, locations) == &"", "no other failure can masquerade as insufficient money: " + reason)
	changed = scenes.duplicate(true)
	changed["ch1_t_supper_pay"]["on_failure"]["insufficient_credits"] = leaf
	s.check(Sources.failure("ch1_t_supper_pay", "insufficient_credits", changed, locations) == &"", "failure route cannot bypass payment and reveal address")
	var entry := &"ch1_dispatch_ali_stall"
	var npc: String = Supper.NPC_SOURCE["npc"]
	for pair: Array in [["ch1_t_supper_pay","ch1_t_supper_paid_goodbye"],["ch1_t_supper_tab","ch1_t_supper_tab_goodbye"]]:
		var completed := {StringName(pair[0]):true}
		s.check(Sources.pending_terminal(npc, entry, pair[1], scenes, locations, completed), "only successful original producer admits its pending goodbye")
		s.check(not Sources.pending_terminal(npc, entry, pair[1], scenes, locations, {}), "uncommitted producer cannot grant a goodbye continuation")
		completed[StringName(pair[1])] = true
		s.check(not Sources.pending_terminal(npc, entry, pair[1], scenes, locations, completed), "completed goodbye cannot be resumed or counted again")
		s.check(not Sources.pending_terminal("res://data/npcs/ch1_ali_lounge.tres", entry, pair[1], scenes, locations, {StringName(pair[0]):true}), "another actual Ali placement cannot own the stall goodbye")
	s.check(before == var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()]), "graph/producer preflight never mutates any live owner")
