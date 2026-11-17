extends Node
## One deliberately invalid motion value must produce one real, specific error.


func _ready() -> void:
	var path := HumanoidAnimator.MOTION_PATH % "collector_brute"
	var source := RigLibrary.load_json(path)
	var fixture := source.duplicate(true)
	fixture["crouch"]["feet"] = ["bad", 0]
	RigLibrary._json_cache[path] = fixture
	var safe := true
	for repetition in 2:
		var motion := HumanoidAnimator._load_motion("collector_brute")
		safe = safe and (motion["crouch"]["feet"] as Array).is_empty()
	var rig := CharacterRig.new()
	add_child(rig)
	safe = safe and rig.setup("collector_brute")
	var input := RigInput.new()
	input.crouching = true
	input.on_floor = true
	for frame in 30:
		rig.animate(1.0 / 60.0, input)
	for bone in rig.bone_order():
		safe = safe and rig.bone(bone).position.is_finite() and is_finite(rig.bone(bone).rotation)
	rig.free()
	RigLibrary._json_cache[path] = source
	if safe:
		print("CROUCH_FEET_INVALID_SAFE")
	get_tree().quit(0 if safe else 1)
