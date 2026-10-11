class_name NpcAnimationSuite
extends TestSuite
## NPC 動畫（NE-83）：動畫資料引用的骨頭都存在、姿勢與循環能運作（坐下降低骨盆、說話改變頭與手臂、循環改變手臂、幅度可調）、
## 沒設定或設錯的循環不會崩潰、走動與持武器時退回人形動畫、NPC 資料的循環名稱會被驗證。

const DATA_PATH := "res://art/rigs/npc_animations.json"
const SKIN := "old_k"


func run() -> void:
	_test_data_references_real_bones()
	await _test_poses()
	await _test_poses_touch_the_ground()
	await _test_talking_and_listening()
	await _test_loops()
	await _test_fallbacks()
	await _test_combat_states_use_the_humanoid_animator()
	await _test_springs_add_to_authored_pose()
	_test_garment_hems_swing()
	_test_npc_data_validation()


## 建立一個 NPC 動畫器的骨架並跑幾格讓角度穩定。
func _rig_with(input: RigInput, settle := 40) -> CharacterRig:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(SKIN, "npc"), "an npc rig builds for %s" % SKIN)
	for i in settle:
		rig.animate(1.0 / 60.0, input)
	await frames(1)
	return rig


func _angle(rig: CharacterRig, bone: StringName) -> float:
	return rig.bone(bone).rotation


func _test_data_references_real_bones() -> void:
	var data := RigLibrary.load_json(DATA_PATH)
	check(not data.is_empty(), "npc animation data loads")
	var rig_bones: Array[String] = []
	for bone: Dictionary in RigLibrary.load_json(str(RigLibrary.character(SKIN).get("rig", ""))).get("bones", []):
		rig_bones.append(str(bone["name"]))
	var specials: Array[String] = ["_hip_x", "_hip_y"]
	for section: String in ["poses", "overlays", "loops"]:
		for key: String in (data.get(section, {}) as Dictionary).keys():
			var entry: Dictionary = data[section][key]
			var names: Array[String] = []
			for bone: Variant in (entry.get("bones", {}) as Dictionary).keys():
				names.append(str(bone))
			for track: Dictionary in entry.get("tracks", []):
				names.append(str(track.get("bone", "")))
				check(float(track.get("period", 1.0)) > 0.0, "%s.%s: a track has a positive period" % [section, key])
			for bone_name in names:
				check(rig_bones.has(bone_name) or specials.has(bone_name), "%s.%s only uses bones the rig has: %s" % [section, key, bone_name])
	for pose: String in ["stand", "sit", "lean", "crouch"]:
		check((data.get("poses", {}) as Dictionary).has(pose), "pose exists: %s" % pose)
	for overlay: String in ["talk", "listen", "wave"]:
		check((data.get("overlays", {}) as Dictionary).has(overlay), "overlay exists: %s" % overlay)


func _test_poses() -> void:
	var input := RigInput.new()
	input.two_handed = false
	var stand := await _rig_with(input)
	var stand_hip := stand.bone(&"hip").position.y
	input.npc_pose = &"sit"
	var sit := await _rig_with(input)
	check(sit.bone(&"hip").position.y > stand_hip + 5.0, "sitting lowers the pelvis (%.1f → %.1f)" % [stand_hip, sit.bone(&"hip").position.y])
	check(_angle(sit, &"leg_front_upper") < -1.0, "sitting puts the thigh forward")
	check(absf(_angle(stand, &"arm_front_upper")) < 0.3, "an unarmed standing npc lets the arm hang (no aiming pose)")
	input.npc_pose = &"lean"
	var lean := await _rig_with(input)
	check(_angle(lean, &"chest") < -0.05, "leaning tips the chest back (%.3f)" % _angle(lean, &"chest"))
	input.npc_pose = &"crouch"
	var crouch := await _rig_with(input)
	check(crouch.bone(&"hip").position.y > stand_hip + 4.0, "crouching lowers the pelvis")


