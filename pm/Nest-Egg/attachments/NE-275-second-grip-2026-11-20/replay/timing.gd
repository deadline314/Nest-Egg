extends "res://tools/melee_art_probe.gd"

const WARMUP_FRAMES := 150
const SAMPLE_FRAMES := 600

func _perf() -> void:
	var camera := get_viewport().get_camera_2d()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	var data: Dictionary = {}
	for id: String in ["glaive","maul"]:
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % id) as WeaponData
		await _arm(weapon, camera)
		await settle(WARMUP_FRAMES)
		var visual := player._visual
		var hold := visual.melee_hold()
		var attachment := visual.rig.get_node_or_null("MeleeHeld") as Node2D
		var dedicated := attachment != null and attachment.visible
		var drawn := visual.shows_melee_weapon() and player.loadout.active_weapon() == weapon
		if not drawn or dedicated != _tag.begins_with("after") or not hold.origin.is_finite() or not is_equal_approx(hold.x.length(), 1.0):
			push_error("[GripBenchmark] active hold is missing for %s" % id)
			_failures += 1
			continue
		var frames := PackedFloat32Array()
		frames.resize(SAMPLE_FRAMES)
		var physics_start := Engine.get_physics_frames()
		var last := Time.get_ticks_usec()
		for i in SAMPLE_FRAMES:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames[i] = float(now - last) / 1000.0
			last = now
		var physics_steps := Engine.get_physics_frames() - physics_start
		if physics_steps < 10:
			push_error("[GripBenchmark] insufficient real physics steps for %s" % id)
			_failures += 1
		data[id] = {"drawn": drawn, "dedicated_attachment": dedicated, "samples_ms": Array(frames), "physics_steps": physics_steps,
			"facing": player.facing, "hold_x": [hold.x.x, hold.x.y], "hold_origin": [hold.origin.x, hold.origin.y],
			"scene_draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	var details := {"tag": _tag, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"engine": Engine.get_version_info().string, "resolution": [get_window().size.x,get_window().size.y],
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"reduced_flashes": Settings.get_reduce_flashes(), "reduced_ui_motion": Settings.get_reduce_ui_motion(),
		"lighting": _lighting, "quality": _quality, "warmup_frames": WARMUP_FRAMES, "records": data, "failures": _failures}
	var writer := FileAccess.open(out_dir.path_join("grip-timings.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[GripBenchmark] cannot write grip-timings.json")
		_failures += 1
		return
	writer.store_string(JSON.stringify(details))
	writer.close()
	print("NE275_HISTORIC_TIMING: ", _tag, " weapons=", data.size(), " failures=", _failures)
