class_name HeavyGunnerArtDeliverySuite
extends EnemySuiteBase
## NE-80 CPU contracts only: no pixel, anatomy, lighting or gameplay-feel acceptance.

const DATA_PATH := "res://data/enemies/heavy_gunner.tres"
const DT := 1.0 / 60.0
const POSES := ["idle", "run", "aim", "crouch", "jump", "block", "stagger", "dead", "walk"]
const LENGTH_BONES := [&"arm_front_lower", &"hand_front", &"arm_back_lower", &"hand_back", &"leg_front_lower", &"foot_front", &"leg_back_lower", &"foot_back"]
var _skin: Dictionary
var _definition: Dictionary


func run() -> void:
	_skin = RigLibrary.character("heavy_gunner")
	_definition = RigLibrary.load_json(str(_skin["rig"]))
	check(Engine.physics_ticks_per_second == 60, "NE-80 actual physics clock is 60 Hz")
	check(not _skin.is_empty() and RigLibrary.has_own_rig("heavy_gunner"), "production heavy gunner has its own rig")
	_test_cycles()
	_test_negative_controls()
	await _test_production_enemy()


func _rig(weapon: String) -> CharacterRig:
	var rig := CharacterRig.new()
	runner.get_tree().root.add_child(rig)
	check(rig.setup("heavy_gunner"), "production heavy gunner builds")
	rig.set_weapon(weapon)
	return rig


func _input(side: int) -> RigInput:
	var input := RigInput.new()
	input.facing = side
	input.aim_dir = Vector2(side, 0)
	input.run_speed = maxf(40.0, (load(DATA_PATH) as EnemyData).move_speed * 2.0)
	return input


func _test_cycles() -> void:
	var data := load(DATA_PATH) as EnemyData
	for weapon: String in ["", data.rig_weapon]:
		for side: int in [-1, 1]:
			for pose: String in POSES:
				var rig := _rig(weapon)
				var input := _input(side)
				# Ten seconds includes complete authored breath (3.31s), sway (8.98s)
				# and several distance-driven walk/run cycles, plus entry/exit.
				var phase_start := rig.animator._phase
				for frame in 660:
					var active := frame >= 30 and frame < 630
					input.velocity = Vector2.ZERO
					input.on_floor = true
					input.crouching = active and pose == "crouch"
					input.blocking = active and pose == "block"
					input.staggered = active and pose == "stagger"
					input.dead = active and pose == "dead"
					input.jumped = false
					input.landed = 0.0
					input.hurt = active and frame == 30 and pose == "stagger"
					if active and pose in ["walk", "run"]:
						input.velocity.x = side * (data.move_speed if pose == "walk" else input.run_speed)
					if active and pose == "aim":
						input.aim_dir = Vector2(side, sin((frame - 30) * TAU / 120.0)).normalized()
					if active and pose == "jump":
						var t := (frame - 30) % 120
						input.on_floor = t >= 66
						input.jumped = t == 0
						input.landed = 0.7 if t == 66 else 0.0
						input.velocity = Vector2(side * data.move_speed, -330.0 + t * 10.0) if t < 66 else Vector2.ZERO
					rig.animate(DT, input)
					var ratio: float = [1.0, 0.5, 0.0, 1.0][mini(3, frame / 165)]
					rig.set_armor_ratio(ratio, false)
					var errors := _errors(rig, input, ratio)
					check(errors.is_empty(), "NE80 %s weapon=%s facing=%d frame=%d ratio=%.1f: %s" % [pose, weapon, side, frame, ratio, str(errors)])
				if pose in ["walk", "run"]:
					check(absf(rig.animator._phase - phase_start) >= TAU, "%s completes a real distance-driven cycle" % pose)
				print("NE80_CYCLE %s weapon=%s facing=%d frames=660 dt=1/60" % [pose, weapon, side])
				rig.free()
			var turning := _rig(weapon)
			var turn_input := _input(side)
			for frame in 240:
				turn_input.facing = side if frame < 120 else -side
				turn_input.aim_dir = Vector2(turn_input.facing, sin(frame * DT)).normalized()
				turn_input.velocity.x = turn_input.facing * data.move_speed if frame < 60 or frame >= 180 else 0.0
				turning.animate(DT, turn_input)
				check(_errors(turning, turn_input, 1.0).is_empty(), "NE80 start/stop/turn/aim weapon=%s frame=%d" % [weapon, frame])
			turning.free()


