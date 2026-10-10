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
var _case_filter := "all"
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
		if arg.begins_with("--capture-out="):
			_capture_dir = arg.trim_prefix("--capture-out=")
		elif arg.begins_with("--case="):
			_case_filter = arg.trim_prefix("--case=").to_upper()
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	EventBus.hit_marker.connect(_on_hit_marker)
	_record("start", {"head": "212768fa4a98e9db5bb1b3f4c067ef6027c7547d"})
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
	if _case_filter == "NE79":
		_finish()
		return
	await _run_heavy_case()
	if _case_filter == "NE80":
		_finish()
		return
	await _run_warden_case()
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
	var vent := await _wait_state(&"vent", 360)
	_check(vent, "heavy gunner naturally completes fire and enters armor-open vent")
	_record("NE80_vent", {"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
		"shots_fired": _enemy.get("shots_fired"), "armor_open": _enemy.is_armor_open(),
		"damage_scale": _enemy.hurtbox.damage_scale, "enemy_health": _enemy.health.current,
		"player_health_before": player_hp_before_burst, "player_health_after": player.health.current,
		"active_projectiles": ProjectilePool.active_count()})
	_check(vent and _enemy.is_armor_open(), "actual vent state exposes heavy gunner armor")
	_check(player.health.current < player_hp_before_burst, "heavy gunner's actual fire projectile damages Player Hurtbox")
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


