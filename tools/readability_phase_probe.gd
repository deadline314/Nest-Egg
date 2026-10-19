extends "res://tools/scene_tour.gd"
## BG-48: same tour coordinates and ContrastProbe; isolate a lamp phase or one layer.
## --lamps=dim|full, --diagnostic-no-fog, --diagnostic-no-wall-shadows.
## Diagnostic captures carry a visible label and never replace the normal tour.

var _diagnostic_no_fog := false
var _diagnostic_no_wall_shadows := false
var _contrast_failures := 0
var _cycle_samples := 0


func _ready() -> void:
	Settings.use_storage("user://readability_phase_settings.cfg")
	var phase := "cycle"
	for arg in OS.get_cmdline_user_args():
		if arg == "--lamps=dim":
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
	label.text = "SOFTWARE FORWARD+ / STATIONARY LIGHTING LAB / lamps=%s%s%s" % [phase,
		" / DIAGNOSTIC: fog hidden" if _diagnostic_no_fog else "",
		" / DIAGNOSTIC: wall shadows hidden" if _diagnostic_no_wall_shadows else ""]
	label.add_theme_font_size_override("font_size", 13)
	layer.add_child(label)
	super._ready()


func _settle(frames: int) -> void:
	for node in find_children("*", "", true, false):
		if _diagnostic_no_fog and node is FogLayer:
			node.visible = false
		elif _diagnostic_no_wall_shadows and node is WallShadows:
			node.suspended = true
	await super._settle(frames)


func _measure(level: Level, world: Rect2) -> Dictionary:
	var result := await super._measure(level, world)
	if result.has("player_contrast"):
		var passed := float(result["player_contrast"]) >= ContrastProbe.MIN_PLAYER_CONTRAST and float(result["edge_contrast"]) >= ContrastProbe.MIN_EDGE_CONTRAST
		result["passed"] = passed
		if not passed:
			_contrast_failures += 1
			printerr("[ReadabilityPhaseProbe] %s at %s: player %.3f / edge %.3f" % [level.data.id, level.player.global_position, result["player_contrast"], result["edge_contrast"]])
		if _cycle_samples > 0:
			var player_min := INF
			var edge_min := INF
			for sample in _cycle_samples:
				await RenderingServer.frame_post_draw
				var probe := ContrastProbe.capture(get_viewport())
				player_min = minf(player_min, probe.character_contrast(level.player.global_position, true))
				edge_min = minf(edge_min, probe.edge_contrast(level.player.global_position))
				await get_tree().create_timer(0.2).timeout
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
	var completed := await super._tour(level_id)
	var path := _out.path_join(level_id).path_join(_tag + "-index.json")
	if FileAccess.file_exists(path):
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		index["probe"] = {"kind": "stationary lighting fixture", "engine": Engine.get_version_info().string,
			"adapter": RenderingServer.get_video_adapter_name(), "quality": Settings.get_light_quality(),
			"brightness": Settings.get_brightness(),
			"lamp_hold": Lamp.flicker_hold, "fog_hidden": _diagnostic_no_fog,
			"cycle_samples": _cycle_samples, "cycle_sample_interval": 0.2,
			"wall_shadows_hidden": _diagnostic_no_wall_shadows,
			"thresholds": {"player": ContrastProbe.MIN_PLAYER_CONTRAST, "edge": ContrastProbe.MIN_EDGE_CONTRAST}}
		var writer := FileAccess.open(path, FileAccess.WRITE)
		if writer == null:
			return false
		writer.store_string(JSON.stringify(index, "  ") + "\n")
	return completed and _contrast_failures == before