## 坐、蹲的時候每個骨架的腳都平放在地面上：最低的腳離地不超過 0.8 像素（不懸空也不陷地），腳掌接近放平。
## 懸空曾經讓凜蹲在櫃台前「像坐在空氣椅子上」；現在用 IK 把腳放在地上，骨盆下沉的量由資料決定。
func _test_poses_touch_the_ground() -> void:
	var skins := PackedStringArray()
	for dir in DirAccess.get_directories_at("res://art/characters"):
		if FileAccess.file_exists("res://art/characters/%s/character.json" % dir):
			skins.append(dir)
	check(skins.size() >= 10, "the character folders were found (%d)" % skins.size())
	for skin in skins:
		for pose: StringName in [&"sit", &"crouch"]:
			var holder := Node2D.new()
			runner.get_tree().root.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			if not rig.setup(skin, "npc"):
				holder.queue_free()
				continue
			var input := RigInput.new()
			input.two_handed = false
			input.npc_pose = pose
			for i in 90:
				rig.animate(1.0 / 60.0, input)
			var floating := rig.animator.ground_level() - rig.animator._lowest_foot_y()
			check(absf(floating) <= 0.8, "%s %s: the lowest foot is on the ground (%.2f px off)" % [skin, pose, floating])
			var foot_angle := absf(rig.animator.foot_angle(&"foot_front"))
			check(foot_angle <= 0.35, "%s %s: the foot lies flat (%.2f rad)" % [skin, pose, foot_angle])
			holder.queue_free()
	await frames(1)


func _test_talking_and_listening() -> void:
	var input := RigInput.new()
	input.two_handed = false
	var quiet := await _rig_with(input)
	var quiet_arm := _angle(quiet, &"arm_front_upper")
	input.talking = true
	var talk := await _rig_with(input, 70)
	check(absf(_angle(talk, &"arm_front_upper") - quiet_arm) > 0.1, "talking moves the arm (gesture)")
	input.talking = false
	input.listening = true
	var listen := await _rig_with(input)
	check(_angle(listen, &"head") > _angle(quiet, &"head") + 0.03, "listening tilts the head")
	input.listening = false
	input.waving = true
	var wave := await _rig_with(input)
	check(_angle(wave, &"arm_front_upper") < -1.8, "waving raises the arm")


func _test_loops() -> void:
	var input := RigInput.new()
	input.two_handed = false
	var base := await _rig_with(input)
	var base_arm := _angle(base, &"arm_front_lower")
	input.npc_loop = &"stir"
	var stir := await _rig_with(input)
	check(absf(_angle(stir, &"arm_front_lower") - base_arm) > 0.3, "the stir loop moves the forearm")
	# 幅度倍率：同一時間點，倍率 0 的循環只剩平均值（沒有擺動）。
	var rig := await _rig_with(input, 1)
	var samples_full: Array[float] = []
	var samples_none: Array[float] = []
	for i in 90:
		input.npc_loop_scale = 1.0
		rig.animate(1.0 / 30.0, input)
		samples_full.append(_angle(rig, &"arm_front_lower"))
	var rig_flat := await _rig_with(input, 1)
	for i in 90:
		input.npc_loop_scale = 0.0
		rig_flat.animate(1.0 / 30.0, input)
		samples_none.append(_angle(rig_flat, &"arm_front_lower"))
	check(_range_of(samples_full) > _range_of(samples_none) + 0.1, "loop_scale 0 removes the swing (%.2f vs %.2f)" % [_range_of(samples_full), _range_of(samples_none)])
	input.npc_loop_scale = 1.0
	# 有 gate 的循環（咳嗽）在一個週期裡會有動作的時段與安靜的時段。
	input.npc_loop = &"cough"
	var cough := await _rig_with(input, 1)
	var low := INF
	var high := -INF
	for i in 8 * 30:
		cough.animate(1.0 / 30.0, input)
		var a := _angle(cough, &"chest")
		low = minf(low, a)
		high = maxf(high, a)
	check(high - low > 0.08, "a gated loop (cough) moves during its window (%.2f)" % (high - low))


func _range_of(values: Array[float]) -> float:
	var low := INF
	var high := -INF
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	return high - low


func _test_fallbacks() -> void:
	var input := RigInput.new()
	input.two_handed = false
	input.npc_pose = &"no_such_pose"
	input.npc_loop = &"no_such_loop"
	var rig := await _rig_with(input)
	check(rig.is_valid() and absf(_angle(rig, &"arm_front_upper")) < 0.3, "an unknown pose and loop fall back to standing without crashing")


