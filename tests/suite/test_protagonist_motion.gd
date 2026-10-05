class_name ProtagonistMotionSuite
extends TestSuite
## 主角動作重設計（NE-191）：新的動作欄位預設值＝不啟用（其他角色的動作完全不變）、凜全速奔跑有騰空而走路沒有、
## 慣性前傾的方向（加速前傾、煞車後仰）、待機時腳固定在地上而骨盆會移動、步態形狀函式的行為。
## NE-192：空中姿勢連續混合、起跳蹬地伸展、落地吸收（下沉再彈回）、衣襬衝量只作用在有資料的角色、整個節點的擠壓縮小。

const DT := 1.0 / 60.0
const OTHERS: Array[String] = ["trooper", "trooper_elite", "sniper", "flamer", "grenadier", "enforcer", "heavy_gunner", "warden", "reclaimer", "slasher", "stalker", "old_k", "mei"]


func run() -> void:
	_test_defaults_are_inert()
	_test_gait_shape()
	_test_inertia_lean()
	await _test_flight_only_at_full_speed()
	await _test_idle_feet_stay_planted()
	await _test_air_pose_is_continuous()
	await _test_takeoff_stretch()
	await _test_landing_absorbs_and_recovers()
	await _test_spring_impulses()
	_test_node_squash_is_soft()


func _make(skin: String, input: RigInput) -> CharacterRig:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(skin), "rig builds: %s" % skin)
	rig.set_weapon("rifle")
	input.facing = 1
	input.on_floor = true
	input.aim_dir = Vector2.RIGHT
	input.two_handed = true
	return rig


func _run(rig: CharacterRig, input: RigInput, frames_count: int) -> void:
	for i in frames_count:
		rig.animate(DT, input)


## 兩腳離地的高度中較低的那一隻（骨架空間，往上為正）：全速奔跑騰空時會大於 0。
func _lowest_foot_height(animator: HumanoidAnimator) -> float:
	return animator.ground_level() - animator._lowest_foot_y()


func _test_defaults_are_inert() -> void:
	var defaults := HumanoidAnimator.DEFAULT_MOTION
	check(float(defaults["inertia"]["gain"]) == 0.0, "default motion has no inertia lean")
	check(float(defaults["move"]["bounce"]) == 0.0 and float(defaults["move"]["rise"]) == 0.0, "default motion has no body bounce")
	check(float(defaults["move"]["duty"]) >= HumanoidAnimator.WALK_DUTY, "default motion has no flight phase")
	check(not bool(defaults["idle"]["pin_feet"]), "default motion does not pin the feet in idle")
	for key: String in (defaults["torso"] as Dictionary).keys():
		check(float(defaults["torso"][key]) == 0.0, "default torso %s is off" % key)
	check(float(defaults["foot"]["heel"]) == 0.0 and float(defaults["foot"]["toe_off"]) == 0.0, "default foot roll is off")
	for skin in OTHERS:
		var motion := HumanoidAnimator._load_motion(skin)
		check(float(motion["inertia"]["gain"]) == 0.0, "%s: inertia lean stays off" % skin)
		check(float(motion["move"]["bounce"]) == 0.0 and float(motion["move"]["rise"]) == 0.0, "%s: body bounce stays off" % skin)
		check(float(motion["move"]["duty"]) == float(defaults["move"]["duty"]), "%s: stride duty is unchanged" % skin)
		check(not bool(motion["idle"]["pin_feet"]), "%s: idle feet are not pinned" % skin)
		check(float(motion["torso"]["hip_swing"]) == 0.0 and float(motion["torso"]["chest_wobble"]) == 0.0, "%s: torso overlay stays off" % skin)
	check(float(defaults["air"]["apex_speed"]) == 0.0 and float(defaults["air"]["takeoff"]["time"]) == 0.0, "default motion keeps the two-pose air and no takeoff stretch")
	check(float(defaults["land"]["gain"]) == 0.0 and float(defaults["land"]["drop"]) == 0.0, "default motion has no landing absorb")
	check(float(defaults["dash"]["hip_drop"]) == 0.0, "default dash does not lower the body")
	for key: String in (defaults["impulse"] as Dictionary).keys():
		check(float(defaults["impulse"][key]) == 0.0, "default spring impulse %s is off" % key)
	for skin in OTHERS:
		var motion := HumanoidAnimator._load_motion(skin)
		check(float(motion["air"]["apex_speed"]) == 0.0 and float(motion["land"]["gain"]) == 0.0 and float(motion["dash"]["hip_drop"]) == 0.0, "%s: air, landing and dash stay as before" % skin)
		check(float(motion["impulse"]["jump"]) == 0.0 and float(motion["impulse"]["land"]) == 0.0, "%s: no spring impulses" % skin)
	var rin := HumanoidAnimator._load_motion("rin")
	check(float(rin["move"]["duty"]) < HumanoidAnimator.WALK_DUTY, "rin runs with a flight phase (duty %.2f)" % float(rin["move"]["duty"]))
	check(float(rin["inertia"]["gain"]) > 0.0 and bool(rin["idle"]["pin_feet"]), "rin has inertia lean and planted idle feet")


