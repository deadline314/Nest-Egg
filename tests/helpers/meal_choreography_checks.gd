extends RefCounted
## Real dispatcher/rig/prop clocks; no Story result dispatch in this preview.

class Monitor extends Node:
	var player: CutscenePlayer
	var samples := 0
	var mouth_samples := 0
	var contact_error := 0.0
	var hold_error := 0.0
	var mouth_error := 0.0
	var ate := false
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 100
	func _process(_delta: float) -> void:
		if not is_instance_valid(player) or player._stage == null or not player._actors.has(&"rin"):
			return
		var stage := player._stage
		var actor: CutsceneActor = player._actors[&"rin"]
		var reach := actor._reaches[0]
		ate = ate or stage.prop_state("noodle_table") == "eaten"
		if reach.weight >= .999 and reach.active():
			var target := reach.target + actor.position if reach._actor_space else reach.target
			contact_error = maxf(contact_error, stage.actors.to_local(actor.hand_contact_global(&"front")).distance_to(target))
			samples += 1
		if not stage.prop_held("meal_chopsticks"):
			return
		var sticks := stage.prop_node("meal_chopsticks") as StageLayers._Sprite
		var palm := stage.to_local(actor.hand_contact_global(&"front"))
		hold_error = maxf(hold_error, stage.to_local(sticks.to_global(sticks.source_point(Vector2(310, 481)))).distance_to(palm))
		if not reach.settled() or reach._binding == null or not stage.prop_node("meal_noodles").visible:
			return
		var head := actor.rig.contact_part(&"head")
		var lip := stage.to_local(head.to_global(CharacterRig.part_source_point(head, Vector2(152, 145))))
		var tip := stage.to_local(sticks.to_global(sticks.source_point(Vector2(1110, 503))))
		mouth_error = maxf(mouth_error, lip.distance_to(tip))
		mouth_samples += 1


static func run(s: TestSuite) -> void:
	var facts := var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])
	var steps: Array = Story._scenes["ch1_t_supper_stay_meal"]["steps"].duplicate(true)
	for index in steps.size():
		if steps[index]["do"] == "say":
			steps[index] = {"do": "wait", "time": .01}
	steps.append({"do": "wait", "time": 300.0})
	var player := CutscenePlayer.new()
	var monitor := Monitor.new()
	monitor.player = player
	s.runner.add_child(player)
	s.runner.add_child(monitor)
	player.play(&"meal_choreography_fixture", {"steps": steps})
	var deadline := Time.get_ticks_msec() + 60000
	while player.steps_run < steps.size() - 1 and Time.get_ticks_msec() < deadline:
		await s.frames(1)
	s.check(player.steps_run == steps.size() - 1, "formal eating beat completes through the real dispatcher")
	s.check(monitor.samples > 12 and monitor.contact_error < .08, "actual full-weight palm stays reachable throughout the eating path (%.5f)" % monitor.contact_error)
	s.check(monitor.hold_error < .08, "same rotating utensil remains joined to the actual palm (%.5f)" % monitor.hold_error)
	s.check(monitor.mouth_samples > 2 and monitor.mouth_error < .08, "visible tips meet actual breathing lips before food disappears (%.5f)" % monitor.mouth_error)
	var stage := player._stage
	var table := stage.prop_node("noodle_table") as StageLayers._Sprite
	var world_table := load("res://data/environment/scene_props/dawn_noodle_stall/dawn_noodle_stall__noodle_bowls_table.tres") as PropData
	var canvas := Vector2(table.texture.get_size()) * table.scale
	var expected := world_table.size * 1.7
	s.check(absf(canvas.x - expected.x) < .01 and absf(canvas.y - expected.y) <= 1.0, "actual map and stage table retain the same physical dimensions within original half-import rounding")
	s.check(SceneAudit.stage_prop_issues("ch1_dawn_noodle_stall", StageLibrary.definition(&"ch1_dawn_noodle_stall"), 1.7).is_empty(), "measured tabletop/feet body passes original proportions and floor rules")
	s.check(not world_table.has_glow and table._glow_sprite == null, "non-emissive table cannot resurrect baked utensils from an obsolete glow map")
	var sticks := stage.prop_node("meal_chopsticks") as StageLayers._Sprite
	var bowl := stage.to_local(table.to_global(table.source_point(Vector2(85, 55))))
	var tip := stage.to_local(sticks.to_global(sticks.source_point(Vector2(1110, 503))))
	s.check(tip.distance_to(bowl) < .08, "returned actual utensil tip rests on the visible bowl source point (%.5f)" % tip.distance_to(bowl))
	s.check(monitor.ate and stage.prop_state("noodle_table") == "eaten", "formal ending retains the original left-bowl eaten state")
	s.check(not stage.prop_held("meal_chopsticks") and not stage.prop_node("meal_noodles").visible and not player._actors[&"rin"].hand_targets_active(), "natural eating end releases hand and prop ownership with food hidden")
	player.cancel()
	monitor.queue_free()
	await s.frames(3)
	s.check(facts == var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()]), "physical eating preview cannot award money, items or story outcomes")
