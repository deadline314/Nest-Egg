extends Node2D

const OUTPUT_DIR := "res://pm/Nest-Egg/images/NE-222-leg-ik"
const CANDIDATE_JSON := "res://pm/Nest-Egg/attachments/NE-222-leg-ik/feasibility-kneel-scan.json"
const GEOMETRY := preload("res://tools/comfyui/rig_reference.gd")
const HIGH_ZOOM := 23.78
const MARGIN := 24.0
const GRIP_TOLERANCE_WORLD := 0.025
const SKELETON_TOLERANCE := 0.00001
const KNEE_COLUMN_HALF_WIDTH := 0.25
const KNEE_FLEXION_MAX_DEGREES := 140.0
const FRONT_THIGH_UP_MAX_DEGREES := 25.0
const FRONT_SHIN_FROM_VERTICAL_MAX_DEGREES := 45.0

var _candidate: Dictionary
var _capture_args := {}


func _ready() -> void:
	_capture_args = _parse_args()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_JSON))
	assert(typeof(parsed) == TYPE_DICTIONARY, "Missing or malformed feasibility candidate JSON: %s" % CANDIDATE_JSON)
	var data: Dictionary = parsed as Dictionary
	assert(str(data.get("scope", "")).begins_with("CPU geometry feasibility scan"), "Unexpected candidate source")
	var candidate_value: Variant = data.get("selected_candidate", {})
	assert(typeof(candidate_value) == TYPE_DICTIONARY, "Candidate JSON is missing selected_candidate dictionary")
	_candidate = candidate_value as Dictionary
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(_capture_args["out"])))
	for zoom in [1.0, HIGH_ZOOM]:
		for facing in [1, -1]:
			await _capture_view(float(zoom), int(facing))
	get_tree().quit()


func _parse_args() -> Dictionary:
	var result := {"out": OUTPUT_DIR}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			result["out"] = arg.trim_prefix("--out=")
	return result