func _test_gait_shape() -> void:
	check(is_nan(GaitShape.body_sag(0.3, 0.44, 0.0, 0.0)), "body sag is disabled (NAN) without bounce or rise")
	var duty := 0.44
	var mid_stance := GaitShape.body_sag(duty * 0.5, duty, 5.0, 2.0)
	var mid_flight := GaitShape.body_sag(0.25 + duty * 0.5, duty, 5.0, 2.0)
	check(is_equal_approx(mid_stance, 5.0), "the body is lowest at mid-stance (%.2f)" % mid_stance)
	check(is_equal_approx(mid_flight, -2.0), "the body is highest in mid-flight (%.2f)" % mid_flight)
	check(is_equal_approx(GaitShape.body_sag(duty * 0.5 + 0.5, duty, 5.0, 2.0), mid_stance), "the bounce repeats once per step (twice per cycle)")
	var legacy := {"droop": 0.25, "heel": 0.0, "toe_off": 0.0}
	check(is_equal_approx(GaitShape.foot_angle(0.7, 0.55, 0.6, legacy), 0.25 * 0.6), "without roll the foot angle is the old droop")
	check(is_zero_approx(GaitShape.foot_angle(0.2, 0.55, 0.0, legacy)), "without roll the planted foot is flat")
	var roll := {"droop": 0.35, "heel": -0.3, "toe_off": 0.5}
	check(GaitShape.foot_angle(0.0, 0.44, 0.0, roll) < -0.2, "heel strike tilts the toe up")
	check(absf(GaitShape.foot_angle(0.44 * 0.5, 0.44, 0.0, roll)) < 0.1, "mid-stance the foot is flat")
	check(GaitShape.foot_angle(0.43, 0.44, 0.0, roll) > 0.3, "toe-off presses the toe down")


func _test_inertia_lean() -> void:
	var params := {"gain": 0.2, "ref_accel": 1600.0, "stiffness": 90.0, "damping": 11.0, "max": 0.3}
	var lean := InertiaLean.new()
	var speed := 0.0
	var peak := 0.0
	for i in 12:
		speed += 1600.0 * DT
		peak = maxf(peak, lean.update(DT, speed, params))
	check(peak > 0.08, "accelerating leans the body forward (%.3f)" % peak)
	for i in 120:
		lean.update(DT, speed, params)
	check(absf(lean.update(DT, speed, params)) < 0.01, "the lean settles at a steady speed")
	var low := 0.0
	for i in 10:
		speed = maxf(0.0, speed - 2100.0 * DT)
		low = minf(low, lean.update(DT, speed, params))
	check(low < -0.08, "braking leans the body back (%.3f)" % low)
	var off := InertiaLean.new()
	check(off.update(DT, 100.0, {"gain": 0.0}) == 0.0 and off.update(DT, 200.0, {"gain": 0.0}) == 0.0, "gain 0 turns the lean off")
	var flipped := InertiaLean.new()
	flipped.update(DT, 150.0, params)
	flipped.reset(-150.0)  # 面向翻轉：速度正負號改變，不能被當成巨大加速度
	var spike := 0.0
	for i in 10:
		spike = maxf(spike, absf(flipped.update(DT, -150.0, params)))
	check(spike < 0.02, "flipping the facing does not cause a lean spike (%.3f)" % spike)


func _test_flight_only_at_full_speed() -> void:
	var input := RigInput.new()
	var rig := _make("rin", input)
	input.run_speed = 150.0
	input.velocity = Vector2(150.0, 0.0)
	_run(rig, input, 60)
	var best := -INF
	var worst := INF
	for i in 120:
		rig.animate(DT, input)
		var height := _lowest_foot_height(rig.animator)
		best = maxf(best, height)
		worst = minf(worst, height)
	check(best > 0.5, "rin has a flight phase at full speed (both feet %.2f px off the ground)" % best)
	check(worst > -2.5, "rin's feet never sink into the ground while running (%.2f)" % worst)
	input.velocity = Vector2(70.0, 0.0)  # 走路（速度比例 0.47）
	_run(rig, input, 60)
	best = -INF
	for i in 120:
		rig.animate(DT, input)
		best = maxf(best, _lowest_foot_height(rig.animator))
	check(best < 0.5, "at walking speed one foot is always on the ground (%.2f)" % best)
	rig.get_parent().queue_free()
	await frames(1)


