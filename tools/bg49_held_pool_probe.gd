extends "res://tools/light_pool_probe.gd"
## Original light-pool formula, with held A/A/B/A at every harbor-zone lamp.
## Restore the old freight profile through the real spatial blend, not at spawn.

const Held49 := preload("res://tools/bg55_enemy_readability_probe.gd")
const Drawing49 := preload("res://tools/held_lighting_state.gd")
var _environment49: WorldEnvironment


func _ready() -> void:
	Settings.use_storage("user://bg49_held_pool.cfg")
	Settings.set_brightness(0.5)
	_environment49 = LightKit.create_environment()
	add_child(_environment49)
	super._ready()


func _state49(level: Level) -> Dictionary:
	var rain: Array[Dictionary] = []
	var lamps: Array[Dictionary] = []
	for node in level.find_children("*", "", true, false):
		if node is RainLayer:
			rain.append({"time": node._time, "drift": node._drift, "visible": node.is_visible_in_tree(), "points": Held49.bytes_sha(var_to_bytes(node._points))})
		elif node is Lamp:
			lamps.append({"position": str(node.global_position), "clock": node._clock, "dead": node.dead, "energy": node._light.energy if node._light != null else 0.0})
	return {"fog_time": level._fog._time, "fog_visible": level._fog.is_visible_in_tree(), "rain": rain,
		"lamps": lamps, "camera": str(get_viewport().get_canvas_transform()), "time_scale": Engine.time_scale,
		"flags": GameState.world_flags.duplicate(true), "drawing_owners": Drawing49.snapshot(level)}


