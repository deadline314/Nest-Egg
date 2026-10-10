extends Node

const LEVEL_MAP := "res://tests/fixtures/cover_map.json"
const ENEMY_DATA := "res://data/enemies/heavy_gunner.tres"
const FLOOR_Y := 320.0
const PLAYER_TILE := 18.0
const ENEMY_TILE := 24.0
const MAX_WAIT_FRAMES := 180
const VIEWPORT_CAPTURE := preload("res://tools/viewport_capture.gd")

var _started_msec := 0
var _capture_dir := ""
var _out_dir := ""
var _head_label := ""
var _capture_images := false
var _checks := 0
var _failures: Array[String] = []
var _events: Array[Dictionary] = []
var _markers: Array[String] = []
var _hurtbox_received: Array[Dictionary] = []
var _hurtbox_blocked: Array[Dictionary] = []
var _level: Level
var _enemy: Enemy
var _player_damage_events: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--head="):
			_head_label = arg.trim_prefix("--head=")
		elif arg == "--capture-images":
			_capture_images = true
	if _out_dir.is_empty() or not _out_dir.is_absolute_path():
		printerr("ERROR: require absolute --out=<fresh-empty-directory>")
		get_tree().quit(2)
		return
	if _head_label.length() != 40:
		printerr("ERROR: require --head=<actual 40-character git revision>")
		get_tree().quit(2)
		return
	var head_regex := RegEx.new()
	head_regex.compile("^[0-9a-fA-F]{40}$")
	if head_regex.search(_head_label) == null:
		printerr("ERROR: --head must be a 40-character hexadecimal git revision")
		get_tree().quit(2)
		return
	if DirAccess.dir_exists_absolute(_out_dir):
		if not DirAccess.get_files_at(_out_dir).is_empty() or not DirAccess.get_directories_at(_out_dir).is_empty():
			printerr("ERROR: --out directory must be empty: " + _out_dir)
			get_tree().quit(2)
			return
	else:
		var mkdir_error := DirAccess.make_dir_recursive_absolute(_out_dir)
		if mkdir_error != OK:
			printerr("ERROR: cannot create --out directory: " + error_string(mkdir_error))
			get_tree().quit(2)
			return
	if _capture_images:
		_capture_dir = _out_dir.path_join("images")
		var image_dir_error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if image_dir_error != OK:
			printerr("ERROR: cannot create capture directory: " + error_string(image_dir_error))
			get_tree().quit(2)
			return
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	EventBus.hit_marker.connect(_on_hit_marker)
	_record("start", {"head": _head_label, "case": "NE80", "capture_images": _capture_images,
		"level_fixture": LEVEL_MAP, "enemy_data": ENEMY_DATA})
	await _run_heavy_case()
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

func _spawn_enemy(enemy_path: String, enemy_tile: float) -> Enemy:
	var data := load(enemy_path) as EnemyData
	if data == null:
		_failures.append("EnemyData failed to load: %s" % enemy_path)
		return null
	var result := _level._create_enemy(data)
	if result == null:
		_failures.append("Level._create_enemy failed: %s" % enemy_path)
		return null
	result.position = Vector2(enemy_tile * 16.0, FLOOR_Y)
	_level._entities.add_child(result)
	_attach_hurtbox_trace(result)
	return result

