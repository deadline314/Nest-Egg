extends "res://tools/ch4_work_lane_probe.gd"
## Formal route/save probe for the factory captain. The banked ST28 slot option
## uses a previously played work-lane route instead of replaying chapters 3–4.

const ARENA := "res://data/levels/ch4_factory_cleaning.tres"
const OFFICE := "res://data/levels/ch4_factory_office.tres"
const MID := &"ch4_atropos_midpoint_ready"
const GONE := &"ch4_egret_departed"
const DENIED := &"ch4_terminal_revival_denied"
const RETREATED := &"ch4_atropos_retreat_ready"
const RELEASED := &"ch4_office_access"
const COVER_GONE := &"ch4_arena_cover_erased"
const HANDOFF := &"ch4_t_egret_handoff"
const SIDE_HOST := &"ch4_egret_at_rail"
const RELEASE_HOST := &"ch4_office_release"
const TIMEOUT := 12000


func _write() -> void:
	if "--from-work" in OS.get_cmdline_user_args():
		var record := await _route_main.continue_game()
		_level = _route_main.level()
		_check(record.get("level") == WORK and is_instance_valid(_level) and GameState.has_flag(CROSSED),
			"the previously completed work area has a genuine arena route")
	else:
		await super._write()
	if _failures or not await _portal(&"work_arena", ARENA) or not await _wait_for_route_input():
		return
	_check(not (_level._portals[&"arena_office"] as Portal).try_use(), "the office cannot open before the fight")
	_check(_boss() != null and not GameState.has_flag(GONE), "the captain starts in phase one")
	await _ordinary_retry()
	_check(not GameState.has_flag(DENIED) and not GameState.has_flag(GONE), "ordinary defeat never commits Egret's result")
	if _failures or not await _reenter():
		return
	var boss := _boss()
	var cover := _arena_cover()
	_check(boss != null and cover != null and not cover.is_broken, "phase one starts with a real marked cover")
	if boss == null or cover == null:
		return
	var larger := _lower_lane()
	_check(larger != null and not larger.is_physics_processing(), "the work machinery is disarmed before the captain wakes")
	if larger == null:
		return
	var player := _level.player
	var camera := _level.camera
	if DisplayServer.get_name() != "headless":
		# Keep the complete combat warning in frame after the area card clears.
		await get_tree().create_timer(2.6, false).timeout
		var midpoint := (larger.global_position.x + boss.global_position.x) * 0.5
		camera.acquire_presentation_focus(self, Vector2(midpoint, boss.global_position.y - 54.0))
	player.teleport_to(Vector2(57.5 * _level._layout.tile_size, boss.global_position.y))
	camera.snap_to_target()
	_check(await _until(func() -> bool: return boss.is_awake()), "the captain wakes in the encounter on sight")
	_check(await _wait_state(larger, WorkSweep.State.WARNING), "the arena uses the earlier readable warning")
	await get_tree().create_timer(0.30, false).timeout
	_capture("atropos-arena")
	camera.release_presentation_focus(self)
	player.health.grant_invulnerability(35.0)
	_check(await _wait_state(larger, WorkSweep.State.LIVE) and cover.is_broken and GameState.has_flag(COVER_GONE),
		"the live sector erases exactly its marked barrier")
	_check(_floor_present(cover), "the load-bearing floor is still solid below the erased cover")
	_damage(boss)
	_check(await _until(func() -> bool: return Story._current_cinematic == HANDOFF), "the half-health boundary starts the registered handoff")
	_check(boss.health.current == int(boss.health.max_health * 0.5) and not boss.hurtbox.enabled
		and not larger.is_physics_processing(), "half health suspends damage and arena sectors")
	Story.reset_active_presentation(&"leave")
	await _settle(15)
	_check(not GameState.has_flag(GONE) and not GameState.has_flag(DENIED), "interruption keeps both atomic flags clear")
	var handoff_actor := _object(SIDE_HOST)
	_check(handoff_actor != null and handoff_actor.is_present(), "the real actor stays visible for a retry")
	if not await _talk(SIDE_HOST):
		return
	var stored := _read_slot()
	var flags: Dictionary = stored.get("story", {}).get("flags", {})
	_check(GameState.has_flag(MID) and boss.phase == 1 and boss.hurtbox.enabled, "the genuine result enables the second phase")
	_check(flags.get(String(GONE), false) and flags.get(String(DENIED), false) and flags.get(String(COVER_GONE), false),
		"one durable save preserves both handoff results and the removed cover")
	await _ordinary_retry()
	_check(GameState.has_flag(GONE) and not GameState.has_flag(RELEASED), "death in phase two never replays the handoff or opens the office")
	if await _reenter():
		var restarted := _boss()
		_check(restarted != null and restarted.phase == 1 and _arena_cover().is_broken, "retry starts phase two with stable floor and cover state")
		_check(_played.count(String(HANDOFF)) == 2, "only the cancelled and accepted handoff played")


