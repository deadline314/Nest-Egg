extends RefCounted
## Kinematic contact invariants for idle/run impulses; separate from actual Player/native runs.
const LEG_BONES := [&"leg_front_upper", &"leg_front_lower", &"foot_front", &"leg_back_upper", &"leg_back_lower", &"foot_back"]
const MAX_LEG_STEP := 0.5
const MAX_PENETRATION := 0.5


static func measure(rig: CharacterRig, facing: int, body: Vector3) -> Dictionary:
	var input := RigInput.new()
	input.facing = facing
	input.aim_dir = Vector2(facing, 0)
	input.run_speed = 150.0
	input.melee_body = body
	for frame in 180:
		rig.animate(1.0 / 60.0, input)
	var previous: Array[float] = []
	for bone in LEG_BONES:
		previous.append(rig.bone(bone).rotation)
	var initial := previous.duplicate()
	var pop := 0.0
	var penetration := 0.0
	var frames: Array[Dictionary] = []
	for frame in 90:
		var speed := maxf(0.0, 260.0 - frame * 18.0) if frame < 45 else -maxf(0.0, 120.0 - (frame - 45) * 8.0)
		input.velocity.x = speed * facing
		rig.position.x += input.velocity.x / 60.0
		rig.animate(1.0 / 60.0, input)
		var angles: Array[float] = []
		for i in LEG_BONES.size():
			var angle := rig.bone(LEG_BONES[i]).rotation
			pop = maxf(pop, absf(angle_difference(previous[i], angle)))
			angles.append(angle)
			previous[i] = angle
		var floor_errors := [rig.animator.bone_pos(&"foot_front").y - rig.animator.ground_level(), rig.animator.bone_pos(&"foot_back").y - rig.animator.ground_level()]
		penetration = maxf(penetration, maxf(floor_errors[0], floor_errors[1]))
		frames.append({"frame": frame, "speed": speed, "angles": angles, "floor_errors": floor_errors})
	return {"leg_pop": pop, "penetration": penetration, "accepted": pop <= MAX_LEG_STEP and penetration <= MAX_PENETRATION, "initial_angles": initial, "frames": frames}
