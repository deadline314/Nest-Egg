class_name EnforcerArtDeliverySuite
extends TestSuite
## NE-79 CPU contracts only. Does not accept source anatomy, alpha seams, rendering or feel.
## General input cases use the shipped enforcer motion profile; FSM cases use Enemy's registered action routing.

const DT := 1.0 / 60.0
const DATA_PATH := "res://data/enemies/shield_rusher.tres"
const BODY_SLOTS := [&"head", &"torso", &"pelvis", &"arm_front_upper", &"arm_front_lower", &"hand_front", &"arm_back_upper", &"arm_back_lower", &"hand_back", &"leg_front_upper", &"leg_front_lower", &"foot_front", &"leg_back_upper", &"leg_back_lower", &"foot_back"]

var _right_samples: Array[PackedVector2Array] = []
var _sample_index := 0


func run() -> void:
	var data := load(DATA_PATH) as EnemyData
	check(data != null and data.rig_skin == "enforcer" and data.rig_shield and not data.rig_two_handed, "NE-79 uses the shipped shield, single-hand weapon and skin configuration")
	if data == null:
		return
	var motion := RigLibrary.load_json(HumanoidAnimator.MOTION_PATH % data.rig_skin)
	for section in ["idle", "move", "air", "dash", "hurt", "death", "block", "crouch"]:
		check(motion.has(section), "enforcer has an authored motion section: %s" % section)
	var actions: Dictionary = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	for side in [1, -1]:
		_sample_index = 0
		var rig := CharacterRig.new()
		runner.get_tree().root.add_child(rig)
		check(rig.setup(data.rig_skin) and rig.animator is HumanoidAnimator, "enforcer builds the official humanoid animator")
		rig.set_weapon(data.rig_weapon)
		var snapshot := _snapshot(rig)
		var input := RigInput.new()
		input.facing = side
		input.aim_dir = Vector2(side, 0.05).normalized()
		input.run_speed = maxf(40.0, data.move_speed * 2.0)
		input.two_handed = data.rig_two_handed
		input.shield_forward = data.rig_shield
		_replay(rig, input, snapshot, "idle", 300)
		var idle_pose := _pose(rig)
		var phase_before: float = rig.animator._phase
		input.velocity.x = side * data.move_speed
		_replay(rig, input, snapshot, "walk", maxi(120, ceili(float(motion["move"]["stride"]) / data.move_speed / DT * 2.0)))
		check(float(rig.animator._phase) - phase_before >= TAU * 2.0 - 0.001, "walk traverses at least two authored stride cycles")
		input.velocity.x = side * data.ability_speed
		_replay(rig, input, snapshot, "run/charge", 120)
		check(_pose(rig).distance_to(idle_pose) > 0.1, "charge speed produces a moving pose rather than unchanged idle")
		input.velocity = Vector2.ZERO
		_replay(rig, input, snapshot, "run to idle", 120)
		input.on_floor = false
		input.jumped = true
		input.velocity.y = -120.0
		_replay(rig, input, snapshot, "jump rise", 60)
		var rise_pose := _pose(rig)
		check(rise_pose.distance_to(idle_pose) > 0.1, "airborne ascent enters a distinct authored pose")
		input.velocity.y = 120.0
		_replay(rig, input, snapshot, "jump fall", 60)
		check(_pose(rig).distance_to(rise_pose) > 0.1, "ascent transitions to a distinct falling pose")
		input.on_floor = true
		input.velocity = Vector2.ZERO
		input.landed = 1.0
		_replay(rig, input, snapshot, "landing to idle", 120)
		for direction in [1, -1]:
			input.dashing = true
			input.dash_started = true
			input.velocity.x = side * direction * data.ability_speed
			_replay(rig, input, snapshot, "dodge %d (animator input, not enemy gameplay)" % direction, 60)
			check(_pose(rig).distance_to(idle_pose) > 0.1, "dodge input produces a distinct authored pose: %d" % direction)
		input.dashing = false
		input.velocity = Vector2.ZERO
		_replay(rig, input, snapshot, "dodge to idle", 120)
		# Route through the real Enemy method, not a copied state->action dictionary.
		var enemy := data.behavior.new() as Enemy
		enemy.configure(data)
		enemy._setup_states()
		for state: String in data.rig_actions:
			check(enemy.fsm.has(StringName(state)), "registered action has a real enemy FSM state: %s" % state)
			var action := str(data.rig_actions[state])
			check(actions.has(action), "registered enforcer action exists: %s" % action)
			if not actions.has(action):
				continue
			var duration := float(actions[action]["duration"])
			enemy.fsm.current = StringName(state)
			for frame in ceili(duration / DT) + 30:
				enemy.fsm.time_in_state = frame * DT
				enemy._update_rig_action()
				input.action = enemy._rig_input.action
				input.action_t = enemy._rig_input.action_t
				check(input.action == StringName(action), "registered action reaches RigInput: %s/%d" % [state, frame])
				_replay(rig, input, snapshot, "attack/FSM %s frame %d" % [state, frame], 1)
			check(input.action_t == 1.0 and float(rig.animator._action_w) > 0.99, "registered action reaches its endpoint and blends in: %s" % state)
			enemy.fsm.current = &"patrol"
			enemy._update_rig_action()
			input.action = enemy._rig_input.action
			_replay(rig, input, snapshot, "action to patrol", 60)
			check(input.action == &"" and float(rig.animator._action_w) == 0.0, "patrol clears the registered action and finishes blend-out")
		enemy.free()
		for pose in ["aim", "crouch", "block", "hit"]:
			input.crouching = pose == "crouch"
			input.blocking = pose == "block"
			input.staggered = pose == "hit"
			input.hurt = pose == "hit"
			input.aim_dir = Vector2(side, -0.6 if pose == "aim" else 0.05).normalized()
			_replay(rig, input, snapshot, pose, 120)
			check(_pose(rig).distance_to(idle_pose) > 0.025, "preview %s input actually changes the pose" % pose)
		input.crouching = false
		input.blocking = false
		input.staggered = false
		input.aim_dir = Vector2(side, 0.05).normalized()
		_replay(rig, input, snapshot, "hit to idle", 120)
		_test_armor_and_controls(rig, input, snapshot)
		# Existing NE-222 death priority is retained, including a stale registered action.
		input.action = StringName(data.rig_actions["dazed"])
		input.action_t = 1.0
		_replay(rig, input, snapshot, "pre-death registered action", 60)
		input.dead = true
		_replay(rig, input, snapshot, "die", maxi(120, ceili(float(motion["death"]["duration"]) / DT) + 60))
		check(float(rig.animator._action_w) == 0.0 and not rig.weapon_root().visible, "death suppresses the stale action and hides the weapon")
		check(_pose(rig).distance_to(idle_pose) > 0.1, "death reaches a distinct pose rather than leaving standing input unchanged")
		print("NE79_CPU_SAMPLES facing=%d fixed_60Hz_frames=%d registered_actions=%s" % [side, _sample_index, str(data.rig_actions)])
		rig.free()
	await frames(1)


