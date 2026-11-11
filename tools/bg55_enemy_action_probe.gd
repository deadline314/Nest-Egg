extends Node
## Real authored AI in its actual level. Only player test position/durability
## and non-target suspension are arranged; no enemy health/FSM/stat writes.
const Capture := preload("res://tools/viewport_capture.gd")
const Held := preload("res://tools/held_lighting_state.gd")
var _out := ""
var _quality := "high"
var _failures := 0
var _records: Array[Dictionary] = []
var _environment: WorldEnvironment


func _ready() -> void:
	Settings.use_storage("user://bg55_action_settings.cfg")
	if OS.get_cmdline_user_args().has("--validate-only"):
		var level_data := load("res://data/levels/ch2_market_gate.tres") as LevelData
		var escort := load("res://data/enemies/ch2_escort.tres") as EnemyData
		var thrower := load("res://data/enemies/ch2_bill_thrower.tres") as EnemyData
		var valid: bool = level_data != null and escort.rig_skin == "collector_brute" and thrower.rig_skin == "collector_gunner"
		print("BG55_ACTION_CPU valid=", valid, " (loading/compile only; not native AI validation)")
		get_tree().quit(0 if valid else 1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--quality="): _quality = arg.trim_prefix("--quality=")
	if not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[BG55 Action] Requires native rendering and absolute --out")
		get_tree().quit(2)
		return
	_environment = LightKit.create_environment()
	add_child(_environment)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var caption := Label.new()
	caption.position = Vector2(12, 12)
	caption.text = "BG55 / NATIVE AUTHORED AI / ARRANGED PLAYER POSITION + 999 HP / NOT A PLAYTHROUGH"
	caption.add_theme_font_size_override("font_size", 12)
	overlay.add_child(caption)
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		printerr("[BG55 Action] FAIL ", message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var quality_before := Settings.get_light_quality()
	var brightness_before := Settings.get_brightness()
	Settings.set_light_quality(LightQuality.Tier.LOW if _quality == "low" else LightQuality.Tier.HIGH)
	Settings.set_brightness(0.5)
	Story.auto_skip = true
	Story._layer.visible = false
	for id in Story.scene_ids(): Story._seen[StringName(id)] = true
	Input.action_press(&"aim_right")
	for id in [&"ch2_escort", &"ch2_bill_thrower"]:
		await _observe(id)
	Input.action_release(&"aim_right")
	Settings.set_light_quality(quality_before)
	Settings.set_brightness(brightness_before)
	var result := {"scope": "Actual level and original enemy AI; test player placed 72 world pixels left, 999 HP with authored hurt invulnerability; other enemies suspended; lightning suppressed; no enemy FSM/health/stat writes; not human play",
		"engine": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "hdr_2d": get_viewport().use_hdr_2d,
		"quality": _quality, "brightness": 0.5, "simulation_time_scale": Engine.time_scale,
		"failures": _failures, "actors": _records}
	var file := FileAccess.open(_out.path_join("actions.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	await AudioRelease.settle(get_tree())
	print("BG55_ACTION actors=%d failures=%d" % [_records.size(), _failures])
	get_tree().quit(1 if _failures else 0)


func _observe(id: StringName) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load("res://data/levels/ch2_market_gate.tres") as LevelData)
	add_child(level)
	var target: Enemy
	for node in level._entities.get_children():
		if node is Enemy:
			if target == null and node.data.id == id: target = node
			else: node.process_mode = Node.PROCESS_MODE_DISABLED
	_check(target != null, "authored target exists: " + str(id))
	if target == null:
		level.queue_free()
		await get_tree().process_frame
		return
	var enemy_start := target.global_position
	var original_hp := target.health.current
	level.player.health.setup(999, level.player.tuning.hurt_invulnerability)
	level.player.global_position = target.global_position - Vector2(72, 0)
	level.player.velocity = Vector2.ZERO
	AimInput.set_virtual_gamepad(level.player, true)
	level.hud.visible = false
	level._lighting._lightning_gap = 1.0e9
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt:
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
		elif node is ChapterCard: node.queue_free()
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * LevelCamera.base_zoom()
	camera.global_position = enemy_start + Vector2(-36, -50)
	camera.reset_smoothing()
	camera.force_update_scroll()
	var started := Time.get_ticks_msec()
	var timeline: Array[Dictionary] = []
	var captures: Array[Dictionary] = []
	var states: Dictionary = {}
	var captured: Dictionary = {}
	var projectiles: Dictionary = {}
	while Time.get_ticks_msec() - started < 8000:
		await get_tree().physics_frame
		var state := str(target.fsm.current)
		states[state] = true
		var tick := {"physics_frame": Engine.get_physics_frames(), "milliseconds": Time.get_ticks_msec() - started,
			"state": state, "state_time": target.fsm.time_in_state, "action": str(target._rig_input.action),
			"action_t": target._rig_input.action_t, "enemy_feet": [target.global_position.x, target.global_position.y],
			"player_feet": [level.player.global_position.x, level.player.global_position.y],
			"enemy_hp": target.health.current, "player_hp": level.player.health.current,
			"rig_fill": target.rig._fill, "light_cap": target.rig._light_cap,
			"weapon_light_origin_error": level.player._weapon_light.global_position.distance_to(level.player.aim_origin().lerp(level.player.muzzle_position(), Player.WEAPON_LIGHT_ORIGIN))}
		timeline.append(tick)
		for bullet in ProjectilePool.container().get_children():
			if bullet is Projectile and bullet.active and bullet.team == Combat.Team.ENEMY:
				projectiles[str(bullet.get_instance_id())] = {"source": str(bullet.spec.source_id), "at": str(bullet.global_position)}
		var phase := mini(2, int(target.fsm.time_in_state / 0.2))
		var key := "%s-%d" % [state, phase]
		if not captured.has(key) and captures.size() < 15:
			captured[key] = true
			await RenderingServer.frame_post_draw
			# The render can occur after a physics transition. Keep the trigger
			# separately and label the actual image with its post-draw state.
			var rendered_state := str(target.fsm.current)
			var probe := ContrastProbe.capture(get_viewport())
			var visual_bounds := target.rig.visual_bounds()
			var filename := "%s-%02d-%s" % [id, captures.size(), rendered_state]
			var raw := FileAccess.open(_out.path_join(filename + ".bin"), FileAccess.WRITE)
			raw.store_buffer(probe._image.get_data())
			raw.close()
			_check(Capture.encode(probe._image, get_viewport().use_hdr_2d).save_png(_out.path_join(filename + ".png")) == OK, "native action PNG saved")
			captures.append({"file": filename + ".png", "raw": filename + ".bin", "format": probe._image.get_format(),
				"size": [probe._image.get_width(), probe._image.get_height()], "state": rendered_state,
				"trigger_state": state, "physics_frame": Engine.get_physics_frames(), "milliseconds": Time.get_ticks_msec() - started,
				"state_time": target.fsm.time_in_state, "action": str(target._rig_input.action), "action_t": target._rig_input.action_t,
				"enemy_feet": [target.global_position.x, target.global_position.y],
				"rig_fill": target.rig._fill, "light_cap": target.rig._light_cap,
				"profile": str(level._lighting.zone_id_at(level.player.global_position.x)),
				"enemy_fill_scale": level._lighting.current.enemy_fill_scale,
				"world_environment_active": get_viewport().find_world_3d().environment == _environment.environment,
				"glow_enabled": _environment.environment.glow_enabled,
				"weapon_light_origin_error_post_draw": level.player._weapon_light.global_position.distance_to(level.player.aim_origin().lerp(level.player.muzzle_position(), Player.WEAPON_LIGHT_ORIGIN)),
				"visual_world_bounds": str(visual_bounds),
				"visual_world_bounds_values": [visual_bounds.position.x, visual_bounds.position.y, visual_bounds.size.x, visual_bounds.size.y],
				"canvas_transform": str(probe._to_screen), "canvas_transform_values": Held.transform_values(probe._to_screen), "density": probe._scale})
	_check(states.has("windup") and states.has("recover"), "real AI completes telegraph and recovery: " + str(id))
	_check(states.has("strike") if id == &"ch2_escort" else not projectiles.is_empty(), "real strike/projectiles observed: " + str(id))
	_check(target.health.current == original_hp, "enemy HP remains authored and unmodified")
	_check(is_equal_approx(level.player.health.invulnerability_time, level.player.tuning.hurt_invulnerability), "authored player hurt protection retained")
	_records.append({"id": str(id), "skin": target.data.rig_skin, "spawn_feet": str(enemy_start),
		"enemy_data_sha256": FileAccess.get_sha256("res://data/enemies/%s.tres" % id), "states": states.keys(),
		"projectiles": projectiles, "timeline": timeline, "captures": captures})
	level.queue_free()
	for _frame in 4: await get_tree().process_frame
