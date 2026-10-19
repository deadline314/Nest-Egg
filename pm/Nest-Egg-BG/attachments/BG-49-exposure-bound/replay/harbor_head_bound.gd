extends "res://tools/harbor_readability_probe.gd"
## Fixed unoccluded harbor fixture only. A rendered opaque head subset supplies
## a lower bound on visible enemy pixels; full body rectangle white is an upper
## bound on its white pixels. Their quotient is conservative, not an exact ratio.

var _exposure_done := false

func _observe_exposure(reference: WeakRef, level_id: String, enemy_path: String) -> void:
	for sample in 3:
		await get_tree().create_timer(1.1).timeout
		var enemy := reference.get_ref() as Enemy
		if not is_instance_valid(enemy):
			return
		await RenderingServer.frame_post_draw
		var probe := ContrastProbe.capture(get_viewport())
		var world_bounds := probe._body_box(enemy.global_position, false)
		world_bounds = world_bounds.merge(enemy.rig.visual_bounds())
		var weapon := enemy.rig._weapon_sprite
		if weapon != null and weapon.texture != null and weapon.is_visible_in_tree():
			world_bounds = world_bounds.merge(weapon.global_transform * weapon.get_rect())
		var rect := probe._screen_rect(world_bounds.grow(1.0))
		var white := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var color := probe._image.get_pixel(x, y)
				if color.r > 0.92 and color.g > 0.92 and color.b > 0.92:
					white += 1
		var before_mode := enemy.process_mode
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		var mask := await _opaque_head(enemy, probe, rect, sample)
		enemy.process_mode = before_mode
		var count: int = mask.get("opaque_head_pixels", 0)
		var upper: Variant = float(white) / count if count > 0 else null
		var valid: bool = count > 0 and int(mask.get("outside_rectangle", -1)) == 0 and bool(mask.get("source_held", false))
		if not valid or float(upper if upper != null else 1.0) > 0.02:
			_failed = true
		var raw_path := "sample%02d-hdr.bin" % sample
		var raw := FileAccess.open(_out_dir.path_join(raw_path), FileAccess.WRITE)
		raw.store_buffer(probe._image.get_data())
		raw.close()
		var display := probe._image.duplicate()
		display.convert(Image.FORMAT_RGBA8)
		display.linear_to_srgb()
		display.save_png(_out_dir.path_join("sample%02d-scene.png" % sample))
		display.get_region(rect).save_png(_out_dir.path_join("sample%02d-scene-crop.png" % sample))
		_exposure.append({"level": level_id, "enemy": enemy_path, "sample": sample, "quality": Settings.get_light_quality(),
			"screen_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"white_pixels_including_background": white, "mask": mask, "valid": valid,
			"enemy_white_ratio_upper_bound": upper, "enemy_only_ratio": null,
			"raw_hdr": {"file": raw_path, "format": probe._image.get_format(), "width": probe._image.get_width(), "height": probe._image.get_height()}})
		var file := FileAccess.open(_out_dir.path_join("enemy-exposure.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"encoding": "raw linear HDR", "fixture": "stationary, unoccluded sweeper at ch1_street harbor; rendered opaque head lower bound only", "observations": _exposure}, "  ") + "\n")
		file.close()
		print("HEAD_BOUND sample=", sample, " white=", white, " opaque_head=", count, " upper=", upper, " valid=", valid)

	_exposure_done = true

func _opaque_head(enemy: Enemy, probe: ContrastProbe, rect: Rect2i, sample: int) -> Dictionary:
	var head: Node2D
	for part: CanvasItem in enemy.rig._parts:
		if part.name == &"head" and part.is_visible_in_tree():
			head = part as Node2D
	if head == null or not (head is Sprite2D or head is Polygon2D):
		return {"error": "no visible head drawable"}
	if head is Polygon2D and head.get_bone_count() > 0:
		return {"error": "GPU-skinned heads require a full skeleton copy; refused"}
	# No script or gameplay clone: copy the actual already-deformed native drawable.
	var ancestor: Node = head
	while ancestor != null:
		if ancestor is CanvasItem and not is_equal_approx((ancestor as CanvasItem).modulate.a, 1.0):
			return {"error": "ancestor alpha requires an explicit compositing proof"}
		ancestor = ancestor.get_parent()
	var before := head.global_transform
	var viewport := SubViewport.new()
	viewport.size = probe._image.get_size()
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.canvas_transform = get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var copy := head.duplicate(0) as Node2D
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(copy)
	copy.global_transform = before
	if OS.get_cmdline_user_args().has("--blank-mask"):
		copy.visible = false
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	pixels.save_png(_out_dir.path_join("sample%02d-head-mask.png" % sample))
	pixels.get_region(rect).save_png(_out_dir.path_join("sample%02d-head-crop.png" % sample))
	var count := 0
	var outside := 0
	for y in pixels.get_height():
		for x in pixels.get_width():
			if pixels.get_pixel(x, y).a >= 0.999:
				if rect.has_point(Vector2i(x, y)):
					count += 1
				else:
					outside += 1
	var held := before == head.global_transform and copy.global_transform == before
	viewport.queue_free()
	return {"opaque_head_pixels": count, "outside_rectangle": outside, "source_held": held,
		"alpha_threshold": 0.999, "source_path": str(head.get_path()), "head_transform": [before.x.x, before.x.y, before.y.x, before.y.y, before.origin.x, before.origin.y]}


## Original stationary readability function, plus an explicit observer join before freeing its real Level.
func _check_level(path: String, spots: Array, enemy_path := "res://data/enemies/grunt.tres") -> void:
	GameState.start_new_run(GameState.difficulties[1])
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var data := (load(path) as LevelData).duplicate()
	data.intro_scene = &""
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	# The rendering lab measures stationary silhouettes, not a combat encounter.
	# Keep lighting events active, but prevent boss/wave spawns from pushing a probe.
	level._arena_triggered = true
	for node in level.find_children("*", "", true, false):
		if node is EncounterZone:
			node.restore_state(true)
	for i in 20:
		await get_tree().process_frame
	var player := level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_") or id.begins_with("c2_radio_"):
			Story._seen[StringName(id)] = true
	# Prompts are UI; their bright text must not inflate the body contrast.
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt:
			node.visible = false
	var layout: LevelLayout = level._layout
	print("== %s" % path.get_file())
	print("%-8s  %-8s  %-8s  %-8s" % ["區段", "玩家對比", "邊緣對比", "敵人對比"])
	for spot: Array in spots:
		if not _only_spots.is_empty() and not _only_spots.has(str(spot[0])):
			continue
		var tile: int = spot[1]
		if tile < 0 or tile * layout.tile_size >= layout.pixel_size().x:
			printerr("[readability_check] %s/%s: column %d is outside the map" % [path, spot[0], tile])
			_failed = true
			continue
		var y := probe_floor(layout, tile, str(spot[0])) - 2.0
		if spot.size() > 2:
			var row := int(spot[2])
			if not layout.cell(tile, row) in ["#", "="]:
				printerr("[readability_check] %s/%s: explicit floor %d/%d has no support" % [path, spot[0], tile, row])
				_failed = true
				continue
			y = float(row) * layout.tile_size - 2.0
		player.global_position = Vector2(tile * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		for node in get_tree().get_nodes_in_group(&"enemies"):
			node.queue_free()
		for i in 60:
			await get_tree().process_frame
		var camera := get_viewport().get_camera_2d() as LevelCamera
		if camera != null:
			camera.snap_to_target()
		var foe: Enemy = null
		var foe_tile := int(spot[3]) if spot.size() > 3 else tile + int(ENEMY_DISTANCE / layout.tile_size)
		var expected_foe_feet := Vector2(foe_tile * layout.tile_size + 8.0, y + 2.0)
		if not enemy_path.is_empty():
			# Legacy probes can put the enemy on a lower, adjacent roof.
			# Validate each actor against its own floor instead of assuming flat ground.
			if spot.size() <= 2:
				expected_foe_feet.y = probe_floor(layout, foe_tile, str(spot[0]))
			foe = _spawn_foe(level, expected_foe_feet - Vector2(0.0, 2.0), enemy_path)
		await get_tree().create_timer(1.2).timeout
		# 警報與霓虹會閃爍：連續取樣幾張取平均，量測才穩定。
		var player_contrast := 0.0
		var edge_contrast := 0.0
		var enemy_contrast := 0.0
		for sample in SAMPLES:
			var probe := ContrastProbe.capture(get_viewport())
			player_contrast += probe.character_contrast(player.global_position, true) / float(SAMPLES)
			edge_contrast += probe.edge_contrast(player.global_position) / float(SAMPLES)
			if is_instance_valid(foe):
				enemy_contrast += probe.character_contrast(foe.global_position) / float(SAMPLES)
			await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		if _detail:
			var last := ContrastProbe.capture(get_viewport())
			print("  ", spot[0], " 主角 ", _parts_text(last.character_parts(player.global_position, true)),
					("  敵人 " + _parts_text(last.character_parts(foe.global_position))) if is_instance_valid(foe) else "")
		var expected_feet := Vector2(tile * layout.tile_size + 8.0, y + 2.0)
		var standing := player.global_position.distance_to(expected_feet) <= 4.0
		if not enemy_path.is_empty():
			standing = standing and is_instance_valid(foe) and foe.global_position.distance_to(expected_foe_feet) <= 4.0
		if not standing:
			printerr("[readability_check] %s/%s: invalid floor sample; player=%s expected=%s enemy=%s expected=%s" % [path, spot[0], player.global_position, expected_feet, str(foe.global_position) if is_instance_valid(foe) else "missing", expected_foe_feet])
		var ok := standing and player_contrast >= ContrastProbe.MIN_PLAYER_CONTRAST and edge_contrast >= ContrastProbe.MIN_EDGE_CONTRAST and (enemy_path.is_empty() or (is_instance_valid(foe) and enemy_contrast >= ContrastProbe.MIN_ENEMY_CONTRAST))
		_failed = _failed or not ok
		var result_label := "取樣無效" if not standing else ("OK" if ok else "太暗（門檻 %.2f / %.2f / %.2f）" % [ContrastProbe.MIN_PLAYER_CONTRAST, ContrastProbe.MIN_EDGE_CONTRAST, ContrastProbe.MIN_ENEMY_CONTRAST])
		print("%-8s  %-8.2f  %-8.2f  %-8s  %s" % [spot[0], player_contrast, edge_contrast, "%.2f" % enemy_contrast if not enemy_path.is_empty() else "N/A", result_label])
		var shot := "%s-%s-%d.png" % [_capture_prefix, data.id, tile]
		if not _out_dir.is_empty():
			# Keep ContrastProbe's linear HDR samples; only encode review PNGs for display.
			var capture_error := preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(_out_dir.path_join(shot))
			if capture_error != OK:
				printerr("[readability_check] %s: %s" % [shot, error_string(capture_error)])
				_failed = true
		var materials: Array[String] = []
		if data.environment != null:
			for zone: EnvZone in data.environment.zones:
				materials.append(zone.material.resource_path)
		_results.append({"level": String(data.id), "path": path, "spot": spot[0], "column": tile, "sampling_valid": standing,
			"feet": [player.global_position.x, player.global_position.y], "enemy": enemy_path,
			"enemy_column": foe_tile, "expected_enemy_feet": [expected_foe_feet.x, expected_foe_feet.y],
			"enemy_feet": [foe.global_position.x, foe.global_position.y] if is_instance_valid(foe) else null,
			"player_contrast": player_contrast, "edge_contrast": edge_contrast,
			"enemy_contrast": enemy_contrast if not enemy_path.is_empty() else null, "passed": ok,
			"theme": data.environment.resource_path if data.environment != null else "",
			"materials": materials, "props": data.load_props(), "screenshot": shot})
	var mask_deadline := Time.get_ticks_msec() + 8000
	while not _exposure_done and Time.get_ticks_msec() < mask_deadline:
		await get_tree().process_frame
	if not _exposure_done or _exposure.size() != 3:
		_failed = true
		printerr("[HeadBound] exposure observer did not finish all three samples")
	remove_child(level)
	level.free()
	await get_tree().process_frame
