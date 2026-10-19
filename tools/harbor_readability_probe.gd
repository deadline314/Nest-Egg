extends "res://tools/ch1_readability_check.gd"
## Original sampling/thresholds plus raw HDR saturation observations.
## A body rectangle includes background. Zero white pixels proves no saturation;
## nonzero pixels require a silhouette mask before assigning an enemy-only ratio.

var _exposure: Array[Dictionary] = []


func _ready() -> void:
	Settings.use_storage("user://harbor_readability_settings.cfg")
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "SOFTWARE FORWARD+ / STATIONARY READABILITY LAB / NOT A PLAYTHROUGH"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 13)
	layer.add_child(label)
	super._ready()


func _spawn_foe(level: Level, position: Vector2, path := "res://data/enemies/grunt.tres") -> Enemy:
	var enemy := super._spawn_foe(level, position, path)
	if enemy != null:
		_observe_exposure.call_deferred(weakref(enemy), str(level.data.id), path)
	return enemy


func _observe_exposure(reference: WeakRef, level_id: String, enemy_path: String) -> void:
	for sample in 3:
		await get_tree().create_timer(1.1).timeout
		var enemy := reference.get_ref() as Enemy
		if not is_instance_valid(enemy):
			return
		await RenderingServer.frame_post_draw
		var probe := ContrastProbe.capture(get_viewport())
		var world_bounds := probe._body_box(enemy.global_position, false)
		var coverage := "legacy contrast box only"
		if enemy.rig != null:
			var body_bounds := enemy.rig.visual_bounds()
			if body_bounds.has_area():
				world_bounds = world_bounds.merge(body_bounds)
				coverage = "visible rig parts and weapon bounds"
			var weapon := enemy.rig._weapon_sprite
			if weapon != null and weapon.texture != null and weapon.is_visible_in_tree():
				world_bounds = world_bounds.merge(weapon.global_transform * weapon.get_rect())
		var rect := probe._screen_rect(world_bounds.grow(1.0))
		var white := 0
		var peak := 0.0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var color := probe._image.get_pixel(x, y)
				peak = maxf(peak, maxf(color.r, maxf(color.g, color.b)))
				if color.r > 0.92 and color.g > 0.92 and color.b > 0.92:
					white += 1
		_exposure.append({"level": level_id, "enemy": enemy_path, "sample": sample,
			"quality": Settings.get_light_quality(), "coverage": coverage,
			"world_bounds": [world_bounds.position.x, world_bounds.position.y, world_bounds.size.x, world_bounds.size.y], "feet": [enemy.global_position.x, enemy.global_position.y],
			"screen_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"white_pixels_including_background": white, "rectangle_pixels": rect.size.x * rect.size.y,
			"hdr_channel_peak": peak, "no_saturation_in_rectangle": white == 0,
			"enemy_only_ratio": 0.0 if white == 0 else null})
		if not _out_dir.is_empty():
			var file := FileAccess.open(_out_dir.path_join("enemy-exposure.json"), FileAccess.WRITE)
			if file == null:
				_failed = true
				return
			file.store_string(JSON.stringify({"encoding": "raw linear HDR viewport", "observations": _exposure}, "  ") + "\n")
			file.close()
