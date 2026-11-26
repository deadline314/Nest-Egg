extends "res://tools/ch4_archive_probe.gd"
## Boots a completed archive run through Main and uses the actual replay portal.

const ARCHIVE := "res://data/levels/ch5_basement_archive.tres"
const Run = preload("res://game/cutscene/local_replay/flood_memory_run.gd")
const Flood = preload("res://game/cutscene/local_replay/flood_memory.gd")


func _write() -> void:
	if not await _resume_to(ARCHIVE):
		return
	var entry := _level._portals.get(&"flood_memory_chip") as Portal
	_check(entry != null and entry.is_open() and GameState.has_flag(&"ch5_anchor_identity_confirmed"),
			"the next memory opens at the physical archive reader after confirming anchor identity")
	if entry == null:
		return
	_level.player.global_position = entry.global_position
	await _settle(24)
	var items := StoryItems.snapshot()
	var flags := GameState.world_flags.duplicate(true)
	var original_position := _level.player.global_position
	var slot := _main.get("_run_store") as RunSaveStore
	var previous := FileAccess.get_file_as_bytes(slot.path)
	var first := await _open(entry)
	if first == null:
		return
	_check(first._stage._actor.rig != null and first._stage._passenger.texture != null,
			"the original actor rig and the remembered passenger are loaded without copying the live player")
	await _walk_until(first, func() -> bool: return first._run.phase == Run.Phase.CHOOSE_ROUTE)
	await _tap(&"move_right")
	_check(first._run.segment == Run.Segment.LOW_STREET, "a real direction input takes the early shortcut")
	first._run.tick(0.0, Run.LOW_WATER_AT)
	_check(first._run.phase == Run.Phase.CHOOSE_ROUTE and first._run.flooded,
			"water advance moves the carrier back to the dry fork")
	await _tap(&"interact")
	_check(first._run.segment == Run.Segment.DRY_STAIRS, "the ordinary interaction takes the dry stair railing")
	if DisplayServer.get_name() != "headless":
		await _walk_until(first, func() -> bool: return first._run.position.x >= 561.0)
		await _settle(15)
		var frame := preload("res://tools/viewport_capture.gd").image(get_viewport())
		_check(frame.save_jpg(_out_dir.path_join("flood-rail.jpg"), 0.86) == OK,
				"captured the actual upper rail route with the carrier and passenger")
	await _walk_until(first, func() -> bool: return first._run.segment == Run.Segment.PAWNSHOP)
	first._run.tick(0.0, Run.LIMIT_SECONDS)
	_check(first._run.position == Vector2(724,302) and first._run.remaining == 600.0,
			"memory timeout preserves the last dry landing and restarts only the local clock")
	await _walk_until(first, func() -> bool: return first._run.phase == Run.Phase.READING)
	await _tap(&"interact")
	_check(first._testimony and first._run.phase == Run.Phase.TESTIMONY,
			"the reader is physically reached, and confirmation shows the testimony")
	if DisplayServer.get_name() != "headless":
		await _settle(80)
		var frame := preload("res://tools/viewport_capture.gd").image(get_viewport())
		_check(frame.save_jpg(_out_dir.path_join("flood-reader.jpg"), 0.86) == OK,
				"captured physical contact at the chair and reader")
	await _tap(&"interact")
	await _settle(8)
	_check(not is_instance_valid(first), "return retires the viewport and releases the memory")
	var second := await _open(entry)
	if second == null:
		return
	await _tap(&"ui_cancel")
	_check(second._testimony and second._run.phase == Run.Phase.WALK, "skipping shows the same testimony without executing the read")
	await _tap(&"ui_cancel")
	await _settle(8)
	_check(not is_instance_valid(second) and not get_tree().paused and not GameplayLock.is_locked(),
			"skipping and returning retire the input owner")
	_check(_level.player.global_position.is_equal_approx(original_position)
			and FileAccess.get_file_as_bytes(slot.path) == previous
			and StoryItems.snapshot() == items and GameState.world_flags == flags,
			"both paths restore the identical world position, inventory, story flags and save bytes")


func _open(entry: Portal) -> Flood:
	_check(entry.try_use(), "player opens the current reader")
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var player: Flood = entry._local_replay as Flood if is_instance_valid(entry._local_replay) else null
		if player != null and player._ready_to_play:
			_check(get_tree().paused and get_tree().get_first_node_in_group(Portal.LOCAL_REPLAY_GROUP) == entry,
					"the active reader owns control without replacing Main")
			return player
		await get_tree().process_frame
	_check(false, "replay didn't load from the physical reader")
	return null


func _walk_until(memory: Flood, arrived: Callable) -> void:
	Input.action_press(&"move_right")
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(memory) and not arrived.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	Input.action_release(&"move_right")
	_check(arrived.call(), "the active movement reaches the awaited memory position")


func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