func _run_heavy_case() -> void:
	await _open_level(&"ne80_organic_combat_probe")
	var player := _level.player
	player.health.setup(999, 0.0)
	if not player.health.damaged.is_connected(_on_player_damaged):
		player.health.damaged.connect(_on_player_damaged)
	player.global_position = Vector2(PLAYER_TILE * 16.0, FLOOR_Y)
	player.velocity = Vector2.ZERO
	_enemy = _spawn_enemy("res://data/enemies/heavy_gunner.tres", ENEMY_TILE)
	if _enemy == null:
		await _finish_level()
		return
	await _physics_frames(4)
	_record("NE80_spawned", {"player_position": _vec(player.global_position), "player_health": player.health.current,
		"enemy_position": _vec(_enemy.global_position), "enemy_health": _enemy.health.current,
		"fsm": String(_enemy.fsm.current), "facing": _enemy.facing, "rig_skin": String(_enemy.data.rig_skin)})
	_check(_enemy.rig != null and _enemy.rig.is_valid(), "heavy gunner uses its configured production rig in Level")
	var spinup := await _wait_state(&"spin_up", 180)
	_check(spinup, "heavy gunner patrol naturally acquires Player and starts spin_up")
	if not spinup:
		_record("NE80_abort", {"reason": "no natural spin_up", "state": String(_enemy.fsm.current)})
		await _finish_level()
		return
	_record("NE80_spin_up", {"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
		"armor_open": _enemy.is_armor_open(), "enemy_facing": _enemy.facing})
	await _capture("NE80_heavy_spin_up_armor_closed")

	var hp_before_block := _enemy.health.current
	var block_index := _markers.size()
	var blocked_shot := await _fire_at_enemy(player, _enemy.global_position + Vector2(0.0, -_enemy.data.body_size.y * 0.5), "NE80_closed_armor", true)
	var blocked := _markers.slice(block_index).has("blocked")
	_record("NE80_closed_armor_result", {"shot": blocked_shot, "markers": _markers.slice(block_index),
		"enemy_health_before": hp_before_block, "enemy_health_after": _enemy.health.current,
		"armor_open": _enemy.is_armor_open()})
	_check(blocked and _enemy.health.current == hp_before_block and not _enemy.is_armor_open(),
		"actual Player projectile is blocked by heavy gunner's closed front armor")

	var firing := await _wait_state(&"fire", 240)
	_check(firing, "heavy gunner naturally advances from spin_up into fire")
	if not firing:
		_record("NE80_abort", {"reason": "no natural fire", "state": String(_enemy.fsm.current)})
		await _finish_level()
		return
	var player_hp_before_burst := player.health.current
	_record("NE80_fire", {"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
		"shots_fired": _enemy.get("shots_fired"), "player_health_before": player_hp_before_burst})
	var vent := await _wait_heavy_vent(360)
	_check(vent, "heavy gunner naturally completes fire and enters armor-open vent")
	_record("NE80_vent", {"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
		"shots_fired": _enemy.get("shots_fired"), "armor_open": _enemy.is_armor_open(),
		"damage_scale": _enemy.hurtbox.damage_scale, "enemy_health": _enemy.health.current,
		"player_health_before": player_hp_before_burst, "player_health_after": player.health.current,
		"active_projectiles": ProjectilePool.active_count()})
	_check(vent and _enemy.is_armor_open(), "actual vent state exposes heavy gunner armor")
	_check(int(_enemy.get("shots_fired")) >= 13, "heavy gunner naturally emitted at least 13 rounds before vent")
	_check(player.health.current < player_hp_before_burst and not _player_damage_events.is_empty(), "heavy gunner projectile damages actual Player Hurtbox")
	await _capture("NE80_heavy_vent_after_natural_fire")
	if vent:
		# Controlled Player reposition within the real vent window keeps this a
		# short-travel production projectile test; the Enemy FSM/armor are untouched.
		player.global_position = _enemy.global_position + Vector2(float(_enemy.facing) * 5.0 * 16.0, 0.0)
		player.velocity = Vector2.ZERO
		await _physics_frames(1)
		var hp_before_vent_hit := _enemy.health.current
		var hit_index := _markers.size()
		var shot := await _fire_at_enemy(player, _enemy.global_position + Vector2(0.0, -_enemy.data.body_size.y * 0.5), "NE80_vent_damage", true)
		var marker_hit := _markers.slice(hit_index).has("hit") or _markers.slice(hit_index).has("weak")
		_record("NE80_vent_hit", {"shot": shot, "markers": _markers.slice(hit_index),
			"health_before": hp_before_vent_hit, "health_after": _enemy.health.current,
			"armor_open": _enemy.is_armor_open(), "damage_scale": _enemy.hurtbox.damage_scale})
		_check(marker_hit and _enemy.health.current < hp_before_vent_hit,
			"actual Player projectile damages heavy gunner through its open vent Hurtbox")
		await _capture("NE80_heavy_vent_player_hit")
	await _finish_level()

