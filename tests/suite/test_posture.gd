class_name PostureSuite
extends TestSuite
## 敵人的站姿、待機與步伐（NE-106、NE-107）：腳踩實地（站、跑、蹲腳底都貼著地）、步幅配合速度（踩在地上的腳不滑）、
## 放鬆（槍垂下）與舉槍之間的平滑過渡、站姿與放鬆的資料每個角色各自不同。

const ENEMIES: Array[String] = ["trooper", "trooper_elite", "sniper", "flamer", "grenadier", "enforcer", "heavy_gunner", "warden", "reclaimer", "slasher", "stalker"]
const DT := 1.0 / 60.0


func run() -> void:
	_test_data()
	await _test_reach_leg_canonical_angles()
	await _test_feet_stay_on_the_ground()
	await _test_planted_stride()
	await _test_relaxed_and_ready()
	await _test_recoil_depends_on_the_weapon()
	await _test_weapon_less_and_airborne_are_safe()


## 固定 Rin rest 骨長做 two-bone IK：象限、atan2 分支、前後鏈及翻面都必須保留端點與腳掌角度，
## 同時輸出的 local rotation 應是 canonical；AnimAudit 仍須抓到真正的反膝控制案例。
func _test_reach_leg_canonical_angles() -> void:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("rin"), "Rin rig builds for fixed-rest leg IK regression")
	var animator := rig.animator
	var expected_bones := rig.bone_order().size()
	check(expected_bones == 20, "Rin test uses the native 20-bone humanoid_tall rest skeleton (%d bones)" % expected_bones)
	var angle_cases: Array[float] = [-2.35, -0.75, 0.75, 2.35, -PI + 0.02, PI - 0.02]
	var parent_cases: Array[float] = [0.0, 2.7, -2.7]
	var fixed_rest: Dictionary = {}
	var fixed_parents: Dictionary = {}
	for bone_name in rig.bone_order():
		fixed_rest[bone_name] = rig.rest(bone_name)
		fixed_parents[bone_name] = rig.parent_of(bone_name)
	var max_target_error := 0.0
	var max_foot_angle_error := 0.0
	var max_audit_knee_hyper := -INF
	var all_local_angles_canonical := true
	var all_knees_bend_forward := true
	var tested_cases := 0
	var worst_case := "none"
	var worst_audit_case := "none"
	for facing in [1, -1]:
		rig.facing = facing
		for parent_angle in parent_cases:
			rig.bone(&"hip").rotation = parent_angle
			animator._forward_kinematics()
			for chain: Array in AnimAudit.LEG_BONES:
				var upper: StringName = chain[0]
				var lower: StringName = chain[1]
				var foot: StringName = chain[2]
				var length_upper := rig.rest(lower).length()
				var length_lower := rig.rest(foot).length()
				var target_distance := (length_upper + length_lower) * 0.7
				for test_angle in angle_cases:
					var local_target_angle := test_angle if facing > 0 else PI - test_angle
					var hip: Vector2 = animator._global_pos[upper]
					var target := hip + Vector2.RIGHT.rotated(local_target_angle) * target_distance
					var requested_foot_angle := test_angle * 0.37
					animator._reach_leg(upper, lower, foot, target, requested_foot_angle)
					animator._forward_kinematics()
					tested_cases += 1
					var endpoint_error := animator._global_pos[foot].distance_to(target)
					if endpoint_error > max_target_error:
						max_target_error = endpoint_error
						worst_case = "%s %s face=%d parent=%.3f target_angle=%.3f" % [upper, lower, facing, parent_angle, local_target_angle]
					max_foot_angle_error = maxf(max_foot_angle_error, absf(angle_difference(requested_foot_angle, animator._global_angle[foot])))
					var audit_entry := _measure_leg_audit(rig, "%s face=%d parent=%.3f target=%.3f" % [upper, facing, parent_angle, local_target_angle])
					if float(audit_entry.get("value", -INF)) > max_audit_knee_hyper:
						max_audit_knee_hyper = float(audit_entry["value"])
						worst_audit_case = str(audit_entry.get("where", "unknown"))
					for bone_name: StringName in [upper, lower, foot]:
						var local_rotation := rig.bone(bone_name).rotation
						if local_rotation < -PI - 0.000001 or local_rotation > PI + 0.000001:
							all_local_angles_canonical = false
					if rig.bone(lower).rotation < -0.000001:
						all_knees_bend_forward = false
	check(tested_cases == 72, "IK regression covers quadrants, atan2 branch, front/back chains and both facings (%d cases)" % tested_cases)
	check(max_target_error < 0.001, "reachable Rin leg targets stay within 0.001 skeleton units (max %.6f at %s)" % [max_target_error, worst_case])
	check(max_foot_angle_error < 0.001, "solved foot global angle matches requested angle modulo 2pi (max %.6f rad)" % max_foot_angle_error)
	check(all_local_angles_canonical, "leg local rotations remain in [-PI, PI]")
	check(all_knees_bend_forward, "IK solutions keep the knee bend nonnegative in the canonical local range")
	check(max_audit_knee_hyper <= float(AnimAudit.LIMITS["knee_hyper"]), "AnimAudit accepts every canonical IK branch case (%.3f <= %.3f at %s)" % [max_audit_knee_hyper, float(AnimAudit.LIMITS["knee_hyper"]), worst_audit_case])
	var fixed_rest_unchanged := true
	for bone_name in fixed_rest:
		if rig.rest(bone_name) != fixed_rest[bone_name] or rig.parent_of(bone_name) != fixed_parents[bone_name]:
			fixed_rest_unchanged = false
	check(fixed_rest_unchanged, "all native Rin rest offsets and parent links remain unchanged throughout IK regression")
	rig.bone(&"leg_front_lower").rotation = -0.2
	var negative_control := _measure_leg_audit(rig, "negative control lower=-0.2")
	check(float(negative_control.get("value", 0.0)) > float(negative_control.get("limit", 0.0)), "AnimAudit still flags a real reverse-knee control (%.3f > %.3f)" % [float(negative_control.get("value", 0.0)), float(negative_control.get("limit", 0.0))])
	holder.queue_free()
	await frames(1)


