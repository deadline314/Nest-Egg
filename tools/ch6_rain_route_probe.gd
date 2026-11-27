extends "res://tools/ch6_lamp_control_probe.gd"
## Genuine forwarded/kept ST53 fixtures. --simulate-known-address adds one older fact in isolation.

const RAIN := "res://data/levels/ch6_rain_chase_alley.tres"
const PORCH := "res://data/levels/ch6_ali_homefront.tres"
const RAIN_BOARD := &"ch6_rain_route_board"
const EAVES := &"ch6_ali_eaves_door"
const PORCH_NOTE := &"ch6_ali_porch_note"
const DONE := &"ch6_ali_rain_arrival_resolved"
const ON_TIME := &"ch6_ali_rain_arrived_on_time"
const KNOWS := &"knows_ali_address"


func _write() -> void:
	if not await _resume_to(RECORDING):
		return
	var store := _main.get("_run_store") as RunSaveStore
	var before := store.read()
	var simulate_known := OS.get_cmdline_user_args().has("--simulate-known-address")
	if simulate_known:
		GameState.set_flag(KNOWS, true)
	if not await _portal(&"recording_relay", YARD):
		return
	var gate := _level._portals.get(&"relay_rain") as Portal
	_check(gate != null, "rain gate exists at the authored forecourt landing")
	if gate == null:
		return
	if not GameState.has_flag(RELAYED):
		_check(not gate.is_open() and not gate.try_use(), "keeping monitoring leaves the chase gate locked")
		_check(not GameState.has_flag(DONE), "no call publishes no arrival")
		return
	if not await _portal(&"relay_rain", RAIN):
		return
	var trial := _level.get_node_or_null("TraversalTrial")
	if trial == null:
		_check(false, "route trial was instantiated on the real alley")
		return
	_check_audit()
	_check(not _actor_present(EAVES) and not (_level._portals.get(&"rain_eaves_porch") as Portal).is_open(),
			"even a known address cannot open an unstarted route")
	if GameState.has_flag(KNOWS):
		if not await _known_route(trial, store):
			return
	else:
		await _service(RAIN_BOARD)
		_check(_played.has("ch6_t_ali_routes_public") and not _actor_present(EAVES),
				"the actual old slot without an address gets only the lit-street guidance")
		if not await _portal(&"rain_public_porch", PORCH):
			return
		await _service(PORCH_NOTE, ["leave"])
		await _service(PORCH_NOTE, ["hear"], &"ch6_t_ali_protective_arrival")
		_check(not GameState.has_flag(DONE), "exiting or skipping the porch response leaves arrival undecided")
		await _service(PORCH_NOTE, ["hear"])
		_check(_flag_is_saved(store, DONE) and not GameState.has_flag(ON_TIME)
				and store.read()["story"]["flags"][String(ON_TIME)] == false,
				"actual street reading saves the explicit protective outcome")
	_check_audit()
	if not await _portal(&"porch_market", RAIN):
		return
	if not await _portal(&"rain_relay", YARD):
		return
	var after := store.read()
	_check(after["story"]["items"] == before["story"]["items"] and after["progression"] == before["progression"]
			and after["runtime"]["loadout"] == before["runtime"]["loadout"] and after["story"]["deaths"] == before["story"]["deaths"],
			"market return retains items, receipts, credits, loadout and deaths")
	_check(not GameState.has_flag(&"ch6_broadcast_started") and _level.get_node_or_null("TraversalTrial") == null,
			"leaving the alley tears down the clock and preserves the off-air state")


func _known_route(trial: Node, store: RunSaveStore) -> bool:
	await _service(RAIN_BOARD, ["run"], &"ch6_t_ali_run_arm")
	_check(int(trial.get("_phase")) == 0, "cancelling instructions does not arm a route")
	await _service(RAIN_BOARD, ["run"])
	_check(int(trial.get("_phase")) == 1 and float(trial.get("_time_left")) == 23.0,
			"the short clock remains armed on the starting ground")
	await _settle(12)
	_check(float(trial.get("_time_left")) == 23.0, "the timer waits until Rin can reach the elevated start")
	await _grounded_tile(Vector2i(20, 17))
	_check(int(trial.get("_phase")) == 2 and float(trial.get("_time_left")) < 23.0,
			"the clock starts at the actual physical tread")
	var before_pause := float(trial.get("_time_left"))
	get_tree().paused = true
	await _settle(20)
	get_tree().paused = false
	_check(float(trial.get("_time_left")) == before_pause, "pause does not consume route time")
	trial.set("_time_left", 0.02)
	await _settle(10)
	_check(int(trial.get("_phase")) == 4 and not _actor_present(EAVES) and not GameState.has_flag(DONE),
			"an expired attempt can be retried and grants no arrival")
	await _service(RAIN_BOARD, ["guide"])
	_check(int(trial.get("_phase")) == 1 and float(trial.get("_time_left")) == 58.0,
			"the same grounded start offers the wider guidance clock")
	if OS.get_cmdline_user_args().has("--real-rain-run"):
		if not await _run_guided_treads():
			return false
	else:
		await _grounded_tile(Vector2i(20, 17))
		await _grounded_tile(Vector2i(30, 13))
		await _grounded_tile(Vector2i(50, 13))
		await _grounded_tile(Vector2i(63, 14))
	_check(int(trial.get("_phase")) == 3 and _actor_present(EAVES), "the grounded upper threshold stops the route clock and exposes consent")
	await _capture_interrupted_attempt(store)
	_check(not GameState.has_flag(DONE) and _actor_present(EAVES), "the player can leave the consent conversation pending")
	await _service(EAVES)
	_check(_flag_is_saved(store, DONE) and _flag_is_saved(store, ON_TIME),
			"the genuine eaves reply saves both on-time and resolved flags")
	if await _portal(&"rain_eaves_porch", PORCH):
		await _service(PORCH_NOTE)
		_check(_played.has("ch6_t_ali_porch_early"), "porch readback keeps Ali's actual selected outcome")
		return true
	return false