func _errors(rig: CharacterRig, input: RigInput, ratio: float) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(rig.body_scale()) or rig.body_scale() <= 0.0:
		errors.append("body-scale")
	if rig.facing != input.facing or not rig.scale.is_finite() or signf(rig.scale.x) != input.facing:
		errors.append("facing")
	for entry: Dictionary in _definition["bones"]:
		var name := StringName(entry["name"])
		var bone := rig.bone(name)
		var authored := RigLibrary.vec2(entry["pos"])
		var parent_name := StringName(entry["parent"])
		var parent: Node2D = rig._skeleton if parent_name == &"" else rig.bone(parent_name)
		if bone == null or bone.get_parent() != parent:
			errors.append("parent:" + str(name))
			continue
		if not bone.position.is_finite() or not bone.global_position.is_finite() or not bone.transform.x.is_finite() or not bone.transform.y.is_finite():
			errors.append("finite:" + str(name))
			continue
		if absf(bone.transform.determinant() - 1.0) > 0.0001:
			errors.append("bone-basis:" + str(name))
		if not bone.rest.origin.is_finite() or bone.rest.origin.distance_to(authored) > 0.0001 or bone.get_length() <= 0.0 or not is_finite(bone.get_length()):
			errors.append("bind:" + str(name))
		if parent.to_global(bone.position).distance_to(bone.global_position) > 0.0001:
			errors.append("joint-transform:" + str(name))
		if name != &"hip" and bone.position.distance_to(authored) > 0.0001:
			errors.append("joint-offset:" + str(name))
		if name in LENGTH_BONES:
			var length := bone.global_position.distance_to(parent.global_position) / rig.body_scale()
			if length <= 0.0 or absf(length - authored.length()) > 0.0001:
				errors.append("length:" + str(name))
	var orders: Array[int] = []
	for entry: Dictionary in _skin["parts"]:
		var order := int(entry.get("armor_order", 0))
		if order > 0 and not orders.has(order): orders.append(order)
	orders.sort()
	var gone := orders.size() - ceili(ratio * orders.size())
	var actual_parts: Array[CanvasItem] = []
	for name: StringName in rig.bone_order():
		for child: Node in rig.bone(name).get_children():
			if child is CanvasItem and not child is Bone2D:
				actual_parts.append(child as CanvasItem)
	if actual_parts.size() != (_skin["parts"] as Array).size():
		errors.append("part-count")
	for entry: Dictionary in _skin["parts"]:
		var slot := str(entry["name"])
		var expected_visible := int(entry.get("armor_order", 0)) == 0 or orders.find(int(entry["armor_order"])) >= gone
		var count := 0
		var found := 0
		for part: CanvasItem in actual_parts:
			if str(part.name) != slot: continue
			found += 1
			if part.is_visible_in_tree(): count += 1
			if part.get_parent() != rig.bone(StringName(entry["bone"])):
				errors.append("mount:" + slot)
			if part.z_index != int(entry.get("z", 0)):
				errors.append("layer:" + slot)
			if not (part as Node2D).transform.x.is_finite() or not (part as Node2D).transform.y.is_finite() or not (part as Node2D).position.is_finite():
				errors.append("part-finite:" + slot)
		if found != 1 or count != int(expected_visible):
			errors.append("slot:" + slot)
	var root := rig.weapon_root()
	var anchor: Dictionary = _definition["weapon_anchor"]
	var actual_anchor := rig.weapon_anchor()
	if actual_anchor[0] != StringName(anchor["bone"]) or (actual_anchor[1] as Vector2).distance_to(RigLibrary.vec2(anchor["pos"])) > 0.0001 or absf(float(actual_anchor[2]) - float(anchor["reach"])) > 0.0001:
		errors.append("weapon-anchor-data")
	if root.get_parent() != rig._skeleton:
		errors.append("weapon-mount")
	if not root.global_position.is_finite() or not root.transform.x.is_finite() or not root.transform.y.is_finite():
		errors.append("weapon-finite")
	var weapon := rig.weapon_def()
	if weapon.is_empty():
		if root.visible: errors.append("unarmed-visible")
	else:
		var authored := RigLibrary.weapon((load(DATA_PATH) as EnemyData).rig_weapon)
		for field: String in ["grip", "foregrip", "muzzle"]:
			if weapon.get(field) != authored.get(field): errors.append("weapon-data:" + field)
		var muzzle := root.to_global((RigLibrary.vec2(authored["muzzle"]) - RigLibrary.vec2(authored["grip"])) * rig.weapon_scale())
		if not rig.muzzle_global().is_finite() or rig.muzzle_global().distance_to(muzzle) > 0.0001:
			errors.append("muzzle")
		if root.visible != (not input.dead): errors.append("weapon-visibility")
		# Normal IK and block must grip the actual minigun, both hands. Dedicated
		# skip_ik enemy actions are separately checked for mount/muzzle contracts.
		if not input.dead and not (rig.animator._action_skip_ik and rig.animator._action_w > 0.001):
			for hand: StringName in [&"hand_front", &"hand_back"]:
				var grip := Vector2.ZERO if hand == &"hand_front" else (RigLibrary.vec2(authored["foregrip"]) - RigLibrary.vec2(authored["grip"])) * rig.weapon_scale()
				if rig.bone(hand).to_global(rig.hand_grip_offset(hand)).distance_to(root.to_global(grip)) >= 0.025:
					errors.append("grip:" + str(hand))
	return errors


func _reject(rig: CharacterRig, input: RigInput, expected: String, label := "") -> void:
	var errors := _errors(rig, input, 0.0)
	check(errors.has(expected), "NE80 negative control rejected %s: %s" % [expected, str(errors)])
	print("NE80_NEGATIVE %s check=%s rejected=%s" % [label if label != "" else expected, expected, errors.has(expected)])


