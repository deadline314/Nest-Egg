extends "res://tools/radio_freeze_probe.gd"
## Real Main, canonical radio, actual durable writer with a narrowly injected rename fault.
## This is an arranged street battle/save regression, not a full chapter playthrough.

const RECORDING := &"ch1_t_booth_recording"
const RECORDING_FLAG := &"ch1_recording_heard"
var _scenario := "retry"
var _filesystem_fault := false
var _fault_store: FaultStore

class FaultStore extends RunSaveStore:
	var refuse := false
	var mutate_after_commit := false
	var refuse_rollback := false
	func _durable_rename(absolute: String, phase: DurablePhase) -> Error:
		if refuse and phase == DurablePhase.PRIMARY_COMMITTED:
			return ERR_CANT_CREATE
		return super._durable_rename(absolute, phase)
	func _durable_rollback(absolute: String) -> Error:
		return ERR_CANT_CREATE if refuse_rollback else super._durable_rollback(absolute)
	func _durable_phase(phase: DurablePhase, _absolute: String) -> void:
		if mutate_after_commit and phase == DurablePhase.PRIMARY_COMMITTED:
			GameState.set_flag(&"ch1_street_route_open", true, false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_filesystem_fault = OS.get_cmdline_user_args().has("--filesystem-fault")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _scenario not in ["retry", "cancel", "death", "recovery", "continue", "continue-cancel", "rollback"] or not _save_dir.is_absolute_path():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_save_dir)
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_durable_run.call_deferred()