func _test_combat_states_use_the_humanoid_animator() -> void:
	var input := RigInput.new()
	input.two_handed = true
	input.velocity = Vector2(150, 0)
	var run := await _rig_with(input)
	check(absf(_angle(run, &"leg_front_upper")) > 0.1 or absf(_angle(run, &"leg_back_upper")) > 0.1, "walking or running still swings the legs")
	var armed := RigInput.new()
	armed.two_handed = true
	armed.aim_dir = Vector2(1, -1).normalized()
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	rig.setup(SKIN, "npc")
	rig.set_weapon("pistol")
	for i in 40:
		rig.animate(1.0 / 60.0, armed)
	await frames(1)
	check(rig.bone(&"hand_front").global_position.distance_to(rig.weapon_root().global_position) < 2.0, "an armed npc actor still holds the weapon (IK)")


func _test_springs_add_to_authored_pose() -> void:
	# Rin uses the humanoid_tall spring rig. Give its coat bone an authored NPC pose
	# through the same cached data path used by NpcAnimator, then restore that cache.
	var had_cached_data := RigLibrary._json_cache.has(DATA_PATH)
	var previous_data: Dictionary = RigLibrary._json_cache.get(DATA_PATH, {}).duplicate(true)
	var test_data := RigLibrary.load_json(DATA_PATH).duplicate(true)
	var poses: Dictionary = test_data["poses"]
	(poses["stand"]["bones"] as Dictionary)["coat_1"] = 0.35
	(poses["sit"]["bones"] as Dictionary)["coat_1"] = -0.35
	RigLibrary._json_cache[DATA_PATH] = test_data

	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("rin", "npc"), "Rin rig loads for authored-cloth spring regression")
	if rig.is_valid() and rig.animator is NpcAnimator and rig.has_bone(&"coat_1"):
		var animator := rig.animator as NpcAnimator
		var input := RigInput.new()
		input.two_handed = false
		input.npc_pose = &"stand"
		for i in 90:
			rig.animate(1.0 / 60.0, input)
		var authored_stand := animator._angles[&"coat_1"]
		var stand_spring := animator._spring_angle[&"coat_1"]
		check(absf(authored_stand) > 0.2, "NPC pose data contributes a nonzero coat author angle (%.3f)" % authored_stand)
		check(is_equal_approx(rig.bone(&"coat_1").rotation, authored_stand + animator._overlay.get(&"coat_1", 0.0) + stand_spring), "spring is added to the authored NPC angle, not substituted")
		var saved_author: float = animator._angles[&"coat_1"]
		var saved_overlay: float = animator._overlay.get(&"coat_1", 0.0)
		var saved_spring: float = animator._spring_angle[&"coat_1"]
		animator._angles[&"coat_1"] = 0.41
		animator._overlay[&"coat_1"] = -0.07
		animator._spring_angle[&"coat_1"] = 0.09
		animator._apply_body()
		var composed_angle := 0.43
		check(is_equal_approx(rig.bone(&"coat_1").rotation, composed_angle), "nonzero authored angle, overlay and spring compose exactly once")
		animator._apply_body()
		check(is_equal_approx(rig.bone(&"coat_1").rotation, composed_angle), "reapplying the body does not accumulate overlay or spring rotation")
		animator._angles[&"coat_1"] = saved_author
		animator._overlay[&"coat_1"] = saved_overlay
		animator._spring_angle[&"coat_1"] = saved_spring
		animator._apply_body()

		# Transition using actual stand/sit pose blending; spring stays separately bounded.
		input.npc_pose = &"sit"
		rig.animate(1.0 / 60.0, input)
		var transition_angle := animator._angles[&"coat_1"]
		check(absf(transition_angle - authored_stand) < 0.7 and not is_equal_approx(transition_angle, -0.35), "stand-to-sit cloth angle transitions instead of snapping")
		for i in 120:
			rig.animate(1.0 / 60.0, input)
		check(absf(animator._angles[&"coat_1"] - -0.35) < 0.04, "sit pose blend reaches its authored cloth angle")

		# The configured spring limits constrain the secondary component independently
		# from the authored pose, which may lie outside those limits.
		animator._spring_velocity[&"coat_1"] = 1000.0
		rig.animate(1.0 / 60.0, input)
		var spring_offset := animator._spring_angle[&"coat_1"]
		check(spring_offset >= -0.120001 and spring_offset <= 0.160001, "spring offset remains within configured min/max (%.3f)" % spring_offset)
		check(is_equal_approx(rig.bone(&"coat_1").rotation, animator._angles[&"coat_1"] + animator._overlay.get(&"coat_1", 0.0) + spring_offset), "spring offset is applied exactly once over the NPC pose")

		# Zero authored angle remains the previous spring-only result.
		(poses["stand"]["bones"] as Dictionary)["coat_1"] = 0.0
		input.npc_pose = &"stand"
		for i in 120:
			rig.animate(1.0 / 60.0, input)
		check(absf(animator._angles[&"coat_1"]) < 0.001, "zero-authored spring bone retains its legacy base angle")
		check(is_equal_approx(rig.bone(&"coat_1").rotation, animator._spring_angle[&"coat_1"]), "zero-authored spring bone exactly matches the previous spring-only output")
	else:
		check(false, "Rin spring fixture exposes the NPC animator and coat_1 bone")
	holder.queue_free()
	var spring_30 := _spring_offset_after(30)
	var spring_60 := _spring_offset_after(60)
	var spring_120 := _spring_offset_after(120)
	check(maxf(absf(spring_30 - spring_60), absf(spring_60 - spring_120)) < 0.01, "spring offset is stable at 30/60/120 FPS (%.4f / %.4f / %.4f)" % [spring_30, spring_60, spring_120])
	if had_cached_data:
		RigLibrary._json_cache[DATA_PATH] = previous_data
	else:
		RigLibrary._json_cache.erase(DATA_PATH)
	await frames(1)


