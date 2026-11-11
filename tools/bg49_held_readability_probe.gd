extends "res://tools/bg55_enemy_readability_probe.gd"
## Original eighteen campaign points, pure-world held A/A/B/A comparisons.
## The reference restores freight only at the authored harbor-approach point;
## other points retain their exact authored profile, rather than changing zones.

const Campaign49 := preload("res://tools/ch1_readability_check.gd")
var _spot49 := ""
var _only49 := ""
var _reference49 := "res://data/lighting/freight.tres"
var _has_enemy49 := false
var _standing49 := {}
var _head_masks49: Dictionary = {}
var _blank_head49 := false


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--validate-only"):
		var base := load("res://tools/readability_check.gd").new() as Node
		var probe := ContrastProbe.new()
		probe._image = Image.create(4, 4, false, Image.FORMAT_RGBF)
		probe._image.fill(Color(0.25, 0.5, 2.0))
		var bytes := probe._image.get_data()
		var sums: Array[float] = [0.1, 0.2, 0.3]
		var data := LevelData.new()
		data.complete_after_intro = true
		data.intro_scene = &"original-intro"
		base._prepare_probe_level(data)
		base._record_probe_sample(probe, null, [], 0, null, sums)
		var valid: bool = bytes == probe._image.get_data() and sums == [0.1, 0.2, 0.3]
		valid = valid and data.complete_after_intro and data.intro_scene == &"original-intro"
		for path in ["res://tools/bg49_world_readability_probe.gd", "res://tools/bg49_held_pool_probe.gd"]:
			valid = valid and load(path) != null
		base.free()
		print("BG49_DEFAULT_HOOK checks=4 failures=", 0 if valid else 1, " (no native alpha validation)")
		get_tree().quit(0 if valid else 1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument == "--blank-head-mask":
			_blank_head49 = true
		if argument.begins_with("--spots="):
			_only49 = argument.trim_prefix("--spots=")
	super._ready()
	_walk_player = true
	for node in get_children():
		if node is CanvasLayer:
			for child in node.get_children():
				if child is Label:
					child.text = "BG49 / ORIGINAL CAMPAIGN POINTS / HELD WORLD / SCRIPTED AIM"


func _capture55(level: Level, world: Rect2, label: String) -> Dictionary:
	# The original campaign checker includes its arranged foe at the viewport
	# edge. Cancel SceneTour's 24px grid-selection margin, keeping its original
	# body/ring geometry and clipping unchanged.
	var record := await super._capture55(level, world.grow(24.0), label)
	var probe := ContrastProbe.capture(get_viewport())
	if bytes_sha(probe._image.get_data()) != record.raw_sha256:
		printerr("[BG49] Capture changed before player/exposure observation")
		_contrast_failures += 1
	var player := level.player
	var parts := probe.character_parts(player.global_position, true)
	var body := probe._body_box(player.global_position, true)
	var edge := Rect2(player.global_position + Vector2(-24, 0), Vector2(48, 3))
	var below := Rect2(player.global_position + Vector2(-24, 8), Vector2(48, 6))
	record["player"] = {"feet": [player.global_position.x, player.global_position.y], "parts": parts, "contrast": maxf(parts.bright, parts.dark),
		"screen_rect": rect_values(probe._screen_rect(body)),
		"outer_screen_rect": rect_values(probe._screen_rect(body.grow(ContrastProbe.RING))),
		"edge_screen_rect": rect_values(probe._screen_rect(edge)),
		"below_screen_rect": rect_values(probe._screen_rect(below)),
		"edge_contrast": probe.edge_contrast(player.global_position)}
	var exposure: Array[Dictionary] = []
	for enemy in record.enemies:
		var actor := instance_from_id(int(enemy.instance)) as Enemy
		var bounds := probe._body_box(actor.global_position, false)
		if actor.rig != null:
			bounds = bounds.merge(actor.rig.visual_bounds())
			var weapon := actor.rig._weapon_sprite
			if weapon != null and weapon.texture != null and weapon.is_visible_in_tree():
				bounds = bounds.merge(weapon.global_transform * weapon.get_rect())
		var rect := probe._screen_rect(bounds.grow(1.0))
		var white := 0
		var peak := 0.0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var color := probe._image.get_pixel(x, y)
				peak = maxf(peak, maxf(color.r, maxf(color.g, color.b)))
				if color.r > 0.92 and color.g > 0.92 and color.b > 0.92:
					white += 1
		exposure.append({"instance": enemy.instance, "id": enemy.id, "screen_rect": rect_values(rect),
			"world_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
			"white_pixels_including_background": white, "peak": peak,
			"enemy_white_ratio": 0.0 if white == 0 and rect.has_area() else null,
			"coverage": "merged legacy body, actual rig and weapon; zero proves zero; nonzero has no enemy-only denominator"})
		if _spot49 == "碼頭入口":
			var mask := await _opaque_head49(actor, probe, rect, level)
			var count: int = mask.get("opaque_head_pixels", 0)
			var valid: bool = count > 0 and int(mask.get("outside_rectangle", -1)) == 0 and bool(mask.get("source_held", false))
			exposure[-1]["head_mask"] = mask
			exposure[-1]["bound_valid"] = valid
			exposure[-1]["enemy_white_ratio_upper_bound"] = float(white) / count if valid else null
			exposure[-1]["enemy_only_ratio"] = null
			if bytes_sha(get_viewport().get_texture().get_image().get_data()) != record.raw_sha256:
				printerr("[BG49] Scene changed while observing held alpha mask")
				_contrast_failures += 1
	record["exposure"] = exposure
	var prompts: Array[String] = []
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt and node.is_visible_in_tree():
			prompts.append(str(node.get_path()))
	record["visible_world_prompts"] = prompts
	record["standing"] = _standing49
	return record


func _opaque_head49(enemy: Enemy, probe: ContrastProbe, rect: Rect2i, level: Level) -> Dictionary:
	var head: Node2D
	for part: CanvasItem in enemy.rig._parts:
		if part.name == &"head" and part.is_visible_in_tree():
			if head != null: return {"error": "ambiguous visible head"}
			head = part as Node2D
		# The full-body bound must include all actual vertices. This fixed skin
		# has no shader sway; refuse unsupported padding/deformation silently
		# extending beyond visual_bounds, rather than guessing an upper bound.
		for uniform in [&"sway_a_shape", &"sway_b_shape"]:
			var shape: Variant = part.get_instance_shader_parameter(uniform)
			if shape is Vector2 and shape.x > 0.0:
				return {"error": "active shader sway needs expanded geometry proof"}
	if head == null or not (head is Sprite2D or head is Polygon2D):
		return {"error": "no supported visible head drawable"}
	if head is Polygon2D and head.get_bone_count() > 0:
		return {"error": "GPU-skinned head requires a full skeleton clone"}
	if not is_equal_approx(head.self_modulate.a, 1.0):
		return {"error": "head alpha is not opaque"}
	var head_material := head.material as ShaderMaterial
	if head_material != null and head_material.shader != CharacterRig.LIGHT_SHADER:
		return {"error": "unsupported head shader alpha/deformation"}
	var ancestor: Node = head
	while ancestor != null:
		if ancestor is CanvasItem and (not is_equal_approx(ancestor.modulate.a, 1.0) or ancestor.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED):
			return {"error": "ancestor alpha or clipping needs a compositing proof"}
		ancestor = ancestor.get_parent()
	var before := head.global_transform
	var view := SubViewport.new()
	view.size = probe._image.get_size()
	view.world_2d = World2D.new()
	view.world_3d = World3D.new()
	view.transparent_bg = true
	view.use_hdr_2d = true
	view.disable_3d = true
	view.canvas_item_default_texture_filter = get_viewport().canvas_item_default_texture_filter
	view.canvas_item_default_texture_repeat = get_viewport().canvas_item_default_texture_repeat
	view.msaa_2d = get_viewport().msaa_2d
	view.snap_2d_transforms_to_pixel = get_viewport().snap_2d_transforms_to_pixel
	view.snap_2d_vertices_to_pixel = get_viewport().snap_2d_vertices_to_pixel
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var combined := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	view.canvas_transform = combined
	var copy := head.duplicate(0) as Node2D
	for child in copy.get_children():
		copy.remove_child(child)
		child.free()
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(copy)
	copy.global_transform = before
	# Preserve inherited sampling modes when the actual parent supplied one.
	var source_parent := head.get_parent()
	while source_parent is CanvasItem:
		if copy.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and source_parent.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			copy.texture_filter = source_parent.texture_filter
		if copy.texture_repeat == CanvasItem.TEXTURE_REPEAT_PARENT_NODE and source_parent.texture_repeat != CanvasItem.TEXTURE_REPEAT_PARENT_NODE:
			copy.texture_repeat = source_parent.texture_repeat
		source_parent = source_parent.get_parent()
	for uniform in [&"sway_a", &"sway_a_shape", &"sway_b", &"sway_b_shape", &"sway_padding", &"sway_bounds"]:
		var value: Variant = head.get_instance_shader_parameter(uniform)
		if value != null: copy.set_instance_shader_parameter(uniform, value)
	if _blank_head49: copy.visible = false
	for frame in 2: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var mask := view.get_texture().get_image()
	if mask.get_format() not in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF]:
		view.queue_free()
		return {"error": "native head alpha requires an unquantized RGBA float target"}
	var count := 0
	var outside := 0
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).a >= 0.999:
				if rect.has_point(Vector2i(x, y)): count += 1
				else: outside += 1
	var raw := mask.get_data()
	var sha := bytes_sha(raw)
	var folder := _out.path_join(str(level.data.id))
	if not _head_masks49.has(sha):
		var stem := "bg49-head-" + sha.substr(0, 16)
		var file := FileAccess.open(folder.path_join(stem + ".bin"), FileAccess.WRITE)
		if file == null:
			view.queue_free()
			return {"error": "cannot preserve actual head alpha bytes"}
		file.store_buffer(raw)
		file.close()
		var encoded := Capture55.encode(mask, true)
		if encoded.save_png(folder.path_join(stem + ".png")) != OK or encoded.get_region(rect).save_png(folder.path_join(stem + "-crop.png")) != OK:
			view.queue_free()
			return {"error": "cannot preserve head alpha review PNG"}
		_head_masks49[sha] = {"raw": stem + ".bin", "png": stem + ".png", "crop": stem + "-crop.png"}
	var source_held: bool = head.global_transform == before and copy.global_transform == before
	view.queue_free()
	return {"opaque_head_pixels": count, "outside_rectangle": outside, "source_held": source_held,
		"alpha_threshold": 0.999, "format": mask.get_format(), "width": mask.get_width(), "height": mask.get_height(),
		"files": _head_masks49[sha], "raw_sha256": sha, "source_path": str(head.get_path()),
		"head_transform": HeldLighting55.transform_values(before), "viewport_transform": HeldLighting55.transform_values(combined),
		"viewport_sampling": {"filter": get_viewport().canvas_item_default_texture_filter,
			"repeat": get_viewport().canvas_item_default_texture_repeat, "msaa": get_viewport().msaa_2d,
			"snap_transforms": get_viewport().snap_2d_transforms_to_pixel, "snap_vertices": get_viewport().snap_2d_vertices_to_pixel},
		"blank_negative_control": _blank_head49, "body_shader_sway_disabled": true,
		"scope": "original stationary dock sweeper only; opaque head requires native visual confirmation of no foreground occlusion; W/H is conservative, not exact"}


