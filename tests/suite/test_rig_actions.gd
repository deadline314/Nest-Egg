class_name RigActionsSuite
extends TestSuite
## 專屬動作（art/rigs/action_poses.json）與敵人招式動畫（NE-89 的機制、NE-75～82 的招式）：動作資料引用的骨頭都存在、
## 進度內插、skip_ik 的手臂依動作角度、沒有的動作不會崩潰、敵人資料的 rig_actions 引用存在的動作與狀態、開槍有後座力。

const PATH := "res://art/rigs/action_poses.json"
const SKINS: Array[String] = ["trooper", "warden", "rin"]


func run() -> void:
	_test_data()
	await _test_playback()
	await _test_death_overrides_enemy_actions()
	await _test_unknown_action()
	await _test_hands_follow_forearm()
	await _test_enemy_data()
	_test_motion_is_not_shared()


func _rig(skin: String, input: RigInput, settle := 40) -> CharacterRig:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(skin), "rig builds: %s" % skin)
	for i in settle:
		rig.animate(1.0 / 60.0, input)
	await frames(1)
	return rig


func _test_data() -> void:
	var actions: Dictionary = RigLibrary.load_json(PATH).get("actions", {})
	check(actions.size() >= 6, "action data has the actions (%d)" % actions.size())
	var family: Array[String] = []
	for bone: Dictionary in RigLibrary.load_json("res://art/rigs/humanoid.json").get("bones", []):
		family.append(str(bone["name"]))
	for skin in SKINS:
		var bones: Array[String] = []
		for bone: Dictionary in RigLibrary.load_json(str(RigLibrary.character(skin).get("rig", ""))).get("bones", []):
			bones.append(str(bone["name"]))
		for name: String in actions.keys():
			var def: Dictionary = actions[name]
			check(float(def.get("duration", 0.0)) > 0.0, "%s has a duration" % name)
			var last_t := -1.0
			for key: Dictionary in def.get("keys", []):
				var t := float(key.get("t", -1.0))
				check(t >= last_t and t >= 0.0 and t <= 1.0, "%s: keys are in order within 0..1" % name)
				last_t = t
				for bone: String in (key.get("bones", {}) as Dictionary).keys():
					# 專屬骨頭（人形家族以外，NE-89）只有宣告它的角色要有；其他人播放時會略過並記錄一次。
					var owner_skin := name.get_slice(".", 0)
					if not family.has(bone) and skin != owner_skin:
						continue
					check(bones.has(bone), "%s only uses bones that %s has: %s" % [name, skin, bone])


func _test_playback() -> void:
	var input := RigInput.new()
	input.two_handed = true
	var idle := await _rig("trooper", input)
	var idle_arm := idle.bone(&"arm_front_upper").rotation
	input.action = &"warden.windup_overhead"
	input.action_t = 1.0
	var raised := await _rig("trooper", input, 60)
	check(raised.bone(&"arm_front_upper").rotation < -2.4, "an overhead windup raises the arm (%.2f)" % raised.bone(&"arm_front_upper").rotation)
	input.action_t = 0.0
	var start := await _rig("trooper", input, 60)
	check(start.bone(&"arm_front_upper").rotation > raised.bone(&"arm_front_upper").rotation + 1.0, "progress 0 is lower than progress 1")
	input.action = &"warden.slam"
	input.action_t = 0.5
	var slam := await _rig("trooper", input, 60)
	check(slam.bone(&"chest").rotation > 0.25, "the slam bends the chest forward")
	input.action = &""
	var after := await _rig("trooper", input, 80)
	check(absf(after.bone(&"arm_front_upper").rotation - idle_arm) < 0.3, "after the action the arm goes back to the normal pose")


