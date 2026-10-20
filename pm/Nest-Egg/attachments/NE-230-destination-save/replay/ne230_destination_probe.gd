extends "res://tools/run_save_probe.gd"
## Real Main and Level signal, actual filesystem refusal, separate-process reads.
## Arranged room/checkpoint fixtures; not a chapter playthrough.

const FIRST := "res://data/levels/ch1_pawnshop.tres"
const TARGET := "res://data/levels/ch1_rooftop.tres"
var _out := ""
var _record: Dictionary = {}

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	super._ready()

func _run() -> void:
	Story.auto_skip = true
	Transition.instant = true
	_main = MainScript.new()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	var store := RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(3)
	if _mode in ["refuse_read", "accept_read"]:
		if DirAccess.dir_exists_absolute(store.path + ".tmp"):
			_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the previous probe-owned obstruction before cold continue")
		var expected := FIRST if _mode == "refuse_read" else TARGET
		_main.call("_on_continue_requested")
		var level := await _room()
		_check(level != null and level.data.resource_path == expected, "fresh Main restores the expected source or accepted destination")
		var saved := store.read()
		_check(Progression.credits == int(saved.get("progression", {}).get("credits", -1)), "cold continue restores the actual saved wallet")
		_check(GameState.has_checkpoint and GameState.checkpoint_level_path == FIRST, "cold continue preserves the real source checkpoint")
		_check(not GameplayLock.is_locked() and not get_tree().paused, "cold continue has no stale route lock")
		await _shot("cold-continue")
		_record = {"expected": expected, "live": level.data.resource_path if level != null else "missing", "saved": saved.get("level")}
		await _finish()
		return
	if _mode not in ["refuse_write", "retry_write", "respawn_write", "chapter_write", "stay_write"]:
		_check(false, "unknown destination probe mode")
		await _finish()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _room()
	_main.call("_on_area_requested", FIRST)
	var source := await _room()
	_check(source != null and source.data.resource_path == FIRST, "real Main establishes the arranged source room")
	if source == null:
		await _finish()
		return
	Story.reset_active_presentation(&"probe_setup")
	GameState.set_checkpoint(source.player.global_position, source.player.checkpoint_snapshot(), {}, Progression.snapshot())
	Story.reset_active_presentation(&"probe_setup")
	Progression.add_credits(37)
	_main.call("_flush_save")
	var baseline := FileAccess.get_file_as_bytes(store.path)
	if _mode == "respawn_write":
		GameState.checkpoint_level_path = TARGET
		GameState.checkpoint_position = LevelBuilder.parse(load(TARGET)).player_start
	var owners := _persistent_owners()
	var source_id := source.get_instance_id()
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "real temp-directory obstruction blocks actual file creation")
	var automatic := _mode in ["respawn_write", "chapter_write"]
	var current: Level
	if automatic:
		if _mode == "respawn_write":
			source.died = true # Arranged automatic-death boundary, not a death playthrough.
			_main.call("_on_retry_requested", source)
		else:
			_main.set("_chapter_complete", true)
			_main.call("_enter_next_level", load(TARGET), source.run_snapshot())
		current = await _room()
	else:
		current = await _request_area(source, TARGET)
	_check(current != null and current.get_instance_id() == source_id and current.data.resource_path == FIRST, "refused destination keeps the exact real source Level")
	_check(_main.get("_level_path") == FIRST and not _main.get("_destination_pending"), "refused destination keeps Main source routing available for retry")
	_check(owners == _persistent_owners(), "refused destination preserves checkpoint, wallet, carried loadout and story")
	_check(baseline == FileAccess.get_file_as_bytes(store.path), "actual refused writer keeps exact primary bytes")
	_record = {"source": FIRST, "attempted": TARGET, "after_refusal": current.data.resource_path if current != null else "missing", "primary_unchanged": baseline == FileAccess.get_file_as_bytes(store.path)}
	var prompt := _prompt()
	_check(prompt != null and prompt.is_visible_in_tree(), "actual refused route exposes a persistent recovery prompt")
	_check(prompt != null and GameplayLock.is_locked() and get_tree().paused, "actual refusal pauses the source while awaiting a decision")
	if prompt != null:
		_check(prompt.can_stay == (not automatic), "only a playable source permits staying")
		var back := InputEventAction.new()
		back.action = &"ui_cancel"
		back.pressed = true
		if automatic:
			prompt._unhandled_input(back)
			_check(_prompt() == prompt, "Back cannot strand an automatic death or chapter handoff")
	await _shot("destination-refused")
	if _mode == "stay_write":
		if prompt != null:
			prompt.cancel_button.pressed.emit()
		await _frames(2)
		_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "stay closes only the owned recovery and resumes gameplay")
		_check(_main.get("_screen") == source and FileAccess.get_file_as_bytes(store.path) == baseline, "stay keeps the exact source and original save")
		await _shot("destination-stayed")
	if _mode in ["retry_write", "respawn_write", "chapter_write"]:
		if prompt != null:
			prompt.retry_button.pressed.emit()
		current = await _room()
		_check(current == source and _prompt() != null, "a second actual refusal retains a retryable modal and source")
		prompt = _prompt()
		_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "clear only the probe-owned fault before retry")
		if prompt != null:
			prompt.retry_button.pressed.emit()
		current = await _room()
		_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "successful modal retry releases its pause and recovery UI")
		_check(current != null and current.data.resource_path == TARGET, "same Main retry enters the destination after actual save succeeds")
		_check(store.read().get("level") == TARGET, "accepted retry is durable in the actual reader")
		_record["after_retry"] = current.data.resource_path if current != null else "missing"
		await _shot("destination-retry-accepted")
	await _finish()

