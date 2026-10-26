extends RefCounted
## A resumed frozen scene must not give combat one unrequested physics step.

class WorldClock extends Node2D:
	var steps := 0
	func _physics_process(_delta: float) -> void:
		steps += 1
		position.x += 1.0


static func run(s: TestSuite) -> void:
	const ID := &"test_resume_paused_world"
	var previous_skip := Story.auto_skip
	Story.reset_active_presentation(&"test_resume_scope")
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	Story._scenes[String(ID)] = {"mode": "animated", "overlay": true, "steps": [{"do": "wait", "time": 60.0}]}
	s.check(not Story.uses_world_actions(ID), "ordinary overlay does not request world physics initialization")
	s.check(Story.uses_world_actions(&"ch1_t_handoff_accept") and Story.uses_world_actions(&"ch1_t_handoff_receipt"), "both authored physical cabinet segments request real physics initialization")
	s.check(not Story.uses_world_actions(&"missing_world_action_scene"), "missing scene cannot request physics initialization")
	var data := (load("res://data/levels/ch1_handoff.tres") as LevelData).duplicate() as LevelData
	data.intro_scene = &""
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	level.configure_resume({"cinematic": String(ID)})
	var world := WorldClock.new()
	level.add_child(world)
	var start_steps: Array[int] = [-1]
	var queued_steps: Array[int] = [-1]
	# The fixture may be created inside an existing physics signal. Compare the
	# queued restore boundary, not unrelated work before deferred initialization.
	var mark_queued_restore := func() -> void:
		queued_steps[0] = world.steps
	level.tree_entered.connect(func() -> void: mark_queued_restore.call_deferred(), CONNECT_ONE_SHOT)
	var started := func(id: StringName, _mode: StringName) -> void:
		if id == ID:
			start_steps[0] = world.steps
	Story.scene_started.connect(started)
	s.runner.get_tree().root.add_child(level)
	for i in 20:
		await s.runner.get_tree().process_frame
		if start_steps[0] >= 0:
			break
	await s.frames(2)
	s.check(start_steps[0] >= 0 and queued_steps[0] >= 0, "ordinary saved cinematic resumes through the real Level and its queued restore boundary")
	s.check(start_steps[0] == queued_steps[0], "ordinary cinematic resume adds no world physics step after queued restoration")
	s.check(s.runner.get_tree().paused and world.steps == start_steps[0], "resumed cinematic keeps live world motion frozen")
	print("RESUME_PHYSICS_SCOPE ", JSON.stringify({"queued_restore_steps": queued_steps[0], "start_steps": start_steps[0], "observed_steps": world.steps, "extra_steps": start_steps[0] - queued_steps[0]}))
	Story.scene_started.disconnect(started)
	Story.reset_active_presentation(&"test_resume_scope_cleanup")
	Story._scenes.erase(String(ID))
	await s.end_level(level)
	Story.auto_skip = previous_skip
