extends RefCounted
const ACTIONS := {"radio_tune_clear": "ch2_t_s02_broadcast", "radio_tune_noise": "ch2_t_s02_tune_wrong"}
const PROP := "res://data/environment/scene_props/radio_workbench/radio_workbench__radio_open_bench.tres"
const Catalog := preload("res://core/story_result_catalog.gd")

static func run(s: TestSuite) -> void:
	_test_projection(s)
	for id: String in ACTIONS:
		var spec := WorldPropAction.definition(id)
		s.check(WorldPropAction.problem(id, ACTIONS[id], true).is_empty(), "authored radio turn is valid: " + id)
		s.check(not WorldPropAction.problem(id, "foreign_scene", true).is_empty(), "radio turn cannot be borrowed by another scene")
		var action := WorldPropAction.new()
		action._spec = spec
		s.check(action._without_reaction(), "static radio knob needs no invented flag reaction")
		for bad: Variant in [0, "true", null]:
			spec["crouch"] = bad
			s.check(not WorldPropAction.problem(id, ACTIONS[id], true).is_empty(), "malformed crouch is rejected")
		spec["crouch"] = true
		spec["reaction"] = ""
		s.check(not WorldPropAction.problem(id, ACTIONS[id], true).is_empty(), "a declared empty reaction cannot become a static knob")
		spec.erase("reaction")
		_test_reach(s, id)
	var pump := WorldPropAction.new()
	pump._spec = WorldPropAction.definition("pump_wheel_drain")
	s.check(not pump._without_reaction(), "the existing drain wheel still requires its declared reaction")

static func _test_projection(s: TestSuite) -> void:
	var catalog := Catalog.new()
	var sealed: Dictionary = catalog._migration["routes"]["ch2_dispatch_radio"]["ch2_t_s02_broadcast"]["effects"]
	var scene: Dictionary = Story._scenes["ch2_t_s02_broadcast"]
	s.check(scene["steps"][0] == {"do": "world_action", "id": "radio_tune_clear"} and Catalog._same_effects(scene, sealed), "map hand presentation keeps original sealed radio effects")
	for field_value: Array in [["set_flags", {"forbidden": true}], ["results", [{"kind": "item_grant", "id": "ch2_radio_clip"}]], ["then", "ch2_t_s02_off"]]:
		var bad := scene.duplicate(true)
		bad[field_value[0]] = field_value[1]
		s.check(not Catalog._same_effects(bad, sealed), "map hands cannot hide scene effects: " + field_value[0])
	var choice_flags := scene.duplicate(true)
	choice_flags["steps"][-1]["set_flags"] = {"forbidden": true}
	s.check(not Catalog._same_effects(choice_flags, sealed), "map hands cannot hide choice flags")
	var flow := scene.duplicate(true)
	flow["steps"][-1]["options"][0]["target"] = "ch2_t_s02_off"
	s.check(not Catalog._same_effects(flow, sealed), "map hands cannot hide changed choice flow")

static func _test_reach(s: TestSuite, id: String) -> void:
	var spec := WorldPropAction.definition(id)
	var prop := PropNode.new()
	prop.setup(load(PROP), Vector2(944, 274))
	s.runner.add_child(prop)
	var rig := CharacterRig.new()
	s.runner.add_child(rig)
	s.check(rig.setup("rin"), "radio contact uses the actual Rin rig")
	rig.global_position = prop.to_global(Vector2(spec["station"][0], spec["station"][1]))
	var input := RigInput.new()
	input.facing = 1
	input.aim_dir = Vector2.RIGHT
	input.on_floor = true
	input.hand_grip_front = true
	input.crouching = true
	for frame in 30: rig.animate(1.0 / 60.0, input)
	var action := WorldPropAction.new()
	action._spec = spec
	action._prop = weakref(prop)
	var worst := 0.0
	var failures := 0
	for frame in 120:
		for sample in 9:
			rig.animate(1.0 / 60.0, input)
			var target := action.rim_global(action._turn_angle(sample / 8.0))
			if not rig.place_hand(&"front", target, 0): failures += 1
			worst = maxf(worst, rig.hand_contact_global(&"front").distance_to(target))
	s.check(failures == 0 and worst <= WorldPropAction.CONTACT_TOLERANCE, "radio crouch reaches every real knob point: %s worst %s failures %s" % [id, worst, failures])
	rig.queue_free()
	prop.queue_free()