func _pose(rig: CharacterRig) -> Vector3:
	return Vector3(rig.bone(&"chest").rotation, rig.bone(&"leg_front_upper").rotation, rig.bone(&"leg_back_upper").rotation)


func _snapshot(rig: CharacterRig) -> Dictionary:
	var bones := {}
	for name in rig.bone_order():
		var b := rig.bone(name)
		bones[name] = [b.position, b.rest, b.get_parent(), rig.rest(name), rig.parent_of(name)]
	var parts := {}
	for part: Node2D in rig._parts:
		parts[part.name] = [part, part.get_parent(), part.transform]
	return {"bones": bones, "parts": parts}


func _issues(rig: CharacterRig, snapshot: Dictionary, dead: bool) -> PackedStringArray:
	var errors := PackedStringArray()
	for name: StringName in snapshot["bones"]:
		var b := rig.bone(name)
		var saved: Array = snapshot["bones"][name]
		# Hip translation is the authored root motion/ground correction; child offsets never change.
		if b.rest != saved[1] or b.get_parent() != saved[2] or rig.rest(name) != saved[3] or rig.parent_of(name) != saved[4] or (name != &"hip" and not b.position.is_equal_approx(saved[0])):
			errors.append("bone bind/parent/local offset: " + str(name))
		if not b.transform.origin.is_finite() or not b.transform.x.is_finite() or not b.transform.y.is_finite() or absf(b.rotation) > TAU or absf(b.transform.determinant() - 1.0) > 0.001:
			errors.append("nonfinite or nonrigid bone transform: " + str(name))
		if not b.global_position.is_finite() or b.global_position.distance_to(rig.global_position) > RigLibrary.standing_height("enforcer") * 2.0:
			errors.append("bone outside finite two-body-height envelope: " + str(name))
	var counts := {}
	var expected_children := {}
	for part: Node2D in rig._parts:
		counts[part.name] = int(counts.get(part.name, 0)) + 1
	for saved: Array in snapshot["parts"].values():
		var parent: Node = saved[1]
		expected_children[parent] = int(expected_children.get(parent, 0)) + 1
	for name in rig.bone_order():
		var b := rig.bone(name)
		var actual := 0
		for child in b.get_children():
			actual += 1 if child is Sprite2D or child is RigPartMesh else 0
		if actual != int(expected_children.get(b, 0)):
			errors.append("unregistered or missing attachment on bone: " + str(name))
	for slot: StringName in snapshot["parts"]:
		var saved: Array = snapshot["parts"][slot]
		var part: Node2D = saved[0]
		if int(counts.get(slot, 0)) != 1 or part.get_parent() != saved[1] or part.transform != saved[2]:
			errors.append("part duplicate/bind/offset: " + str(slot))
	for slot in BODY_SLOTS:
		var part: CanvasItem = snapshot["parts"][slot][0]
		if not part.visible:
			errors.append("hidden underlying body slot: " + str(slot))
	var shield: Node2D = snapshot["parts"][&"riot_shield"][0]
	var expected_shield: Transform2D = rig.bone(&"hand_back").global_transform * (snapshot["parts"][&"riot_shield"][2] as Transform2D)
	if not shield.visible or not shield.global_transform.is_equal_approx(expected_shield):
		errors.append("shield relative bone matrix")
	if not dead and not rig.weapon_def().is_empty():
		var palm := rig.bone(&"hand_front").to_global(rig.hand_grip_offset(&"hand_front"))
		if palm.distance_to(rig.weapon_root().global_position) >= 0.025:
			errors.append("weapon grip relative to front hand")
		var def := rig.weapon_def()
		var delta := (RigLibrary.vec2(def["muzzle"]) - RigLibrary.vec2(def["grip"])) * rig.weapon_scale()
		var muzzle := rig.weapon_root().global_transform * delta
		if not rig.muzzle_global().is_finite() or rig.muzzle_global().distance_to(muzzle) >= 0.001:
			errors.append("muzzle relative weapon matrix")
	return errors


