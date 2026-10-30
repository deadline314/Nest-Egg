extends "res://tests/probes/training_completion.gd"
## Explicit original warehouse/street fixtures, not a natural chapter playthrough.
## Positions and lethal health events are declared fixtures; no result flags are set.
var _actor: Node
var _flag := &"ch1_flood_gate_open"
var _channel := &"flood_c"
var _kind := "flood"
var _entry := Vector2.ZERO
var _source_key := ""
var _overlap_started := false

func _run() -> void:
	_kind = "boss" if _mode.begins_with("boss") else "encounter" if _mode.begins_with("encounter") else "flood"
	_flag = &"watchdog_defeated" if _kind == "boss" else &"ch1_street_route_open" if _kind == "encounter" else &"ch1_flood_gate_open"
	_channel = &"watchdog_gate" if _kind == "boss" else &"arena_street_blockade" if _kind == "encounter" else &"flood_c"
	if _mode.begins_with("overlap"):
		Story._scenes["test_channel_overlap"] = {"mode":"radio", "freeze":true, "lines":[{"speaker":"old_k", "text":"這是明示的重疊閱讀樣本。"}]}
	_main = load("res://game/main.gd").new()
	var store := RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(8)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		_check(_level() != null and _level().is_initialized(), "cold original primary restores its complete original area")
		if _mode in ["cancel_read", "death_read"]:
			await _frames(12)
			_check(not GameState.has_flag(_flag) and not _pit().triggered, "cancel/recovery cold read restores the unaccepted original mechanism and flag")
			_check(GameState.deaths == 0 and not _player().is_dead(), "original whole-run recovery never saves a partial death")
		else:
			_check(GameState.has_flag(_flag), "cold accepted primary preserves its actual world result")
			if _mode == "overlap_read":
				var position := _player().global_position
				for frame in range(120):
					if Story._layer.is_radio_frozen(): break
					await get_tree().process_frame
				print("COLD_FREEZE radio=", Story._layer.is_radio_frozen(), " before=", position, " after=", _player().global_position, " deaths=", GameState.deaths)
				_check(Story._layer.is_radio_frozen() and _player().global_position == position and GameState.deaths == 0, "cold important reading freezes before the flooded hazard gets any new physics")
				_check(not Story._completed.has(&"test_channel_overlap"), "cold exact primary retains its original unfinished dependent reading")
				await _read_radio()
				await get_tree().process_frame
				_check(Story._completed.has(&"test_channel_overlap") and _main.get("_cinematic") == "", "cold dependent reading completes the matching restored request")
			elif _mode == "route_read":
				await _frames(12)
				_check(_level().data.id == &"ch1_warehouse" and not _level()._resume.get("ending", false) and not _main.get("_chapter_complete"), "cold source-room result never becomes a fake chapter completion")
				_check(_pit().triggered and _gates_open(), "cold source-room result retains its actual accepted mechanism")
			elif _kind == "flood":
				_check(_pit().triggered and _gates_open(), "cold flood primary restores the matching plate and gate before any new physics")
			elif _kind == "boss":
				await _frames(4)
				_check(_boss() == null and _gates_open(), "cold boss primary restores the genuinely defeated actor and its open gate")
				_check(Story._layer._radio_active and not Story._completed.has(&"ch1_c11_watchdog"), "cold committed boss result retains its unread important explanation")
				await _read_radio()
				await _frames(4)
				_check(Story._completed.has(&"ch1_c11_watchdog") and _main.get("_cinematic") == "", "finishing the original resumed explanation retires its exact saved request")
			else:
				_check(_encounter().state == &"cleared", "cold encounter primary restores the actual cleared encounter")
		await _shot("channel-cold")
		await _done()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	if _mode == "overlap":
		# Explicit callback ordering fixture: the reading host opens before
		# Level receives the same real plate event.
		EventBus.mechanism_toggled.connect(func(channel: StringName, active: bool) -> void:
			if channel == _channel and active and not _overlap_started:
				_overlap_started = Story.play(&"test_channel_overlap"))
	if _mode in ["route", "route_retry"]:
		# Explicitly order a real open portal callback before Level receives
		# the plate signal. Both callbacks are from original registered nodes.
		EventBus.mechanism_toggled.connect(func(channel: StringName, active: bool) -> void:
			if channel != _channel or not active: return
			for portal: Portal in _level()._portals.values():
				if portal.is_open():
					portal.try_use()
					break)
	_main.call("_on_area_requested", "res://data/levels/ch1_street.tres" if _kind == "encounter" else "res://data/levels/ch1_warehouse.tres")
	await _frames(30)
	await _finish_story()
	await _read_radio()
	await _wait_control()
	_check(_level() != null and _level().is_initialized(), "explicit original area fixture is live under real Main")
	if _mode == "flood":
		for path: String in ["res://data/levels/ch2_ledger_office.tres", "res://data/levels/ch3_gate_hall.tres"]:
			var other := Level.new()
			other.configure(load(path))
			_check(not _main.get("_channel_completion").request(other, &"fixture", true), "unmigrated nonlethal boss contract retains its existing channel owner: " + path)
			other.free()
	_entry = _player().global_position
	_actor = _boss() if _kind == "boss" else _encounter() if _kind == "encounter" else _pit()
	_check(_actor != null and not GameState.has_flag(_flag), "original registered source starts without its result")
	if _actor == null: await _done(); return
	# Hold only fixture locomotion while the authored nearby reading is prepared.
	# Its real GUI completion is saved before the subsequent IO obstruction.
	_player().set_physics_process(false)
	if _kind != "boss": _player().global_position = _actor.global_position + Vector2(0, -16)
	await _frames(4)
	await _finish_story()
	await _read_radio()
	await _wait_control()
	_player().global_position = _entry
	_player().velocity = Vector2.ZERO
	_main.call("_save_run")
	_before = FileAccess.get_file_as_bytes(store.path)
	FileAccess.open(_save_dir.path_join("original-primary.json"), FileAccess.WRITE).store_buffer(_before)
	_check(not _before.is_empty() and DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "owned real IO obstruction begins after an ordinary complete original primary")
	GameState.flag_changed.connect(func(flag: StringName, value: Variant) -> void:
		if flag != _flag or value != true: return
		var bytes := FileAccess.get_file_as_bytes(store.path)
		var saved := RunSaveCodec.decode(bytes.get_string_from_utf8())
		var durable := false
		if saved.has("data"):
			var runtime: Dictionary = saved["data"]["runtime"]
			durable = runtime["area"]["consumed"].get(_source_key, false) if _kind == "boss" else runtime["world"].get(_actor.state_key(), false)
			for gate: Gate in _gate_nodes(): durable = durable and runtime["world"].get(gate.state_key(), false)
		_observations.append(saved.has("data") and saved["data"]["story"]["flags"].get(String(_flag), false) and durable and _gates_open())
		var source := _level()
		_main.call("_show_main_menu")
		_check(_level() == source and _main.get("_active_run"), "a result notification cannot replace its publishing original screen")
		FileAccess.open(_save_dir.path_join("result-primary.json"), FileAccess.WRITE).store_buffer(bytes))
	if _mode in ["route", "route_retry"]:
		GameState.flag_changed.connect(func(flag: StringName, value: Variant) -> void:
			if flag == _flag and value == true:
				_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "obstruct only the later destination write after accepting the world result"))
	if _mode == "forged":
		EventBus.mechanism_toggled.emit(_channel, true)
		await _frames(2)
		_check(not GameState.has_flag(_flag) and _prompt() == null, "raw forged channel cannot authorize an original live result")
		var duplicate := FloodPit.new()
		duplicate.configure(_pit().data, Vector2i.ZERO, 16)
		duplicate.position = _pit().position
		_level()._entities.add_child(duplicate)
		duplicate.trigger()
		await _frames(2)
		_check(not GameState.has_flag(_flag) and _prompt() == null, "unregistered duplicate cannot authorize its matching channel")
		duplicate.queue_free()
		await _frames(2)
		for gate: Gate in _gate_nodes(): gate.restore_state(false)
	if _kind == "boss":
		_source_key = _tracked_key(_actor)
		_check(not _source_key.is_empty(), "original boss belongs to the original map tracking identity")
		print("FIXTURE: apply a lethal health event to the original registered boss; not player combat acceptance")
		_actor.health.kill(DamageInfo.create(_actor.health.current, Combat.Team.PLAYER, &"probe_world_source"))
	elif _kind == "encounter":
		print("FIXTURE: original encounter membership and lethal member health events; not chapter combat acceptance")
		_actor.begin()
		await _read_radio()
	else:
		print("FIXTURE: place the original player above the original plate, then use actual physics contact")
		_player().global_position = _actor.global_position + Vector2(0, -16)
	_player().set_physics_process(true)
	for i in 1800:
		if _prompt() != null: break
		if _kind == "encounter":
			for ref: WeakRef in _actor._members:
				var enemy := ref.get_ref() as Enemy
				if is_instance_valid(enemy) and not enemy.is_dying(): enemy.health.kill(DamageInfo.create(enemy.health.current, Combat.Team.PLAYER, &"probe_world_source"))
		await _frames(1)
	await _frames(4)
	if _mode == "overlap": _check(_overlap_started and Story._layer.is_radio_frozen(), "overlap fixture really has a distinct important reading lock")
	_check(_prompt() != null and get_tree().paused and _level().channel_result_pending, "actual world action pauses on a refused complete save")
	_check(not GameState.has_flag(_flag) and _observations.is_empty(), "refused world result cannot publish any accepted flag")
	_check(FileAccess.get_file_as_bytes(store.path) == _before, "refused world result retains exact original primary bytes")
	await _shot("channel-refused")
	if _mode == "cancel":
		_main.call("_show_main_menu")
		await _frames(6)
		_check(FileAccess.get_file_as_bytes(store.path) == _before and not GameState.has_flag(_flag), "menu cancellation retains the complete original primary and unaccepted result")
		DirAccess.remove_absolute(store.path + ".tmp")
		await _done()
		return
	if _mode in ["death", "stale"]:
		var source := _level()
		if _mode == "death":
			_player().health.kill(DamageInfo.create(_player().health.current, Combat.Team.ENEMY, &"probe_interruption"))
			await _frames(4)
			_main.call("_on_retry_requested", source)
			_check(source.died and _level() == source and _prompt() != null, "pending result interruption cannot retry into a partly accepted death/world")
		else:
			var original := _pit().data
			_pit().data = original.duplicate(true)
			_prompt().get("retry_button").pressed.emit()
			await _frames(2)
			_check(_prompt() != null and not GameState.has_flag(_flag), "changed original source requires a whole-run recovery")
			_pit().data = original
		_check(FileAccess.get_file_as_bytes(store.path) == _before and not GameState.has_flag(_flag), "interruption cannot persist a changed mechanism with an unaccepted flag")
		DirAccess.remove_absolute(store.path + ".tmp")
		_prompt().get("retry_button").pressed.emit()
		await _frames(12)
		_check(_level() != source and not _pit().triggered and not GameState.has_flag(_flag), "recovery restores the actual original mechanism and complete run")
		_check(GameState.deaths == 0 and not _player().is_dead(), "original recovery restores the original life/death state too")
		await _done()
		return
	if _prompt() != null: _prompt().get("retry_button").pressed.emit()
	await _frames(3)
	_check(not GameState.has_flag(_flag) and FileAccess.get_file_as_bytes(store.path) == _before, "second refusal keeps the same whole original run")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only this test's owned obstruction")
	if _mode == "overlap":
		# Emulate a finish callback already queued by that host; it may not
		# write the changed plate while the world-result prompt still owns it.
		for i in 8:
			if Story._layer._radio_queue.is_empty(): break
			Story._layer.advance_radio()
		await _frames(2)
		_check(not Story._completed.has(&"test_channel_overlap") and FileAccess.get_file_as_bytes(store.path) == _before, "dependent radio completion cannot save a half-accepted world result")

	if _prompt() != null: _prompt().get("retry_button").pressed.emit()
	await _frames(4)
	_check(GameState.has_flag(_flag) and _observations == [true], "one original world result notifies only after its matching durable world and flag")
	_check(_prompt() == null and not _level().channel_result_pending, "accepted result releases its pending route/save scope")
	if _mode == "overlap":
		var read := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
		_check(Story._completed.has(&"test_channel_overlap") and read.has("data") and read["data"]["story"]["flags"].get(String(_flag), false), "dependent reading resumes only after its world result is durably installed")

	if _kind == "boss": _check(not is_instance_valid(_actor), "retry accepts the retained genuine boss receipt after its original actor was freed")
	if _mode in ["route", "route_retry"]:
		var saved := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
		_check(_main.get("_destination_save_prompt") != null and _level().data.id == &"ch1_warehouse", "queued original route waits after its separate destination refusal")
		_check(saved.has("data") and not saved["data"]["runtime"]["ending"] and saved["data"]["state"]["pending_portal"] == "", "accepted source result is never a fake chapter ending or a destination portal")
		if _mode == "route_retry":
			var target_portal := GameState.pending_portal
			_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the later owned destination obstruction")
			_main.get("_destination_save_prompt").retry_requested.emit()
			await _frames(8)
			var destination := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
			_check(_level().data.id != &"ch1_warehouse" and _main.get("_destination_save_prompt") == null, "retrying the separate destination completes the original queued route")
			_check(destination.has("data") and destination["data"]["state"]["pending_portal"] == String(target_portal), "destination retry preserves its original target portal")
		else:
			_main.get("_destination_save_prompt").cancel_requested.emit()
			await _frames(2)
			_check(not _level()._finished and _level()._pause_menu.allowed and _level()._inventory.allowed and _main.get("_destination_save_prompt") == null, "staying after destination refusal restores the original area's route controls")
			_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the later owned destination obstruction")

	await _shot("channel-saved")
	await _done()