func _durable_run() -> void:
	Story.auto_skip = false
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_fault_store = FaultStore.new(_save_dir.path_join("slot.json"))
	# Observer runs while paused; the actual game must retain its normal pausable inheritance.
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	_main.set("_run_store", _fault_store)
	add_child(_main)
	await _frames(30)
	await _wait_route()
	if _scenario in ["continue", "continue-cancel"]:
		_main.call("_on_continue_requested")
		var continued := await _wait_street()
		_check(continued != null, "fresh Main continue restores the real street")
		var expected := _scenario == "continue"
		_check(GameState.has_flag(RECORDING_FLAG) == expected and Story.progress_snapshot().has(RECORDING) == expected, "fresh process restores the exact committed or canceled radio facts")
		_check(not GameplayLock.is_locked() and not get_tree().paused, "fresh continue has no radio/error lock")
		if not expected:
			_check(Story.play(RECORDING), "fresh process can play the previously canceled canonical radio")
			Story.reset_active_presentation(&"probe_cleanup")
		_finish()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _wait_route()
	for i in 180:
		Story.skip_cinematic()
		await _frames(1)
	_main.call("_on_area_requested", LEVEL)
	var level := await _wait_street()
	_check(level != null, "Main enters the canonical street")
	if level == null:
		_finish()
		return
	for i in 300:
		Story.skip_cinematic()
		await _read_all(Story._layer)
		await _frames(1)
		if not GameplayLock.is_locked() and not _main.call("_route_pending"):
			break
	# Arrange combat proximity, not story results or completion flags.
	level.player.health.setup(9999, 0.0)
	level.player.global_position.x = 96.0 * 16.0
	await _frames(15)
	await _read_all(Story._layer)
	AimInput.using_gamepad = true
	Input.action_press(&"aim_right")
	Input.action_press(&"shoot")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release(&"shoot")
	Input.action_release(&"aim_right")
	var bullets := ProjectilePool.container().get_children().filter(func(n: Node) -> bool: return n is Projectile and (n as Projectile).visible)
	_check(not bullets.is_empty(), "real player fire leaves a live projectile")
	_main.call("_save_run")
	var old_bytes := FileAccess.get_file_as_bytes(_fault_store.path)
	var old_flags := GameState.world_flags.duplicate(true)
	var old_seen := Story.progress_snapshot()
	var published := [0]
	var consistent := [true]
	var on_flag := func(flag: StringName, _value: Variant) -> void:
		if flag == RECORDING_FLAG:
			published[0] += 1
			var on_disk := _fault_store.read()
			consistent[0] = consistent[0] and Story.progress_snapshot().has(RECORDING) and on_disk.get("story", {}).get("seen", []).has(String(RECORDING))
	GameState.flag_changed.connect(on_flag)
	var navigation := QuestMapState.for_run()
	var nav_bytes := var_to_bytes(navigation.snapshot())
	var areas := GameState.area_states
	_fault_store.refuse_rollback = _scenario == "rollback"
	_fault_store.refuse = not _filesystem_fault
	Story.play(RECORDING)
	await _frames(3)
	var bullet := bullets[0] as Projectile if not bullets.is_empty() else null
	var bullet_at := bullet.global_position if bullet != null else Vector2.ZERO
	var enemies := _enemy_positions(level)
	var clock := GameState.run_time
	var health := level.player.health.current
	_check(not enemies.is_empty(), "the canonical street contains actual enemies")
	print("RADIO_WORLD_BEFORE ", JSON.stringify({"projectile": bullet.get_instance_id() if bullet != null else 0, "position": [bullet_at.x, bullet_at.y], "enemies": str(enemies), "clock": clock, "health": health}))
	await _shot("NE-246-canonical-reading")
	# Autosaves during reading are legitimate old-state writes. Capture the exact
	# durable boundary immediately before the final confirmation, not before reading.
	var layer: DialogueLayer = Story._layer
	for line_index in Story.resolved_lines(RECORDING).size():
		if not await _wait_radio_line(layer):
			break
		if line_index == Story.resolved_lines(RECORDING).size() - 1:
			_main.call("_flush_save")
			old_bytes = FileAccess.get_file_as_bytes(_fault_store.path)
			old_flags = GameState.world_flags.duplicate(true)
			old_seen = Story.progress_snapshot()
			if _filesystem_fault:
				_check(DirAccess.make_dir_absolute(_fault_store.path + ".tmp") == OK, "a real blocking temp directory refuses file writes")
		Input.parse_input_event(_key(true))
		await _frames(2)
		Input.parse_input_event(_key(false))
	await _frames(4)
	var gate: Node = _main.get("_radio_completion")
	if gate == null:
		_check(false, "a refused real writer opens persistent retry/cancel")
		_check(GameState.world_flags == old_flags and Story.progress_snapshot() == old_seen, "rejection publishes neither completion nor flags")
		_check(get_tree().paused, "save rejection keeps the world paused")
		GameState.flag_changed.disconnect(on_flag)
		_finish()
		return
	_check(gate.blocks_save() and is_instance_valid(gate.get("_prompt")), "a refused real writer opens persistent retry/cancel")
	var original_path := _fault_store.path + ".bak" if _scenario == "rollback" else _fault_store.path
	_check(FileAccess.get_file_as_bytes(original_path) == old_bytes, "rejected write preserves exact original primary or recovery backup bytes")
	_check(GameState.world_flags == old_flags and Story.progress_snapshot() == old_seen and published[0] == 0, "rejection publishes neither completion nor flags")
	await _frames(80)
	_main.call("_queue_save")
	_main.call("_save_run")
	await _frames(3)
	_check(FileAccess.get_file_as_bytes(original_path) == old_bytes, "background and explicit saves cannot bypass the pending gate")
	_check(bullet != null and bullet.global_position == bullet_at and _enemy_positions(level) == enemies, "the same live projectile and enemies stay frozen through rejection")
	_check(GameState.run_time == clock and level.player.health.current == health and get_tree().paused, "play clock, health and world remain paused through rejection")
	print("RADIO_WORLD_REJECTED ", JSON.stringify({"projectile": bullet.get_instance_id() if bullet != null else 0, "position": [bullet.global_position.x, bullet.global_position.y] if bullet != null else [], "enemies": str(_enemy_positions(level)), "clock": GameState.run_time, "health": level.player.health.current}))
	await _shot("NE-246-save-refused")
	var previous_level_id := level.get_instance_id()
	if _scenario == "rollback":
		_check(gate.get("_reload_original") and not gate.get("_recovery"), "failed rollback requests original progress without claiming a new commit")
		_fault_store.refuse = false
		_fault_store.refuse_rollback = false
		(gate.get("_prompt") as Control).get("retry_button").pressed.emit()
		_check(await _wait_restored(previous_level_id), "Main restores a new level and finishes its transition")
		_check(not GameState.has_flag(RECORDING_FLAG) and not Story.progress_snapshot().has(RECORDING), "real Main reloads original backup with the refused radio still unread")
		_check(not gate.blocks_save() and not GameplayLock.is_locked(), "original-backup reload clears the recovery lock")
	elif _scenario == "cancel":
		(gate.get("_prompt") as Control).get("cancel_button").pressed.emit()
		await _frames(2)
		_check(not gate.blocks_save() and not GameplayLock.is_locked(), "cancel releases only the owned recovery pause")
		_check(not GameState.has_flag(RECORDING_FLAG) and not Story.progress_snapshot().has(RECORDING), "cancel leaves the radio unfinished and replayable")
		_check(Story.play(RECORDING), "canceled canonical radio can play again")
		Story.reset_active_presentation(&"probe_cleanup")
	elif _scenario == "death":
		level.player.health.kill(DamageInfo.create(9999, Combat.Team.ENEMY, &"probe"))
		await _frames(2)
		_check(not gate.blocks_save() and int(gate.get("_lock")) == 0, "death cancels the pending result and releases its own lock")
		_check(not Story.progress_snapshot().has(RECORDING), "death during refused completion does not mark the radio read")
	else:
		_fault_store.refuse = false
		if _filesystem_fault:
			_check(DirAccess.remove_absolute(_fault_store.path + ".tmp") == OK, "remove only the probe-owned blocking directory before retry")
		_fault_store.mutate_after_commit = _scenario == "recovery"
		(gate.get("_prompt") as Control).get("retry_button").pressed.emit()
		if _scenario == "recovery":
			_check(gate.get("_recovery") and gate.blocks_save(), "post-commit source change offers committed-save recovery")
			_check(not (gate.get("_prompt") as Control).get("cancel_button").visible, "committed progress can never be canceled as an unsaved result")
			await _shot("NE-246-save-committed-recovery")
			_fault_store.mutate_after_commit = false
			(gate.get("_prompt") as Control).get("retry_button").pressed.emit()
			_check(await _wait_restored(previous_level_id), "Main restores a new level and finishes its transition")
			_check(GameState.has_flag(RECORDING_FLAG) and Story.progress_snapshot().has(RECORDING), "real Main restore installs the committed result")
		else:
			_check(GameState.has_flag(RECORDING_FLAG) and Story.progress_snapshot().has(RECORDING), "retry installs the exact saved flag and radio completion")
			_check(is_same(areas, GameState.area_states) and is_same(navigation, QuestMapState.for_run()) and var_to_bytes(navigation.snapshot()) == nav_bytes, "flag-only install retains area identity and all exploration")
		await _frames(2)
		_check(not gate.blocks_save() and not GameplayLock.is_locked(), "successful completion releases recovery without a stale lock")
		var saved := _fault_store.read()
		_check(saved.get("story", {}).get("flags", {}).get(String(RECORDING_FLAG), false) and saved.get("story", {}).get("seen", []).has(String(RECORDING)), "actual slot contains both completed facts")
	_check(published[0] == (1 if _scenario == "retry" else 0), "normal completion publishes one flag; whole-run restore and cancel retain their publication contracts")
	_check(consistent[0], "completion observers always see the already-saved complete story")
	GameState.flag_changed.disconnect(on_flag)
	_finish()


func _wait_route() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and _main.call("_route_pending"):
		await _frames(1)


func _wait_street() -> Level:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		var level := _main.get("_screen") as Level
		if level != null and level.data.resource_path == LEVEL and level.is_initialized() and not _main.call("_route_pending"):
			return level
		await _frames(1)
	return null


func _wait_restored(previous_id: int) -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		var current := _main.get("_screen") as Level
		if current != null and current.get_instance_id() != previous_id and current.data.resource_path == LEVEL and current.is_initialized() and not _main.call("_route_pending") and not GameplayLock.is_locked() and not get_tree().paused:
			return true
		await _frames(1)
	return false


func _finish() -> void:
	print("RADIO_DURABLE_PROBE scenario=%s failures=%d" % [_scenario, _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var root := Control.new()
	canvas.add_child(root)
	UiKit.fit_to_viewport(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var note := UiKit.label("通訊保存驗證：安排戰鬥位置；非整章通關", UiKit.FS_BODY, Palette.WARNING)
	note.position = Vector2(12, 338)
	root.add_child(note)
	await super._shot(name)
	canvas.queue_free()
