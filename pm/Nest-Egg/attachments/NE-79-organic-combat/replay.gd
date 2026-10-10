extends Node

const LEVEL_MAP := "res://tests/fixtures/cover_map.json"
const ENEMY_DATA := "res://data/enemies/shield_rusher.tres"
const FLOOR_Y := 320.0
const PLAYER_TILE := 18.0
const ENEMY_TILE := 24.0
const MAX_WAIT_FRAMES := 180
const VIEWPORT_CAPTURE := preload("res://tools/viewport_capture.gd")

var _started_msec := 0
var _capture_dir := ""
var _head_label := "unspecified"
var _capture_images := false
var _checks := 0
var _failures: Array[String] = []
var _events: Array[Dictionary] = []
var _markers: Array[String] = []
var _hurtbox_received: Array[Dictionary] = []
var _hurtbox_blocked: Array[Dictionary] = []
var _level: Level
var _enemy: Enemy


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_capture_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--head="):
			_head_label = arg.trim_prefix("--head=")
		elif arg == "--capture-images":
			_capture_images = true
	if _capture_dir.is_empty() or not _capture_dir.is_absolute_path():
		printerr("ERROR: pass --out=<fresh absolute output directory>")
		get_tree().quit(2)
		return
	var output_dir := DirAccess.open(_capture_dir)
	if output_dir != null and (not output_dir.get_files().is_empty() or not output_dir.get_directories().is_empty()):
		printerr("ERROR: --out directory must be fresh and empty: " + _capture_dir)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	EventBus.hit_marker.connect(_on_hit_marker)
	_record("start", {"head": _head_label})
	await _open_level(&"ne79_organic_combat_probe")
	if _level == null or _level.player == null:
		_failures.append("Level failed to create its actual Player")
		_finish()
		return

	var player := _level.player
	player.health.setup(12, 0.0)
	player.global_position = Vector2(PLAYER_TILE * 16.0, FLOOR_Y)
	player.velocity = Vector2.ZERO
	var enemy_data := load(ENEMY_DATA) as EnemyData
	if enemy_data == null:
		_failures.append("EnemyData failed to load: %s" % ENEMY_DATA)
		_finish()
		return
	_enemy = _level._create_enemy(enemy_data)
	if _enemy == null:
		_failures.append("Level._create_enemy failed for %s" % ENEMY_DATA)
		_finish()
		return
	_enemy.position = Vector2(ENEMY_TILE * 16.0, FLOOR_Y)
	_level._entities.add_child(_enemy)
	_attach_hurtbox_trace(_enemy)
	await _physics_frames(4)
	_record("spawned", {
		"player_position": _vec(player.global_position),
		"player_health": player.health.current,
		"enemy_id": String(_enemy.data.id),
		"enemy_position": _vec(_enemy.global_position),
		"enemy_health": _enemy.health.current,
		"enemy_fsm": String(_enemy.fsm.current),
		"enemy_facing": _enemy.facing,
		"enemy_shield_layers": _enemy.shield,
		"uses_actual_rig": _enemy.rig != null,
	})
	_check(_enemy.rig != null and _enemy.rig.is_valid(), "enforcer spawned with its configured production rig")
	_check(_enemy.fsm.current == &"patrol" or _enemy.fsm.current == &"windup", "enemy starts in its actual patrol/aggro path (%s)" % _enemy.fsm.current)

	var entered_windup := await _wait_state(&"windup", MAX_WAIT_FRAMES)
	_check(entered_windup, "natural AI sees the Player and enters windup")
	if not entered_windup:
		_record("preflight_abort", {"reason": "natural patrol did not acquire player", "state": String(_enemy.fsm.current)})
		await _finish_level()
		_finish()
		return
	_record("natural_windup", {"enemy_fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state, "enemy_facing": _enemy.facing})
	await _capture("NE79_enforcer_windup")

	var markers_before := _markers.size()
	var enemy_hp_before_block := _enemy.health.current
	var ammo_before := player.loadout.mag_in(player.loadout.active_slot)
	var player_weapon := player.loadout.active_weapon()
	player.aim_dir = (_enemy.global_position - player.muzzle_position()).normalized()
	player.facing = 1 if player.aim_dir.x >= 0.0 else -1
	var muzzle := player.muzzle_position()
	var hit_from_side := signf(muzzle.x - _enemy.global_position.x)
	_record("front_fire_request", {
		"player_weapon": String(player_weapon.id) if player_weapon != null else "<none>",
		"projectile_spec": String(player_weapon.projectile.resource_path) if player_weapon != null and player_weapon.projectile != null else "<none>",
		"muzzle_world": _vec(muzzle),
		"player_aim": _vec(player.aim_dir),
		"enemy_facing": _enemy.facing,
		"origin_side_sign": hit_from_side,
		"health_before": enemy_hp_before_block,
		"ammo_before": ammo_before,
	})
	_check(hit_from_side == float(_enemy.facing), "blocked probe originates on the enemy's actual facing side")
	player.call(&"_try_fire")
	await _wait_marker(&"blocked", 30, markers_before)
	var blocked_seen := _markers.slice(markers_before).has("blocked")
	_record("front_projectile_result", {
		"markers": _markers.slice(markers_before),
		"enemy_health_before": enemy_hp_before_block,
		"enemy_health_after": _enemy.health.current,
		"ammo_before": ammo_before,
		"ammo_after": player.loadout.mag_in(player.loadout.active_slot),
		"projectile_active_count": ProjectilePool.active_count(),
		"result": "blocked" if blocked_seen else "no blocked marker",
	})
	_check(blocked_seen, "Player._try_fire creates a real projectile that the shield_rusher guard blocks")
	_check(_enemy.health.current == enemy_hp_before_block, "front projectile block leaves enemy HP unchanged")
	_check(player.loadout.mag_in(player.loadout.active_slot) < ammo_before, "blocked shot consumed ammo through the real Player/WeaponSystem path")

	var entered_charge := await _wait_state(&"charge", MAX_WAIT_FRAMES)
	_check(entered_charge, "natural telegraph completes and enemy enters charge without forced FSM transition")
	_record("natural_attack", {"enemy_fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state, "player_health": player.health.current})
	var player_hp_before_attack := player.health.current
	var reached_skid := await _wait_state(&"skid", MAX_WAIT_FRAMES)
	_record("attack_end", {
		"enemy_fsm": String(_enemy.fsm.current),
		"player_health_before": player_hp_before_attack,
		"player_health_after": player.health.current,
		"enemy_position": _vec(_enemy.global_position),
		"enemy_velocity": _vec(_enemy.velocity),
	})
	_check(reached_skid, "charge ends in the actual skid state")
	_check(player.health.current < player_hp_before_attack, "natural charge/contact hits the actual Player Hurtbox")
	await _capture("NE79_enforcer_charge_skid")

	# The second shot is a controlled rear-side hit setup: the actor's FSM remains
	# naturally active; only the test Player's position is moved to exercise the
	# real rear guard/Hurtbox route without changing Enemy state or guard code.
	var moved_player := Vector2(_enemy.global_position.x + 6.0 * 16.0, FLOOR_Y)
	player.global_position = moved_player
	player.velocity = Vector2.ZERO
	await _physics_frames(2)
	var rear_target := _enemy.global_position + Vector2(0.0, -_enemy.data.body_size.y * 0.5)
	player.aim_dir = (rear_target - player.muzzle_position()).normalized()
	player.facing = -1
	var rear_side_sign := signf(player.muzzle_position().x - _enemy.global_position.x)
	var enemy_hp_before_rear := _enemy.health.current
	var rear_markers_before := _markers.size()
	_record("rear_fire_request", {
		"player_position": _vec(player.global_position),
		"muzzle_world": _vec(player.muzzle_position()),
		"enemy_facing": _enemy.facing,
		"origin_side_sign": rear_side_sign,
		"state": String(_enemy.fsm.current),
		"enemy_health_before": enemy_hp_before_rear,
	})
	_check(rear_side_sign != float(_enemy.facing), "rear hit probe originates opposite the enemy's actual facing")
	player.call(&"_try_fire")
	await _wait_marker(&"hit", 30, rear_markers_before)
	var damaged_marker := _markers.slice(rear_markers_before).has("hit") or _markers.slice(rear_markers_before).has("weak")
	_record("rear_projectile_result", {
		"markers": _markers.slice(rear_markers_before),
		"enemy_health_before": enemy_hp_before_rear,
		"enemy_health_after": _enemy.health.current,
		"result": "damaged" if _enemy.health.current < enemy_hp_before_rear else "unchanged",
	})
	_check(damaged_marker and _enemy.health.current < enemy_hp_before_rear, "real Player projectile damages enemy from the rear via Hurtbox")
	await _capture("NE79_enforcer_rear_hit")

	await _finish_level()
	_finish()

func _open_level(level_id: StringName) -> void:
	if not EventBus.hit_marker.is_connected(_on_hit_marker):
		EventBus.hit_marker.connect(_on_hit_marker)
	GameState.start_new_run(GameState.difficulties[1])
	var level_data := LevelData.new()
	level_data.id = level_id
	level_data.layout_path = LEVEL_MAP
	_level = Level.new()
	_level.configure(level_data)
	get_tree().root.add_child(_level)
	await _physics_frames(4)
	_check(_level.player != null, "%s Level created an actual Player" % level_id)

func _wait_state(state: StringName, frame_limit: int) -> bool:
	for _i in frame_limit:
		if _enemy == null or not is_instance_valid(_enemy):
			return false
		if _enemy.fsm.current != state:
			await get_tree().physics_frame
			if _enemy.fsm.current != state:
				continue
		_record("fsm_state", {"state": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state, "enemy_position": _vec(_enemy.global_position)})
		return true
	return _enemy != null and _enemy.fsm.current == state

func _wait_marker(kind: StringName, frame_limit: int, from_index: int) -> void:
	for _i in frame_limit:
		if _markers.slice(from_index).has(String(kind)):
			return
		await get_tree().physics_frame

func _on_hit_marker(kind: StringName) -> void:
	_markers.append(String(kind))
	_record("hit_marker", {"kind": String(kind)})

func _attach_hurtbox_trace(enemy: Enemy) -> void:
	if enemy.hurtbox == null:
		return
	if not enemy.hurtbox.hit_received.is_connected(_on_enemy_hit_received):
		enemy.hurtbox.hit_received.connect(_on_enemy_hit_received)
	if not enemy.hurtbox.hit_blocked.is_connected(_on_enemy_hit_blocked):
		enemy.hurtbox.hit_blocked.connect(_on_enemy_hit_blocked)
	for part: Hurtbox in enemy.hurtbox.parts:
		if not part.hit_received.is_connected(_on_enemy_hit_received):
			part.hit_received.connect(_on_enemy_hit_received)
		if not part.hit_blocked.is_connected(_on_enemy_hit_blocked):
			part.hit_blocked.connect(_on_enemy_hit_blocked)

func _on_enemy_hit_received(info: DamageInfo) -> void:
	var hit := {"part": String(info.part), "weak_hit": info.weak_hit, "amount": info.amount,
		"source_id": String(info.source_id), "origin": _vec(info.origin)}
	_hurtbox_received.append(hit)
	_record("enemy_hurtbox_received", hit)

func _on_enemy_hit_blocked(info: DamageInfo) -> void:
	var blocked := {"part": String(info.part), "source_id": String(info.source_id), "origin": _vec(info.origin)}
	_hurtbox_blocked.append(blocked)
	_record("enemy_hurtbox_blocked", blocked)

func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame

func _capture(name: String) -> void:
	if not _capture_images:
		return
	var tree := get_tree()
	var was_paused := tree.paused
	var sim_before := {
		"enemy_fsm": String(_enemy.fsm.current) if _enemy != null and is_instance_valid(_enemy) else "",
		"enemy_fsm_time": _enemy.fsm.time_in_state if _enemy != null and is_instance_valid(_enemy) else -1.0,
		"enemy_position": _vec(_enemy.global_position) if _enemy != null and is_instance_valid(_enemy) else [],
		"player_position": _vec(_level.player.global_position) if _level != null and is_instance_valid(_level) and _level.player != null else [],
		"player_health": _level.player.health.current if _level != null and is_instance_valid(_level) and _level.player != null else -1,
	}
	# Freeze simulation while the native Forward+ renderer resolves the exact event frame.
	# The fixture script resumes on frame_post_draw; enemy/player state must remain fixed.
	tree.paused = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := VIEWPORT_CAPTURE.image(get_viewport())
	var path := _capture_dir.path_join(name + ".png")
	var error := image.save_png(path)
	var sim_after := {
		"enemy_fsm": String(_enemy.fsm.current) if _enemy != null and is_instance_valid(_enemy) else "",
		"enemy_fsm_time": _enemy.fsm.time_in_state if _enemy != null and is_instance_valid(_enemy) else -1.0,
		"enemy_position": _vec(_enemy.global_position) if _enemy != null and is_instance_valid(_enemy) else [],
		"player_position": _vec(_level.player.global_position) if _level != null and is_instance_valid(_level) and _level.player != null else [],
		"player_health": _level.player.health.current if _level != null and is_instance_valid(_level) and _level.player != null else -1,
	}
	tree.paused = was_paused
	var stable := sim_before == sim_after
	_check(stable, "%s native readback does not advance the combat simulation" % name)
	if error != OK:
		_failures.append("native capture failed (%s): %s" % [name, error_string(error)])
		printerr("ERROR: native capture failed (%s): %s" % [name, error_string(error)])
	else:
		_record("native_capture", {"name": name, "path": path, "size": [image.get_width(), image.get_height()],
			"simulation_frozen": stable, "simulation_before": sim_before, "simulation_after": sim_after})

func _finish_level() -> void:
	if EventBus.hit_marker.is_connected(_on_hit_marker):
		EventBus.hit_marker.disconnect(_on_hit_marker)
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		await _physics_frames(3)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: " + message)

func _record(kind: String, data: Dictionary) -> void:
	_events.append({"t_msec": Time.get_ticks_msec() - _started_msec, "event": kind, "data": data})

func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]

func _finish() -> void:
	var source_hashes := {
		"fixture_script": FileAccess.get_sha256("res://pm/Nest-Egg/attachments/NE-79-organic-combat/replay.gd"),
		"fixture_scene": FileAccess.get_sha256("res://pm/Nest-Egg/attachments/NE-79-organic-combat/replay.tscn"),
		"level": FileAccess.get_sha256("res://game/level/level.gd"),
		"enemy_data": FileAccess.get_sha256(ENEMY_DATA),
		"enemy_behavior": FileAccess.get_sha256("res://game/enemies/shield_rusher.gd"),
		"enemy_base": FileAccess.get_sha256("res://game/enemies/enemy.gd"),
		"player": FileAccess.get_sha256("res://game/player/player.gd"),
		"projectile": FileAccess.get_sha256("res://game/projectiles/projectile.gd"),
		"weapon_system": FileAccess.get_sha256("res://core/weapon_system.gd"),
		"projectile_pool": FileAccess.get_sha256("res://autoload/projectile_pool.gd"),
		"hurtbox": FileAccess.get_sha256("res://core/components/hurtbox.gd"),
		"pistol_data": FileAccess.get_sha256("res://data/weapons/pistol.tres"),
		"pistol_projectile": FileAccess.get_sha256("res://data/projectiles/pistol_shot.tres"),
		"physics_fixture": FileAccess.get_sha256(LEVEL_MAP),
		"character_json": FileAccess.get_sha256("res://art/characters/enforcer/character.json"),
		"rig_json": FileAccess.get_sha256("res://art/rigs/enforcer.json"),
	}
	var character := JSON.parse_string(FileAccess.get_file_as_string("res://art/characters/enforcer/character.json")) as Dictionary
	var texture_hashes: Dictionary = {}
	for texture_value: Variant in character.get("textures", {}).values():
		if not texture_value is Dictionary:
			continue
		for field: String in ["file", "glow"]:
			var relative_path := String(texture_value.get(field, ""))
			if relative_path.is_empty():
				continue
			var texture_path := "res://art/characters/enforcer/" + relative_path
			if FileAccess.file_exists(texture_path):
				texture_hashes[texture_path] = FileAccess.get_sha256(texture_path)
			if field == "file" and relative_path.ends_with(".png"):
				var normal_path := "res://art/characters/enforcer/" + relative_path.trim_suffix(".png") + "_n.png"
				if FileAccess.file_exists(normal_path):
					texture_hashes[normal_path] = FileAccess.get_sha256(normal_path)
	source_hashes["enforcer_texture_sources"] = texture_hashes
	var output := {
		"head": _head_label,
		"case": "NE-79 enforcer / shield_rusher",
		"level_fixture": LEVEL_MAP,
		"enemy_data": ENEMY_DATA,
		"godot": Engine.get_version_info(),
		"checks": _checks,
		"failures": _failures,
		"events": _events,
		"source_sha256": source_hashes,
	}
	var file := FileAccess.open(_capture_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		printerr("ERROR: could not write replay manifest into " + _capture_dir)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("COMBAT_PREFLIGHT checks=%d failures=%d elapsed_msec=%d" % [_checks, _failures.size(), Time.get_ticks_msec() - _started_msec])
	await get_tree().create_timer(0.2, true, false, true).timeout
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