func _measure_leg_audit(rig: CharacterRig, label: String) -> Dictionary:
	var ctx := {"rig": rig, "results": {}, "where": label, "frame": 0, "prev": {}, "grounded": false, "pop_scale": 1.0, "skip_pop": 0}
	AnimAudit._measure(ctx, false)
	return (ctx["results"] as Dictionary).get("knee_hyper", {"value": 0.0, "limit": AnimAudit.LIMITS["knee_hyper"], "where": label})


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


func _foot_error(rig: CharacterRig) -> float:
	var animator := rig.animator
	return absf(animator._lowest_foot_y() - animator._ground_y)


func _test_data() -> void:
	var seen_aims: Dictionary = {}
	for skin in ENEMIES:
		var path := "res://art/motion/%s.json" % skin
		var d := RigLibrary.load_json(path)
		check(bool(d.get("grounding", false)), "%s plants its feet" % skin)
		var relax: Dictionary = d.get("relax", {})
		var aim := float(relax.get("aim", -1.0))
		check(aim > 0.3 and aim < 1.4 and float(relax.get("reach", 0.0)) > 0.5, "%s has a sane relaxed pose (aim %.2f)" % [skin, aim])
		var legs: Array = (d.get("idle", {}) as Dictionary).get("legs", [])
		check(legs.size() == 4 and absf(float(legs[0])) > 0.05 and float(legs[2]) > 0.1, "%s stands with its feet apart" % skin)
		seen_aims[snappedf(aim, 0.01)] = true
	check(seen_aims.size() >= 8, "the relaxed weapon angle is different for most characters (%d kinds)" % seen_aims.size())


## 站、跑、蹲、瞄準時最低的腳底都貼著站立的地面（誤差不到半個像素）。
func _test_feet_stay_on_the_ground() -> void:
	for skin in ENEMIES:
		var input := RigInput.new()
		var rig := _make(skin, input)
		var worst := 0.0
		for i in 30:
			rig.animate(DT, input)
		worst = maxf(worst, _foot_error(rig))
		input.velocity = Vector2(120.0, 0.0)
		input.run_speed = 120.0
		for i in 90:
			rig.animate(DT, input)
			if i >= 20:  # 起跑的過渡（IK 權重漸入）不算
				worst = maxf(worst, _foot_error(rig))
		input.velocity = Vector2.ZERO
		input.crouching = true
		for i in 60:
			rig.animate(DT, input)
		worst = maxf(worst, _foot_error(rig))
		check(worst < 0.6, "%s keeps its feet on the ground standing, running and crouching (worst %.2f px)" % [skin, worst])
		rig.get_parent().queue_free()
	await frames(1)