func _spring_offset_after(fps: int) -> float:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	var result := 0.0
	if rig.setup("rin", "npc") and rig.animator is NpcAnimator and rig.has_bone(&"coat_1"):
		var input := RigInput.new()
		input.two_handed = false
		input.velocity = Vector2(120.0, 0.0)
		for i in fps * 2:
			rig.animate(1.0 / float(fps), input)
		result = (rig.animator as NpcAnimator)._spring_angle[&"coat_1"]
	holder.queue_free()
	return result


func _test_garment_hems_swing() -> void:
	# NE-221：老 K 的大衣下襬與阿婆的圍裙掛在彈簧骨上，走動時要真的擺動，站定後回到原位。
	for skin: String in ["old_k", "ah_po"]:
		var rig := CharacterRig.new()
		runner.get_tree().root.add_child(rig)
		check(rig.setup(skin, "npc") and rig.has_bone(&"coat_1") and rig.has_bone(&"coat_2"), "%s has hem bones coat_1 and coat_2" % skin)
		if rig.is_valid() and rig.has_bone(&"coat_1"):
			var input := RigInput.new()
			input.two_handed = false
			var rest_angle := rig.bone(&"coat_1").rotation
			input.velocity = Vector2(150.0, 0.0)
			var swing := 0.0
			for i in 60:
				rig.animate(1.0 / 60.0, input)
				swing = maxf(swing, absf(rig.bone(&"coat_1").rotation - rest_angle))
			check(swing > 0.02, "%s hem swings while walking (%.3f rad)" % [skin, swing])
			input.velocity = Vector2.ZERO
			for i in 180:
				rig.animate(1.0 / 60.0, input)
			check(absf(rig.bone(&"coat_1").rotation - rest_angle) < 0.03, "%s hem settles when standing still (%.3f rad)" % [skin, absf(rig.bone(&"coat_1").rotation - rest_angle)])
		rig.queue_free()


func _test_npc_data_validation() -> void:
	check(NpcAnimator.loop_names().has("stir") and NpcAnimator.loop_names().has("hammer"), "the loop names are listed")
	var npc := NpcData.new()
	npc.id = &"test_npc_loop"
	npc.display_name = "測試"
	npc.loop = &"no_such_loop"
	check(not npc.validate().is_empty() and "".join(npc.validate()).contains("no_such_loop"), "an unknown loop name is reported with its place")
	npc.loop = &"stir"
	npc.loop_scale = 0.0
	check("".join(npc.validate()).contains("loop_scale"), "a loop_scale of 0 is reported")