func _test_negative_controls() -> void:
	var rig := _rig("minigun")
	var input := _input(1)
	for frame in 60: rig.animate(DT, input)
	rig.set_armor_ratio(0.0, false)
	check(_errors(rig, input, 0.0).is_empty(), "negative controls start from valid production rig")
	var torso := rig.bone(&"chest").get_node("torso") as CanvasItem
	var original_parent := torso.get_parent()
	torso.reparent(rig.bone(&"hip"), false)
	_reject(rig, input, "mount:torso")
	torso.reparent(original_parent, false)
	var bone := rig.bone(&"hand_front")
	var original_position := bone.position
	bone.position *= 1.1
	_reject(rig, input, "length:hand_front")
	bone.position = original_position
	torso.visible = false
	_reject(rig, input, "slot:torso", "hidden-underlayer")
	torso.visible = true
	var duplicate := torso.duplicate() as CanvasItem
	rig.bone(&"hip").add_child(duplicate)
	_reject(rig, input, "slot:torso", "duplicate-visible-slot")
	duplicate.free()
	# NaN is injected into the private Bone2D bind, avoiding a renderer call.
	var original_rest := bone.rest
	bone.rest = Transform2D(0.0, Vector2(NAN, 1.0))
	_reject(rig, input, "bind:hand_front")
	bone.rest = original_rest
	rig.facing = -1
	_reject(rig, input, "facing")
	rig.facing = 1
	var root := rig.weapon_root()
	root.reparent(rig.bone(&"chest"), false)
	_reject(rig, input, "weapon-mount")
	root.reparent(rig._skeleton, false)
	check(_errors(rig, input, 0.0).is_empty(), "negative controls restore valid production rig")
	rig.free()


func _test_production_enemy() -> void:
	await open_level(18.0)
	var gunner := spawn(DATA_PATH, 24.0) as HeavyGunner
	await physics_frames(4)
	check(gunner != null and gunner.rig != null and gunner.rig.skin_id == "heavy_gunner" and gunner.rig.weapon_def() == RigLibrary.weapon("minigun"), "Level creates production HeavyGunner skin and real minigun")
	check(await wait_state(gunner, &"spin_up", 180), "actual AI naturally starts spin_up")
	var closed := await _player_shot(gunner)
	check(closed == Hurtbox.Result.BLOCKED and gunner.health.current == 14 and not gunner.is_armor_open(), "C3 real pistol closed armor 14 -> 14")
	check(await wait_state(gunner, &"vent", 360), "actual AI naturally fires and vents")
	check(gunner.shots_fired >= 13 and gunner.is_armor_open(), "production firing opens vent after at least 13 shots")
	place_player(gunner.global_position.x / 16.0 + gunner.facing * 5.0)
	await physics_frames(1)
	var vent := await _player_shot(gunner)
	check(vent == Hurtbox.Result.DAMAGED and gunner.health.current == 12, "C3 real pistol vent 14 -> 12")
	print("NE80_COMBAT closed=%d vent=%d final_hp=%d shots=%d" % [closed, vent, gunner.health.current, gunner.shots_fired])
	gunner.set_physics_process(false)
	for side: int in [-1, 1]:
		gunner.facing = side
		for state: StringName in [&"spin_up", &"fire", &"vent"]:
			gunner.fsm.transition(state)
			for frame in 120:
				gunner.fsm.time_in_state = frame * DT
				gunner._drive_rig(DT)
				var errors := _errors(gunner.rig, gunner._rig_input, float(gunner.health.current) / gunner.health.max_health)
				check(errors.is_empty() and gunner._muzzle().distance_to(gunner.rig.muzzle_global()) < 0.0001, "NE80 production action %s side=%d frame=%d: %s" % [state, side, frame, str(errors)])
	gunner.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


func _player_shot(gunner: HeavyGunner) -> int:
	var result: Array[int] = []
	var blocked := func(_info: DamageInfo) -> void: result.append(Hurtbox.Result.BLOCKED)
	var received := func(_info: DamageInfo) -> void: result.append(Hurtbox.Result.DAMAGED)
	gunner.hurtbox.hit_blocked.connect(blocked)
	gunner.hurtbox.hit_received.connect(received)
	var player := level.player
	for frame in 180:
		if player._fire_cooldown_left <= 0.0 and not player.loadout.is_reloading(): break
		await physics_frames(1)
	var ammo := player.loadout.mag_in(player.loadout.active_slot)
	player.aim_dir = (gunner.global_position + Vector2(0, -gunner.data.body_size.y * 0.5) - player.muzzle_position()).normalized()
	player.facing = 1 if player.aim_dir.x >= 0.0 else -1
	player._try_fire()
	check(player.loadout.mag_in(player.loadout.active_slot) == ammo - 1, "actual Player consumes one pistol round")
	for frame in 60:
		if not result.is_empty(): break
		await physics_frames(1)
	gunner.hurtbox.hit_blocked.disconnect(blocked)
	gunner.hurtbox.hit_received.disconnect(received)
	return result[0] if not result.is_empty() else -1
