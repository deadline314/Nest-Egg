extends "res://tools/scene_tour.gd"
## BG-48: same tour coordinates and ContrastProbe; isolate a lamp phase or one layer.
## --lamps=dim|full, --diagnostic-no-fog, --diagnostic-no-wall-shadows.
## --reference-fog restores the original lounge fog density in this process only.
## Diagnostic captures carry a visible label and never replace the normal tour.

var _diagnostic_no_fog := false
var _diagnostic_no_wall_shadows := false
var _contrast_failures := 0
var _cycle_samples := 0
var _reference_fog := false
var _fixed_aim := false
var _paired_fog_clock := -1.0


func _ready() -> void:
	Settings.use_storage("user://readability_phase_settings.cfg")
	seed(481111)
	var phase := "cycle"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--paired-fog-clock="):
			var value := arg.trim_prefix("--paired-fog-clock=")
			if not value.is_valid_float() or float(value) < 0.0:
				push_error("[ReadabilityPhaseProbe] Paired fog clock requires a nonnegative number")
				get_tree().quit(2)
				return
			_paired_fog_clock = float(value)
		elif arg == "--fixed-aim":
			_fixed_aim = true
			Input.action_press(&"aim_right")
		elif arg == "--reference-fog":
			_reference_fog = true
		elif arg == "--lamps=dim":
			Lamp.flicker_hold = 0.0
			phase = "dim"
		elif arg == "--lamps=full":
			Lamp.flicker_hold = 1.0
			phase = "full"
		elif arg.begins_with("--lamps="):
			var value := arg.trim_prefix("--lamps=")
			if not value.is_valid_float() or float(value) < 0.0 or float(value) > 1.0:
				printerr("[ReadabilityPhaseProbe] --lamps must be dim, full, or a fraction in 0..1")
				get_tree().quit(2)
				return
			Lamp.flicker_hold = float(value)
			phase = value
		elif arg == "--cycle-samples=16":
			_cycle_samples = 16
		elif arg == "--diagnostic-no-fog":
			_diagnostic_no_fog = true
		elif arg == "--diagnostic-no-wall-shadows":
			_diagnostic_no_wall_shadows = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(12, 12)
	label.text = "%s / %s / STATIONARY LIGHTING LAB / lamps=%s%s%s%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), phase,
		" / REFERENCE: original lounge fog" if _reference_fog else "",
		" / DIAGNOSTIC: fog hidden" if _diagnostic_no_fog else "",
		" / DIAGNOSTIC: wall shadows hidden" if _diagnostic_no_wall_shadows else ""]
	label.add_theme_font_size_override("font_size", 13)
	if _paired_fog_clock >= 0.0:
		label.text += " / FIXED FOG CLOCK %.2f" % _paired_fog_clock
	layer.add_child(label)
	super._ready()


func _settle(frames: int) -> void:
	for node in find_children("*", "", true, false):
		if _fixed_aim and node is Player:
			AimInput.set_virtual_gamepad(node, true)
		elif _paired_fog_clock >= 0.0 and node is FogLayer:
			# A declared stationary phase control, without hiding or thinning fog.
			# Refresh its real light-tint cache for this camera before drawing.
			node.set_process(false)
			node._time = _paired_fog_clock
			node._tint_refresh = 0.0
			node._process(0.0)
		elif _diagnostic_no_fog and node is FogLayer:
			node.visible = false
		elif _diagnostic_no_wall_shadows and node is WallShadows:
			node.suspended = true
	await super._settle(frames)


