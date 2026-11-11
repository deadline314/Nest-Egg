extends "res://tools/fixture_states_probe.gd"
## BG-47 local Forward+ acceptance. The inherited route uses actual projectile physics.
## --fallback uses process-local invalid resources at existing texture paths; no file is moved.

var _fallback := false
var _campaign_barrel := false
var _faults_enabled := true
var _invalid_resources: Array[Resource] = []


func _ready() -> void:
	_fallback = "--fallback" in OS.get_cmdline_user_args()
	_campaign_barrel = "--campaign-barrel" in OS.get_cmdline_user_args()
	_faults_enabled = "--no-override" not in OS.get_cmdline_user_args()
	super._ready()


func _run() -> void:
	if _campaign_barrel:
		await _run_campaign_barrel()
	elif _fallback:
		await _run_fallback()
	else:
		await super._run()


func _photo(id: String, level: Level) -> void:
	var geometry: Array[Dictionary] = []
	for node in level._entities.get_children():
		if node is Breakable and not node.is_broken:
			var body := node as Breakable
			var floor_point := level.authored_floor_below(body.global_position - Vector2(0, 1), 4)
			var gap := floor_point.y - body.global_position.y if floor_point.is_finite() else INF
			_check(absf(gap) <= 2, "%s %s has authored floor support within 2 px" % [id, body.data.id])
			_check(body.z_index == WorldLayers.ENTITY_BEHIND, "%s %s is behind every character part" % [id, body.data.id])
			if body._body_art != null:
				var art_rect := Rect2(body._body_art.position, body._body_art.texture.get_size() * body._body_art.scale)
				var shape := body._shape_node.shape as RectangleShape2D
				var collision_rect := Rect2(body._shape_node.position - shape.size * 0.5, shape.size)
				_check(art_rect.is_equal_approx(collision_rect), "%s %s art matches its unchanged collision" % [id, body.data.id])
			geometry.append({"kind": "breakable", "id": String(body.data.id), "feet": [body.position.x, body.position.y], "floor_gap": gap, "z": body.z_index})
		elif node is PowerSwitch:
			var power := node as PowerSwitch
			var floor_point := level.authored_floor_below(power.global_position - Vector2(0, 1), 4)
			var gap := floor_point.y - power.global_position.y if floor_point.is_finite() else INF
			_check(absf(gap) <= 2 and power.z_index == WorldLayers.ENTITY_BEHIND, "%s power cabinet is supported and behind characters" % id)
			geometry.append({"kind": "power", "floor_gap": gap, "z": power.z_index, "active": power.active})
	if id.contains("lift"):
		var lift := _prop_at(level, Lift, 50) as Lift
		_check(absf(level.player.global_position.y - lift.global_position.y) <= 2 and level.player.is_on_floor(), "the actual player stands on the moving lift collision")
		_check(lift._rails.z_index == WorldLayers.RAILS and lift.z_index == WorldLayers.ENTITY_BEHIND, "fixed rails and deck remain behind all character parts")
		if lift._art != null:
			_check(lift._art.position.is_equal_approx(Vector2(-lift._width * 0.5, 0)) and (lift._art.texture.get_size() * lift._art.scale).is_equal_approx(Vector2(lift._width, Lift.PLATFORM_THICKNESS)), "lift art top and width equal its standable collision")
		geometry.append({"kind": "lift", "player_feet_y": level.player.global_position.y, "deck_y": lift.global_position.y, "on_floor": level.player.is_on_floor(), "rails_y": lift._rails.global_position.y})
	_caption.text = ("HEADLESS" if DisplayServer.get_name() == "headless" else "NATIVE FORWARD+ / " + RenderingServer.get_video_adapter_name()) + "\nARRANGED FIXTURE / " + id
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_capture(id)
	_shots.append({"file": id + ".png", "level": level.data.resource_path, "geometry": geometry,
		"player_feet": [level.player.position.x, level.player.position.y], "camera": [get_viewport().get_camera_2d().global_position.x, get_viewport().get_camera_2d().global_position.y]})


