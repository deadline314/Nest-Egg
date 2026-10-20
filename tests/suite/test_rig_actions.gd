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
	await _test_far_hand_and_hems()
	await _test_springs_settle()
	await _test_sway_mesh_binding()
	await _test_rin_visible_cloth()


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


## 空手的遠側手藏在身體後面（NE-218：髖前緣探出一隻沒有前臂的手）、圍裙坐下時搭在腿上、區域擺動的資料有接到零件。
func _test_far_hand_and_hems() -> void:
	for skin: String in ["vig", "yong", "ali"]:
		for speed: float in [0.0, 60.0, 150.0]:
			var input := RigInput.new()
			input.two_handed = false
			input.velocity = Vector2(speed, 0.0)
			var rig := await _rig(skin, input, 90)
			var worst := 0.0
			for i in 60:  # 一整個擺臂週期
				rig.animate(1.0 / 60.0, input)
				worst = maxf(worst, absf(rig.bone(&"hand_back").global_position.x - rig.bone(&"leg_front_upper").global_position.x))
			check(worst <= 3.0, "%s at speed %.0f: the empty far wrist stays behind the hip (%.1f world px from its centre)" % [skin, speed, worst])
			rig.get_parent().queue_free()
	var seated := RigInput.new()
	seated.two_handed = false
	seated.npc_pose = &"sit"
	var sitting := CharacterRig.new()
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	holder.add_child(sitting)
	check(sitting.setup("ali", "npc"), "npc rig builds: ali")
	for i in 90:
		sitting.animate(1.0 / 60.0, seated)
	check(sitting.bone(&"coat_1").rotation < -0.5, "ali's apron lies on her lap when she sits (%.2f)" % sitting.bone(&"coat_1").rotation)
	check(not sitting._sway_targets.is_empty(), "ali's hair sway region is bound to her head part")
	holder.queue_free()


## 次級擺動（NE-257）：翻面與瞬移不甩動、撞到上下限不帶著速度、靜止 2 秒內停下來、更新率 30 與 60 幅度相近。
func _test_springs_settle() -> void:
	var peaks: Array[float] = []
	for fps: float in [60.0, 30.0]:
		var input := RigInput.new()
		input.velocity = Vector2(220.0, 0.0)
		var rig := await _rig("rin", input, int(fps))
		var animator: HumanoidAnimator = rig.animator
		var peak := 0.0
		for i in int(fps):
			rig.animate(1.0 / fps, input)
			peak = maxf(peak, absf(float(animator._spring_angle[&"hair_2"])))
		peaks.append(peak)
		check(float(animator._spring_angle[&"hair_1"]) <= 0.95 + 0.001 and float(animator._spring_angle[&"hair_2"]) <= 0.7 + 0.001, "rin's ponytail stays inside its limits while running")
		input.velocity = Vector2.ZERO
		for i in int(fps * 2.0):
			rig.animate(1.0 / fps, input)
		check(absf(float(animator._spring_velocity[&"hair_2"])) < 0.25, "rin's ponytail is at rest 2 s after she stops (%.3f rad/s at %d fps)" % [float(animator._spring_velocity[&"hair_2"]), int(fps)])
		input.velocity = Vector2(220.0, 0.0)
		for i in int(fps):
			rig.animate(1.0 / fps, input)
		input.facing = -1
		input.velocity = Vector2(-220.0, 0.0)
		rig.animate(1.0 / fps, input)
		check(absf(float(animator._spring_velocity[&"hair_1"])) < 2.0, "turning round does not whip the ponytail (%.2f rad/s)" % float(animator._spring_velocity[&"hair_1"]))
		for i in int(fps):
			rig.animate(1.0 / fps, input)
		rig.get_parent().position += Vector2(900.0, 0.0)
		rig.animate(1.0 / fps, input)
		check(is_zero_approx(float(animator._spring_velocity[&"hair_1"])) or absf(float(animator._spring_velocity[&"hair_1"])) < 2.0, "a teleport resets the ponytail")
		rig.get_parent().queue_free()
	check(absf(peaks[0] - peaks[1]) < 0.12, "the ponytail swings about as far at 30 as at 60 updates a second (%.2f vs %.2f)" % [peaks[0], peaks[1]])