## Enemy FSMs stop ticking after death and can leave their last action set. Death must take priority in the shared animator.
func _test_death_overrides_enemy_actions() -> void:
	var cases: Array[Dictionary] = [
		{"skin": "enforcer", "action": &"shield_rusher.stagger_back"},
		{"skin": "heavy_gunner", "action": &"heavy_gunner.vent"},
		{"skin": "warden", "action": &"warden.vent"},
	]
	for case: Dictionary in cases:
		for facing in [-1, 1]:
			for force in [0.0, 1.0]:
				var action_input := RigInput.new()
				action_input.facing = facing
				action_input.action = case["action"]
				action_input.action_t = 1.0
				var action_rig := await _rig(case["skin"], action_input, 90)
				check(float(action_rig.animator._action_w) > 0.99, "%s action is active before death (facing %d, force %.1f)" % [case["skin"], facing, force])
				var action_chest := action_rig.bone(&"chest").rotation

				var clear_input := RigInput.new()
				clear_input.facing = facing
				var clear_rig := await _rig(case["skin"], clear_input, 90)
				check(absf(action_chest - clear_rig.bone(&"chest").rotation) > 0.025, "%s action changes the living pose before death" % case["skin"])

				action_input.dead = true
				action_input.death_dir = -1.0 if facing < 0 else 1.0
				action_input.death_force = force
				clear_input.dead = true
				clear_input.death_dir = action_input.death_dir
				clear_input.death_force = force
				for frame in 90:
					action_rig.animate(1.0 / 60.0, action_input)
					clear_rig.animate(1.0 / 60.0, clear_input)
				var action_pose := _death_pose_signature(action_rig)
				var clear_pose := _death_pose_signature(clear_rig)
				check(_pose_distance(action_pose, clear_pose) < 0.001, "%s death pose ignores the stale action (facing %d, force %.1f; delta %.5f)" % [case["skin"], facing, force, _pose_distance(action_pose, clear_pose)])
				check(float(action_rig.animator._action_w) <= 0.001, "%s clears action weight while dead" % case["skin"])
				check(not action_rig.weapon_root().visible, "%s hides weapon while dead" % case["skin"])

				# Clearing the action and reviving must not resurrect stale action state.
				action_input.dead = false
				action_input.action = &""
				clear_input.dead = false
				for frame in 90:
					action_rig.animate(1.0 / 60.0, action_input)
					clear_rig.animate(1.0 / 60.0, clear_input)
				check(float(action_rig.animator._action_w) <= 0.001, "%s has no stale action after revival" % case["skin"])
				check(_pose_distance(_death_pose_signature(action_rig), _death_pose_signature(clear_rig)) < 0.001, "%s returns to the same non-action pose after revival" % case["skin"])
				action_rig.get_parent().queue_free()
				clear_rig.get_parent().queue_free()


func _death_pose_signature(rig: CharacterRig) -> PackedFloat32Array:
	var values := PackedFloat32Array([rig.animator._hip_offset.x, rig.animator._hip_offset.y])
	for bone_name: StringName in [&"hip", &"chest", &"head", &"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"]:
		values.append(rig.bone(bone_name).rotation)
	return values


func _pose_distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var difference := 0.0
	for i in a.size():
		difference = maxf(difference, absf(a[i] - b[i]))
	return difference


## 手的貼圖朝 +X 畫：手臂垂下、沒握武器的手要順著前臂（不然手腕折成直角）；人物與 NPC 站著、走路、蹲下都一樣。
func _test_hands_follow_forearm() -> void:
	for skin in ["rin", "old_k", "nurse", "night_worker", "resident", "ah_po", "wataru", "mei"]:
		for state in ["idle", "walk", "crouch"]:
			var input := RigInput.new()
			if state == "walk":
				input.velocity = Vector2(60, 0)
				input.run_speed = 90.0
			input.crouching = state == "crouch"
			var rig := await _rig(skin, input, 60)
			for side in ["front", "back"]:
				var lower := _part_sprite(rig, "arm_%s_lower" % side)
				var hand := _part_sprite(rig, "hand_%s" % side)
				if lower == null or hand == null:
					check(false, "%s has an arm and a hand sprite (%s)" % [skin, side])
					continue
				var forearm_dir := (lower.to_global(Vector2(0, 1)) - lower.to_global(Vector2.ZERO)).normalized()
				var hand_dir := (hand.to_global(Vector2(1, 0)) - hand.global_position).normalized()
				var angle := absf(rad_to_deg(forearm_dir.angle_to(hand_dir)))
				check(angle < 25.0, "%s (%s, %s): the free hand follows the forearm (%.0f degrees off)" % [skin, state, side, angle])
			rig.get_parent().queue_free()


