extends RefCounted
## 可選蹲姿髖角的資料邊界、舊資料相容性及各出口；不改骨長與落腳解法。
const SKIN := "ch2_greycoat"
const MOTION := "res://art/motion/ch2_greycoat.json"


static func run(s: TestSuite) -> void:
	for value: Variant in [0, 0.0, -PI * .5, PI * .5, 1.0]:
		s.check(HumanoidAnimator.crouch_hip_problem(value).is_empty(), "蹲姿髖角接受有限值與合法邊界")
	for value: Variant in [null, false, "1", [], {}, NAN, INF, -INF, PI * .5 + .001, -PI * .5 - .001]:
		s.check(not HumanoidAnimator.crouch_hip_problem(value).is_empty(), "蹲姿髖角拒絕錯誤型別、非有限值與超界角度")
	var source := RigLibrary.load_json(MOTION)
	var rigs: Array[CharacterRig] = []
	for configured in [false, true]:
		var fixture := source.duplicate(true)
		(fixture["crouch"] as Dictionary).erase("hip")
		if configured: fixture["crouch"]["hip"] = 0.0
		RigLibrary._json_cache[MOTION] = fixture
		var rig := CharacterRig.new()
		s.runner.add_child(rig)
		s.check(rig.setup(SKIN), "舊資料零旋轉相容性角色可建立")
		rigs.append(rig)
	RigLibrary._json_cache[MOTION] = source
	for state in ["idle", "walk", "crouch", "dash", "air", "block", "dead"]:
		var input := _input(state)
		var a := (rigs[0].animator as HumanoidAnimator)._body_pose(0, input, input.velocity, 0)
		var b := (rigs[1].animator as HumanoidAnimator)._body_pose(0, input, input.velocity, 0)
		s.check(a == b, "省略 hip 與明寫零在 %s 產生完全相同的舊目標" % state)
	for rig in rigs: rig.free()
	var fixture := source.duplicate(true)
	fixture["crouch"]["hip"] = 1 # JSON 整數亦須被正確轉為弧度。
	RigLibrary._json_cache[MOTION] = fixture
	var rig := CharacterRig.new()
	s.runner.add_child(rig)
	s.check(rig.setup(SKIN), "有限蹲姿髖角角色可建立")
	RigLibrary._json_cache[MOTION] = source
	var animator := rig.animator as HumanoidAnimator
	for facing in [-1, 1]:
		for state in ["idle", "walk", "dash", "air", "block", "dead"]:
			var input := _input("crouch")
			input.facing = facing
			_step(rig, input)
			s.check(absf(float(animator._angles[&"hip"]) - 1.0) < .001, "蹲姿正反向均到達資料髖角")
			input = _input(state)
			input.facing = facing
			if state == "dead": input.crouching = true # 中斷時殘留蹲輸入不能覆蓋死亡。
			_step(rig, input)
			var target := animator._body_pose(0, input, input.velocity, 0)
			s.check(absf(angle_difference(float(animator._angles[&"hip"]), float(target[&"hip"]))) < .001, "離開蹲姿至 %s 會回到該姿勢髖角" % state)
			input = _input("idle")
			_step(rig, input)
			s.check(absf(float(animator._angles[&"hip"])) < .001, "釋放與中斷後待機回到零旋轉")
	rig.free()


static func _input(state: String) -> RigInput:
	var input := RigInput.new()
	input.two_handed = false
	match state:
		"walk": input.velocity.x = 40.0
		"crouch": input.crouching = true
		"dash": input.dashing = true
		"air": input.on_floor = false; input.velocity.y = -40.0
		"block": input.blocking = true
		"dead": input.dead = true
	return input


static func _step(rig: CharacterRig, input: RigInput) -> void:
	for frame in 100: rig.animate(1.0 / 60.0, input)