func _read_radio() -> void:
	for i in 1800:
		if not Story._layer._radio_active: return
		var event := InputEventAction.new()
		event.action = &"ui_accept"
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)

func _wait_control() -> void:
	for i in 1800:
		if not GameplayLock.is_locked() and not Story.is_cinematic_active() and not _main.call("_story_save_blocked"): return
		await _finish_story()
		await _read_radio()
		await _frames(1)

func _pit() -> FloodPit:
	for node: Node in _level().channel_sources:
		if is_instance_valid(node) and node is FloodPit: return node
	return null

func _boss() -> Enemy:
	for node: Node in _level().channel_sources:
		if is_instance_valid(node) and node is Enemy and node.data.id == &"watchdog": return node
	return null

func _encounter() -> EncounterZone:
	for node: Node in _level().channel_sources:
		if is_instance_valid(node) and node is EncounterZone and node.data.channel == _channel: return node
	return null

func _gate_nodes() -> Array[Gate]:
	var result: Array[Gate] = []
	for node in _level()._entities.get_children():
		if node is Gate and node.data.channel == _channel and not node.data.arena_gate: result.append(node)
	return result

func _gates_open() -> bool:
	return _gate_nodes().all(func(gate: Gate) -> bool: return gate.is_open)

func _tracked_key(node: Node) -> String:
	for key: String in _level()._tracked:
		if is_same(_level()._tracked[key], node): return key
	return ""

func _prompt() -> Control:
	var owner: Variant = _main.get("_channel_completion")
	return owner.get("_prompt") as Control if owner is Node else null