func _fire_at_enemy(player: Player, target: Vector2, label: String, follow_enemy := false, follow_part: Hurtbox = null) -> Dictionary:
	var result := {"label": label, "fired": false, "reload_started": false, "damage": 0, "marker": "", "health_before": _enemy.health.current}
	for _i in 180:
		if follow_part != null and is_instance_valid(follow_part):
			target = follow_part.center()
		elif follow_enemy and _enemy != null and is_instance_valid(_enemy):
			target = _enemy.global_position + Vector2(0.0, -_enemy.data.body_size.y * 0.5)
		if player.loadout.is_reloading():
			await get_tree().physics_frame
			continue
		if player._fire_cooldown_left > 0.0:
			await get_tree().physics_frame
			continue
		if player.loadout.mag_in(player.loadout.active_slot) <= 0:
			var reload_aim := (target - player.muzzle_position()).normalized()
			player.aim_dir = reload_aim
			player.facing = 1 if reload_aim.x >= 0.0 else -1
			player.call(&"_try_fire") # Real empty-mag behavior starts the production reload.
			result["reload_started"] = player.loadout.is_reloading()
			continue
		var direction := (target - player.muzzle_position()).normalized()
		player.aim_dir = direction
		player.facing = 1 if direction.x >= 0.0 else -1
		var markers_before := _markers.size()
		var health_before := _enemy.health.current
		var ammo_before := player.loadout.mag_in(player.loadout.active_slot)
		var muzzle := player.muzzle_position()
		player.call(&"_try_fire")
		result["fired"] = player.loadout.mag_in(player.loadout.active_slot) < ammo_before
		result["muzzle_world"] = _vec(muzzle)
		result["target_world"] = _vec(target)
		result["enemy_position_at_fire"] = _vec(_enemy.global_position) if _enemy != null and is_instance_valid(_enemy) else []
		result["ammo_before"] = ammo_before
		for _frame in 60:
			if _markers.size() > markers_before:
				break
			await get_tree().physics_frame
		var marker_events := _markers.slice(markers_before)
		result["marker"] = marker_events[0] if not marker_events.is_empty() else "timeout"
		result["health_after"] = _enemy.health.current
		result["damage"] = health_before - _enemy.health.current
		result["markers"] = marker_events
		_record("player_shot", result.duplicate(true))
		return result
	result["timeout"] = "player fire cooldown/reload not ready within 180 physics frames"
	_record("player_shot_timeout", result.duplicate(true))
	return result

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
	if not _capture_images or _capture_dir.is_empty():
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


func _on_player_damaged(info: DamageInfo) -> void:
	var entry := {"amount": info.amount, "source_id": String(info.source_id), "origin": _vec(info.origin),
		"player_health": _level.player.health.current if _level != null and is_instance_valid(_level) else -1,
		"enemy_fsm": String(_enemy.fsm.current) if _enemy != null and is_instance_valid(_enemy) else ""}
	_player_damage_events.append(entry)
	_record("player_hurtbox_damage", entry)

func _wait_heavy_vent(frame_limit: int) -> bool:
	var previous_shot_count := int(_enemy.get("shots_fired"))
	for _frame in frame_limit:
		if _enemy == null or not is_instance_valid(_enemy):
			return false
		if _enemy.fsm.current == &"vent":
			_record("natural_vent_reached", {"fsm_time": _enemy.fsm.time_in_state,
				"shots_fired": int(_enemy.get("shots_fired")), "player_health": _level.player.health.current,
				"player_damage_events": _player_damage_events.size(), "active_projectiles": ProjectilePool.active_count()})
			return true
		await get_tree().physics_frame
		var shot_count := int(_enemy.get("shots_fired"))
		if shot_count > previous_shot_count:
			for shot_number in range(previous_shot_count + 1, shot_count + 1):
				_record("enemy_projectile_fired", {"shot_number": shot_number,
					"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
					"enemy_position": _vec(_enemy.global_position), "muzzle_world": _vec(_enemy._muzzle()),
					"aim": _vec(_enemy.get("_aim")), "player_position": _vec(_level.player.global_position),
					"player_health": _level.player.health.current, "active_projectiles": ProjectilePool.active_count()})
			previous_shot_count = shot_count
	return _enemy != null and is_instance_valid(_enemy) and _enemy.fsm.current == &"vent"



