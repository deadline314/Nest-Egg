extends RefCounted

static func run(s: TestSuite) -> void:
	const STAGE := &"ch1_dawn_noodle_stall"
	var stage := StageLibrary.build(STAGE)
	var prop: Sprite2D = stage._props.get("noodle_table")
	s.check(prop != null and stage.prop_state("noodle_table") == "default", "formal noodle table begins with its original full bowl texture")
	if prop == null:
		stage.free()
		return
	var original := prop.texture
	var origin := prop.position
	var size := Vector2(original.get_size()) * prop.scale
	var facts := var_to_bytes([GameState.world_flags, StoryItems.snapshot(), Progression.snapshot(), Story.progress_snapshot()])
	s.check(stage.set_prop_state("noodle_table", "eaten"), "formal table can select its actual registered after-meal texture")
	s.check(prop.texture != original and prop.position == origin, "texture state changes without moving its furniture anchor")
	var next_size := Vector2(prop.texture.get_size()) * prop.scale
	s.check(absf(next_size.x - size.x) < 0.01 and absf(next_size.y - size.y) <= 1.0, "different source resolutions preserve world width and floor baseline within one stage pixel")
	s.check(facts == var_to_bytes([GameState.world_flags, StoryItems.snapshot(), Progression.snapshot(), Story.progress_snapshot()]), "visual prop state cannot grant story flags items credits or completion")
	var selected := prop.texture
	s.check(not stage.set_prop_state("noodle_table", "unknown") and not stage.set_prop_state("missing", "eaten") and prop.texture == selected, "unknown state and prop leave the actual rendered texture intact")
	s.check(stage.set_prop_state("noodle_table", "default") and prop.texture == original, "returning to default restores the identical source texture")
	stage.free()
	var replacement := StageLibrary.build(STAGE)
	s.check(replacement.prop_state("noodle_table") == "default", "a fresh stage cannot inherit another player's eaten state")
	replacement.free()
	var definition := {"kind": "sprite", "path": "res://art/environment/props/trash_can.png", "pos": [0, 0], "id": "fixture", "states": {"bad": {"path": "res://art/missing.png"}}}
	s.check(not StageLayers.prop_state_problem(definition).is_empty(), "missing state texture is a content error")
	definition["states"] = {"bad": {"path": definition["path"], "handler": "queue_free"}}
	s.check(not StageLayers.prop_state_problem(definition).is_empty(), "state definitions reject arbitrary extra fields and handlers")
	var invalid := {"mode": "animated", "steps": [{"do": "scene", "id": String(STAGE)}, {"do": "prop", "id": "noodle_table", "state": "unknown"}]}
	s.check(not CutsceneChecker.validate("test_bad_cutscene_prop", invalid, {}).is_empty(), "cutscene checker refuses unregistered prop states before playback")
	invalid["steps"][0]["prop_states"] = {"noodle_table": "unknown"}
	s.check(not CutsceneChecker.validate("test_bad_cutscene_prop", invalid, {}).is_empty(), "cutscene checker also refuses invalid initial states before fade-in")
	var meal: Dictionary = Story._scenes["ch1_t_supper_stay_meal"]
	var state_index := -1
	var finished_line := -1
	for i in meal["steps"].size():
		var step: Dictionary = meal["steps"][i]
		if step.get("do") == "prop" and step.get("state") == "eaten":
			state_index = i
		if str(step.get("text", "")).begins_with("這碗我吃完了"):
			finished_line = i
	s.check(state_index >= 0 and state_index < finished_line, "the formal authored meal changes its visible bowl before Rin says she finished")
	var address: Dictionary = Story._scenes["ch1_t_supper_stay_address"]
	s.check(address["steps"][0].get("prop_states", {}).get("noodle_table") == "eaten", "the formal next segment reconstructs eaten state before its first fade-in")