func _measure(level: Level, world: Rect2) -> Dictionary:
	_reference55 = _reference49 if _spot49 == "碼頭入口" else ""
	var result := await super._measure(level, world)
	var records: Array = result.bg55.records
	if _spot49 != "碼頭入口":
		# The parent elides a no-op B/A pair. Keep the same five-stage
		# protocol here even where both profiles are intentionally identical.
		records[-1]["label"] = "product"
		var identical := level._lighting.current.duplicate() as LightingProfile
		await _apply55(level, identical)
		records.append(await _capture55(level, world, "restore-product"))
		await _apply55(level, identical)
		records.append(await _capture55(level, world, "authored-final"))
		for observation: Dictionary in records:
			result.bg55.controls_valid = bool(result.bg55.controls_valid) and observation.held == records[0].held and observation.raw_sha256 == records[0].raw_sha256
	var product: Dictionary = records[-1]
	if _has_enemy49 and (product.enemies.is_empty() or product.exposure.is_empty()):
		printerr("[BG49] Original arranged enemy is absent from the measurements")
		_contrast_failures += 1
	if product.player.contrast < ContrastProbe.MIN_PLAYER_CONTRAST or product.player.edge_contrast < ContrastProbe.MIN_EDGE_CONTRAST:
		printerr("[BG49] Player/edge below unchanged threshold at " + _spot49)
		_contrast_failures += 1
	for record in records:
		if not record.visible_world_prompts.is_empty():
			printerr("[BG49] World prompt contaminates " + _spot49)
			_contrast_failures += 1
		if _spot49 != "碼頭入口" and record.raw_sha256 != records[0].raw_sha256:
			printerr("[BG49] Unchanged point differs in held counterfactual: " + _spot49)
			_contrast_failures += 1
	if _spot49 == "碼頭入口":
		for exposure in product.exposure:
			if not bool(exposure.get("bound_valid", false)) or float(exposure.get("enemy_white_ratio_upper_bound") if exposure.get("enemy_white_ratio_upper_bound") != null else 1.0) > 0.02:
				printerr("[BG49] Invalid or above-2% opaque-head upper bound")
				_contrast_failures += 1
	result["bg49"] = {"spot": _spot49, "kind": "same current geometry; original freight profile restored only at harbor; not historical checkout",
		"reference_profile": _reference55, "reference_sha256": FileAccess.get_sha256(_reference55) if not _reference55.is_empty() else "",
		"source_sha256": FileAccess.get_sha256("res://tools/bg49_held_readability_probe.gd")}
	return result