## 這根骨頭上的零件（一般的 Sprite2D，或做成可彎曲網格的 RigPartMesh）。
func _part_sprite(rig: CharacterRig, bone_name: String) -> Node2D:
	var bone := rig.bone(StringName(bone_name))
	if bone == null:
		return null
	for child in bone.get_children():
		if (child is Sprite2D or child is RigPartMesh) and child.name == bone_name:
			return child as Node2D
	return null


func _test_unknown_action() -> void:
	var input := RigInput.new()
	input.action = &"no_such_action"
	input.action_t = 0.5
	var rig := await _rig("trooper", input)
	check(rig.is_valid(), "an unknown action does not break the rig")


func _test_enemy_data() -> void:
	var actions: Dictionary = RigLibrary.load_json(PATH).get("actions", {})
	var found := 0
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data == null or data.rig_actions.is_empty():
			continue
		found += 1
		for state: Variant in data.rig_actions.keys():
			check(actions.has(str(data.rig_actions[state])), "%s: state %s plays an action that exists (%s)" % [file, state, data.rig_actions[state]])
		if data.behavior != null:
			var source := (data.behavior as GDScript).source_code
			for state: Variant in data.rig_actions.keys():
				check(source.contains('&"%s"' % str(state)), "%s: the behaviour has a state named %s" % [file, state])
	check(found >= 5, "several enemies have rig actions (%d)" % found)
	# 不共用：同一個動作只能被一個敵人使用，而且動作名稱以敵人 id 開頭。
	var owner_of: Dictionary = {}
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data == null:
			continue
		for state: Variant in data.rig_actions.keys():
			var name := str(data.rig_actions[state])
			check(name.begins_with(file.get_basename() + "."), "%s: action %s is named after its own enemy" % [file, name])
			check(not owner_of.has(name) or owner_of[name] == file, "action %s is not shared between enemies (%s, %s)" % [name, owner_of.get(name, ""), file])
			owner_of[name] = file


## 不共用動畫：每個角色都有自己的動作資料，任兩個角色至少有 4 個數值不同（移動、待機、死亡），而且死亡的倒下方式不能全部相同。
func _test_motion_is_not_shared() -> void:
	const FIELDS: Array[String] = ["move.stride", "move.swing", "move.knee_bend", "move.hip_bounce", "move.chest_lean", "idle.breath_speed",
			"idle.hip_bob", "death.duration", "death.rotation", "death.fold", "look.head", "hurt.kick"]
	var profiles: Dictionary = {}
	for id in DirAccess.get_directories_at("res://art/characters"):
		var path := HumanoidAnimator.MOTION_PATH % id
		check(ResourceLoader.exists(path), "%s has its own motion data (art/motion/%s.json)" % [id, id])
		if ResourceLoader.exists(path):
			profiles[id] = RigLibrary.load_json(path)
	var ids: Array = profiles.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var differing := 0
			for field in FIELDS:
				if not is_equal_approx(_field(profiles[ids[i]], field), _field(profiles[ids[j]], field)):
					differing += 1
			check(differing >= 4, "%s and %s do not share their motion (%d of %d values differ)" % [ids[i], ids[j], differing, FIELDS.size()])


func _field(profile: Dictionary, path: String) -> float:
	var node: Variant = profile
	for part in path.split("."):
		node = (node as Dictionary).get(part, {}) if typeof(node) == TYPE_DICTIONARY else {}
	return float(node) if typeof(node) == TYPE_FLOAT or typeof(node) == TYPE_INT else NAN

