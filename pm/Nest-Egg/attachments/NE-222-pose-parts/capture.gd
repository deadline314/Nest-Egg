extends Node
## Synthetic same-source attachment plumbing capture. Do not treat it as accepted kneel art.
## Run only under tools/comfyui/gpu_lock.py with Forward+; this script does not initiate ComfyUI.

const CELL_SIZE := Vector2i(320, 260)
const STATES := [&"base", &"pose", &"cleared"]
const FACINGS := [1, -1]
const ARMOR_RATIOS := [1.0, 0.5, 0.0]
const POSE_KEY := &"capture_same_source"
const FIXTURE_ID := "Ne222PoseAttachmentNative.synthetic.same-source.v1"
const CAPTURE := preload("res://tools/viewport_capture.gd")

var _checks := 0
var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_dir = argument.trim_prefix("--out=")
	if output_dir.is_empty():
		push_error("NE222 attachment capture requires --out=<absolute directory>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK and not DirAccess.dir_exists_absolute(output_dir):
		push_error("NE222 attachment capture cannot create output directory: %s" % output_dir)
		get_tree().quit(2)
		return

	var source_skin := RigLibrary.character("rin")
	if source_skin.is_empty():
		push_error("NE222 attachment capture could not load the Rin skin")
		get_tree().quit(2)
		return
	var fixture := _same_source_fixture(source_skin)
	_check(RenderingServer.get_current_rendering_method() == "forward_plus", "capture runs with the project's native Forward+ renderer")
	var viewport := SubViewport.new()
	viewport.size = CELL_SIZE
	viewport.use_hdr_2d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := Node2D.new()
	viewport.add_child(stage)
	stage.add_child(LightKit.create_environment())
	var background := ColorRect.new()
	background.color = Color("5b6577")
	background.size = Vector2(CELL_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -100
	stage.add_child(background)
	var ground := Line2D.new()
	ground.points = PackedVector2Array([Vector2(0, CELL_SIZE.y - 25), Vector2(CELL_SIZE.x, CELL_SIZE.y - 25)])
	ground.width = 1.0
	ground.default_color = Color("293344")
	ground.z_index = -10
	stage.add_child(ground)
	var key_light := LightKit.create_point_light(Color("f0f4ff"), 520.0, 0.9, false, false)
	key_light.position = Vector2(CELL_SIZE.x * 0.5, CELL_SIZE.y * 0.35)
	stage.add_child(key_light)

	var composite := Image.create(CELL_SIZE.x * STATES.size(), CELL_SIZE.y * FACINGS.size() * ARMOR_RATIOS.size(), false, Image.FORMAT_RGBA8)
	var rows: Array[Dictionary] = []
	var row_index := 0
	for facing: int in FACINGS:
		for armor_ratio: float in ARMOR_RATIOS:
			var holder := Node2D.new()
			holder.position = Vector2(CELL_SIZE.x * 0.5, CELL_SIZE.y - 25)
			holder.scale = Vector2.ONE * 3.0
			stage.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			var cache_key := RigLibrary.CHARACTER_PATH % "rin"
			var had_cached := RigLibrary._json_cache.has(cache_key)
			var old_cached: Dictionary = RigLibrary._json_cache.get(cache_key, {})
			RigLibrary._json_cache[cache_key] = fixture
			var setup_ok := rig.setup("rin")
			if had_cached:
				RigLibrary._json_cache[cache_key] = old_cached
			else:
				RigLibrary._json_cache.erase(cache_key)
			_check(setup_ok, "the production CharacterRig.setup path accepts the explicitly synthetic same-source fixture")
			if not setup_ok:
				holder.queue_free()
				get_tree().quit(1)
				return
			_check(rig._pose_slots.has(&"armor_pelvis") and rig._pose_slots.has(&"pelvis_dmg") and rig._pose_slots.has(&"foot_front"), "fixture includes intact armor, same-bone damage underlayer, and glow boot slots")
			if str(fixture.get("capture_geometry_mode", "")).begins_with("rigid control"):
				_check(not CharacterRig.force_rigid_limbs, "rigid control uses its fixture limb_bend setting without changing the global force_rigid_limbs switch")
				for rigid_slot: StringName in [&"armor_pelvis", &"pelvis_dmg", &"foot_front"]:
					_check(rig._pose_slots[rigid_slot]["base"] is Sprite2D, "rigid control base slot '%s' follows fixture limb_bend=false through production setup" % rigid_slot)
			var foot_alternate := rig._pose_slots[&"foot_front"]["alternatives"][POSE_KEY] as Sprite2D
			var foot_canvas := foot_alternate.texture as CanvasTexture
			_check(foot_canvas != null and foot_canvas.normal_texture != null and rig._part_has_glow(foot_alternate), "the boot alternative preserves the real Rin diffuse, normal and glow channels")

			rig.facing = facing
			rig.set_armor_ratio(armor_ratio, false)
			var input := RigInput.new()
			input.facing = facing
			input.aim_dir = Vector2(facing, 0.0)
			input.on_floor = true
			input.velocity = Vector2.ZERO
			for frame in 90:
				rig.animate(1.0 / 60.0, input)
			var bones_before := _bone_snapshot(rig)
			var base_visible := _visible_pose_counts(rig)
			_check(_counts_at_most_one(base_visible), "base row has at most one visible node for each pose logical slot (%s, armor %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			var base_image := await _capture_cell(viewport)
			_check(rig.set_pose_parts(POSE_KEY), "the synthetic pose selector succeeds (%s, armor %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			var selected_visible := _visible_pose_counts(rig)
			_check(_counts_at_most_one(selected_visible), "selected row has at most one visible node for each logical slot (%s, armor %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			var pose_image := await _capture_cell(viewport)
			_check(rig.set_pose_parts(&""), "the synthetic pose selection clears (%s, armor %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			var cleared_visible := _visible_pose_counts(rig)
			_check(_counts_at_most_one(cleared_visible), "cleared row has at most one visible node for each logical slot (%s, armor %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			var cleared_image := await _capture_cell(viewport)
			var bones_after := _bone_snapshot(rig)
			_check(bones_before == bones_after, "selection and clear preserve all 20 canonical bone identities, parents, rest and settled transforms (%s, armor %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			_check(_images_equal(base_image, cleared_image), "base and cleared actual rendered RGBA are byte-identical at identical armor/facing (%s, %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			_check(_images_equal(base_image, pose_image), "same-source selected alternatives render identically to base at identical armor/facing (%s, %.1f)" % ["R" if facing == 1 else "L", armor_ratio])
			var destination_y := row_index * CELL_SIZE.y
			composite.blit_rect(base_image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(0, destination_y))
			composite.blit_rect(pose_image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(CELL_SIZE.x, destination_y))
			composite.blit_rect(cleared_image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(CELL_SIZE.x * 2, destination_y))
			rows.append({"row": row_index, "facing": facing, "armor_ratio": armor_ratio,
				"states": {"base": base_visible, "pose": selected_visible, "cleared": cleared_visible}})
			row_index += 1
			holder.queue_free()
			await get_tree().process_frame

	var image_path := output_dir.path_join("attachment-plumbing-forward-plus.png")
	var image_error := composite.save_png(image_path)
	_check(image_error == OK, "the actual rendered viewport cells save as PNG")
	var report := {
		"fixture_id": str(fixture.get("pose_attachment_fixture_id", FIXTURE_ID)),
		"fixture_geometry": str(fixture.get("capture_geometry_mode", "production mesh baseline")),
		"fixture_limb_bend": bool(fixture.get("limb_bend", true)),
		"character_rig_force_rigid_limbs": CharacterRig.force_rigid_limbs,
		"fixture_is_synthetic": true,
		"uses_existing_rin_diffuse_normal_glow_sources": true,
		"canonical_pose_art_acceptance": false,
		"native_forward_plus_capture": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info(),
		"image": image_path,
		"viewport_cell_size": [CELL_SIZE.x, CELL_SIZE.y],
		"composite_size": [composite.get_width(), composite.get_height()],
		"hdr_2d": true,
		"lighting": "LightKit.create_environment + LightKit.create_point_light",
		"states_columns": ["base", "pose", "cleared"],
		"settled_animator_steps_per_row": 90,
		"animator_advanced_between_columns": false,
		"source_texture_files": {
			"pelvis": RigLibrary.character_dir("rin").path_join(str((fixture["textures"]["pelvis"] as Dictionary)["file"])),
			"pelvis_dmg": RigLibrary.character_dir("rin").path_join(str((fixture["textures"]["pelvis_dmg"] as Dictionary)["file"])),
			"foot": RigLibrary.character_dir("rin").path_join(str((fixture["textures"]["foot"] as Dictionary)["file"])),
		},
		"row_order": rows,
		"checks": _checks,
		"failures": _failures,
		"notes": [
			"The pose set uses the same existing Rin textures, pivots, offsets, rotations, scale, z and bones as the base parts.",
			"This verifies attachment plumbing and deterministic state restoration only; it does not validate anatomy, authored pose pixels, grip, or gameplay.",
			"No weapon is attached in this plumbing capture.",
		],
	}
	var report_path := output_dir.path_join("attachment-plumbing-forward-plus.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_check(false, "the capture report can be written")
	else:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("NE222_ATTACHMENT_CAPTURE renderer=%s driver=%s adapter=%s checks=%d failures=%d png=%s json=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), _checks, _failures.size(), image_path, report_path])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _same_source_fixture(source_skin: Dictionary) -> Dictionary:
	var fixture := source_skin.duplicate(true)
	fixture["pose_attachment_fixture_id"] = FIXTURE_ID
	fixture["capture_geometry_mode"] = "production mesh baseline"
	fixture["armor_debris"] = false
	fixture["pose_parts"] = {
		POSE_KEY: {
			"texture_scale": float(fixture.get("texture_scale", 0.25)),
			"parts": [
				{"slot": "armor_pelvis", "texture": "pelvis", "bone": "hip"},
				{"slot": "pelvis_dmg", "texture": "pelvis_dmg", "bone": "hip"},
				{"slot": "foot_front", "texture": "foot", "bone": "foot_front"},
			],
		}
	}
	return fixture


func _capture_cell(viewport: SubViewport) -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return CAPTURE.image(viewport)


func _bone_snapshot(rig: CharacterRig) -> Dictionary:
	var snapshot: Dictionary = {}
	for bone_name in rig.bone_order():
		var bone := rig.bone(bone_name)
		snapshot[bone_name] = [bone.get_instance_id(), bone.get_parent().get_instance_id(), bone.rest,
			bone.position, bone.rotation, bone.scale]
	return snapshot


func _visible_pose_counts(rig: CharacterRig) -> Dictionary:
	var counts: Dictionary = {}
	for slot_name: StringName in rig._pose_slots:
		var slot: Dictionary = rig._pose_slots[slot_name]
		var base_part: CanvasItem = slot["base"]
		var count := 1 if base_part.visible else 0
		for alternative: CanvasItem in (slot["alternatives"] as Dictionary).values():
			if alternative.visible:
				count += 1
		counts[str(slot_name)] = count
	return counts


func _counts_at_most_one(counts: Dictionary) -> bool:
	for count: int in counts.values():
		if count > 1:
			return false
	return true


func _images_equal(first: Image, second: Image) -> bool:
	if first.get_size() != second.get_size() or first.get_format() != second.get_format():
		return false
	for y in first.get_height():
		for x in first.get_width():
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: " + message)