func _persistent_owners() -> PackedByteArray:
	return var_to_bytes([GameState.has_checkpoint, GameState.checkpoint_level_path, GameState.checkpoint_position, GameState.checkpoint_loadout, GameState._carried_loadout, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])

## Wait for the actual deferred Level->Main delivery, then for Main's route. No
## fixed frame count is used to assume that an unprocessed request was refused.
func _request_area(level: Level, path: String) -> Level:
	var delivered := [false]
	level.area_requested.connect(func(_path: String) -> void: delivered[0] = true, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	level.area_requested.emit(path)
	var deadline := Time.get_ticks_msec() + 120000
	while not delivered[0] and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(delivered[0], "actual deferred route signal was delivered")
	return await _room()

func _room() -> Level:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		var level := _main.get("_screen") as Level
		if level != null and level.is_initialized() and _prompt() != null:
			await _frames(2)
			return level
		if level != null and level.is_initialized() and not _main.call("_route_pending") and not Story.is_cinematic_active() and Story._passive_requests.is_empty() and not GameplayLock.is_locked():
			return level
		await _frames(1)
	_check(false, "real Main route settles before the time guard")
	return _main.get("_screen") as Level

func _prompt() -> Control:
	return _main.get("_destination_save_prompt") if _main.has_method("_retry_destination_save") else null

func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var note := Label.new()
	note.text = "SOFTWARE FORWARD+ / ARRANGED ROUTE + IO FAULT / NOT A PLAYTHROUGH"
	note.position = Vector2(12, 12)
	note.add_theme_font_size_override("font_size", 12)
	canvas.add_child(note)
	await _frames(2)
	await RenderingServer.frame_post_draw
	preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(_out.path_join(name + ".png"))
	canvas.queue_free()

func _finish() -> void:
	_record["mode"] = _mode
	_record["checks"] = _checks
	_record["failures"] = Array(_failures)
	_record["engine"] = Engine.get_version_info().string
	_record["probe_sha256"] = FileAccess.get_sha256("res://work/ne230_destination_probe.gd")
	_record["prompt_sha256"] = FileAccess.get_sha256("res://ui/destination_save_prompt.gd")
	_record["main_sha256"] = FileAccess.get_sha256("res://game/main.gd")
	if not _out.is_empty():
		var file := FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_record, "  ") + "\n")
		file.close()
	await super._finish()
