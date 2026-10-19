extends "res://tools/light_pool_probe.gd"
## Diagnostic only: paired fog-density intervention in one held live scene.
## All layers remain visible. This is not a historical checkout or playthrough.

func _measure_level(level_id: String, data: LevelData) -> Dictionary:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(SETTLE_FRAMES)
	level.hud.visible = false
	for child: Node in level.get_children():
		if child is ChapterCard:
			child.queue_free()
	level.player.visible = false
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	var focus := Node2D.new()
	level.add_child(focus)
	focus.global_position = level.player.global_position
	level._lighting._target = focus
	var flags := GameState.world_flags.duplicate(true)
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Node2D).visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
	level._lighting._lightning_gap = 1.0e9
	var lamps: Array[Lamp] = []
	var rains: Array[RainLayer] = []
	for node: Node in level.find_children("*", "Node", true, false):
		if node is Lamp and not node.dead:
			lamps.append(node)
		if node is RainLayer:
			rains.append(node)
	lamps.sort_custom(func(a: Lamp, b: Lamp) -> bool: return a.position.x < b.position.x)
	for item in lamps:
		item.use_flicker(LampFlicker.STABLE, 0)
		item._flicker = 1.0
	var lamp := lamps[-1]
	_place_focus(level, lamp)
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * LevelCamera.base_zoom() * VIEW_ZOOM
	camera.global_position = lamp.global_position + Vector2(0, 60)
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _settle(SETTLE_FRAMES)
	var harbor: LightingProfile
	for zone in level._lighting._zones:
		if zone.profile.id == &"harbor_approach":
			harbor = zone.profile
	assert(harbor != null and is_equal_approx(harbor.fog_density, 0.5))
	# Hold simulation, not drawing: original fog/rain/shadows/rim remain present.
	level.process_mode = Node.PROCESS_MODE_DISABLED
	level._fog.set_process(false)
	for rain in rains:
		rain.set_process(false)
	var held := _atmosphere(level, rains, camera)
	var records: Array[Dictionary] = []
	for density: float in [1.3, 0.5, 1.3, 0.5]:
		harbor.fog_density = density
		level._lighting.snap()
		level._fog.queue_redraw()
		await _settle(3)
		var image := Capture.image(get_viewport())
		var file := "%s-%s-pair%02d.png" % [_tag, level_id, records.size()]
		image.save_png(_out.path_join(file))
		var record := _measure_lamp(image, lamp, level._scenery_walls)
		record["file"] = file
		record["profile_density"] = density
		record["applied_density"] = level._fog.density
		record["atmosphere"] = _atmosphere(level, rains, camera)
		record["held_state_unchanged"] = record["atmosphere"] == held
		record["flags_unchanged"] = GameState.world_flags == flags
		if not record["held_state_unchanged"] or not record["flags_unchanged"] or float(record["ratio"]) <= 0.0:
			_invalid_samples += 1
		records.append(record)
		print("FOG_PAIR ", _quality, " profile=", density, " applied=", level._fog.density, " ratio=", record["ratio"], " held=", record["held_state_unchanged"])
	harbor.fog_density = 0.5
	level.queue_free()
	await _settle(6)
	return {"kind": "paired runtime fog intervention; held visible atmosphere; not historical checkout", "tile": int(lamp.position.x / 16.0) if is_instance_valid(lamp) else 176, "records": records}

func _atmosphere(level: Level, rains: Array[RainLayer], camera: Camera2D) -> Dictionary:
	var rain_states: Array = []
	for rain in rains:
		rain_states.append({"time": rain._time, "drift": rain._drift, "visible": rain.is_visible_in_tree()})
	return {"fog_time": level._fog._time, "fog_visible": level._fog.is_visible_in_tree(), "rain": rain_states, "camera": [camera.global_position.x, camera.global_position.y], "rim": [level._lighting._rim_light.global_position.x, level._lighting._rim_light.global_position.y, level._lighting._rim_light.energy, level._lighting._rim_light.enabled]}