func _measure_level(level_id: String, source: LevelData) -> Dictionary:
	var time_before := Engine.time_scale
	GameState.start_new_run(GameState.difficulties[1])
	var data := source.duplicate() as LevelData
	data.intro_scene = &""
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(24)
	level.hud.visible = false
	level.player.visible = false
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	var focus := Node2D.new()
	level.add_child(focus)
	level._lighting._target = focus
	level._lighting._lightning_gap = 1.0e9
	var lamps: Array[Lamp] = []
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt:
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
		elif node is Enemy:
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
		elif node is ChapterCard:
			node.queue_free()
		elif node is Lamp and not node.dead:
			node.use_flicker(LampFlicker.STABLE, 0)
			node._flicker = 1.0
			if level._lighting.zone_id_at(node.global_position.x) == &"harbor_approach":
				lamps.append(node)
	var zones: Array[LightingZone] = []
	var authored: LightingProfile
	for zone in level._lighting._zones:
		if zone.profile.id == &"harbor_approach":
			zones.append(zone)
			authored = zone.profile
	if lamps.is_empty() or zones.is_empty():
		printerr("[BG49Pool] No live harbor lamp/profile in " + level_id)
		_invalid_samples += 1
		level.queue_free()
		await _settle(6)
		return {}
	var reference := load("res://data/lighting/freight.tres") as LightingProfile
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * LevelCamera.base_zoom() * VIEW_ZOOM
	var observations: Array[Dictionary] = []
	for lamp in lamps:
		focus.global_position = lamp.global_position
		camera.global_position = lamp.global_position + Vector2(0, 60)
		camera.reset_smoothing()
		camera.force_update_scroll()
		level._lighting.snap()
		await _settle(24)
		Drawing49.preserve_physics_bodies(level)
		level.process_mode = Node.PROCESS_MODE_DISABLED
		Engine.time_scale = 0.0
		Drawing49.sync(level)
		await _settle(3)
		var held := _state49(level)
		var pairs: Array[Dictionary] = []
		for label: String in ["A0", "A1", "product", "restore-A", "authored-final"]:
			var profile := authored if label in ["product", "authored-final"] else reference
			for zone in zones:
				zone.profile = profile
			level._lighting.snap()
			Drawing49.sync(level)
			level._fog._tint_refresh = 0.0
			level._fog._process(0.0)
			level._fog.queue_redraw()
			await _settle(3)
			var raw := get_viewport().get_texture().get_image()
			var active := get_viewport().find_world_3d().environment
			var bloom_valid: bool = active == _environment49.environment and active.glow_enabled
			if not bloom_valid:
				_invalid_samples += 1
			var encoded := Capture.encode(raw, get_viewport().use_hdr_2d)
			var stem := "%s-lamp%d-%s" % [level_id, int(lamp.position.x / 16.0), label]
			var file := FileAccess.open(_out.path_join(stem + ".bin"), FileAccess.WRITE)
			if file == null or encoded.save_png(_out.path_join(stem + ".png")) != OK:
				_invalid_samples += 1
			else:
				file.store_buffer(raw.get_data())
				file.close()
			var record := super._measure_lamp(encoded, lamp, level._scenery_walls)
			var bands: Array[Dictionary] = []
			for drop: float in BAND_DROPS:
				var center := lamp.global_position + Vector2(0, drop)
				var eligible := drop < lamp.light_radius * 0.8 and level._scenery_walls.covers(Rect2(center - Vector2(POOL_HALF_WIDTH, BAND_HEIGHT * 0.5), Vector2(POOL_HALF_WIDTH * 2.0, BAND_HEIGHT)))
				var far_coverage: Array[bool] = []
				for side: float in [-1.0, 1.0]:
					var start := center.x + side * lamp.light_radius * FAR_FROM
					var end := center.x + side * lamp.light_radius * FAR_TO
					far_coverage.append(level._scenery_walls.covers(Rect2(minf(start, end), center.y - BAND_HEIGHT * 0.5, absf(end - start), BAND_HEIGHT)))
				bands.append({"drop": drop, "pool_wall_eligible": eligible, "far_wall_eligible": far_coverage})
			record.merge({"label": label, "raw": stem + ".bin", "png": stem + ".png", "width": raw.get_width(), "height": raw.get_height(),
				"format": raw.get_format(), "raw_sha256": Held49.bytes_sha(raw.get_data()), "state": _state49(level),
				"applied_fog": level._fog.density, "target_x": focus.global_position.x, "lamp_x": lamp.global_position.x,
				"zone_id": str(level._lighting.zone_id_at(focus.global_position.x)), "profile": profile.resource_path,
				"bloom_active": bloom_valid, "brightness": Settings.get_brightness(),
				"lamp_position": [lamp.global_position.x, lamp.global_position.y], "lamp_radius": lamp.light_radius,
				"bands": bands, "world_to_screen": str(get_viewport().get_final_transform() * get_viewport().get_canvas_transform()),
				"world_to_screen_values": Drawing49.transform_values(get_viewport().get_final_transform() * get_viewport().get_canvas_transform()),
				"formula": {"height": BAND_HEIGHT, "half_width": POOL_HALF_WIDTH, "far_from": FAR_FROM, "far_to": FAR_TO, "far_min": 0.004}})
			pairs.append(record)
			if record.state != held or not record.state.drawing_owners.valid or float(record.ratio) <= 0.0 or absf(focus.global_position.x - lamp.global_position.x) > 0.001:
				_invalid_samples += 1
		var valid: bool = pairs[0].raw_sha256 == pairs[1].raw_sha256 and pairs[0].raw_sha256 == pairs[3].raw_sha256 and pairs[2].raw_sha256 == pairs[4].raw_sha256
		var no_drop: bool = float(pairs[2].ratio) >= float(pairs[0].ratio)
		if not valid or not no_drop:
			_invalid_samples += 1
		observations.append({"lamp_tile": int(lamp.position.x / 16.0), "fixture": lamp.fixture_id, "controls_valid": valid, "no_drop": no_drop, "records": pairs})
		print("BG49_POOL tile=", int(lamp.position.x / 16.0), " A=", pairs[0].ratio, " B=", pairs[2].ratio, " valid=", valid)
	for zone in zones:
		zone.profile = authored
	Engine.time_scale = time_before
	level.queue_free()
	await _settle(6)
	return {"kind": "held live spatial blend; freight reference vs authored harbor; not historical checkout", "observations": observations,
		"engine": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(), "hdr": get_viewport().use_hdr_2d,
		"source_sha256": FileAccess.get_sha256("res://tools/bg49_held_pool_probe.gd"), "formula_sha256": FileAccess.get_sha256("res://tools/light_pool_probe.gd")}
