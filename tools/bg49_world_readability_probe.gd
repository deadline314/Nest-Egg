extends "res://tools/harbor_readability_probe.gd"
## Original sixteen time samples at each of the eighteen campaign positions.
## Keep prompts disabled throughout the run: hiding once is undone by their owner.

var _prompts49 := {}
var _scan49 := true
var _roi_samples49: Array[Dictionary] = []
var _roi_failed49 := false
var _presentation49: Dictionary = {}
const Drawing49 := preload("res://tools/held_lighting_state.gd")
const HeldProbe49 := preload("res://tools/bg55_enemy_readability_probe.gd")


func _ready() -> void:
	super._ready()
	Settings.set_brightness(0.5)
	for node in get_children():
		if node is CanvasLayer:
			for child in node.get_children():
				if child is Label:
					child.text = "BG49 / PURE WORLD / ORIGINAL 18 POINTS + 16 TIME SAMPLES / SCRIPTED AIM"


func _process(delta: float) -> void:
	super._process(delta)
	# Pin the sampler's documented rightward aim against unrelated OS mouse
	# events, using the existing scripted-input owner, not a hardware claim.
	for player in get_tree().get_nodes_in_group(&"player"):
		AimInput.set_virtual_gamepad(player, true)
	if not _scan49:
		return
	for node in find_children("*", "", true, false):
		if node is WorldPrompt:
			_prompts49[str(node.get_path())] = true
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
	_scan49 = false


func _check_level(path: String, spots: Array, enemy_path := "res://data/enemies/grunt.tres") -> void:
	_scan49 = true
	await super._check_level(path, spots, enemy_path)


func _prepare_probe_level(data: LevelData) -> void:
	# The inherited fixture already suppresses entry presentations. Dawn also
	# auto-completes after entry, creating a blocking ending card; suppress
	# that flow only on this copied fixture so normal gravity can settle.
	_presentation49[str(data.id)] = {"original_complete_after_intro": data.complete_after_intro,
		"fixture_complete_after_intro": false, "scope": "copied LevelData presentation only; resources/lighting/gameplay unchanged"}
	data.complete_after_intro = false


func _roi49(probe: ContrastProbe, rect: Rect2i, stem: String) -> Dictionary:
	var image := probe._image.get_region(rect)
	var bytes := image.get_data()
	var relative := "roi/" + stem + ".bin"
	var error := DirAccess.make_dir_recursive_absolute(_out_dir.path_join("roi"))
	var file := FileAccess.open(_out_dir.path_join(relative), FileAccess.WRITE) if error == OK else null
	if file == null:
		_roi_failed49 = true
		printerr("[BG49World] Cannot preserve native float ROI: " + relative)
		return {}
	file.store_buffer(bytes)
	file.close()
	return {"raw": relative, "sha256": HeldProbe49.bytes_sha(bytes), "format": image.get_format(),
		"source_rect": HeldProbe49.rect_values(rect), "width": image.get_width(), "height": image.get_height()}


