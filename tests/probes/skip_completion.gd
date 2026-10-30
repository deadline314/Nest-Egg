extends "res://tests/probes/training_completion.gd"

func _run() -> void:
	_main = load("res://game/main.gd").new()
	var store := RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(8)
	if _mode in ["read", "cancel_read", "trained_read"]: _main.call("_on_continue_requested")
	else: _main.call("_on_start_requested", GameState.difficulties[1])
	for i in 600:
		if _level() != null and _level().is_initialized(): break
		await _frames(1)
	_check(_level() != null, "real Main initializes its original area")
	if _level() == null: await _done(); return
	await _frames(90)
	if _mode in ["read", "trained_read"]:
		_check(_level().data.resource_path == "res://data/levels/ch1_pawnshop.tres", "exact committed route cold-read enters the original supper destination")
		_check(GameState.has_flag(&"ch1_prologue_skipped") and GameState.has_flag(&"ch1_prologue_exit"), "cold accepted skip preserves both results")
		_check(GameState.has_flag(&"ch1_prologue_bench_done") == (_mode == "trained_read") and not GameState.has_flag(&"ch1_prologue_done"), "cold skip preserves genuine practice without inventing completion")
		await _shot("skip-cold")
		await _done()
		return
	await _finish_story()
	await _frames(8)
	if _mode == "trained":
		var bench := _station(&"ch1_training_workbench")
		await _walk_to(bench.global_position.x)
		await _finish_story()
		_check(GameState.has_flag(bench.data.done_flag), "original input completes practice before choosing skip")
	_main.call("_save_run")
	_before = FileAccess.get_file_as_bytes(store.path)
	FileAccess.open(_save_dir.path_join("original-primary.json"), FileAccess.WRITE).store_buffer(_before)
	_check(not _before.is_empty() and not GameState.has_flag(&"ch1_prologue_skipped"), "real original primary has no skip result")
	if _mode == "cancel_read":
		_check(_level().data.resource_path == "res://data/levels/ch1_prologue.tres" and not GameState.has_flag(&"ch1_prologue_exit"), "cancelled original primary stays in original unskipped practice")
		var bench := _station(&"ch1_training_workbench")
		await _walk_to(bench.global_position.x)
		_check(GameState.has_flag(bench.data.done_flag), "cancelled cold read can complete its actual original practice")
		await _done()
		return
	GameState.flag_changed.connect(func(flag: StringName, _value: Variant) -> void:
		if flag not in [&"ch1_prologue_skipped", &"ch1_prologue_exit"]: return
		var bytes := FileAccess.get_file_as_bytes(store.path)
		var saved := RunSaveCodec.decode(bytes.get_string_from_utf8())
		_observations.append(saved.has("data") and saved["data"]["level"] == "res://data/levels/ch1_pawnshop.tres"
			and saved["data"]["story"]["flags"].get("ch1_prologue_skipped", false)
			and saved["data"]["story"]["flags"].get("ch1_prologue_exit", false)
			and GameState.has_flag(&"ch1_prologue_skipped") and GameState.has_flag(&"ch1_prologue_exit"))
		FileAccess.open(_save_dir.path_join("result-primary.json"), FileAccess.WRITE).store_buffer(bytes)
		_main.call("_show_main_menu")
		_check(_level() != null and _level().data.resource_path == "res://data/levels/ch1_prologue.tres", "flag notification cannot replace its publishing source screen"))
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "real IO obstruction created")
	var source := _level()
	var pause := InputEventAction.new()
	pause.action = &"pause"
	pause.pressed = true
	Input.parse_input_event(pause)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await _frames(2)
	pause = InputEventAction.new()
	pause.action = &"pause"
	Input.parse_input_event(pause)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await _frames(2)
	_check(source._pause_menu._root.visible, "actual pause action opens its menu")
	if not source._pause_menu._root.visible:
		DirAccess.remove_absolute(store.path + ".tmp")
		await _done()
		return
	source._pause_menu._skip_button.pressed.emit()
	await _frames(2)
	_check(source._pause_menu._skip_confirm != null, "original short press asks for skip confirmation")
	source._pause_menu._confirm_skip()
	await _frames(8)
	_check(not GameState.has_flag(&"ch1_prologue_skipped") and not GameState.has_flag(&"ch1_prologue_exit"), "refused skip cannot publish skipped or exit results")
	_check(FileAccess.get_file_as_bytes(store.path) == _before, "refused skip leaves exact original primary")
	_check(_level() == source, "refused skip stays in original area")
	_check(_prompt() != null and get_tree().paused and not source._finished, "refused skip holds the original live area and offers recovery")
	_check(_observations.is_empty(), "refused skip emits no accepted flag notifications")
	var pending := _prompt()
	source._skip_area()
	_check(_prompt() == pending and not GameState.has_flag(&"ch1_prologue_skipped"), "duplicate confirmation cannot replace or publish the pending skip")
	await _shot("skip-refused")
	if _mode == "stale":
		var portal := source._portals.get(source.data.skip_portal) as Portal
		var original := portal.data
		portal.data = original.duplicate(true)
		portal.data.target_portal = &"tool_changed_destination"
		if _prompt() != null: _prompt().get("retry_button").pressed.emit()
		await _frames(4)
		_check(_prompt() == null and not source._finished and _level() == source, "changed original route loses its pending source ownership")
		_check(not GameState.has_flag(&"ch1_prologue_skipped") and FileAccess.get_file_as_bytes(store.path) == _before and _observations.is_empty(), "stale route cannot grant or save a skip")
		portal.data = original
		_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only owned stale-route obstruction")
		await _done()
		return
	if _mode == "cancel":
		if _prompt() != null: _prompt().get("cancel_button").pressed.emit()
		await _frames(4)
		_check(_prompt() == null and not get_tree().paused and not source._finished and _level() == source, "cancel returns control to the original practice")
		_check(not GameState.has_flag(&"ch1_prologue_skipped") and FileAccess.get_file_as_bytes(store.path) == _before and _observations.is_empty(), "cancel leaves exact original bytes and no skip result")
		await _shot("skip-cancelled")
		_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only owned IO obstruction after cancellation")
		await _done()
		return
	if _prompt() != null: _prompt().get("retry_button").pressed.emit()
	await _frames(4)
	_check(_prompt() != null and not GameState.has_flag(&"ch1_prologue_skipped") and FileAccess.get_file_as_bytes(store.path) == _before, "second refusal preserves the same original progress")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only owned IO obstruction")
	if _prompt() != null: _prompt().get("retry_button").pressed.emit()
	await _frames(8)
	_check(GameState.has_flag(&"ch1_prologue_skipped") and GameState.has_flag(&"ch1_prologue_exit"), "successful retry accepts the authored skip exactly once")
	_check(_level() != source and _level().data.resource_path == "res://data/levels/ch1_pawnshop.tres", "saved skip enters the original destination without a second route write")
	_check(_observations == [true, true], "each result observer sees both accepted flags and the durable destination")
	_check(GameState.has_flag(&"ch1_prologue_bench_done") == (_mode == "trained") and not GameState.has_flag(&"ch1_prologue_done"), "skipping preserves genuine practice without inventing completion")
	await _shot("skip-saved")
	await _done()

func _prompt() -> Control:
	var owner: Variant = _main.get("_skip_completion")
	return owner.get("_prompt") as Control if owner is Node else null