func _measure(level: Level, world: Rect2) -> Dictionary:
	var result := await super._measure(level, world)
	result["facing"] = level.player.facing
	result["aim_dir"] = [level.player.aim_dir.x, level.player.aim_dir.y]
	result["player_world"] = [level.player.global_position.x, level.player.global_position.y]
	result["lighting_zone"] = str(level._lighting.zone_id_at(level.player.global_position.x))
	result["fog_density"] = level._lighting.current.fog_density
	result["ambient_color"] = str(level._lighting.current.ambient_color)
	result["fog_clock"] = level._fog._time
	result["lamps"] = _lamp_observations(level)
	var geometry := ContrastProbe.capture(get_viewport())
	var body_box := geometry._body_box(level.player.global_position, true)
	result["geometry"] = {"image_size": str(geometry._image.get_size()), "image_format": geometry._image.get_format(),
		"density": geometry._scale, "canvas_transform": str(geometry._to_screen),
		"body_screen_rect": str(geometry._screen_rect(body_box)), "body_pixel_count": geometry._pixel_count(body_box)}
	if _fixed_aim and (level.player.facing != 1 or not level.player.aim_dir.is_equal_approx(Vector2.RIGHT)):
		_contrast_failures += 1
		printerr("[ReadabilityPhaseProbe] Fixed aim drift: %s facing=%d aim=%s" % [level.data.id, level.player.facing, level.player.aim_dir])
	if result.has("player_contrast"):
		var passed := float(result["player_contrast"]) >= ContrastProbe.MIN_PLAYER_CONTRAST and float(result["edge_contrast"]) >= ContrastProbe.MIN_EDGE_CONTRAST
		result["passed"] = passed
		if not passed:
			_contrast_failures += 1
			printerr("[ReadabilityPhaseProbe] %s at %s: player %.3f / edge %.3f" % [level.data.id, level.player.global_position, result["player_contrast"], result["edge_contrast"]])
		if _cycle_samples > 0:
			var player_min := INF
			var edge_min := INF
			var raw_cycle: Array[Dictionary] = []
			for sample in _cycle_samples:
				await RenderingServer.frame_post_draw
				var probe := ContrastProbe.capture(get_viewport())
				var player_value := probe.character_contrast(level.player.global_position, true)
				var edge_value := probe.edge_contrast(level.player.global_position)
				player_min = minf(player_min, player_value)
				edge_min = minf(edge_min, edge_value)
				raw_cycle.append({"sample": sample, "player": player_value, "edge": edge_value, "fog_clock": level._fog._time, "lamps": _lamp_observations(level)})
				await get_tree().create_timer(0.2).timeout
			result["cycle_samples_raw"] = raw_cycle
			result["cycle_player_min"] = player_min
			result["cycle_edge_min"] = edge_min
			var cycle_passed := player_min >= ContrastProbe.MIN_PLAYER_CONTRAST and edge_min >= ContrastProbe.MIN_EDGE_CONTRAST
			result["cycle_passed"] = cycle_passed
			if not cycle_passed:
				_contrast_failures += 1
				printerr("[ReadabilityPhaseProbe] cycle minimum %s at %s: player %.3f / edge %.3f" % [level.data.id, level.player.global_position, player_min, edge_min])
	return result


func _tour(level_id: String) -> bool:
	var before := _contrast_failures
	if _paired_fog_clock >= 0.0:
		seed(481111 + level_id.hash())
	# Restore only the original fog density in memory. Keep today's scene, lamps,
	# shadows and character identical; this is a single-factor reference, not an
	# historical checkout. Never write the resource back to disk.
	var profile: LightingProfile
	var density_before := 0.0
	if _reference_fog:
		profile = load("res://data/lighting/lounge_front.tres") as LightingProfile
		var reference := load("res://data/lighting/market.tres") as LightingProfile
		if profile == null or reference == null:
			push_error("[ReadabilityPhaseProbe] Missing lounge_front or market lighting profile")
			return false
		density_before = profile.fog_density
		profile.fog_density = reference.fog_density
	var completed := await super._tour(level_id)
	if profile != null:
		profile.fog_density = density_before
	var path := _out.path_join(level_id).path_join(_tag + "-index.json")
	if FileAccess.file_exists(path):
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		index["probe"] = {"kind": "stationary lighting fixture", "engine": Engine.get_version_info().string,
			"adapter": RenderingServer.get_video_adapter_name(), "quality": Settings.get_light_quality(),
			"renderer": RenderingServer.get_current_rendering_method(), "reference_fog": _reference_fog,
			"hdr_2d": get_viewport().use_hdr_2d,
			"fixed_gamepad_aim": _fixed_aim,
			"paired_fog_clock": _paired_fog_clock,
			"brightness": Settings.get_brightness(),
			"lamp_hold": Lamp.flicker_hold, "fog_hidden": _diagnostic_no_fog,
			"cycle_samples": _cycle_samples, "cycle_sample_interval": 0.2,
			"wall_shadows_hidden": _diagnostic_no_wall_shadows,
			"source_sha256": {"tools/contrast_probe.gd": FileAccess.get_sha256("res://tools/contrast_probe.gd"),
				"tools/viewport_capture.gd": FileAccess.get_sha256("res://tools/viewport_capture.gd"),
				"tools/readability_phase_probe.gd": FileAccess.get_sha256("res://tools/readability_phase_probe.gd"),
				"tools/scene_tour.gd": FileAccess.get_sha256("res://tools/scene_tour.gd"),
				"data/lighting/lounge_front.tres": FileAccess.get_sha256("res://data/lighting/lounge_front.tres"),
				"data/lighting/market.tres": FileAccess.get_sha256("res://data/lighting/market.tres")},
			"thresholds": {"player": ContrastProbe.MIN_PLAYER_CONTRAST, "edge": ContrastProbe.MIN_EDGE_CONTRAST}}
		var writer := FileAccess.open(path, FileAccess.WRITE)
		if writer == null:
			return false
		writer.store_string(JSON.stringify(index, "  ") + "\n")
	return completed and _contrast_failures == before


func _exit_tree() -> void:
	if _fixed_aim:
		Input.action_release(&"aim_right")


func _lamp_observations(level: Level) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for node in level.find_children("*", "", true, false):
		if node is Lamp:
			values.append({"at": [node.global_position.x, node.global_position.y], "state": str(node.flicker_state),
				"dead": node.dead, "energy": node._light.energy if node._light != null else 0.0,
				"clock": node._clock, "fixture": node.fixture_id})
	return values
