extends RefCounted
## Compare the rejected lateral pull against a supported downward detachment,
## across real idle poses with the same fixed bones and registered closed palm.

static func run(suite: TestSuite) -> void:
	var prop := PropNode.new()
	var data := load("res://data/environment/scene_props/handoff/handoff__commission_cabinet.tres") as PropData
	prop.setup(data, Vector2(288,263))
	suite.runner.add_child(prop)
	var reaction := PropReaction.attach(prop, "handoff_cabinet", data.size)
	var rig := CharacterRig.new()
	suite.runner.add_child(rig)
	suite.check(rig.setup("rin"), "receipt reach regression uses the actual Rin rig")
	rig.position = Vector2(312,320)
	var input := RigInput.new()
	input.facing = -1
	input.on_floor = true
	input.hand_grip_front = true
	var paper := reaction._paper_visual
	var start := paper.to_global(Vector2(0,paper.length))
	var old_goal := start + Vector2(-2,2)
	var goal := start + Vector2(0,1)
	var rejected := 0
	var failures := 0
	var worst := 0.0
	for frame in 360:
		rig.animate(1.0/60.0,input)
		if not rig.place_hand(&"front", old_goal, PI):
			rejected += 1
		rig.animate(0.0,input)
		if not rig.place_hand(&"front", goal, PI):
			failures += 1
		worst = maxf(worst,rig.hand_contact_global(&"front").distance_to(goal))
	print("PAPER_REACH %s" % JSON.stringify({"poses":360,"legacy_unreachable":rejected,
		"downward_unreachable":failures,"worst_palm_error":worst}))
	suite.check(rejected > 0, "the original lateral receipt pull exceeds fixed-bone reach in real idle poses: " + str(rejected))
	suite.check(failures == 0 and worst <= WorldPropAction.CONTACT_TOLERANCE,
			"downward paper detachment stays reachable throughout real idle poses: " + str(worst))
	var action := WorldPropAction.new()
	action._paper_start = start
	action._spec = WorldPropAction.definition("handoff_take_paper")
	action.phase = "pull"
	# The pull's goal uses the paper, independent of the player argument.
	suite.check(action._goal(null,reaction).distance_to(goal) < 0.001,
			"the actual receipt choreography uses the verified detachment goal")
	rig.free()
	prop.free()
