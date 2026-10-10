extends Node

const LEVEL_LAYOUT := "res://tests/fixtures/cover_map.json"
const DATA_PATHS := {
	"enforcer": "res://data/enemies/shield_rusher.tres",
	"heavy_gunner": "res://data/enemies/heavy_gunner.tres",
	"warden": "res://data/enemies/warden.tres",
}
const STATE_LISTS := {
	"enforcer": [&"patrol", &"windup", &"charge", &"skid", &"dazed"],
	"heavy_gunner": [&"patrol", &"spin_up", &"fire", &"vent"],
	"warden": [&"intro", &"idle", &"burst_windup", &"burst", &"leap_windup", &"leap", &"fan_windup", &"summon_windup", &"core_windup", &"core_recover", &"phase_shift"],
}
const FIXED_DT := 1.0 / 60.0
const GAMEPLAY_VIEWPORT := Vector2i(1280, 720)
const DETAIL_VIEWPORT := Vector2i(1536, 1400)

var _checks := 0
var _failures: Array[String] = []
var _level: Level
var _output := ""
var _capture_enabled := false
var _probe_one := false
var _sample_serial := 0
var _baseline_entity_ids: Dictionary[int, bool] = {}
var _initial_scale_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
var _initial_window_size := GAMEPLAY_VIEWPORT
var _initial_viewport_size := Vector2i(640, 360)
const PROVENANCE_FILES := [
	"res://game/enemies/warden_boss.gd",
	"res://game/enemies/enemy.gd",
	"res://game/rig/character_rig.gd",
	"res://data/enemies/warden.tres",
]


func _ready() -> void:
	print("CAPTURE_FIXTURE_READY")
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	_initial_scale_mode = get_window().content_scale_mode
	_initial_window_size = get_window().size
	_initial_viewport_size = get_viewport().size
	var args := OS.get_cmdline_user_args()
	_probe_one = args.has("--probe-one")
	_capture_enabled = args.has("--capture")
	_output = _arg_value(args, "--out", "")
	_run.call_deferred()