func _capture_view(zoom: float, facing: int) -> void:
	var viewport := SubViewport.new()
	viewport.name = "KneelCapture_%s_%s" % [str(zoom).replace(".", "p"), "right" if facing > 0 else "left"]
	viewport.size = Vector2i(32, 32)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var stage := Node2D.new()
	stage.name = "HDRStage"
	viewport.add_child(stage)
	stage.add_child(LightKit.create_environment())
	var key_light := LightKit.create_point_light(Color("f0f4ff"), 900.0, 0.75, false, false)
	key_light.name = "NeutralKeyLight"
	stage.add_child(key_light)

	var holder := Node2D.new()
	holder.name = "CaptureScale"
	holder.scale = Vector2.ONE * zoom
	stage.add_child(holder)

	var rig := CharacterRig.new()
	_setup_rig(rig, holder, facing)
	var input := RigInput.new()
	input.on_floor = true
	input.two_handed = true
	input.facing = facing
	input.aim_dir = Vector2(float(facing), 0.0)
	for _frame in 120:
		rig.animate(1.0 / 60.0, input)
	rig.set_weapon("rifle")
	# set_weapon changes the image/scale; settle the production input state once more before applying the candidate.
	for _frame in 2:
		rig.animate(1.0 / 60.0, input)
	var animator: HumanoidAnimator = rig.animator
	_apply_candidate_pose(rig, animator, input)
	rig.refresh_limbs()
	await get_tree().process_frame
	rig.refresh_limbs()
	await get_tree().process_frame

	var prefit_bounds := _visible_bounds(rig)
	assert(prefit_bounds.size.x > 0.0 and prefit_bounds.size.y > 0.0, "Visible rig/weapon bounds are empty")
	viewport.size = Vector2i(ceili(prefit_bounds.size.x + MARGIN * 2.0), ceili(prefit_bounds.size.y + MARGIN * 2.0))
	holder.position = Vector2(MARGIN - prefit_bounds.position.x, MARGIN - prefit_bounds.position.y)
	key_light.position = Vector2(viewport.size) * 0.5
	await get_tree().process_frame
	rig.refresh_limbs()
	await RenderingServer.frame_post_draw

	var final_bounds := _visible_bounds(rig)
	assert(final_bounds.position.x >= MARGIN - 1.0 and final_bounds.position.y >= MARGIN - 1.0,
		"Visible bounds clipped at top/left: %s" % final_bounds)
	assert(final_bounds.end.x <= float(viewport.size.x) - MARGIN + 1.0 and final_bounds.end.y <= float(viewport.size.y) - MARGIN + 1.0,
		"Visible bounds clipped at right/bottom: %s within %s" % [final_bounds, viewport.size])
	var floor_y := holder.position.y
	var floor := Line2D.new()
	floor.name = "MeasuredFloorY0"
	floor.points = PackedVector2Array([Vector2(0.0, floor_y), Vector2(float(viewport.size.x), floor_y)])
	floor.width = 1.0
	floor.default_color = Color(0.2, 0.75, 0.9, 0.8)
	floor.z_index = -100
	viewport.add_child(floor)
	await RenderingServer.frame_post_draw

	var contact := _contact_measurements(rig, animator)
	var grip := _grip_measurements(rig)
	var bones := _bone_records(rig, animator)
	var parts := _part_records(rig)
	var image: Image = preload("res://tools/viewport_capture.gd").image(viewport)
	var filename := "kneel_%s_facing_%s.png" % ["game_1x" if is_equal_approx(zoom, 1.0) else "source_23p78x", "right" if facing > 0 else "left"]
	var abs_out: String = ProjectSettings.globalize_path(str(_capture_args["out"]))
	assert(image.save_png(abs_out.path_join(filename)) == OK, "Failed to save capture: %s" % filename)
	var capture := {
		"status": "written after this scene's assertions pass; still not source/art/native acceptance",
		"candidate_json": CANDIDATE_JSON,
		"candidate_snapshot_head": "811351caf8e0d6229d366037522bba7d77ecd3f4",
		"zoom": zoom,
		"facing": facing,
		"size": [viewport.size.x, viewport.size.y],
		"transparent_background": true,
		"hdr_2d": viewport.use_hdr_2d,
		"light_setup": {"environment": "LightKit.create_environment", "key_color": "f0f4ff", "radius": 900.0, "energy": 0.75,
			"position_capture": _vec_record(key_light.position)},
		"renderer": "project default; scene does not override Forward+ renderer/materials",
		"scale_matrix": _transform_record(holder.get_global_transform()),
		"character_scale": rig._base_scale,
		"texture_scale": rig._texture_scale,
		"viewport_bounds": _rect_record(final_bounds),
		"floor_y_capture_pixels": floor_y,
		"bones": bones,
		"parts": parts,
		"contacts": contact,
		"weapon": grip,
		"image": filename,
	}
	var json_path := abs_out.path_join(filename.get_basename() + ".json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	assert(file != null, "Cannot write capture metadata: %s" % json_path)
	file.store_string(JSON.stringify(capture, "\t"))
	file.close()
	print("native-feasible capture prepared: %s %s; grip %.6f/%.6f world px; sole/knee %s" % [filename, str(viewport.size), grip["front_residual_world"], grip["back_residual_world"], str(contact)])
	viewport.queue_free()
	await get_tree().process_frame


func _setup_rig(rig: CharacterRig, holder: Node2D, facing: int) -> void:
	holder.add_child(rig)
	rig.position = Vector2.ZERO
	rig.facing = facing
	assert(rig.setup("rin"), "CharacterRig setup failed for Rin")
	rig.facing = facing
	rig.set_weapon("rifle")
	assert(rig.weapon_root().visible, "Rifle weapon root should be visible")


func _apply_candidate_pose(rig: CharacterRig, animator: HumanoidAnimator, input: RigInput) -> void:
	assert(float(_candidate["front_thigh_up_degrees"]) <= FRONT_THIGH_UP_MAX_DEGREES)
	assert(float(_candidate["front_shin_from_vertical_degrees"]) <= FRONT_SHIN_FROM_VERTICAL_MAX_DEGREES)
	assert(float(_candidate["front_knee_flexion_degrees"]) <= KNEE_FLEXION_MAX_DEGREES)
	assert(float(_candidate["rear_knee_flexion_degrees"]) <= KNEE_FLEXION_MAX_DEGREES)
	var hip_target := _point("hip")
	var front_knee_target := _point("front_knee")
	var front_ankle_target := _point("front_ankle")
	var rear_knee_target := _point("rear_knee")
	var rear_ankle_target := _point("rear_ankle")
	var front_upper_target := _point("front_upper_origin")
	var rear_upper_target := _point("rear_upper_origin")
	animator._hip_offset = hip_target - rig.rest(&"hip")
	animator._ground_shift = 0.0
	animator._angles[&"hip"] = 0.0
	animator._angles[&"chest"] = 0.04
	animator._angles[&"neck"] = -0.04
	animator._angles[&"head"] = 0.0
	animator._overlay.clear()
	animator._apply_body()
	animator._forward_kinematics()
	# These targets are animator/skeleton coordinates. _reach_leg consumes them before CharacterRig scale (1.15) and capture zoom.
	animator._reach_leg(&"leg_front_upper", &"leg_front_lower", &"foot_front", front_ankle_target, 0.0)
	animator._forward_kinematics()
	var rear_lower_direction: float = (rear_ankle_target - rear_knee_target).angle()
	var rear_foot_global_angle: float = rear_lower_direction - PI * 0.5
	animator._reach_leg(&"leg_back_upper", &"leg_back_lower", &"foot_back", rear_ankle_target, rear_foot_global_angle)
	animator._forward_kinematics()
	animator._solve_arms(input, 0.0)
	animator._forward_kinematics()
	rig.refresh_limbs()
	assert(rig.bone(&"hip").position.distance_to(hip_target) <= SKELETON_TOLERANCE, "Hip target transform mismatch")
	assert(animator.bone_pos(&"leg_front_upper").distance_to(front_upper_target) <= SKELETON_TOLERANCE, "Front IK origin differs from candidate")
	assert(animator.bone_pos(&"leg_front_lower").distance_to(front_knee_target) <= SKELETON_TOLERANCE, "Front IK knee differs from candidate")
	assert(animator.bone_pos(&"foot_front").distance_to(front_ankle_target) <= SKELETON_TOLERANCE, "Front IK ankle differs from candidate")
	assert(animator.bone_pos(&"leg_back_upper").distance_to(rear_upper_target) <= SKELETON_TOLERANCE, "Rear IK origin differs from candidate/rest offset")
	assert(animator.bone_pos(&"leg_back_lower").distance_to(rear_knee_target) <= SKELETON_TOLERANCE, "Rear IK knee differs from candidate")
	assert(animator.bone_pos(&"foot_back").distance_to(rear_ankle_target) <= SKELETON_TOLERANCE, "Rear IK ankle differs from candidate")
	var front_upper_length: float = animator.bone_pos(&"leg_front_upper").distance_to(animator.bone_pos(&"leg_front_lower"))
	var front_lower_length: float = animator.bone_pos(&"leg_front_lower").distance_to(animator.bone_pos(&"foot_front"))
	var rear_upper_length: float = animator.bone_pos(&"leg_back_upper").distance_to(animator.bone_pos(&"leg_back_lower"))
	var rear_lower_length: float = animator.bone_pos(&"leg_back_lower").distance_to(animator.bone_pos(&"foot_back"))
	assert(absf(front_upper_length - rig.rest(&"leg_front_lower").length()) <= SKELETON_TOLERANCE, "Front femur length changed")
	assert(absf(front_lower_length - rig.rest(&"foot_front").length()) <= SKELETON_TOLERANCE, "Front shin length changed")
	assert(absf(rear_upper_length - rig.rest(&"leg_back_lower").length()) <= SKELETON_TOLERANCE, "Rear femur length changed")
	assert(absf(rear_lower_length - rig.rest(&"foot_back").length()) <= SKELETON_TOLERANCE, "Rear shin length changed")
	var local_rear_foot_degrees := rad_to_deg(rig.bone(&"foot_back").rotation)
	var global_rear_foot_degrees := rad_to_deg(animator._global_angle[&"foot_back"])
	var reached_rear_lower_global: float = animator._global_angle[&"leg_back_lower"]
	assert(absf(angle_difference(rear_foot_global_angle, reached_rear_lower_global)) <= 0.01,
		"Rear calf global angle must be derived from target ankle-knee; target=%s got=%s" % [rear_foot_global_angle, reached_rear_lower_global])
	assert(absf(local_rear_foot_degrees) <= 0.001, "Rear foot should locally align with its calf in this candidate; local=%s" % local_rear_foot_degrees)
	assert(absf(wrapf(global_rear_foot_degrees - float(_candidate["rear_foot_global_angle_degrees"]), -180.0, 180.0)) <= 0.01,
		"Rear foot global skeleton angle differs from candidate field")
	var front_knee_hyper := _anim_audit_knee_hyper(rig.bone(&"leg_front_lower").rotation)
	var rear_knee_hyper := _anim_audit_knee_hyper(rig.bone(&"leg_back_lower").rotation)
	var knee_hyper_limit := float(AnimAudit.LIMITS["knee_hyper"])
	assert(front_knee_hyper <= knee_hyper_limit and rear_knee_hyper <= knee_hyper_limit,
		"Candidate exceeds AnimAudit reverse-bend limit: front %.6f rear %.6f limit %.6f" % [front_knee_hyper, rear_knee_hyper, knee_hyper_limit])
	assert(_anim_audit_knee_hyper(-0.2) > knee_hyper_limit,
		"Negative control: a lower-bone rotation of -0.2 rad must be detected as reverse bend")


func _contact_measurements(rig: CharacterRig, animator: HumanoidAnimator) -> Dictionary:
	var skeleton := rig._skeleton
	var front_foot := _part_named(rig, &"foot_front") as Sprite2D
	var rear_foot := _part_named(rig, &"foot_back") as Sprite2D
	assert(front_foot != null and rear_foot != null, "Both foot sprites are required for alpha contact")
	var front_sole := _opaque_lowest_sprite_point(front_foot, skeleton)
	var rear_sole := _opaque_lowest_sprite_point(rear_foot, skeleton)
	assert(absf(float(front_sole["skeleton_point"][1])) <= 0.02, "Front boot opaque sole is not on floor: %s" % front_sole)
	assert(absf(float(rear_sole["skeleton_point"][1])) <= 0.02, "Rear boot opaque sole is not on floor: %s" % rear_sole)
	var knee := animator.bone_pos(&"leg_back_lower")
	var knee_samples: Array[Dictionary] = []
	for part in rig._parts:
		if part.name not in [&"leg_back_upper", &"leg_back_lower"]:
			continue
		if part is RigPartMesh:
			knee_samples.append_array(_mesh_alpha_points_near_joint(part as RigPartMesh, skeleton, knee))
		elif part is Sprite2D:
			knee_samples.append_array(_sprite_alpha_points_near_joint(part as Sprite2D, skeleton, knee))
	assert(not knee_samples.is_empty(), "No original alpha samples near the rear knee joint")
	var lowest_knee := knee_samples[0]
	for sample in knee_samples:
		if float(sample["skeleton_point"][1]) > float(lowest_knee["skeleton_point"][1]):
			lowest_knee = sample
	assert(absf(float(lowest_knee["skeleton_point"][1])) <= 0.03,
		"Rear knee source-alpha contour is not in contact with floor: %s" % lowest_knee)
	return {
		"floor_skeleton_y": 0.0,
		"front_opaque_sole": front_sole,
		"rear_opaque_sole": rear_sole,
		"rear_knee_joint_skeleton": _vec_record(knee),
		"rear_lower_global_angle_from_target_degrees": rad_to_deg((animator.bone_pos(&"foot_back") - knee).angle() - PI * 0.5),
		"rear_knee_source_alpha_contact_point": lowest_knee,
		"rear_knee_alpha_samples_in_joint_column": knee_samples.size(),
		"rear_foot_rotation_global_skeleton_degrees": rad_to_deg(animator._global_angle[&"foot_back"]),
		"rear_foot_rotation_local_bone_degrees": rad_to_deg(rig.bone(&"foot_back").rotation),
		"anim_audit_knee_hyper_front_radians": _anim_audit_knee_hyper(rig.bone(&"leg_front_lower").rotation),
		"anim_audit_knee_hyper_rear_radians": _anim_audit_knee_hyper(rig.bone(&"leg_back_lower").rotation),
		"anim_audit_knee_hyper_limit_radians": AnimAudit.LIMITS["knee_hyper"],
		"negative_control_reverse_rotation_radians": -0.2,
		"negative_control_reverse_detected": _anim_audit_knee_hyper(-0.2) > float(AnimAudit.LIMITS["knee_hyper"]),
	}


func _grip_measurements(rig: CharacterRig) -> Dictionary:
	var definition := rig.weapon_def()
	assert(not definition.is_empty() and str(definition.get("id", "rifle")) != "", "Rifle definition was not loaded")
	var front_hand := rig.bone(&"hand_front")
	var rear_hand := rig.bone(&"hand_back")
	var front_palm: Vector2 = front_hand.global_transform * rig.hand_grip_offset(&"hand_front")
	var rear_palm: Vector2 = rear_hand.global_transform * rig.hand_grip_offset(&"hand_back")
	var front_grip := rig.weapon_root().global_position
	var foregrip_local := (RigLibrary.vec2(definition["foregrip"]) - RigLibrary.vec2(definition["grip"])) * rig.weapon_scale()
	var rear_grip: Vector2 = rig.weapon_root().global_transform * foregrip_local
	var front_residual := front_palm.distance_to(front_grip)
	var rear_residual := rear_palm.distance_to(rear_grip)
	assert(front_residual <= GRIP_TOLERANCE_WORLD, "Front palm-to-rifle-grip residual %.6f exceeds %.3f world px" % [front_residual, GRIP_TOLERANCE_WORLD])
	assert(rear_residual <= GRIP_TOLERANCE_WORLD, "Rear palm-to-rifle-foregrip residual %.6f exceeds %.3f world px" % [rear_residual, GRIP_TOLERANCE_WORLD])
	var weapon_sprite: Sprite2D = rig.weapon_root().get_child(0) as Sprite2D
	assert(weapon_sprite != null and weapon_sprite.texture != null, "Rifle sprite texture is missing")
	var source_geometry: Dictionary = GEOMETRY.geometry(weapon_sprite)
	var pixel_to_capture: Transform2D = weapon_sprite.global_transform * Transform2D(0.0, weapon_sprite.offset)
	var pixel_to_skeleton: Transform2D = rig._skeleton.global_transform.affine_inverse() * pixel_to_capture
	source_geometry["source_pixels_to_capture"] = _transform_record(pixel_to_capture)
	source_geometry["capture_to_source_pixels"] = _transform_record(pixel_to_capture.affine_inverse())
	source_geometry["source_pixels_to_rig_skeleton"] = _transform_record(pixel_to_skeleton)
	source_geometry["texture_channels"] = _texture_channels(weapon_sprite.texture)
	return {"weapon_id": "rifle", "weapon_visible": rig.weapon_root().visible, "source_geometry": source_geometry,
		"front_palm_global_world": _vec_record(front_palm), "front_weapon_grip_global_world": _vec_record(front_grip),
		"front_residual_world": front_residual, "back_palm_global_world": _vec_record(rear_palm),
		"back_weapon_foregrip_global_world": _vec_record(rear_grip), "back_residual_world": rear_residual,
		"tolerance_world": GRIP_TOLERANCE_WORLD}


func _bone_records(rig: CharacterRig, animator: HumanoidAnimator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for name in rig.bone_order():
		var bone := rig.bone(name)
		if name != &"hip":
			assert(bone.position.distance_to(rig.rest(name)) <= SKELETON_TOLERANCE,
				"Local rest offset changed for %s: %s versus %s" % [name, bone.position, rig.rest(name)])
		var local_transform := bone.transform
		var global_transform := bone.global_transform
		result.append({"name": str(name), "parent": str(rig.parent_of(name)), "local_position": _vec_record(bone.position),
			"local_rotation_radians": bone.rotation, "local_rotation_degrees": rad_to_deg(bone.rotation),
			"global_position_capture": _vec_record(bone.global_position), "global_rotation_radians": bone.global_rotation,
			"global_rotation_degrees": rad_to_deg(bone.global_rotation), "animator_skeleton_position": _vec_record(animator.bone_pos(name)),
			"animator_skeleton_global_angle_radians": animator.foot_angle(name), "animator_skeleton_global_angle_degrees": rad_to_deg(animator.foot_angle(name)),
			"rest_position": _vec_record(rig.rest(name)), "local_transform": _transform_record(local_transform),
			"global_transform": _transform_record(global_transform)})
	return result


func _part_records(rig: CharacterRig) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var skeleton_inverse: Transform2D = rig._skeleton.global_transform.affine_inverse()
	for part in rig._parts:
		var was_visible := part.visible
		if part is RigPartMesh and not was_visible:
			part.visible = true
			(part as RigPartMesh).refresh()
			part.visible = false
		var record: Dictionary = GEOMETRY.geometry(part)
		record["name"] = str(part.name)
		record["parent_bone"] = str(part.get_parent().name)
		record["z"] = part.z_index
		record["visible_in_capture"] = was_visible and part.is_visible_in_tree()
		record["local_transform"] = _transform_record(part.transform)
		record["global_transform_capture"] = _transform_record(part.global_transform)
		if part is Sprite2D:
			var sprite := part as Sprite2D
			var pixel_to_local := Transform2D(0.0, sprite.offset)
			var pixel_to_capture: Transform2D = sprite.global_transform * pixel_to_local
			var pixel_to_skeleton: Transform2D = skeleton_inverse * pixel_to_capture
			record["source_pixels_to_capture"] = _transform_record(pixel_to_capture)
			record["capture_to_source_pixels"] = _transform_record(pixel_to_capture.affine_inverse())
			record["source_pixels_to_rig_skeleton"] = _transform_record(pixel_to_skeleton)
			record["texture_channels"] = _texture_channels(sprite.texture)
		elif part is RigPartMesh:
			var mesh := part as RigPartMesh
			var local_to_skeleton: Transform2D = skeleton_inverse * mesh.global_transform
			var skel_vertices: Array = []
			for vertex in mesh.deformed_vertices():
				skel_vertices.append(_vec_record(local_to_skeleton * vertex))
			record["deformed_vertices_rig_skeleton"] = skel_vertices
			record["source_uv_to_skeleton_piecewise"] = true
		result.append(record)
	return result


func _visible_bounds(rig: CharacterRig) -> Rect2:
	var bounds := Rect2()
	var has_point := false
	for part in rig._parts:
		if not part.is_visible_in_tree():
			continue
		if part is Sprite2D:
			var sprite_rect := _sprite_global_rect(part as Sprite2D)
			if not has_point:
				bounds = sprite_rect
				has_point = true
			else:
				bounds = bounds.merge(sprite_rect)
		elif part is RigPartMesh:
			for vertex in (part as RigPartMesh).deformed_vertices():
				var point: Vector2 = part.to_global(vertex)
				if not has_point:
					bounds = Rect2(point, Vector2.ZERO)
					has_point = true
				else:
					bounds = bounds.expand(point)
	for node in _descendants(rig.weapon_root()):
		if node is Sprite2D and node.is_visible_in_tree():
			var sprite_rect := _sprite_global_rect(node as Sprite2D)
			if not has_point:
				bounds = sprite_rect
				has_point = true
			else:
				bounds = bounds.merge(sprite_rect)
	assert(has_point, "Could not measure visible part bounds")
	return bounds


func _sprite_global_rect(sprite: Sprite2D) -> Rect2:
	var rect := sprite.get_rect()
	var transform := sprite.global_transform
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var output := Rect2(transform * corners[0], Vector2.ZERO)
	for i in range(1, corners.size()):
		output = output.expand(transform * corners[i])
	return output


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _part_named(rig: CharacterRig, part_name: StringName) -> CanvasItem:
	for part in rig._parts:
		if part.name == part_name:
			return part
	return null


func _opaque_lowest_sprite_point(sprite: Sprite2D, skeleton: Skeleton2D) -> Dictionary:
	var image := _diffuse_texture(sprite.texture).get_image()
	var lowest := Vector2(INF, -INF)
	var native := Vector2.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 0.5:
				continue
			var point := skeleton.to_local(sprite.to_global(Vector2(x, y) + sprite.offset))
			count += 1
			if point.y > lowest.y:
				lowest = point
				native = Vector2(x, y)
	assert(count > 0, "%s has no opaque pixels" % sprite.name)
	return {"part": str(sprite.name), "native_alpha_pixel": _vec_record(native), "skeleton_point": _vec_record(lowest), "opaque_pixel_count": count}


func _sprite_alpha_points_near_joint(sprite: Sprite2D, skeleton: Skeleton2D, joint: Vector2) -> Array[Dictionary]:
	var image := _diffuse_texture(sprite.texture).get_image()
	var output: Array[Dictionary] = []
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 0.5:
				continue
			var p := skeleton.to_local(sprite.to_global(Vector2(x, y) + sprite.offset))
			if absf(p.x - joint.x) <= KNEE_COLUMN_HALF_WIDTH:
				output.append({"part": str(sprite.name), "native_alpha_pixel": _vec_record(Vector2(x, y)), "skeleton_point": _vec_record(p)})
	return output


func _mesh_alpha_points_near_joint(mesh: RigPartMesh, skeleton: Skeleton2D, joint: Vector2) -> Array[Dictionary]:
	var texture := _diffuse_texture(mesh.texture)
	var image := texture.get_image()
	var uv := mesh.uv
	var vertices := mesh.deformed_vertices()
	var output: Array[Dictionary] = []
	for triangle in mesh.polygons:
		var indices: PackedInt32Array = triangle
		if indices.size() != 3:
			continue
		var u0 := uv[indices[0]]
		var u1 := uv[indices[1]]
		var u2 := uv[indices[2]]
		var p0 := vertices[indices[0]]
		var p1 := vertices[indices[1]]
		var p2 := vertices[indices[2]]
		var denominator := (u1.y - u2.y) * (u0.x - u2.x) + (u2.x - u1.x) * (u0.y - u2.y)
		if absf(denominator) < 0.000001:
			continue
		var min_x := maxi(0, floori(minf(u0.x, minf(u1.x, u2.x))))
		var max_x := mini(image.get_width() - 1, ceili(maxf(u0.x, maxf(u1.x, u2.x))))
		var min_y := maxi(0, floori(minf(u0.y, minf(u1.y, u2.y))))
		var max_y := mini(image.get_height() - 1, ceili(maxf(u0.y, maxf(u1.y, u2.y))))
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				if image.get_pixel(x, y).a < 0.5:
					continue
				var sample := Vector2(x + 0.5, y + 0.5)
				var a := ((u1.y - u2.y) * (sample.x - u2.x) + (u2.x - u1.x) * (sample.y - u2.y)) / denominator
				var b := ((u2.y - u0.y) * (sample.x - u2.x) + (u0.x - u2.x) * (sample.y - u2.y)) / denominator
				var c := 1.0 - a - b
				if a < -0.0001 or b < -0.0001 or c < -0.0001:
					continue
				var mesh_local := p0 * a + p1 * b + p2 * c
				var skeleton_point := skeleton.to_local(mesh.to_global(mesh_local))
				if absf(skeleton_point.x - joint.x) <= KNEE_COLUMN_HALF_WIDTH:
					output.append({"part": str(mesh.name), "native_alpha_pixel": _vec_record(sample), "skeleton_point": _vec_record(skeleton_point)})
	return output


func _diffuse_texture(texture: Texture2D) -> Texture2D:
	assert(texture != null, "A contact part has no texture")
	if texture is CanvasTexture:
		var diffuse := (texture as CanvasTexture).diffuse_texture
		assert(diffuse != null, "CanvasTexture has no diffuse channel")
		return diffuse
	return texture


func _texture_channels(texture: Texture2D) -> Dictionary:
	if texture is CanvasTexture:
		var canvas := texture as CanvasTexture
		return {"type": "CanvasTexture", "diffuse": canvas.diffuse_texture.resource_path if canvas.diffuse_texture != null else "",
			"normal": canvas.normal_texture.resource_path if canvas.normal_texture != null else "",
			"normal_preserved": canvas.normal_texture != null}
	return {"type": texture.get_class() if texture != null else "missing", "normal": "", "normal_preserved": false}


func _point(key: String) -> Vector2:
	return Vector2(_candidate[key][0], _candidate[key][1])


func _anim_audit_knee_hyper(lower_rotation: float) -> float:
	# Mirrors AnimAudit._measure: the metric is positive only when the lower segment reverses.
	return -lower_rotation


func _transform_record(value: Transform2D) -> Array:
	return [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]


func _rect_record(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _vec_record(value: Vector2) -> Array:
	return [value.x, value.y]