func _run_fallback() -> void:
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	FixtureArt.clear_cache()
	var missing := &"test_missing_prop_bg47_absent"
	_check(not ResourceLoader.exists(FixtureArt.FOLDER + String(missing) + ".png"), "the missing-file request really has no resource")
	if _faults_enabled:
		_check(FixtureArt.texture(missing) == null and FixtureArt.texture(missing) == null, "a real absent path safely returns null on repeated requests")
	var ids: Array[StringName] = []
	for body: StringName in FixtureArt.BREAKABLE_BODIES.values():
		ids.append_array(FixtureArt.body_parts(body))
	for parts: Array in FixtureArt.MECHANISM_PARTS.values():
		for id: StringName in parts:
			ids.append(id)
	for id in ids:
		var path := FixtureArt.FOLDER + String(id) + ".png"
		_check(FileAccess.file_exists(path), "formal texture exists unchanged on disk: " + path)
		RigLibrary._texture_cache.erase(path)
		if _faults_enabled:
			var invalid := Resource.new()
			invalid.take_over_path(path)
			_invalid_resources.append(invalid)
	var data := PropsSuite.level_data()
	# Use the current authored chapter; PropsSuite defaults to the legacy chapter_01.
	data.chapter = &"ch1_kasa"
	var zone := LightingZone.new()
	zone.profile = load("res://data/lighting/facility.tres")
	data.lighting_zones = [zone]
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(20)
	level.hud.hide()
	level.player.health.setup(999, 0.0)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_set_scripted_aim(level.player, true)
	for column in [10, 30, 20]:
		var body := _prop_at(level, Breakable, column) as Breakable
		_check(body._body_art == null and body.health.current > 0 and not body._shape_node.disabled, "a refused formal body retains health and its original solid collision: " + String(body.data.id))
		level.player.global_position = body.global_position + Vector2(-60, -2)
		level_camera_snap()
		await _settle(4)
		await _photo("fallback-" + String(body.data.id) + "-intact", level)
		while not body.is_broken:
			if not await _shoot(body, level):
				break
		await _settle(2)
		_check(body.is_broken and not body.visible and not body.hurtbox.enabled, "fallback body still breaks from real projectile collisions: " + String(body.data.id))
	var lift := _prop_at(level, Lift, 50) as Lift
	_check(lift._art == null and lift._rails._left == null and lift._rails._top == null, "refused deck and rails retain the procedural fallback")
	var rail_position := lift._rails.global_position
	level.player.global_position = lift.global_position + Vector2(0, -2)
	for frame in 360:
		await get_tree().physics_frame
		if lift._phase == Lift.Phase.UP and lift.position.y < lift._start_y - 10 and level.player.is_on_floor() and absf(level.player.global_position.y - lift.global_position.y) <= 2:
			break
	level_camera_snap()
	await _photo("fallback-lift-riding", level)
	_check(lift._rails.global_position == rail_position, "fallback rails stay fixed while the original platform moves")
	var power := _prop_at(level, PowerSwitch, 56) as PowerSwitch
	_check(power._art_on == null and power._art_off == null, "refused power panels retain the procedural cabinet")
	level.player.global_position = power.global_position + Vector2(-20, -2)
	level_camera_snap()
	await _settle(4)
	Input.action_press(&"interact")
	await get_tree().physics_frame
	Input.action_release(&"interact")
	await _settle(4)
	_check(power.active and not PowerGrid.is_powered(lift), "fallback cabinet still cuts power through actual interaction")
	await _photo("fallback-power-cut", level)
	for id in ids:
		_check(FixtureArt.texture(id) == null, "product loader reports and caches the refused formal path: " + String(id))
	_set_scripted_aim(level.player, false)
	level.queue_free()
	await _settle(4)
	# Release the process-local resource-cache overrides before normal engine teardown.
	for invalid in _invalid_resources:
		invalid.resource_path = ""
	_invalid_resources.clear()
	FixtureArt.clear_cache()
	await AudioRelease.settle(get_tree())
	print("BG47_FALLBACK_EXIT world_valid=", is_instance_valid(level), " orphans=", Node.get_orphan_node_ids().size())
	var expected_errors := ids.size() + 1 if _faults_enabled else 0
	var report := {"kind": "isolated process: true absent test path plus invalid Resource.take_over_path for formal paths; no asset files modified", "engine": Engine.get_version_info().string,
		"chapter": String(data.chapter), "light_profile": zone.profile.resource_path, "faults_enabled": _faults_enabled,
		"adapter": RenderingServer.get_video_adapter_name(), "checks": _checks, "failures": _failures, "expected_loader_errors": expected_errors, "formal_ids": ids, "shots": _shots}
	var file := FileAccess.open(_out_dir.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("BG47_FALLBACK checks: %d, failures: %d expected_loader_errors: %d" % [_checks, _failures, expected_errors])
	# Let this awaited helper return and release its locals before SceneTree teardown.
	get_tree().quit.call_deferred(1 if _failures > 0 else 0)


func _run_campaign_barrel() -> void:
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	# Arrangement only: retain original map, barrel, lighting and every lamp/weather effect.
	# Suppress story entrances and nearby AI; this is not a campaign playthrough.
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var source := "res://data/levels/ch1_warehouse.tres"
	var level := Level.new()
	level.configure(load(source))
	add_child(level)
	await _settle(24)
	level.hud.hide()
	level.player.health.setup(999, 0.0)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	var barrel: Throwable
	for node in level.find_children("*", "", true, false):
		if node is Throwable and node.data.look == ThrowableData.Look.BARREL:
			barrel = node
			break
	_check(barrel != null, "the canonical warehouse really spawns its authored fuel barrel")
	if barrel != null:
		_set_scripted_aim(level.player, true)
		level.player.global_position = barrel.global_position + Vector2(-60, -2)
		level_camera_snap()
		await _wait(2.0)
		_check(barrel._body_art != null and barrel._body_art.texture == FixtureArt.texture(&"breakable_barrel"), "the authored warehouse barrel uses the formal intact material")
		await _photo("campaign-warehouse-barrel-intact", level)
		_shots[-1]["barrel"] = _barrel_view(barrel)
		var health_before := barrel.health.current
		ProjectilePool.spawn(load("res://data/projectiles/pistol_shot.tres"), barrel.world_center() + Vector2(-30, 0), Vector2.RIGHT, Combat.Team.PLAYER)
		for frame in 60:
			await get_tree().physics_frame
			if barrel.health.current < health_before:
				break
		_check(barrel.health.current == health_before - 1 and not barrel.is_fuse_lit(), "one real projectile damages the original barrel without prematurely lighting its fuse")
		await _wait(0.18)
		_check(barrel._body_art.texture == FixtureArt.texture(&"breakable_barrel_damaged"), "the original damaged state selects its own texture in the canonical warehouse")
		await _photo("campaign-warehouse-barrel-damaged", level)
		_shots[-1]["barrel"] = _barrel_view(barrel)
		_set_scripted_aim(level.player, false)
	level.queue_free()
	await _settle(4)
	await AudioRelease.settle(get_tree())
	var report := {"kind": "arranged camera at an unmodified authored warehouse barrel; original map/light/lamp/weather retained; not campaign playthrough", "level": source,
		"engine": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(), "checks": _checks, "failures": _failures, "shots": _shots}
	var file := FileAccess.open(_out_dir.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("BG47_WAREHOUSE checks: %d, failures: %d" % [_checks, _failures])
	get_tree().quit.call_deferred(1 if _failures > 0 else 0)


func _barrel_view(barrel: Throwable) -> Dictionary:
	return {"position": [barrel.position.x, barrel.position.y], "health": barrel.health.current, "texture": barrel._body_art.texture.resource_path,
		"body_modulate": str(barrel.modulate), "sprite_modulate": str(barrel._body_art.modulate), "material": str(barrel._body_art.material)}
