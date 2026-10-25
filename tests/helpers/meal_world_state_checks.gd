extends RefCounted
## Map presentation follows the existing accepted meal flag; no new outcomes.

static func run(s: TestSuite) -> void:
	const FLAG := &"ch1_supper_meal_done"
	var flags := GameState.world_flags.duplicate(true)
	var facts := var_to_bytes([Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/ch1_stall_map.json"))
	var registered := false
	for entry: Dictionary in map.get("props", []):
		if entry.get("id") == "dawn_noodle_stall__noodle_bowls_table":
			registered = entry.get("react") == "noodle_meal"
	s.check(registered, "actual stall map binds its table to the accepted meal state")
	var data := load("res://data/environment/scene_props/dawn_noodle_stall/dawn_noodle_stall__noodle_bowls_table.tres") as PropData
	GameState.set_flag(FLAG, false)
	var host := PropNode.new()
	host.setup(data, Vector2(100, 250))
	s.runner.add_child(host)
	var reaction := PropReaction.attach(host, "noodle_meal", data.size)
	s.check(reaction != null and not reaction.is_swapped() and host.get_child(0).visible, "uncompleted meal keeps the actual full-bowl map sprite")
	GameState.set_flag(FLAG, true)
	var replacement := reaction._swap_node
	s.check(reaction.is_swapped() and replacement.visible and not host.get_child(0).visible, "accepted meal hides the old table and reveals the actual eaten variant")
	s.check(replacement.data.size.is_equal_approx(data.size) and not replacement.data.has_glow, "map state replacement preserves support dimensions without a stale utensil glow")
	GameState.set_flag(FLAG, true)
	s.check(reaction._swap_node == replacement and not reaction.is_processing(), "repeated completion reuses one idle replacement without replaying animation")
	host.free()
	var cold := PropNode.new()
	cold.setup(data, Vector2(100, 250))
	s.runner.add_child(cold)
	var rebuilt := PropReaction.attach(cold, "noodle_meal", data.size)
	s.check(rebuilt.is_swapped() and rebuilt._swap_node.visible, "new map instance reconstructs eaten state immediately from the real flag")
	cold.free()
	GameState.world_flags = flags
	s.check(facts == var_to_bytes([Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()]), "map visual replacement cannot award items, credits or story completion")