func _capture_interrupted_attempt(store: RunSaveStore) -> void:
	var owner := _object(EAVES)
	var settled := [false]
	var start := func() -> void:
		await owner._talk()
		settled[0] = true
	start.call()
	await _drive([], func() -> bool: return Story._current_cinematic == &"ch6_t_ali_at_eaves")
	await _settle(14)
	_check(store.read().get("cinematic") == "ch6_t_ali_at_eaves", "the genuine slot captures the interrupted upper reply")
	var path := _save_dir.get_base_dir().path_join("interrupted-slot")
	_check(DirAccess.make_dir_recursive_absolute(path) == OK
			and DirAccess.copy_absolute(store.path, path.path_join("slot.json")) == OK,
			"copied the actual interrupted checkpoint before exiting")
	Story.skip_cinematic()
	await _drive([], func() -> bool: return settled[0])


func _continue() -> void:
	if OS.get_cmdline_user_args().has("--interrupted-cold"):
		await _continue_interrupted()
		return
	if not await _resume_to(YARD):
		return
	var expected := OS.get_cmdline_user_args().has("--simulate-known-address")
	_check(GameState.has_flag(DONE) and GameState.has_flag(ON_TIME) == expected,
			"cold Continue restores the exact arrival branch and closes the unfinished clock")
	if await _portal(&"relay_rain", RAIN):
		var trial := _level.get_node_or_null("TraversalTrial")
		_check(trial != null and int(trial.get("_phase")) == 0 and not _actor_present(EAVES),
				"returning to a settled alley does not restart the deadline")
		if await _portal(&"rain_market", PORCH):
			await _service(PORCH_NOTE)
			var scene := "ch6_t_ali_porch_early" if expected else "ch6_t_ali_porch_protective"
			_check(_played.has(scene), "market-return readback restores the same safe branch")


func _continue_interrupted() -> void:
	if not await _resume_to(RAIN):
		return
	var trial := _level.get_node_or_null("TraversalTrial")
	_check(trial != null and int(trial.get("_phase")) == 0 and not _actor_present(EAVES),
			"cold interrupted route has a fresh clock and keeps the upper reply hidden")
	_check(not _played.has("ch6_t_ali_at_eaves") and not GameState.has_flag(DONE),
			"the uncompleted upper reply does not replay or grant a result")
	var board := _object(RAIN_BOARD)
	_check(board != null and _level.player.global_position.distance_to(board.global_position) <= 64.0,
			"cold interrupted route returns to the same alley's safe sign")
	await _service(RAIN_BOARD, ["guide"])
	_check(trial != null and int(trial.get("_phase")) == 1, "the player can rearm the route from the cold safe start")


## Exercise the actual jump and movement actions from the sign to the eaves.
func _run_guided_treads() -> bool:
	var stages := [
		[Vector2i(17, 17), true],
		[Vector2i(20, 17), false],
		[Vector2i(25, 15), true],
		[Vector2i(31, 13), true],
		[Vector2i(37, 12), true],
		[Vector2i(52, 13), false],
		[Vector2i(63, 14), false],
	]
	for index in stages.size():
		var stage: Array = stages[index]
		if not await _drive_tread(stage[0], stage[1]):
			return false
		if index == 3 and OS.get_cmdline_user_args().has("--rain-proof") and DisplayServer.get_name() != "headless":
			await _capture("ST-54-eaves")
	return true


func _drive_tread(cell: Vector2i, jump: bool) -> bool:
	var tile := float(_level._layout.tile_size)
	var goal := Vector2((float(cell.x) + 0.5) * tile, (cell.y + 1) * tile)
	var player: Player = _level.player
	_set_route_input(&"jump", jump)
	var reached := false
	for frame in 180:
		var offset := goal.x - player.global_position.x
		var going_left := offset < -4.0
		var going_right := offset > 4.0
		_set_route_input(&"move_left", going_left)
		_set_route_input(&"move_right", going_right)
		await get_tree().physics_frame
		if frame > 3 and not going_left and not going_right and player.is_on_floor() and absf(player.global_position.y - goal.y) < 2.0:
			reached = true
			break
	_set_route_input(&"jump", false)
	_set_route_input(&"move_left", false)
	_set_route_input(&"move_right", false)
	# Keep the release and the next press on separate physics ticks.
	await get_tree().physics_frame
	_check(reached, "real %s reached supporting tread %s from the previous one" % ["jump" if jump else "run", cell])
	return reached


func _set_route_input(action: StringName, active: bool) -> void:
	if active and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not active and Input.is_action_pressed(action):
		Input.action_release(action)


func _grounded_tile(cell: Vector2i) -> void:
	var tile := float(_level._layout.tile_size)
	_level.player.global_position = Vector2((float(cell.x) + .5) * tile, (cell.y + 1) * tile)
	_level.player.velocity = Vector2.ZERO
	await _settle(10)
	_check(_level.player.is_on_floor() and absf(_level.player.global_position.y - (cell.y + 1) * tile) < 2.0,
			"real tread supports the player at %s" % cell)
