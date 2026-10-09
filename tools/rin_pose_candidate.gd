extends Node2D
## Isolated pose-art review. It does not change the player's assets or animator.

const WORK := "res://art_src/characters/rin_pose_variants/03_parts/"
const Capture := preload("res://tools/viewport_capture.gd")
var _out := ""
var _facing := 1
var _zoom := 3.4


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--facing="):
			_facing = -1 if arg.trim_prefix("--facing=") == "-1" else 1
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
	assert(_zoom > 0 and _zoom <= 3.4)
	add_child(LightKit.create_environment())
	var bg := ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("62697b")
	bg.z_index = -10
	add_child(bg)
	for column in 3:
		var stage := Node2D.new()
		stage.position = Vector2(95 + column * 213, 327)
		stage.scale = Vector2.ONE * _zoom
		add_child(stage)
		var rig := CharacterRig.new()
		stage.add_child(rig)
		assert(rig.setup("rin"))
		rig.set_weapon("rifle" if column == 2 else "")
		var input := RigInput.new()
		input.on_floor = true
		input.facing = _facing
		input.aim_dir = Vector2(_facing, 0)
		for frame in 90:
			rig.animate(1.0 / 60.0, input)
		if column > 0:
			_attach_pose(rig, "crouch" if column == 1 else "kneel", input)
		var label := Label.new()
		label.position = Vector2(12 + column * 213, 8)
		label.text = ["APPROVED UPPER BODY / STAND", "CROUCH ART / CANDIDATE", "KNEEL ART / CANDIDATE"][column]
		label.add_theme_font_size_override("font_size", 11)
		add_child(label)
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(column * 213, 327), Vector2(column * 213 + 210, 327)])
		line.width = 1.0
		line.default_color = Color("bbccd8")
		add_child(line)
	_capture.call_deferred()


func _attach_pose(rig: CharacterRig, pose: String, input: RigInput) -> void:
	var data := JSON.parse_string(FileAccess.get_file_as_string(WORK + pose + "/parts.json")) as Dictionary
	assert(not data.is_empty())
	var density: float = data["px_per_world"]
	var waist := RigLibrary.vec2(data["waist"])
	var source := Image.load_from_file(ProjectSettings.globalize_path(WORK + pose + "/source_rgba.png"))
	assert(source != null)
	var rect := source.get_used_rect()
	var ground: float = rect.end.y - 1
	var hip_bone := rig.bone(&"hip")
	# Align the candidate waist to the approved torso; old lower parts are hidden.
	hip_bone.position.y = (waist.y - ground) / density - rig.rest(&"chest").y
	hip_bone.rotation = 0
	rig.bone(&"chest").rotation = 0.16 if pose == "crouch" else 0
	rig.animator._forward_kinematics()
	rig.animator._solve_arms(input, 0)
	rig.refresh_limbs()
	for part in rig._parts:
		if part.get_parent().name in ["hip", "leg_front_upper", "leg_front_lower", "foot_front", "leg_back_upper", "leg_back_lower", "foot_back"]:
			part.visible = false
	# Candidate bones are measured from this pose; canonical lengths are audited separately.
	var lower := Skeleton2D.new()
	lower.name = "PoseCandidateSkeleton"
	hip_bone.add_child(lower)
	var origin := Vector2(waist.x, waist.y - rig.rest(&"chest").y * density)
	var chains := [["hip", "", "hip", ""],
		["leg_front_upper", "hip", "hip", "knee_front"],
		["leg_front_lower", "leg_front_upper", "knee_front", "ankle_front"],
		["foot_front", "leg_front_lower", "ankle_front", ""],
		["leg_back_upper", "hip", "hip_back", "knee_back"],
		["leg_back_lower", "leg_back_upper", "knee_back", "ankle_back"],
		["foot_back", "leg_back_lower", "ankle_back", ""]]
	var bones: Dictionary = {}
	var points: Dictionary = {}
	var angles: Dictionary = {}
	for chain in chains:
		var point := RigLibrary.vec2(data["joints"][chain[2]])
		var angle := 0.0
		var length := 1.0
		if chain[3] != "":
			var axis := RigLibrary.vec2(data["joints"][chain[3]]) - point
			angle = axis.angle() - PI * 0.5
			length = axis.length() / density
		var bone := Bone2D.new()
		bone.name = chain[0]
		var parent: Node2D = lower if chain[1] == "" else bones[chain[1]]
		var parent_point: Vector2 = origin if chain[1] == "" else points[chain[1]]
		var parent_angle: float = 0 if chain[1] == "" else angles[chain[1]]
		bone.position = ((point - parent_point) / density).rotated(-parent_angle)
		bone.rotation = angle - parent_angle
		bone.rest = bone.transform
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(length)
		bone.set_bone_angle(PI * 0.5)
		parent.add_child(bone)
		assert(bone.global_position.distance_to(lower.to_global((point - origin) / density)) < 0.001)
		bones[chain[0]] = bone
		points[chain[0]] = point
		angles[chain[0]] = angle
		if chain[3] != "":
			var canonical: float = rig.rest(&"leg_front_lower" if chain[0].ends_with("upper") else &"foot_front").length()
			print(pose, " ", chain[0], " source length=", length, " canonical=", canonical)
	for entry in data["parts"]:
		var bone: Bone2D = bones[entry["bone"]]
		var sprite := Sprite2D.new()
		var image := Image.load_from_file(ProjectSettings.globalize_path(WORK + pose + "/" + entry["file"]))
		assert(image != null)
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.centered = false
		sprite.offset = -RigLibrary.vec2(entry["pivot"])
		sprite.scale = Vector2.ONE / density
		sprite.rotation = -float(angles[entry["bone"]])
		sprite.z_index = entry["z"]
		sprite.material = rig._light_material
		bone.add_child(sprite)
	# Art placement only; this must not be mistaken for canonical-chain validation.
	var adjustment: Dictionary = data.get("review_adjustment", {})
	var rear: Bone2D = bones["foot_back"]
	rear.rotation += float(adjustment.get("rear_foot_rotation", 0))
	rear.position += RigLibrary.vec2(adjustment.get("rear_foot_shift")).rotated(-float(angles["leg_back_lower"]))


func _capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not _out.is_empty():
		var image := Capture.image(get_viewport())
		assert(image.save_png(_out) == OK)
		print("Rin pose candidate: ", image.get_size(), " -> ", _out)
	get_tree().quit()