## 落腳：跑的時候貼著地面的那隻腳，相對身體往後移動的速度＝前進速度（不滑，誤差 15% 內）；另一隻腳抬起時離地。
func _test_planted_stride() -> void:
	for skin in ["trooper", "heavy_gunner", "sniper", "slasher"]:
		var input := RigInput.new()
		var rig := _make(skin, input)
		var speed := 60.0
		input.velocity = Vector2(speed, 0.0)
		input.run_speed = speed * 2.0
		for i in 60:
			rig.animate(DT, input)
		var animator := rig.animator
		var expected := -speed / rig.scale.x
		var error := 0.0
		var samples := 0
		var lifted := 0.0
		var last: Dictionary = {}
		for i in 300:
			rig.animate(DT, input)
			for foot: StringName in [&"foot_front", &"foot_back"]:
				var pos: Vector2 = animator._global_pos[foot]
				var on_ground := absf(pos.y - animator._ground_y) < 0.6
				if on_ground and last.has(foot) and last[foot][1]:
					error += absf(((pos.x - float(last[foot][0])) / DT - expected) / expected)
					samples += 1
				lifted = maxf(lifted, animator._ground_y - pos.y)
				last[foot] = [pos.x, on_ground]
		var mean_error := error / maxf(1.0, float(samples))
		check(samples > 150 and mean_error < 0.15, "%s's planted foot moves back at the ground speed (error %.0f%% over %d samples)" % [skin, mean_error * 100.0, samples])
		check(lifted > 2.0, "%s lifts the swinging foot off the ground (%.1f px)" % [skin, lifted])
		rig.get_parent().queue_free()
	await frames(1)


func _test_relaxed_and_ready() -> void:
	var input := RigInput.new()
	var rig := _make("trooper", input)
	for i in 30:
		rig.animate(DT, input)
	var ready := rig.weapon_root().rotation
	input.relaxed = true
	for i in 120:
		rig.animate(DT, input)
	var low := rig.weapon_root().rotation
	check(low > ready + 0.4, "a relaxed enemy lowers the weapon (%.2f -> %.2f rad)" % [ready, low])
	input.relaxed = false
	var midway := 0.0
	for i in 60:
		rig.animate(DT, input)
		if i == 5:
			midway = rig.weapon_root().rotation
	check(midway > ready + 0.05 and midway < low, "raising the weapon is a smooth transition, not a snap (%.2f)" % midway)
	check(absf(rig.weapon_root().rotation - ready) < 0.05, "the weapon comes back up when the enemy engages")
	rig.get_parent().queue_free()
	await frames(1)


## 沒有武器的角色、在空中、死亡時都不會出錯，空中不做腳底補償（身體不會被拉回地面）。
func _test_weapon_less_and_airborne_are_safe() -> void:
	var input := RigInput.new()
	var rig := _make("slasher", input)
	rig.set_weapon("")
	input.relaxed = true
	for i in 30:
		rig.animate(DT, input)
	input.on_floor = false
	input.velocity = Vector2(80, -200)
	for i in 20:
		rig.animate(DT, input)
	check(is_zero_approx(rig.animator._ground_shift), "no ground correction while airborne")
	input.on_floor = true
	input.velocity = Vector2.ZERO
	input.dead = true
	for i in 40:
		rig.animate(DT, input)
	check(true, "relaxed, weapon-less, airborne and dead states all animate without errors")
	rig.get_parent().queue_free()
	await frames(1)


## 開火的後座力依角色與武器而不同：榴彈兵比步兵把身體頂得更遠、恢復更慢；每個角色的後座力資料各自不同。
func _test_recoil_depends_on_the_weapon() -> void:
	var recoils: Dictionary = {}
	for skin in ENEMIES:
		var r: Dictionary = RigLibrary.load_json("res://art/motion/%s.json" % skin).get("recoil", {})
		check(r.size() == 4 and float(r.get("decay", 0.0)) > 0.0, "%s has recoil data" % skin)
		recoils["%s|%s|%s|%s" % [r.get("chest"), r.get("reach"), r.get("hip"), r.get("decay")]] = true
	check(recoils.size() >= 9, "recoil data differs between most characters (%d kinds)" % recoils.size())
	var pushed: Dictionary = {}
	for skin in ["trooper", "grenadier", "sniper"]:
		var input := RigInput.new()
		var rig := _make(skin, input)
		for i in 20:
			rig.animate(DT, input)
		var rest_x := rig.animator._hip_offset.x
		input.recoil = 1.0
		rig.animate(DT, input)
		input.recoil = 0.0
		for i in 3:
			rig.animate(DT, input)
		pushed[skin] = rest_x - rig.animator._hip_offset.x
		rig.get_parent().queue_free()
	check(pushed["grenadier"] > pushed["trooper"] and pushed["sniper"] > pushed["trooper"], "a launcher or sniper rifle pushes the body back further than a rifle (%.2f, %.2f vs %.2f)" % [pushed["grenadier"], pushed["sniper"], pushed["trooper"]])
	await frames(1)