func _continue() -> void:
	var saved := _read_slot()
	_check(saved.get("level") == ARENA, "the previous process exited in the unfinished arena")
	_main.call("_on_continue_requested")
	if not await _wait_level(SAFETY):
		_check(false, "cold continue recovers at the safe platform")
		return
	_level = _main_level()
	_check(await _wait_for_route_input(), "safe continue finishes loading")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_level.player.is_on_floor() and GameState.has_flag(GONE) and GameState.has_flag(DENIED)
		and GameState.has_flag(COVER_GONE), "the safe entry settles on solid ground with both durable results")
	if not await _reenter():
		return
	var boss := _boss()
	_check(boss != null and boss.phase == 1 and _arena_cover().is_broken and _played.count(String(HANDOFF)) == 0,
		"cold re-entry restores phase two without respawning cover or repeating the departure")
	if boss == null:
		return
	var player := _level.player
	player.health.grant_invulnerability(25.0)
	player.teleport_to(boss.global_position - Vector2(42, 0))
	_check(await _until(func() -> bool: return boss.is_awake()), "the restored captain can be fought")
	var event_count := [0]
	var exit_marked := [false]
	var mark_exit := func(id: StringName, value: Variant) -> void:
		if id == RETREATED and value == true:
			exit_marked[0] = absf(boss.global_position.x - float(boss.pattern.hooks["retreat_x"])) < 4.0
	GameState.flag_changed.connect(mark_exit)
	var boss_defeated := func() -> void: event_count[0] += 1
	EventBus.boss_defeated.connect(boss_defeated)
	_damage(boss)
	_check(await _until(func() -> bool: return GameState.has_flag(RETREATED)), "the captain reaches the right-hand exit alive")
	GameState.flag_changed.disconnect(mark_exit)
	_check(exit_marked[0], "the retreat flag is published at the actual shutter")
	await _settle(5)
	_check(_boss() == null and event_count[0] == 0 and not GameState.has_flag(RELEASED), "withdrawal leaves no corpse or global boss victory")
	EventBus.boss_defeated.disconnect(boss_defeated)
	await _talk(RELEASE_HOST)
	_check(GameState.has_flag(RELEASED), "the terminal preserves the withdrawal and opens the office")
	if await _portal(&"arena_office", OFFICE) and await _portal(&"office_arena", ARENA):
		_check(_boss() == null and _arena_cover().is_broken, "visiting the office and returning preserves the cleared arena")


func _ordinary_retry() -> void:
	var original := _level
	var deaths := GameState.deaths
	var lethal := DamageInfo.create(999, Combat.Team.ENEMY, &"factory_sweep")
	lethal.ignore_invulnerability = true
	_level.player.health.take_damage(lethal)
	_check(await _until(func() -> bool: return _find_death_screen() != null), "an ordinary defeat shows recovery options")
	var screen := _find_death_screen()
	if screen == null:
		return
	screen.retry_requested.emit()
	if not await _wait_level(SAFETY, original):
		_check(false, "retry returns to the safe platform")
		return
	_level = _main_level()
	_check(GameState.deaths == deaths + 1 and _level.player.health.current > 0, "only one death and recovery were counted")


func _reenter() -> bool:
	return await _portal(&"safety_work", WORK) and await _portal(&"work_arena", ARENA) and await _wait_for_route_input()


func _read_slot() -> Dictionary:
	return (_main.get("_run_store") as RunSaveStore).read()


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _boss() -> PatternBoss:
	for actor: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		if actor.data.id == &"atropos" and not actor.is_queued_for_deletion():
			return actor as PatternBoss
	return null


func _arena_cover() -> Breakable:
	for node: Node in get_tree().get_nodes_in_group(WorldState.GROUP):
		var cover := node as Breakable
		if cover != null and cover.data.id == &"ch4_arena_cover" and _level.is_ancestor_of(cover):
			return cover
	return null


func _lower_lane() -> Area2D:
	for node: Node in _level.find_children("*", "Area2D", true, false):
		var sector := node as Area2D
		if node.get_script() == WorkSweep and (sector.get("_profile") as MechanismData).id == &"ch4_arena_lower_sweep":
			return sector
	return null


func _damage(boss: PatternBoss) -> void:
	var shot := DamageInfo.create(boss.health.max_health * 2, Combat.Team.PLAYER, &"atropos_probe")
	shot.ignore_invulnerability = true
	boss.health.take_damage(shot)


func _capture(name: String) -> void:
	if name != "atropos-arena" or DisplayServer.get_name() == "headless":
		return
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(image.save_jpg(_out_dir.path_join(name + ".jpg"), 0.86) == OK, "captured the real arena warning")