func _record_probe_sample(probe: ContrastProbe, level: Level, spot: Array, sample: int, foe: Enemy, sums: Array[float]) -> void:
	var player := level.player
	var player_body := probe._body_box(player.global_position, true)
	var body := probe._screen_rect(player_body)
	var outer := probe._screen_rect(player_body.grow(ContrastProbe.RING))
	var edge := probe._screen_rect(Rect2(player.global_position + Vector2(-24, 0), Vector2(48, 3)))
	var below := probe._screen_rect(Rect2(player.global_position + Vector2(-24, 8), Vector2(48, 6)))
	var stem := "%s-%d-%02d" % [level.data.id, int(spot[1]), sample]
	# Player outer includes the body and both ground strips. Store their exact
	# float pixels once, never a screenshot-encoded or re-quantized input.
	var record := {"level": str(level.data.id), "spot": str(spot[0]), "column": int(spot[1]), "sample": sample,
		"physics_frame": Engine.get_physics_frames(), "microseconds": Time.get_ticks_usec(),
		"source_size": [probe._image.get_width(), probe._image.get_height()], "density": probe._scale,
		"canvas_transform_values": Drawing49.transform_values(probe._to_screen),
		"viewport_final_transform_values": Drawing49.transform_values(get_viewport().get_final_transform()),
		"player": {"feet": [player.global_position.x, player.global_position.y], "on_floor": player.is_on_floor(),
			"space_valid": PhysicsServer2D.body_get_space(player.get_rid()).is_valid(), "support": HeldProbe49.ground_support(player),
			"facing": player.facing, "aim": [player.aim_dir.x, player.aim_dir.y],
			"body": HeldProbe49.rect_values(body), "outer": HeldProbe49.rect_values(outer),
			"edge": HeldProbe49.rect_values(edge), "below": HeldProbe49.rect_values(below),
			"roi": _roi49(probe, outer, stem + "-player")},
		"enemy": null, "cumulative_original": {"player": sums[0], "edge": sums[1], "enemy": sums[2]}}
	if is_instance_valid(foe):
		var enemy_box := probe._body_box(foe.global_position, false)
		var enemy_outer := probe._screen_rect(enemy_box.grow(ContrastProbe.RING))
		record["enemy"] = {"feet": [foe.global_position.x, foe.global_position.y], "on_floor": foe.is_on_floor(),
			"space_valid": PhysicsServer2D.body_get_space(foe.get_rid()).is_valid(), "support": HeldProbe49.ground_support(foe),
			"body": HeldProbe49.rect_values(probe._screen_rect(enemy_box)), "outer": HeldProbe49.rect_values(enemy_outer),
			"roi": _roi49(probe, enemy_outer, stem + "-enemy")}
	var visible_prompts: Array[String] = []
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt and node.is_visible_in_tree(): visible_prompts.append(str(node.get_path()))
	record["visible_world_prompts"] = visible_prompts
	if not visible_prompts.is_empty(): _roi_failed49 = true
	_roi_samples49.append(record)


func _run() -> void:
	await super._run()
	if _out_dir.is_empty():
		return
	var path := _out_dir.path_join("readability-report.json")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var roi_path := _out_dir.path_join("roi-samples.json")
	var roi_file := FileAccess.open(roi_path, FileAccess.WRITE)
	if roi_file == null or _roi_failed49:
		printerr("[BG49World] Native ROI capture failed or world prompt was visible")
		get_tree().quit(1)
	if roi_file != null:
		roi_file.store_string(JSON.stringify({"kind": "exact original float pixel ROIs; not full-frame float; original whole PNG remains separate",
			"samples_per_spot": SAMPLES, "sample_interval": SAMPLE_INTERVAL, "records": _roi_samples49}, "\t"))
		roi_file.close()
	report["native_float_rois"] = {"file": "roi-samples.json", "samples": _roi_samples49.size(), "failed": _roi_failed49,
		"same_original_probe_input": true, "default_observer_is_noop": true}
	report["fixture_presentation"] = _presentation49
	# The parent has now restored settings, which can resize the window. The
	# saved PNG is authoritative for each capture, not this later viewport.
	for result: Dictionary in report["results"]:
		var saved := Image.load_from_file(_out_dir.path_join(str(result["screenshot"])))
		if saved == null or saved.is_empty():
			push_error("[BG49World] Missing completed PNG: " + str(result["screenshot"]))
			get_tree().quit(2)
			return
		result["capture_size"] = [saved.get_width(), saved.get_height()]
	var environment := get_viewport().find_world_3d().environment
	var bloom_valid: bool = environment != null and environment.glow_enabled
	if not bloom_valid:
		printerr("[BG49World] Main-equivalent HDR bloom is not active")
		get_tree().quit(1)
	report["pure_world"] = {"world_prompt_process_disabled": true, "distinct_prompt_paths": _prompts49.keys(),
		"bloom_active": bloom_valid,
		"final_viewport_texture_size_after_settings_restore": [get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()],
		"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"hdr_2d": get_viewport().use_hdr_2d, "source_sha256": FileAccess.get_sha256("res://tools/bg49_world_readability_probe.gd"),
		"original_sampling_sha256": FileAccess.get_sha256("res://tools/readability_check.gd"),
		"original_points_sha256": FileAccess.get_sha256("res://tools/ch1_readability_check.gd"),
		"viewport_capture_sha256": FileAccess.get_sha256("res://tools/viewport_capture.gd"),
		"contrast_probe_sha256": FileAccess.get_sha256("res://tools/contrast_probe.gd")}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[BG49World] Cannot preserve final metadata: " + path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