func _replay(rig: CharacterRig, input: RigInput, snapshot: Dictionary, label: String, count: int) -> void:
	var first := ""
	var mirror_error := 0.0
	for frame in count:
		rig.animate(DT, input)
		var issues := _issues(rig, snapshot, input.dead)
		if first.is_empty() and not issues.is_empty():
			first = "frame %d: %s" % [frame, ", ".join(issues)]
		var points := PackedVector2Array()
		for name in rig.bone_order():
			points.append(rig.bone(name).global_position - rig.global_position)
		points.append((snapshot["parts"][&"riot_shield"][0] as Node2D).global_position - rig.global_position)
		if not input.dead:
			points.append(rig.muzzle_global() - rig.global_position)
		if input.facing == 1:
			_right_samples.append(points)
		elif _sample_index < _right_samples.size():
			var reference := _right_samples[_sample_index]
			for i in points.size():
				mirror_error = maxf(mirror_error, points[i].distance_to(Vector2(-reference[i].x, reference[i].y)))
		else:
			first = "missing right-facing reference"
		_sample_index += 1
		input.jumped = false
		input.landed = 0.0
		input.dash_started = false
		input.hurt = false
	check(first.is_empty(), "enforcer %s facing %d: %d fixed 60Hz samples (%s)" % [label, input.facing, count, first])
	if input.facing == -1:
		check(mirror_error < 0.001, "enforcer %s mirrors every sampled bone, shield and live muzzle once (error %.5f)" % [label, mirror_error])


func _test_armor_and_controls(rig: CharacterRig, input: RigInput, snapshot: Dictionary) -> void:
	check(rig.armor_count() == 4, "enforcer keeps four real armor groups")
	for remaining in range(rig.armor_count(), -1, -1):
		rig.set_armor_ratio(float(remaining) / rig.armor_count(), false)
		check(rig._armor_visible == remaining, "armor stage %d is reached" % remaining)
		for group in rig._armor.size():
			for part: CanvasItem in rig._armor[group]:
				check(part.visible == (group >= rig.armor_count() - remaining), "armor stage %d preserves removal order: %s" % [remaining, part.name])
		_replay(rig, input, snapshot, "armor stage %d same underlying slots" % remaining, 60)
	# Controls mutate only these disposable runtime nodes and restore before continuing.
	var hand := rig.bone(&"hand_front")
	var position := hand.position
	hand.position.x += 1.0
	check(_issues(rig, snapshot, false).has("bone bind/parent/local offset: hand_front"), "negative control rejects a moved wrist")
	hand.position = position
	var scale := hand.scale
	hand.scale *= 1.1
	check(_issues(rig, snapshot, false).has("nonfinite or nonrigid bone transform: hand_front"), "negative control rejects changed bone scale")
	hand.scale = scale
	var shield: Node2D = snapshot["parts"][&"riot_shield"][0]
	var offset := shield.position
	shield.position.x += 1.0
	check(_issues(rig, snapshot, false).has("shield relative bone matrix"), "negative control rejects shield displacement")
	shield.position = offset
	var body: CanvasItem = snapshot["parts"][&"torso"][0]
	body.visible = false
	check(_issues(rig, snapshot, false).has("hidden underlying body slot: torso"), "negative control rejects missing body after armor removal")
	body.visible = true
	var sprite := rig._weapon_sprite
	var weapon_offset := sprite.offset
	sprite.offset.x += 1.0
	check(_issues(rig, snapshot, false).has("muzzle relative weapon matrix"), "negative control rejects a one-texel muzzle offset")
	sprite.offset = weapon_offset
	var extra := Sprite2D.new()
	extra.name = "extra_hand"
	hand.add_child(extra)
	check(_issues(rig, snapshot, false).has("unregistered or missing attachment on bone: hand_front"), "negative control rejects an extra actual hand attachment node")
	extra.free()
	rig.set_armor_ratio(1.0, false)
	_replay(rig, input, snapshot, "armor restored and controls cleaned", 60)