func _test_idle_feet_stay_planted() -> void:
	var input := RigInput.new()
	var rig := _make("rin", input)
	_run(rig, input, 90)
	var foot_min := INF
	var foot_max := -INF
	var hip_min := INF
	var hip_max := -INF
	for i in 600:  # 10 秒：超過一個重心轉移的週期
		rig.animate(DT, input)
		var foot_x := rig.animator.bone_pos(&"foot_front").x
		var hip_x := rig.animator.bone_pos(&"hip").x
		foot_min = minf(foot_min, foot_x)
		foot_max = maxf(foot_max, foot_x)
		hip_min = minf(hip_min, hip_x)
		hip_max = maxf(hip_max, hip_x)
	check(foot_max - foot_min < 0.5, "idle: the planted foot does not slide (%.2f px)" % (foot_max - foot_min))
	check(hip_max - hip_min > 1.5, "idle: the pelvis shifts side to side so the weight moves (%.2f px)" % (hip_max - hip_min))
	check(absf(_lowest_foot_height(rig.animator)) < 0.6, "idle: the feet stay on the ground (%.2f)" % _lowest_foot_height(rig.animator))
	rig.get_parent().queue_free()
	await frames(1)


func _airborne(input: RigInput, vy: float) -> void:
	input.on_floor = false
	input.velocity = Vector2(80.0, vy)


## 垂直速度由上升掃到下落時，每一格每根骨頭的角度變化都很小（沒有在頂點瞬間切換姿勢）。
func _test_air_pose_is_continuous() -> void:
	var input := RigInput.new()
	var rig := _make("rin", input)
	_run(rig, input, 30)
	_airborne(input, -420.0)
	_run(rig, input, 20)
	var previous: Dictionary = {}
	var worst := 0.0
	var vy := -420.0
	while vy < 420.0:
		_airborne(input, vy)
		rig.animate(DT, input)
		for bone_name in rig.animator._rig.bone_order():
			var rotation := rig.bone(bone_name).rotation
			if previous.has(bone_name):
				worst = maxf(worst, absf(wrapf(rotation - float(previous[bone_name]), -PI, PI)))
			previous[bone_name] = rotation
		vy += 1000.0 * DT
	check(worst < 0.12, "the air pose changes smoothly from rising to falling (worst %.3f rad per frame)" % worst)
	rig.get_parent().queue_free()
	await frames(1)


## 起跳後前 0.1 秒後腿向後伸直蹬地，之後收腿（後腿大腿的角度變小）。
func _test_takeoff_stretch() -> void:
	var input := RigInput.new()
	var rig := _make("rin", input)
	_run(rig, input, 30)
	_airborne(input, -420.0)
	input.jumped = true
	_run(rig, input, 1)
	input.jumped = false
	_run(rig, input, 6)
	var stretched := rig.bone(&"leg_back_upper").rotation
	_run(rig, input, 30)
	var tucked := rig.bone(&"leg_back_upper").rotation
	check(stretched > tucked + 0.05, "right after take-off the back leg is pushed out behind, then tucks (%.2f → %.2f)" % [stretched, tucked])
	rig.get_parent().queue_free()
	await frames(1)


## 落地：骨盆先下沉（吸收衝擊），然後彈回站姿；衝擊越大下沉越深。
func _test_landing_absorbs_and_recovers() -> void:
	var depths: Array[float] = []
	for impact in [0.3, 1.0]:
		var input := RigInput.new()
		var rig := _make("rin", input)
		_run(rig, input, 120)
		var standing := rig.bone(&"hip").position.y
		var lowest := standing
		input.landed = impact
		for i in 90:
			rig.animate(DT, input)
			input.landed = 0.0
			lowest = maxf(lowest, rig.bone(&"hip").position.y)
		depths.append(lowest - standing)
		check(absf(rig.bone(&"hip").position.y - standing) < 1.0, "after landing the body returns to standing height (impact %.1f)" % impact)
		rig.get_parent().queue_free()
	check(depths[0] > 1.0, "a light landing still bends the knees (%.2f px)" % depths[0])
	check(depths[1] > depths[0] + 1.0 and depths[1] < 14.0, "a hard landing sinks deeper but not through the floor (%.2f vs %.2f px)" % [depths[1], depths[0]])
	await frames(1)


## 起跳、落地時凜的衣襬與頭髮被注入速度（有資料）；沒有資料的角色完全不動。
func _test_spring_impulses() -> void:
	for skin: String in ["rin", "trooper"]:
		var input := RigInput.new()
		var rig := _make(skin, input)
		_run(rig, input, 120)
		var before: float = 0.0
		for bone_name: StringName in rig.animator._spring_velocity.keys():
			before += absf(rig.animator._spring_velocity[bone_name])
		input.landed = 0.8
		rig.animate(DT, input)
		var after: float = 0.0
		for bone_name: StringName in rig.animator._spring_velocity.keys():
			after += absf(rig.animator._spring_velocity[bone_name])
		if skin == "rin":
			check(after > before + 1.0, "landing kicks rin's coat and hair springs (%.2f → %.2f)" % [before, after])
		else:
			check(absf(after - before) < 0.5, "%s springs are not kicked by landing (%.2f → %.2f)" % [skin, before, after])
		rig.get_parent().queue_free()
	await frames(1)


func _test_node_squash_is_soft() -> void:
	check(PlayerVisual.SQUASH_SCALE <= 0.35, "the sprite squash is a third of the old amount or less (%.2f)" % PlayerVisual.SQUASH_SCALE)