func _run_warden_case() -> void:
	await _open_level(&"ne81_organic_combat_probe")
	var player := _level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(PLAYER_TILE * 16.0, FLOOR_Y)
	player.velocity = Vector2.ZERO
	_enemy = _spawn_enemy("res://data/enemies/warden.tres", 30.0)
	if _enemy == null:
		await _finish_level()
		return
	await _physics_frames(4)
	_record("NE81_spawned", {"player_position": _vec(player.global_position), "player_health": player.health.current,
		"enemy_position": _vec(_enemy.global_position), "enemy_health": _enemy.health.current,
		"fsm": String(_enemy.fsm.current), "facing": _enemy.facing, "phase": _enemy.get("_phase"),
		"rig_skin": String(_enemy.data.rig_skin)})
	_check(_enemy.rig != null and _enemy.rig.is_valid(), "Warden uses its configured production rig in Level")

	# Cross the real 50% threshold with shots produced by Player._try_fire; no
	# direct health mutation and no private phase/FSM mutation is used.
	var shot_count := 0
	var confirmed_hits := 0
	while int(_enemy.get("_phase")) < 2 and shot_count < 75:
		var shot := await _fire_at_enemy(player, _enemy.global_position + Vector2(0.0, -_enemy.data.body_size.y * 0.5), "NE81_phase_damage", true)
		shot_count += 1 if bool(shot.get("fired", false)) else 0
		confirmed_hits += 1 if int(shot.get("damage", 0)) > 0 else 0
		if bool(shot.get("reload_started", false)):
			continue
		if not bool(shot.get("fired", false)):
			await _physics_frames(1)
	var phase := int(_enemy.get("_phase"))
	_record("NE81_phase_threshold", {"player_weapon": String(player.loadout.active_weapon().id),
		"shots_fired": shot_count, "confirmed_player_hits": confirmed_hits,
		"warden_health": _enemy.health.current, "warden_max_health": _enemy.health.max_health,
		"phase": phase, "fsm": String(_enemy.fsm.current), "player_health": player.health.current})
	_check(phase == 2 and _enemy.health.current <= floori(float(_enemy.health.max_health) / 2.0),
		"real Player damage naturally crosses Warden's half-health phase threshold")
	if phase < 2:
		_record("NE81_abort", {"reason": "phase threshold not reached by bounded actual fire"})
		await _finish_level()
		return

	var core_windup := await _wait_state(&"core_windup", 2400)
	_check(core_windup, "phase-two Warden naturally selects core_windup without forced state transitions")
	if not core_windup:
		_record("NE81_abort", {"reason": "natural attack selection did not reach core_windup", "state": String(_enemy.fsm.current)})
		await _finish_level()
		return
	_record("NE81_core_windup", {"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
		"telegraph": _enemy.is_telegraphing(), "phase": _enemy.get("_phase"),
		"core_world": _vec(_enemy.rig.bone(&"core_port").global_position),
		"active_projectiles_before": ProjectilePool.active_count(),
		"player_health_before_volley": player.health.current})
	await _capture("NE81_warden_core_windup")
	# Place only the test Player inside a short, unobstructed range before the
	# natural telegraph expires. The boss keeps its own target tracking/FSM.
	player.global_position = _enemy.global_position + Vector2(float(_enemy.facing) * 6.0 * 16.0, 0.0)
	player.velocity = Vector2.ZERO
	var core_projectiles_before := ProjectilePool.active_count()
	var player_hp_before_core_volley := player.health.current
	var core_part: Hurtbox = null
	for part: Hurtbox in _enemy.hurtbox.parts:
		if part.part_id == &"core":
			core_part = part
	_check(core_part != null, "Warden exposes the production core Hurtbox in phase two")
	var core_fire := await _wait_state(&"core_recover", 120)
	var active_after_fire := ProjectilePool.active_count()
	var core_recover_entry_state := String(_enemy.fsm.current)
	var core_recover_entry_scale := core_part.damage_scale if core_part != null else 0.0
	_record("NE81_core_recover_entry", {"fsm": core_recover_entry_state,
		"fsm_time": _enemy.fsm.time_in_state,
		"core_damage_scale": core_recover_entry_scale,
		"active_projectiles_before": core_projectiles_before,
		"active_projectiles_immediately_after_fire": active_after_fire,
		"enemy_position": _vec(_enemy.global_position),
		"player_position": _vec(player.global_position),
		"player_health": player.health.current})
	_check(core_fire and core_recover_entry_state == "core_recover" and is_equal_approx(core_recover_entry_scale, 2.0),
		"natural core windup enters recover with the actual core Hurtbox exposed")
	await _capture("NE81_warden_core_recover_entry")
	var player_hp_after_core_volley := player.health.current
	var volley_wait_frames := 0
	for _frame in 120:
		if player.health.current < player_hp_before_core_volley:
			break
		await get_tree().physics_frame
		volley_wait_frames += 1
	player_hp_after_core_volley = player.health.current
	_record("NE81_core_recover", {"fsm": String(_enemy.fsm.current), "fsm_time": _enemy.fsm.time_in_state,
		"core_damage_scale": core_part.damage_scale if core_part != null else 0.0,
		"active_projectiles_before": core_projectiles_before,
		"active_projectiles_immediately_after_fire": active_after_fire,
		"active_projectiles_at_end": ProjectilePool.active_count(),
		"projectile_delta_at_fire": active_after_fire - core_projectiles_before,
		"frames_until_player_damage": volley_wait_frames,
		"player_health_before_volley": player_hp_before_core_volley,
		"player_health_after_volley": player_hp_after_core_volley})
	_check(core_fire and active_after_fire >= core_projectiles_before + 3,
		"Warden's core windup fires three actual pooled projectiles")
	_check(player_hp_after_core_volley < player_hp_before_core_volley,
		"Warden's natural core volley hits the actual Player Hurtbox")
	await _capture("NE81_warden_core_volley_player_hit")
	if core_fire and core_part != null and _enemy.fsm.current == &"core_recover" and is_equal_approx(core_part.damage_scale, 2.0):
		player.global_position = _enemy.global_position + Vector2(float(_enemy.facing) * 4.0 * 16.0, 0.0)
		player.velocity = Vector2.ZERO
		await _physics_frames(1)
		var health_before_core_hit := _enemy.health.current
		var core_index := _markers.size()
		var hit_event_index := _hurtbox_received.size()
		var core_shot := await _fire_at_enemy(player, core_part.center(), "NE81_exposed_core_damage", false, core_part)
		var core_marker := _markers.slice(core_index).has("weak") or _markers.slice(core_index).has("hit")
		var part_hits := _hurtbox_received.slice(hit_event_index)
		var core_hit := false
		for hit_event: Dictionary in part_hits:
			if hit_event.get("part", "") == "core" and bool(hit_event.get("weak_hit", false)):
				core_hit = true
		_record("NE81_core_player_hit", {"shot": core_shot, "markers": _markers.slice(core_index),
			"health_before": health_before_core_hit, "health_after": _enemy.health.current,
			"core_damage_scale": core_part.damage_scale,
			"root_damage_scale": _enemy.hurtbox.damage_scale,
			"core_center_world": _vec(core_part.center()),
			"resolved_core_part": core_hit,
			"part_hit_events": part_hits})
		_check(core_marker and _enemy.health.current < health_before_core_hit and not part_hits.is_empty(),
			"actual Player projectile damages Warden during the naturally exposed-core recovery window")
		await _capture("NE81_warden_core_recover_player_hit")
	else:
		_record("NE81_core_player_hit_skipped", {"reason": "core recover ended before a controlled Player shot could be fired",
			"fsm": String(_enemy.fsm.current), "core_damage_scale": core_part.damage_scale if core_part != null else 0.0,
			"player_health": player.health.current})
		_check(false, "core-recovery Player shot window remains open after the natural volley hits")
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
	if _capture_dir.is_empty():
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
	var output := {
		"head": "212768fa4a98e9db5bb1b3f4c067ef6027c7547d",
		"case": "NE-79 enforcer / shield_rusher",
		"case_filter": _case_filter,
		"level_fixture": LEVEL_MAP,
		"enemy_data": ENEMY_DATA,
		"godot": Engine.get_version_info(),
		"checks": _checks,
		"failures": _failures,
		"events": _events,
		"source_sha256": {
			"fixture_script": FileAccess.get_sha256("res://.godot/ne79-ne80-ne81-organic-combat/enforcer_preflight.gd"),
			"fixture_scene": FileAccess.get_sha256("res://.godot/ne79-ne80-ne81-organic-combat/enforcer_preflight.tscn"),
			"level": FileAccess.get_sha256("res://game/level/level.gd"),
			"enemy_data": FileAccess.get_sha256(ENEMY_DATA),
			"heavy_data": FileAccess.get_sha256("res://data/enemies/heavy_gunner.tres"),
			"warden_data": FileAccess.get_sha256("res://data/enemies/warden.tres"),
			"enemy_behavior": FileAccess.get_sha256("res://game/enemies/shield_rusher.gd"),
			"heavy_behavior": FileAccess.get_sha256("res://game/enemies/heavy_gunner.gd"),
			"warden_behavior": FileAccess.get_sha256("res://game/enemies/warden_boss.gd"),
			"enemy_base": FileAccess.get_sha256("res://game/enemies/enemy.gd"),
			"player": FileAccess.get_sha256("res://game/player/player.gd"),
			"projectile": FileAccess.get_sha256("res://game/projectiles/projectile.gd"),
			"weapon_system": FileAccess.get_sha256("res://core/weapon_system.gd"),
			"projectile_pool": FileAccess.get_sha256("res://autoload/projectile_pool.gd"),
			"hurtbox": FileAccess.get_sha256("res://core/components/hurtbox.gd"),
			"pistol_data": FileAccess.get_sha256("res://data/weapons/pistol.tres"),
			"pistol_projectile": FileAccess.get_sha256("res://data/projectiles/pistol_shot.tres"),
			"physics_fixture": FileAccess.get_sha256("res://tests/fixtures/cover_map.json"),
		},
	}
	var file := FileAccess.open("res://.godot/ne79-ne80-ne81-organic-combat/enforcer-preflight.json", FileAccess.WRITE)
	if file == null:
		printerr("ERROR: could not write private combat manifest")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("COMBAT_PREFLIGHT checks=%d failures=%d elapsed_msec=%d" % [_checks, _failures.size(), Time.get_ticks_msec() - _started_msec])
	# Match the project smoke-test shutdown so delayed sounds and active audio
	# streams are released before Godot reports ObjectDB/resource leaks.
	await get_tree().create_timer(0.2, true, false, true).timeout
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