func _run() -> void:
	print("CAPTURE_FIXTURE_RUN")
	if _capture_enabled and _output.is_empty():
		_fail("--capture requires --out=<absolute-directory>")
		_finish(1)
		return
	if _capture_enabled:
		var absolute := ProjectSettings.globalize_path(_output)
		if not absolute.is_absolute_path():
			_fail("capture output must resolve to an absolute path")
			_finish(1)
			return
		DirAccess.make_dir_recursive_absolute(absolute)
		_output = absolute

	await _start_level()
	if not is_instance_valid(_level) or not is_instance_valid(_level.player):
		_fail("actual Level fixture failed to construct")
		_finish(1)
		return

	var manifest := {
		"engine": Engine.get_version_info(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"graphics_api": ProjectSettings.get_setting("rendering/rendering_device/driver.windows", "unknown"),
		"checkout_head": _checkout_head(),
		"source_sha256": _source_hashes(),
		"capture_requested": _capture_enabled,
		"frames": [],
		"checks": 0,
		"failures": [],
	}
	_check(not str(manifest["checkout_head"]).is_empty(), "capture records the current checkout HEAD")
	_check((manifest["source_sha256"] as Dictionary).size() == PROVENANCE_FILES.size(),
		"capture records source hashes for Warden, Enemy, CharacterRig and Warden data")
	for skin in DATA_PATHS:
		if _probe_one and skin != "warden":
			continue
		print("CAPTURE_SKIN %s" % skin)
		var data := load(DATA_PATHS[skin]) as EnemyData
		_check(data != null, "%s EnemyData loads" % skin)
		if data == null:
			continue
		_check(data.validate().is_empty(), "%s EnemyData validates" % skin)
		for facing in [1, -1]:
			if _probe_one and facing != 1:
				continue
			var enemy := await _spawn_actual_enemy(data, facing)
			if enemy == null:
				continue
			_check(enemy.rig != null and enemy.rig.has_bone(&"chest"), "%s facing %d builds actual actor rig" % [skin, facing])
			_check(enemy.data.rig_weapon != "" and enemy.rig.weapon_def().size() > 0, "%s facing %d has configured weapon data" % [skin, facing])
			for state: StringName in STATE_LISTS[skin]:
				if _probe_one and state != &"leap_windup":
					continue
				_check(enemy.fsm.has(state), "%s runtime FSM contains %s" % [skin, state])
				if not enemy.fsm.has(state):
					continue
				if state == &"core_recover":
					enemy.fsm.transition(&"core_windup")
					for _frame in ceili((enemy.data.telegraph_time + 0.1) / FIXED_DT):
						if enemy.fsm.is_in(&"core_recover"):
							break
						await get_tree().physics_frame
					await _settle_actor()
					_check(enemy.fsm.is_in(&"core_recover"), "warden core windup advances through real FSM into recovery")
				else:
					enemy.fsm.transition(state)
					await _settle_actor()
				if _capture_enabled:
					var angles: Array[String] = ["level"]
					if _probe_one:
						angles = ["level"]
					elif state in [&"windup", &"spin_up", &"fire", &"burst_windup", &"burst", &"leap_windup", &"fan_windup", &"summon_windup", &"core_windup"]:
						angles = ["level", "above", "below"]
					for angle_name in angles:
						_set_target_angle(enemy, facing, angle_name)
						await _settle_actor()
						for zoom in ([3.4] if _probe_one else [1.0, 3.4]):
							manifest["frames"].append(await _capture_frame(enemy, skin, str(enemy.fsm.current), facing, zoom, angle_name, "actual-fsm"))
				if state == &"vent" and enemy is HeavyGunner:
					_check((enemy as HeavyGunner).is_armor_open(), "heavy_gunner vent enter opens armor through actual FSM")
				if state == &"core_recover" and str(enemy.data.id) == "warden":
					_check(_core_damage_scale(enemy) > 1.0, "warden core exposure is active through actual FSM handler")
				if state == &"patrol" and enemy is HeavyGunner:
					_check(not (enemy as HeavyGunner).is_armor_open(), "heavy_gunner patrol keeps armor closed")
				if state == &"dead":
					continue
			if _capture_enabled and not _probe_one:
				await _capture_damage_and_death(enemy, skin, facing, manifest)
			if enemy.get_parent() != null:
				enemy.get_parent().remove_child(enemy)
			enemy.free()
			_cleanup_capture_entities()
			await get_tree().process_frame
	await _end_level()
	manifest["checks"] = _checks
	manifest["failures"] = _failures.duplicate()
	if _capture_enabled:
		manifest["frame_count"] = manifest["frames"].size()
		manifest["unique_paths"] = _unique_frame_paths(manifest["frames"])
		_check(manifest["frame_count"] == manifest["unique_paths"], "capture manifest paths are unique")
		if _probe_one:
			_check(manifest["frame_count"] == 1, "single-frame probe writes exactly one image")
		for frame: Dictionary in manifest["frames"]:
			var relative_path := str(frame.get("path", ""))
			if relative_path.is_empty():
				_check(false, "capture frame is missing an output path")
				continue
			var image_path := _output.path_join(relative_path)
			_check(FileAccess.file_exists(image_path), "capture output exists: %s" % frame["path"])
			_check(FileAccess.get_sha256(image_path) == str(frame["image_sha256"]), "capture image hash matches manifest: %s" % frame["path"])
		manifest["checks"] = _checks
		manifest["failures"] = _failures.duplicate()
		var file := FileAccess.open(_output.path_join("manifest.json"), FileAccess.WRITE)
		if file == null:
			_fail("cannot write capture manifest")
		else:
			file.store_string(JSON.stringify(manifest, "\t"))
			file.close()
	print("NE79_80_81_ACTUAL_ENEMY_CAPTURE checks=%d failures=%d capture=%s" % [_checks, _failures.size(), str(_capture_enabled)])
	_finish(0 if _failures.is_empty() else 1)


func _start_level() -> void:
	print("CAPTURE_LEVEL_START")
	GameState.start_new_run(GameState.difficulties[1])
	var level_data := LevelData.new()
	level_data.id = &"ne79_80_81_native_capture"
	level_data.layout_path = LEVEL_LAYOUT
	level_data.show_chapter_card = false
	_level = Level.new()
	_level.configure(level_data)
	get_tree().root.add_child(_level)
	print("CAPTURE_LEVEL_ADDED")
	await get_tree().process_frame
	await get_tree().process_frame
	print("CAPTURE_LEVEL_FRAMES")
	for node in _level.get("_entities").get_children():
		_baseline_entity_ids[node.get_instance_id()] = true
	if is_instance_valid(_level.player):
		_level.player.health.setup(999, 0.0)
		_level.player.global_position = Vector2(160.0, 320.0)


func _spawn_actual_enemy(data: EnemyData, facing: int) -> Enemy:
	print("CAPTURE_SPAWN %s %d" % [data.id, facing])
	var enemy := _level._create_enemy(data)
	if enemy == null:
		_fail("Level._create_enemy returned null for %s" % data.id)
		return null
	enemy.position = Vector2(27.0 * 16.0, 20.0 * 16.0)
	_level.get("_entities").add_child(enemy)
	print("CAPTURE_ENEMY_ADDED %s" % data.id)
	await get_tree().physics_frame
	print("CAPTURE_ENEMY_PHYSICS %s" % data.id)
	if is_instance_valid(_level.camera):
		_level.camera.target = enemy
		_level.camera.snap_to_target()
	_level.player.global_position = enemy.global_position + Vector2(-facing * 150.0, -24.0)
	enemy.facing = facing
	await _settle_actor()
	if is_instance_valid(_level.camera):
		# LevelCamera restores its gameplay zoom on physics ticks; freeze only the
		# capture camera after it has tracked this real actor.
		_level.camera.set_physics_process(false)
	return enemy


func _capture_damage_and_death(enemy: Enemy, skin: String, facing: int, manifest: Dictionary) -> void:
	var samples := [ceili(enemy.health.max_health * 0.66), ceili(enemy.health.max_health * 0.33)]
	for target_hp in samples:
		if target_hp >= enemy.health.current or target_hp <= 0:
			continue
		var damage: int = enemy.health.current - int(target_hp)
		var info := DamageInfo.create(damage, Combat.Team.PLAYER, &"native_capture")
		info.ignore_invulnerability = true
		info.bypass_guard = true
		info.origin = enemy.global_position + Vector2(-enemy.facing * 24.0, -12.0)
		var accepted := enemy.hurtbox.receive(info)
		_check(accepted == Hurtbox.Result.DAMAGED, "%s actual hurtbox accepts deterministic capture damage" % skin)
		await _settle_actor()
		for zoom in [1.0, 3.4]:
			manifest["frames"].append(await _capture_frame(enemy, skin, "health_%d" % enemy.health.current, facing, zoom, "level", "actual-hurtbox"))
	var death := DamageInfo.create(enemy.health.current, Combat.Team.PLAYER, &"native_capture_death")
	death.ignore_invulnerability = true
	death.bypass_guard = true
	death.origin = enemy.global_position + Vector2(-enemy.facing * 24.0, -12.0)
	var died := enemy.hurtbox.receive(death)
	_check(died == Hurtbox.Result.DAMAGED and enemy.is_dying(), "%s actual hurtbox starts real death flow" % skin)
	await _settle_actor()
	for zoom in [1.0, 3.4]:
		manifest["frames"].append(await _capture_frame(enemy, skin, "dead", facing, zoom, "level", "actual-death"))


func _set_target_angle(enemy: Enemy, facing: int, angle_name: String) -> void:
	var target_offset := Vector2(-facing * 150.0, -24.0)
	match angle_name:
		"above":
			target_offset.y = -115.0
		"below":
			target_offset.y = 80.0
	_level.player.global_position = enemy.global_position + target_offset
	enemy.facing = facing


func _capture_frame(enemy: Enemy, skin: String, state: String, facing: int, zoom: float, angle_name: String, source: String) -> Dictionary:
	var detail_view := zoom > 1.0
	var window := get_window()
	var saved_mode := window.content_scale_mode
	var saved_window_size := window.size
	var saved_viewport_size: Vector2i = get_viewport().size
	if detail_view:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.size = DETAIL_VIEWPORT
		get_viewport().size = DETAIL_VIEWPORT
	else:
		window.size = GAMEPLAY_VIEWPORT
	_level.camera.target = enemy
	_level.camera.zoom = Vector2.ONE * zoom
	if detail_view:
		_level.camera.offset = Vector2.ZERO
		_level.camera.global_position = _actor_visual_bounds(enemy).get_center()
		_level.camera.reset_smoothing()
	else:
		_level.camera.snap_to_target()
	for _i in 2:
		await get_tree().process_frame
		await _await_capture_draw()
	var viewport_size := get_viewport().get_visible_rect().size
	var render_size: Vector2i = get_viewport().size
	var actor_bounds := _actor_visual_bounds(enemy)
	var actor_screen_bounds := _world_rect_to_screen(actor_bounds)
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var actor_fully_in_frame := viewport_rect.grow(-2.0).encloses(actor_screen_bounds)
	_check(actor_fully_in_frame, "%s/%s actor bounds fit viewport %.0fx%.0f at zoom %.1f (screen bounds %s)" % [
		skin, state, viewport_size.x, viewport_size.y, zoom, actor_screen_bounds])
	var viewport_texture := get_viewport().get_texture()
	var image := viewport_texture.get_image() if viewport_texture != null else null
	var expected_image_size := DETAIL_VIEWPORT if detail_view else GAMEPLAY_VIEWPORT
	var expected_visible_size := DETAIL_VIEWPORT if detail_view else Vector2i(640, 360)
	_check(window.size == expected_image_size, "window physical size is the requested capture size")
	_check(viewport_size == Vector2(expected_visible_size),
		"visible viewport is %s, expected %s after content-scale selection" % [viewport_size, expected_visible_size])
	var image_size := image.get_size() if image != null else Vector2i.ZERO
	_check(render_size == expected_image_size and image_size == expected_image_size,
		"capture viewport/render image size is %s / %s, expected %s" % [render_size, image_size, expected_image_size])
	if detail_view:
		_check(window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED,
			"detail viewport renders at native physical size with content scaling disabled")
	_sample_serial += 1
	var relative := "%s/%s_%s_f%d_z%.1f_s%04d_ft%s_at%s.png" % [
		skin, state, angle_name, facing, zoom, _sample_serial,
		_time_token(enemy.fsm.time_in_state), _time_token(enemy._rig_input.action_t)]
	var absolute := _output.path_join(relative)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var save_error := image.save_png(absolute) if image != null else ERR_UNAVAILABLE
	_check(save_error == OK and image_size.x > 0 and image_size.y > 0, "native screenshot saved for %s/%s" % [skin, state])
	var sprite := enemy.rig.get("_weapon_sprite") as Sprite2D if enemy.rig != null else null
	var camera_transform := _level.camera.global_transform
	var row := {
		"path": relative.replace("\\", "/"),
		"skin": skin,
		"enemy_data": str(enemy.data.resource_path),
		"state": state,
		"fsm_state": str(enemy.fsm.current),
		"fsm_time": enemy.fsm.time_in_state,
		"action": str(enemy._rig_input.action),
		"action_t": enemy._rig_input.action_t,
		"facing": facing,
		"requested_zoom": zoom,
		"camera_zoom": [_level.camera.zoom.x, _level.camera.zoom.y],
		"physical_window_size": [window.size.x, window.size.y],
		"viewport_size": [viewport_size.x, viewport_size.y],
		"viewport_render_size": [render_size.x, render_size.y],
		"content_scale_mode": window.content_scale_mode,
		"content_scale_size": [window.content_scale_size.x, window.content_scale_size.y],
		"viewport_canvas_transform": [
			[get_viewport().get_canvas_transform().x.x, get_viewport().get_canvas_transform().x.y],
			[get_viewport().get_canvas_transform().y.x, get_viewport().get_canvas_transform().y.y],
			[get_viewport().get_canvas_transform().origin.x, get_viewport().get_canvas_transform().origin.y],
		],
		"camera_framing": "diagnostic_actor_bounds" if detail_view else "level_camera_gameplay_context",
		"actor_bounds_world": [actor_bounds.position.x, actor_bounds.position.y, actor_bounds.size.x, actor_bounds.size.y],
		"actor_bounds_screen": [actor_screen_bounds.position.x, actor_screen_bounds.position.y, actor_screen_bounds.size.x, actor_screen_bounds.size.y],
		"actor_fully_in_frame": actor_fully_in_frame,
		"camera_global_transform": [
			[camera_transform.x.x, camera_transform.x.y],
			[camera_transform.y.x, camera_transform.y.y],
			[camera_transform.origin.x, camera_transform.origin.y],
		],
		"target_angle": angle_name,
		"health_ratio": enemy.health.ratio(),
		"armor_open": (enemy as HeavyGunner).is_armor_open() if enemy is HeavyGunner else false,
		"core_damage_scale": _core_damage_scale(enemy),
		"muzzle_world": [enemy._muzzle().x, enemy._muzzle().y],
		"weapon_sprite_visible": sprite != null and sprite.visible,
		"capture_source": source,
		"image_size": [image_size.x, image_size.y],
		"image_sha256": FileAccess.get_sha256(absolute) if save_error == OK else "",
	}
	if detail_view:
		window.content_scale_mode = saved_mode
		window.size = saved_window_size
		get_viewport().size = saved_viewport_size
		await get_tree().process_frame
		await _await_capture_draw()
	return row


func _actor_visual_bounds(enemy: Enemy) -> Rect2:
	var bounds := enemy.rig.visual_bounds() if enemy.rig != null else Rect2()
	var weapon := enemy.rig.get("_weapon_sprite") as Sprite2D if enemy.rig != null else null
	if weapon == null or not weapon.is_visible_in_tree() or weapon.texture == null:
		return bounds
	var rect := weapon.get_rect()
	var xf := weapon.get_global_transform()
	var points := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var weapon_bounds := Rect2(xf * points[0], Vector2.ZERO)
	for point in points:
		weapon_bounds = weapon_bounds.expand(xf * point)
	return weapon_bounds if not bounds.has_area() else bounds.merge(weapon_bounds)


func _world_rect_to_screen(bounds: Rect2) -> Rect2:
	var canvas := get_viewport().get_canvas_transform()
	var points := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	var result := Rect2(canvas * points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(canvas * point)
	return result


func _core_damage_scale(enemy: Enemy) -> float:
	if str(enemy.data.id) != "warden":
		return 1.0
	for part in enemy.hurtbox.parts:
		if part.part_id == &"core":
			return part.damage_scale
	return 1.0


func _settle_actor() -> void:
	for _i in 1:
		await get_tree().physics_frame
	if _capture_enabled:
		await _await_capture_draw()


func _await_capture_draw() -> void:
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


func _arg_value(args: PackedStringArray, name: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(name + "="):
			return arg.trim_prefix(name + "=")
	return fallback


func _checkout_head() -> String:
	var output: Array[String] = []
	var project_root := ProjectSettings.globalize_path("res://")
	var exit_code := OS.execute("git", PackedStringArray(["-C", project_root, "rev-parse", "HEAD"]), output, true)
	return output[0].strip_edges() if exit_code == 0 and not output.is_empty() else ""


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in PROVENANCE_FILES:
		if FileAccess.file_exists(path):
			hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
	return hashes


func _time_token(value: float) -> String:
	return ("%.3f" % value).replace("-", "m").replace(".", "p")


func _unique_frame_paths(frames: Array) -> int:
	var paths: Dictionary[String, bool] = {}
	for frame: Dictionary in frames:
		var path := str(frame.get("path", ""))
		if path.is_empty() or paths.has(path):
			return -1
		paths[path] = true
	return paths.size()


func _cleanup_capture_entities() -> void:
	var entities := _level.get("_entities") as Node
	if entities == null:
		return
	for node in entities.get_children():
		if _baseline_entity_ids.has(node.get_instance_id()):
			continue
		entities.remove_child(node)
		node.free()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("CAPTURE_FAIL: " + message)


func _end_level() -> void:
	for action in [&"move_right", &"shoot", &"jump", &"aim_right", &"aim_left", &"block"]:
		Input.action_release(action)
	if is_instance_valid(_level):
		get_tree().root.remove_child(_level)
		_level.free()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_window().content_scale_mode = _initial_scale_mode
	get_window().size = _initial_window_size
	get_viewport().size = _initial_viewport_size
	for _frame in 2:
		await get_tree().process_frame


func _finish(code: int) -> void:
	# Heavy vent and Warden core previews intentionally allocate brief pooled FX.
	# Let their documented lifetimes expire before the private process exits.
	await get_tree().create_timer(1.2, true, false, true).timeout
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	get_tree().quit(code)