func _sha(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _finish() -> void:
	var dependencies := {
		"fixture_script": "res://.godot/ne80-organic-delivery/heavy_preflight.gd",
		"fixture_scene": "res://.godot/ne80-organic-delivery/heavy_preflight.tscn",
		"level": "res://game/level/level.gd",
		"level_data": "res://data/scripts/level_data.gd",
		"physics_fixture": LEVEL_MAP,
		"enemy_data": ENEMY_DATA,
		"enemy_behavior": "res://game/enemies/heavy_gunner.gd",
		"enemy_base": "res://game/enemies/enemy.gd",
		"player": "res://game/player/player.gd",
		"weapon_system": "res://core/weapon_system.gd",
		"projectile": "res://game/projectiles/projectile.gd",
		"projectile_pool": "res://autoload/projectile_pool.gd",
		"hurtbox": "res://core/components/hurtbox.gd",
		"health_component": "res://core/components/health_component.gd",
		"heavy_projectile": "res://data/projectiles/heavy_gunner_shot.tres",
		"player_pistol": "res://data/weapons/pistol.tres",
		"player_pistol_projectile": "res://data/projectiles/pistol_shot.tres",
		"rig": "res://art/rigs/heavy_gunner.json",
		"weapon_visual_config": "res://art/weapons/weapons.json",
		"weapon_visual": "res://art/weapons/minigun.png",
		"weapon_normal": "res://art/weapons/minigun_n.png",
		"weapon_glow": "res://art/weapons/minigun_glow.png",
		"character": "res://art/characters/heavy_gunner/character.json",
	}
	var hashes: Dictionary = {}
	for key in dependencies:
		hashes[key] = _sha(dependencies[key])
	var texture_hashes: Dictionary = {}
	var missing_textures: Array[String] = []
	var skin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dependencies["character"]))
	for texture_key in skin.get("textures", {}):
		var texture: Dictionary = skin["textures"][texture_key]
		var files: Array[String] = []
		var required_files: Array[String] = []
		var diffuse := String(texture.get("file", ""))
		if not diffuse.is_empty():
			files.append(diffuse)
			required_files.append(diffuse)
			var stem := diffuse.trim_suffix(".png")
			files.append(stem + "_n.png")
			required_files.append(stem + "_n.png")
			var glow := String(texture.get("glow", ""))
			if not glow.is_empty():
				files.append(glow)
				files.append(glow.trim_suffix(".png") + "_n.png")
		for file_name in files:
			var path := "res://art/characters/heavy_gunner/" + file_name
			if FileAccess.file_exists(path):
				texture_hashes[path] = _sha(path)
			elif required_files.has(file_name):
				missing_textures.append(path)
	var output := {
		"head": _head_label,
		"case": "NE-80 heavy_gunner organic combat preflight",
		"capture_images": _capture_images,
		"level_fixture": LEVEL_MAP,
		"enemy_data": ENEMY_DATA,
		"godot": Engine.get_version_info(),
		"checks": _checks,
		"failures": _failures,
		"events": _events,
		"hurtbox_received": _hurtbox_received,
		"hurtbox_blocked": _hurtbox_blocked,
		"player_damage_events": _player_damage_events,
		"source_sha256": hashes,
		"character_texture_sha256": texture_hashes,
		"missing_character_textures": missing_textures,
		"elapsed_msec": Time.get_ticks_msec() - _started_msec,
	}
	var file := FileAccess.open(_out_dir.path_join("NE80-heavy-preflight.json"), FileAccess.WRITE)
	if file == null:
		printerr("ERROR: could not write NE80 private manifest: " + _out_dir)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("NE80_PREFLIGHT head=%s checks=%d failures=%d elapsed_msec=%d" % [_head_label, _checks, _failures.size(), Time.get_ticks_msec() - _started_msec])
	await get_tree().create_timer(0.2, true, false, true).timeout
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