func _tour(level_id: String) -> bool:
	if not Campaign49.PROBES.has(level_id):
		printerr("[BG49] No original campaign points for " + level_id)
		return false
	var path := "res://data/levels/%s.tres" % level_id
	var source := load(path) as LevelData
	if source == null or DirAccess.make_dir_recursive_absolute(_out.path_join(level_id)) != OK:
		return false
	var failures_before := _contrast_failures
	var results: Array[Dictionary] = []
	for spot: Array in Campaign49.PROBES[level_id]:
		if not _only49.is_empty() and not _only49.split(",").has(str(spot[0])):
			continue
		_spot49 = str(spot[0])
		GameState.start_new_run(GameState.difficulties[1])
		var data := source.duplicate() as LevelData
		data.intro_scene = &""
		data.show_chapter_card = false
		var original_auto_ending := data.complete_after_intro
		data.complete_after_intro = false
		var level := Level.new()
		level.configure(data)
		add_child(level)
		level._arena_triggered = true
		for node in level.find_children("*", "", true, false):
			if node is EncounterZone:
				node.restore_state(true)
			elif node is WorldPrompt:
				node.visible = false
				node.process_mode = Node.PROCESS_MODE_DISABLED
			elif node is ChapterCard:
				node.queue_free()
		for node in get_tree().get_nodes_in_group(&"enemies"):
			node.queue_free()
		level.hud.visible = false
		level.player.health.setup(999, 0.0)
		AimInput.set_virtual_gamepad(level.player, true)
		var tile := int(spot[1])
		var floor_y := float(spot[2]) * level._layout.tile_size
		var expected := Vector2(tile * level._layout.tile_size + 8.0, floor_y)
		level.player.global_position = expected - Vector2(0, 2)
		level.player.velocity = Vector2.ZERO
		var foe: Enemy
		var foe_expected := Vector2((tile + 6) * level._layout.tile_size + 8.0, floor_y)
		if level_id in ["ch1_street", "ch1_warehouse", "ch1_vault"]:
			foe = level._create_enemy(load("res://data/enemies/sweeper.tres"))
			foe.data = foe.data.duplicate()
			foe.data.detect_range = 0.0
			foe.data.attack_range = 0.0
			foe.data.move_speed = 0.0
			foe.position = foe_expected - Vector2(0, 2)
			foe.facing = -1
			level._entities.add_child(foe)
			foe.health.setup(999, 0.0)
		_has_enemy49 = foe != null
		# Make the arranged foe visible before waiting: an off-screen actor's
		# activation culling otherwise prevents gravity/ground contact updates.
		var camera := get_viewport().get_camera_2d() as LevelCamera
		camera.snap_to_target()
		camera.force_update_scroll()
		var landed := false
		var ground_ticks := 0
		for tick in 120:
			await get_tree().physics_frame
			ground_ticks += 1
			if level.player.is_on_floor() and (foe == null or foe.is_on_floor()):
				landed = true
				break
		await _settle(24)
		camera.set_physics_process(false)
		camera.snap_to_target()
		camera.force_update_scroll()
		level._lighting.snap()
		_sync55(level)
		await _settle(4)
		var valid := landed and level.player.is_on_floor() and level.player.global_position.distance_to(expected) <= 0.1
		if foe != null:
			valid = valid and foe.is_on_floor() and foe.global_position.distance_to(foe_expected) <= 0.1
		_standing49 = {"player_on_floor": level.player.is_on_floor(), "enemy_on_floor": foe.is_on_floor() if foe != null else null,
			"player_gap": level.player.global_position.y - expected.y, "enemy_gap": foe.global_position.y - foe_expected.y if foe != null else null,
			"physics_ticks": ground_ticks, "valid": valid, "original_complete_after_intro": original_auto_ending,
			"fixture_complete_after_intro": false}
		_contact55 = ground_support(level.player)
		_contact55["kind"] = "natural live move_and_slide before hold; independent support ray after hold"
		_contact55["on_floor"] = level.player.is_on_floor()
		_contact55["layout_floor"] = floor_y
		_contact55["valid"] = valid and bool(_contact55.get("found", false)) and absf(float(_contact55.get("gap", INF))) <= 0.1
		if not _contact55.valid:
			_contrast_failures += 1
		if not valid:
			printerr("[BG49] Actors not on original sampling floors: " + _spot49)
			_contrast_failures += 1
		var transform := get_viewport().get_canvas_transform().affine_inverse()
		var world := transform * get_viewport().get_visible_rect()
		var result := await _measure(level, world)
		result["sampling_valid"] = valid
		result["expected_player_feet"] = str(expected)
		result["actual_player_feet"] = str(level.player.global_position)
		results.append(result)
		print("BG49_POINT ", level_id, " / ", _spot49, " / valid=", valid)
		Engine.time_scale = _time_scale55
		level.queue_free()
		for frame in 6:
			await get_tree().process_frame
		_held55 = null
	var writer := FileAccess.open(_out.path_join(level_id).path_join("bg49-held.json"), FileAccess.WRITE)
	if writer == null:
		return false
	writer.store_string(JSON.stringify({"level": level_id, "quality": Settings.get_light_quality(), "brightness": Settings.get_brightness(),
		"engine": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "hdr": get_viewport().use_hdr_2d,
		"level_sha256": FileAccess.get_sha256(path), "results": results}, "\t"))
	if results.is_empty():
		printerr("[BG49] No original sampling point matches " + _only49)
		return false
	return failures_before == _contrast_failures