## NE-257：腰部改為 RigPartMesh 後，原本的鑰匙／衣襬區域仍須接到真正渲染的零件。
func _test_sway_mesh_binding() -> void:
	for skin in ["ali", "banyan", "collector_brute", "collector_gunner", "egret", "lin", "vig", "xiaowei", "ye", "zhi"]:
		var rig := await _rig(skin, RigInput.new(), 1)
		for spring: Dictionary in rig._springs:
			if not spring.has("warp"):
				continue
			var id := StringName(str(spring["id"]))
			var targets: Array = rig._sway_targets.get(id, [])
			check(not targets.is_empty(), "%s/%s binds its authored region to a renderable part" % [skin, id])
			rig.set_sway(id, 0.07)
			for target: Array in targets:
				var part := target[0] as CanvasItem
				var shape: Vector2 = part.get_instance_shader_parameter(target[1])
				check(is_equal_approx(shape.x, float(spring["warp"]["width"])) and is_equal_approx(shape.y, 0.07), "%s/%s updates the actual part shader" % [skin, id])
				if part is RigPartMesh:
					check(part.get_instance_shader_parameter("sway_padding") == 0.0, "%s/%s leaves mesh vertices and UV geometry unchanged" % [skin, id])
				else:
					check(part is Sprite2D, "%s/%s only binds supported render nodes" % [skin, id])
		var moving := RigInput.new()
		moving.velocity = Vector2(220, 0)
		for tick in 30:
			rig.animate(1.0 / 60.0, moving)
		for spring: Dictionary in rig.springs():
			if not spring.has("warp"):
				continue
			var id := StringName(str(spring["id"]))
			var angle := float(rig.animator._spring_angle[id])
			check(absf(angle) > 0.001, "%s/%s responds to actual movement input" % [skin, id])
			for target: Array in rig._sway_targets.get(id, []):
				var rendered: Vector2 = (target[0] as CanvasItem).get_instance_shader_parameter(target[1])
				check(is_equal_approx(rendered.y, angle), "%s/%s sends the simulated spring angle to the rendered part" % [skin, id])
		rig.get_parent().queue_free()
	await frames(1)


## NE-257: simulate actual inputs and inspect the render nodes, not the unused coat bones.
func _test_rin_visible_cloth() -> void:
	var peaks: Array[float] = []
	for fps: int in [30, 60]:
		var input := RigInput.new()
		var rig := await _rig("rin", input, 1)
		var animator: HumanoidAnimator = rig.animator
		var found := 0
		for spring: Dictionary in rig.springs():
			if not spring.has("warp"):
				continue
			var part_name := str(spring["warp"]["part"])
			if part_name not in ["armor_jacket", "armor_jacket_far"]:
				continue
			found += 1
			var targets: Array = rig._sway_targets.get(StringName(str(spring["id"])), [])
			check(targets.size() == 1, "rin/%s binds exactly one visible jacket part" % part_name)
			check(absf(float(spring["min"])) <= 0.05 and absf(float(spring["max"])) <= 0.05, "rin/%s keeps short cloth inside a small angle" % part_name)
		check(found == 2, "rin has actual near and far jacket follow regions")
		animator.reset_springs()
		var idle_drift := 0.0
		for tick in fps * 4:
			rig.animate(1.0 / fps, input)
			for spring: Dictionary in animator._springs:
				var key := animator._spring_key(spring)
				idle_drift = maxf(idle_drift, absf(float(animator._spring_angle[key]) - float(spring.get("rest", 0.0))))
		check(idle_drift < 0.00001, "rin stands without perpetual wind drift at %d Hz (%.7f)" % [fps, idle_drift])
		input.velocity = Vector2(220, 0)
		var peak := 0.0
		for tick in fps:
			rig.animate(1.0 / fps, input)
			for key: StringName in rig._sway_targets:
				var angle := float(animator._spring_angle[key])
				peak = maxf(peak, absf(angle))
				for target: Array in rig._sway_targets[key]:
					var rendered: Vector2 = (target[0] as CanvasItem).get_instance_shader_parameter(target[1])
					check(is_equal_approx(rendered.y, angle), "rin jacket renders the simulated angle at %d Hz" % fps)
		check(peak > 0.005, "rin movement reaches actual jacket pixels at %d Hz" % fps)
		peaks.append(peak)
		input.velocity = Vector2.ZERO
		input.landed = 0.8
		rig.animate(1.0 / fps, input)
		input.landed = 0.0
		for tick in fps * 2:
			rig.animate(1.0 / fps, input)
		var residual := 0.0
		for spring: Dictionary in animator._springs:
			var key := animator._spring_key(spring)
			residual = maxf(residual, absf(float(animator._spring_angle[key]) - float(spring.get("rest", 0.0))))
			residual = maxf(residual, absf(float(animator._spring_velocity[key])))
		check(residual < 0.01, "rin all follow settles after landing and stop within 2 s at %d Hz (%.6f)" % [fps, residual])
		rig.get_parent().queue_free()
	await frames(1)
	check(absf(peaks[0] - peaks[1]) < 0.002, "rin cloth peak is similar at 30 and 60 Hz")
