extends RefCounted
## Optional crouch foot targets, their exits, and an isolated corrupt-data error.
const SKIN := "collector_brute"
const MOTION := "res://art/motion/collector_brute.json"
const FEET := [&"foot_front", &"foot_back"]


static func run(s: TestSuite) -> void:
	var source := RigLibrary.load_json(MOTION)
	var actions := RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH)
	var fixture := actions.duplicate(true)
	fixture["actions"]["collector_brute.test_feet"] = {"duration": 0.2, "blend": 14, "keys": [{"t": 0.0, "bones": {"foot_front": 0.4, "foot_back": -0.2}}, {"t": 1.0, "bones": {"foot_front": 0.4, "foot_back": -0.2}}]}
	RigLibrary._json_cache[HumanoidAnimator.ACTIONS_PATH] = fixture
	for facing in [-1, 1]:
		var motion := source.duplicate(true)
		motion["crouch"]["feet"] = [-0.8, -1.3]
		RigLibrary._json_cache[MOTION] = motion
		var rig := CharacterRig.new()
		s.runner.add_child(rig)
		s.check(rig.setup(SKIN), "crouch foot fixture builds")
		RigLibrary._json_cache[MOTION] = source
		var input := RigInput.new()
		input.facing = facing
		input.on_floor = true
		input.aim_dir = Vector2(facing, 0)
		input.run_speed = 76.0
		input.velocity.x = 38.0 * facing
		step(rig, input, 180)
		input.crouching = true
		input.velocity = Vector2.ZERO
		input.action = &"collector_brute.windup_slash"
		input.action_t = 1.0
		grounded_steps(s, rig, input, "walk to crouch")
		var animator := rig.animator as HumanoidAnimator
		s.check(absf(animator.foot_angle(FEET[0])) < 0.001 and absf(animator.foot_angle(FEET[1])) < 0.001, "configured crouch keeps both boots horizontal facing %d" % facing)
		input.crouching = false
		input.velocity.x = 38.0 * facing
		input.action = &""
		grounded_steps(s, rig, input, "crouch to walk")
		s.check(animator._gait_w >= 0.999 and animator._action_w <= 0.001, "leaving crouch restores the complete gait facing %d" % facing)
		input.velocity = Vector2.ZERO
		step(rig, input, 90)
		var worst_angle := 0.0
		for frame in 12:
			rig.animate(1.0 / 60.0, input)
			for foot in FEET:
				worst_angle = maxf(worst_angle, absf(animator.foot_angle(foot)))
		s.check(worst_angle < 0.001, "both boots stay horizontal while returning to idle facing %d (%.6f)" % [facing, worst_angle])
		input.on_floor = false
		input.velocity.y = -80.0
		step(rig, input, 90)
		input.on_floor = true
		input.velocity = Vector2.ZERO
		step(rig, input, 1)
		s.check(absf(animator.foot_angle(FEET[0])) < 0.001 and absf(animator.foot_angle(FEET[1])) < 0.001, "both boots use the ground plane on the first landing frame")
		input.crouching = true
		input.velocity = Vector2.ZERO
		input.action = &"collector_brute.test_feet"
		step(rig, input, 90)
		s.check(absf(animator._angles[FEET[0]] - 0.4) < 0.001 and absf(animator._angles[FEET[1]] + 0.2) < 0.001, "explicit foot action retains priority")
		input.crouching = false
		step(rig, input, 90)
		s.check(absf(animator._angles[FEET[0]] - 0.4) < 0.001 and absf(animator._angles[FEET[1]] + 0.2) < 0.001, "explicit grounded foot action retains priority")
		input.crouching = false
		input.action = &""
		step(rig, input, 90)
		s.check(absf(animator.foot_angle(FEET[0])) < 0.001 and absf(animator.foot_angle(FEET[1])) < 0.001, "released foot action returns both boots to the ground plane")
		input.crouching = true
		input.action = &"collector_brute.test_feet"
		step(rig, input, 90)
		input.dead = true # Keep both stale inputs, as an interrupted enemy FSM can.
		step(rig, input, 90)
		s.check(at_base(animator) and animator._action_w <= 0.001, "death clears stale crouch and foot action facing %d" % facing)
		rig.free()
	RigLibrary._json_cache[HumanoidAnimator.ACTIONS_PATH] = actions
	RigLibrary._json_cache[MOTION] = source
	for empty in [false, true]:
		var motion := source.duplicate(true)
		if empty:
			motion["crouch"]["feet"] = []
		else:
			(motion["crouch"] as Dictionary).erase("feet")
		RigLibrary._json_cache[MOTION] = motion
		var rig := CharacterRig.new()
		s.runner.add_child(rig)
		s.check(rig.setup(SKIN), "legacy foot fixture builds")
		var input := RigInput.new()
		input.crouching = true
		var pose := (rig.animator as HumanoidAnimator)._body_pose(0, input, Vector2.ZERO, 0)
		s.check(not pose.has(FEET[0]) and not pose.has(FEET[1]), "omitted/empty feet preserve the legacy target set")
		rig.free()
	RigLibrary._json_cache[MOTION] = source
	for value: Variant in [[], [0, 0], [-PI, PI]]:
		s.check(HumanoidAnimator.crouch_feet_problem(value).is_empty(), "empty and finite boundary foot values are valid")
	s.check(not HumanoidAnimator.crouch_feet_problem(["bad", 0]).is_empty(), "invalid foot element is identified")
	# Capture the real production error in a separate process. Do not silence the
	# engine error channel or let this expected corrupt fixture pollute suite logs.
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "120", "res://tests/probes/rig_crouch_feet_invalid.tscn"])
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true)
	var raw := "\n".join(PackedStringArray(output))
	var expected := "ERROR: [HumanoidAnimator] res://art/motion/collector_brute.json: crouch.feet"
	var valid := exit_code == 0 and raw.contains("CROUCH_FEET_INVALID_SAFE") and raw.count(expected) == 1 and raw.count("ERROR:") == 1 and not raw.contains("SCRIPT ERROR")
	if not valid:
		printerr(raw)
	s.check(valid, "invalid feet safely fall back and report the character/field exactly once")


static func step(rig: CharacterRig, input: RigInput, frames: int) -> void:
	for frame in frames:
		rig.animate(1.0 / 60.0, input)


static func at_base(animator: HumanoidAnimator) -> bool:
	return absf(animator._angles[FEET[0]]) < 0.001 and absf(animator._angles[FEET[1]]) < 0.001


static func grounded_steps(s: TestSuite, rig: CharacterRig, input: RigInput, label: String) -> void:
	var worst_float := 0.0
	var worst_below := 0.0
	for frame in 90:
		rig.animate(1.0 / 60.0, input)
		var animator := rig.animator as HumanoidAnimator
		var error := animator._lowest_foot_y() - animator.ground_level()
		worst_float = maxf(worst_float, -error)
		worst_below = maxf(worst_below, error)
	s.check(worst_float <= float(AnimAudit.LIMITS["foot_floating"]) and worst_below <= float(AnimAudit.LIMITS["foot_below_ground"]), "%s uses the existing grounded foot limits (float %.4f, below %.4f)" % [label, worst_float, worst_below])
