extends RefCounted
## Exercise the authored mechanics with the real dispatcher and update clocks.
## Dialogue is shortened; results remain owned by Story, never by this preview.

class ContactMonitor extends Node:
	var player: CutscenePlayer
	var samples := 0
	var worst_contact := 0.0
	var worst_hold := 0.0
	var witnessed_flow := false
	var witnessed_lid := false
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 100  # Actors 0, held stage props 10, then observations.
	func _process(_delta: float) -> void:
		if not is_instance_valid(player) or player._stage == null:
			return
		var stage := player._stage
		witnessed_flow = witnessed_flow or stage.prop_node("tap_water").visible
		witnessed_lid = witnessed_lid or stage.prop_node("kettle_lid").rotation > 1.1
		for id: StringName in player._actors:
			var actor: CutsceneActor = player._actors[id]
			for reach: CutsceneReach in actor._reaches:
				if reach.weight < .999 or not reach.active():
					continue
				var target := reach.target + actor.position if reach._actor_space else reach.target
				var actual := stage.actors.to_local(actor.hand_contact_global(reach.hand))
				worst_contact = maxf(worst_contact, actual.distance_to(target))
				samples += 1
		if stage.prop_held("kettle"):
			var kettle := stage.prop_node("kettle") as StageLayers._Sprite
			var grip := stage.to_local(kettle.to_global(kettle.source_point(Vector2(350, 200))))
			var palm := stage.to_local(player._actors[&"k"].hand_contact_global(&"front"))
			worst_hold = maxf(worst_hold, grip.distance_to(palm))


static func run(s: TestSuite) -> void:
	var facts := var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])
	var formal: Dictionary = Story._scenes["ch1_c14_home"]
	var steps: Array = formal["steps"].duplicate(true)
	for index in steps.size():
		if steps[index]["do"] == "say":
			steps[index] = {"do": "wait", "time": .01}
		elif steps[index]["do"] == "fade":
			steps[index] = {"do": "wait", "time": 300.0}
	var player := CutscenePlayer.new()
	var monitor := ContactMonitor.new()
	monitor.player = player
	s.runner.add_child(player)
	s.runner.add_child(monitor)
	player.play(&"kitchen_choreography_fixture", {"steps": steps})
	var deadline := Time.get_ticks_msec() + 160000
	while is_instance_valid(player) and player.steps_run < steps.size() - 1 and Time.get_ticks_msec() < deadline:
		await s.frames(1)
	s.check(player.steps_run == steps.size() - 1, "authored kitchen mechanics finish through the real dispatcher")
	s.check(monitor.witnessed_flow and monitor.witnessed_lid, "actual animated lid opens and local filling flow runs")
	s.check(monitor.samples > 20 and monitor.worst_contact < .08, "full-weight contacts remain reachable throughout posture and target transitions (%.5f)" % monitor.worst_contact)
	s.check(monitor.worst_hold < .08, "actual held source point follows the palm throughout authored carry (%.5f)" % monitor.worst_hold)
	var stage := player._stage
	s.check(stage.prop_node("kettle").position.distance_to(_mat_support(stage)) < .08 and stage.prop_state("kettle") == "filled", "natural choreography sets the full kettle down on the physical mat")
	s.check(not stage.prop_held("kettle") and not stage.prop_node("tap_water").visible and not stage.prop_node("stove_flame").visible and absf(stage.prop_node("kettle_lid").rotation) < .001, "natural end releases held ownership with stove tap and lid closed")
	player.cancel()
	monitor.queue_free()
	await s.frames(3)
	s.check(facts == var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()]), "mechanical playback cannot change story custody or progression")
	var cold := StageLibrary.build(&"ch1_pawnshop_kitchen")
	s.check(cold.prop_state("kettle") == "filled" and cold.prop_node("kettle").position.distance_to(_mat_support(cold)) < .001 and not cold.prop_node("tap_water").visible and not cold.prop_node("stove_heat").visible, "fresh stage rebuilds the cold filled state instead of retaining an interrupted flow")
	cold.free()


static func _mat_support(stage: StageLibrary.Stage) -> Vector2:
	var surface := (stage.prop_node("kettle_mat") as StageLayers._Rect)._rect
	return Vector2(surface.get_center().x, surface.position.y)
