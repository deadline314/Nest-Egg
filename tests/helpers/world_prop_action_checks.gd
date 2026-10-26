extends RefCounted

static func run(suite: TestSuite) -> void:
	_test_resume_choices(suite)
	for pair: Array in [["handoff_insert", "ch1_t_handoff_accept"], ["handoff_take_paper", "ch1_t_handoff_receipt"]]:
		suite.check(WorldPropAction.problem(pair[0], pair[1], true).is_empty(), "authored world action accepts JSON numeric facing: " + pair[0])
		suite.check(not WorldPropAction.problem(pair[0], "another_scene", true).is_empty(), "a world action cannot be borrowed by another scene")
		suite.check(not WorldPropAction.problem(pair[0], pair[1], false).is_empty(), "a world action requires the actual map overlay")
	var spec := WorldPropAction.definition("handoff_insert")
	var original := spec.duplicate(true)
	for bad: Variant in [true, "1", 0, 0.5, INF, NAN]:
		spec["facing"] = bad
		suite.check(not WorldPropAction.problem("handoff_insert", "ch1_t_handoff_accept", true).is_empty(), "bad world action facing is rejected: " + str(bad))
	spec.assign(original)
	for bad: Variant in [null, [true, 2], [1, "2"], [INF, 0], [0, NAN], [0, 257]]:
		spec["station"] = bad
		suite.check(not WorldPropAction.problem("handoff_insert", "ch1_t_handoff_accept", true).is_empty(), "bad world action station is rejected: " + str(bad))
	spec.assign(original)
	for bad: Variant in [true, "5", -1, 0, 9, INF, NAN]:
		spec["width"] = bad
		suite.check(not WorldPropAction.problem("handoff_insert", "ch1_t_handoff_accept", true).is_empty(), "bad held item width is rejected: " + str(bad))
	spec.assign(original)
	suite.check(WorldPropAction.problem("handoff_insert", "ch1_t_handoff_accept", true).is_empty(), "invalid controls restore the original world action")
	for id: Variant in [null, true, 1, "../handoff_insert", "missing_world_action"]:
		suite.check(not WorldPropAction.problem(id, "ch1_t_handoff_accept", true).is_empty(), "world action names never resolve arbitrary paths")
	var camera := LevelCamera.new()
	var first := RefCounted.new()
	var second := RefCounted.new()
	var prior := camera.process_mode
	var zoom := camera.zoom
	suite.check(not camera.acquire_presentation_focus(first, Vector2.INF), "invalid camera focus does not acquire ownership")
	suite.check(camera.acquire_presentation_focus(first, Vector2(300, 290)) and camera.process_mode == Node.PROCESS_MODE_ALWAYS,
			"one presentation may frame the paused world")
	suite.check(not camera.acquire_presentation_focus(second, Vector2.ZERO), "a second presentation cannot steal camera focus")
	camera.release_presentation_focus(second)
	suite.check(camera._presentation_owner != null and camera._presentation_owner.get_ref() == first, "non-owner camera cleanup is harmless")
	camera.release_presentation_focus(first)
	suite.check(camera._presentation_owner == null and camera.process_mode == prior and camera.zoom == zoom,
			"own camera cleanup restores processing and preserves zoom")
	camera.free()


static func _test_resume_choices(suite: TestSuite) -> void:
	var scenes := {
		"test_world_resume_root": {"mode": "animated", "steps": [{"do": "branch", "steps": [{"do": "choice", "options": [{"target": "test_world_resume_choice"}]}]}]},
		"test_world_resume_choice": {"mode": "animated", "then": "test_world_resume_tail"},
		"test_world_resume_tail": {"mode": "animated", "then": "test_world_resume_root"},
		"test_world_resume_foreign": {"mode": "animated"},
	}
	for id: String in scenes:
		suite.check(not Story._scenes.has(id), "resume fixture never replaces authored scene: " + id)
		Story._scenes[id] = scenes[id]
	suite.check(Story.is_chained_scene(&"test_world_resume_root", &"test_world_resume_choice"), "cold NPC resume follows an authored choice inside a branch")
	suite.check(Story.is_chained_scene(&"test_world_resume_root", &"test_world_resume_tail"), "cold NPC resume follows choice then continuation")
	suite.check(not Story.is_chained_scene(&"test_world_resume_root", &"test_world_resume_foreign"), "cyclic authored chain cannot authorize an unrelated completion")
	suite.check(not Story.is_chained_scene(&"test_world_resume_root", &"missing_world_resume"), "cyclic authored chain terminates for a missing segment")
	Story._scenes["test_world_resume_root"]["steps"] = [{"do": "choice", "options": null}]
	suite.check(not Story.is_chained_scene(&"test_world_resume_root", &"test_world_resume_choice"), "malformed choice cannot authorize a resumed result")
	for id: String in scenes:
		Story._scenes.erase(id)
	for i in 70:
		Story._scenes["test_world_resume_bound_" + str(i)] = {"mode": "animated", "then": "test_world_resume_bound_" + str(i + 1)}
	suite.check(Story.is_chained_scene(&"test_world_resume_bound_0", &"test_world_resume_bound_2"), "bounded resume traversal keeps ordinary continuations")
	suite.check(not Story.is_chained_scene(&"test_world_resume_bound_0", &"test_world_resume_bound_69"), "oversized resume chain stops at the declared safety limit")
	for i in 70:
		Story._scenes.erase("test_world_resume_bound_" + str(i))
