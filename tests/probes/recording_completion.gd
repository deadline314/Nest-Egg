extends "res://tests/probes/channel_completion.gd"
## Real original booth/input/phone event; metadata damage is an explicit fixture.
const RECORDING := &"ch1_t_booth_recording"
const AREA := "res://data/levels/ch1_booth_alley.tres"
const Sources := preload("res://game/story_flag_sources.gd")
const MODES := ["intact", "missing", "malformed", "shifted", "foreign", "choice", "source", "condition"]
var _store: RunSaveStore
var _started := false
var _selected := false
var _notices := 0
var _checkpoint_calls := 0
var _events: Array[Dictionary] = []
var _checkpoint_entry: Dictionary
var _boundary_recorded := false
var _passive_gate: Callable
var _cinematic_gate: Callable

func _run() -> void:
	_main = load("res://game/main.gd").new()
	_store = RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store", _store)
	add_child(_main)
	await _frames(8)
	EventBus.checkpoint_reached.connect(func(_position: Vector2) -> void: _checkpoint_calls += 1)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		await _frames(12)
		_check(_level() != null and _level().data.resource_path == AREA, "cold recording primary restores its actual original phone-booth area")
		_check(GameState.has_flag(&"ch1_recording_heard") and Story._completed.has(RECORDING), "cold read restores the genuinely accepted recording result and history")
		_check(_booth() != null and _booth().activated and GameState.has_checkpoint, "cold primary restores its real original activated checkpoint")
		_check(_prompt() == null and not get_tree().paused, "cold accepted recording has no stale recovery pause")
		GameState.flag_changed.connect(_on_flag)
		Story.scene_started.connect(_on_started)
		await _dial()
		for frame in 600:
			if _booth() != null and _booth().is_calling():
				await _frames(1)
			else: break
		await _frames(4)
		_check(_booth() != null and _booth().activated and not _started and _notices == 0, "original booth can back up again without replaying or republishing its accepted recording")
		await _shot("recording-cold")
		await _done()
		return
	_check(_mode in MODES, "supported finite recording corruption fixture")
	if _mode not in MODES:
		await _done()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	_main.call("_on_area_requested", AREA)
	await _frames(12)
	await _finish_story()
	await _wait_control()
	_check(not GameState.has_flag(&"ch1_recording_heard") and not Story._completed.has(RECORDING), "original recording is genuinely unheard before its actual checkpoint event")
	_check(Sources.valid(String(RECORDING), Story._scenes, Story._scene_sources), "original recording matches its independent authored source")
	var original_scene: Dictionary = Story._scenes[String(RECORDING)].duplicate(true)
	var original_source: String = Story._scene_sources[String(RECORDING)]
	var scene: Dictionary = Story._scenes[String(RECORDING)]
	match _mode:
		"missing": scene.erase("freeze")
		"malformed": scene["freeze"] = 1
		"shifted": scene["completion_policy"] = "main_terminal_results_v1"
		"foreign": scene["set_flags"] = ["ch1_label_guitar_seen"]
		"source": Story._scene_sources[String(RECORDING)] = "res://data/story/chapter_01.json"
		"condition": scene["when"] = {"not": {"flag": "ch1_recording_heard", "equals": true}}
		"choice":
			scene.erase("freeze")
			scene["mode"] = "animated"
			scene["overlay"] = true
			scene["steps"] = [{"do": "choice", "text": "Declared unregistered checkpoint recording choice", "default": "inject", "options": [{"id": "inject", "text": "Attempt an unrelated result", "set_flags": {"ch1_label_guitar_seen": true}}, {"id": "leave", "text": "Leave"}]}]
	Story.scene_started.connect(_on_started)
	GameState.flag_changed.connect(_on_flag)
	_passive_gate = Story.passive_completion_gate
	_cinematic_gate = Story.cinematic_completion_gate
	Story.passive_completion_gate = func(id: StringName, request: int) -> Dictionary:
		if id == RECORDING: _capture_boundary()
		return _passive_gate.call(id, request)
	Story.cinematic_completion_gate = func(id: StringName, request: int) -> Dictionary:
		if id == RECORDING: _capture_boundary()
		return _cinematic_gate.call(id, request)
	await _dial()
	await _drive_recording()
	await _frames(4)
	_check(_started and _booth() != null and _booth().activated and GameState.has_checkpoint, "real original phone interaction requests its actual checkpoint recording")
	_check(not GameState.has_flag(&"ch1_recording_heard") and not GameState.has_flag(&"ch1_label_guitar_seen") and not Story._completed.has(RECORDING), "unaccepted recording cannot install its own or another declared result or history")
	_check(_notices == 0, "unaccepted original recording has no result notification")
	_check(not _before.is_empty() and FileAccess.get_file_as_bytes(_store.path) == _before, "refusal preserves the exact complete actually saved checkpoint entry")
	_check(_prompt() != null and get_tree().paused and _main.get("_result_completion").get("_prompt") == null, "original flag owner retains its real recording and recovery prompt")
	_check(bool(_main.get("_story_completion").get("_reload_original")) == (_mode != "intact"), "invalid metadata requires original recovery while normal IO retains its same retry")
	if _mode == "choice": _check(_selected, "actual original recording really presents and selects its injected choice")
	FileAccess.open(_out.path_join("refused-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(_store.path))
	await _shot("recording-" + _mode + "-refused")
	Story._scenes[String(RECORDING)] = original_scene
	Story._scene_sources[String(RECORDING)] = original_source
	var old_level := _level().get_instance_id()
	if _mode == "intact":
		_check(DirAccess.remove_absolute(_store.path + ".tmp") == OK, "remove only the owned ordinary IO obstruction before original retry")
	else:
		_started = false
	if _prompt() != null: _prompt().retry_button.pressed.emit()
	await _frames(12)
	if _mode != "intact":
		_check(_level() != null and _level().get_instance_id() != old_level and _level().data.resource_path == AREA, "whole-original recovery reconstructs the actual original checkpoint area")
		_check(not GameState.has_flag(&"ch1_recording_heard") and not Story._completed.has(RECORDING) and _prompt() == null, "original recovery keeps the original recording genuinely unheard")
		# A corrupted cinematic mode may have durably recorded an unread entry.
		# Otherwise the actual checkpoint must be dialled again to request it.
		if not Story._layer._radio_active and not Story.is_cinematic_active(): await _dial()
		await _drive_recording()
	await _frames(8)
	_check(GameState.has_flag(&"ch1_recording_heard") and Story._completed.has(RECORDING) and _notices == 1, "only the genuinely accepted original recording publishes its real result once")
	_check(not GameState.has_flag(&"ch1_label_guitar_seen"), "corrected original recording never grants an unrelated declared flag")
	_check(_prompt() == null and not get_tree().paused and not Story._layer._radio_active, "accepted original recording releases its original UI and gameplay pause")
	_check(_booth() != null and _booth().activated and GameState.has_checkpoint, "accepted recording preserves the actual original checkpoint")
	await _shot("recording-" + _mode + "-accepted")
	await _done()

func _booth() -> Checkpoint:
	if _level() == null: return null
	for node: Node in _level()._entities.get_children():
		if node is Checkpoint: return node
	return null

func _dial() -> void:
	var booth := _booth()
	_check(booth != null, "actual original alley owns its actual phone booth")
	if booth == null: return
	_player().global_position = booth.global_position + Vector2(-23, 0)
	_player().velocity = Vector2.ZERO
	_level().camera.snap_to_target()
	await _frames(8)
	for frame in 120:
		if booth.can_dial(): break
		await get_tree().process_frame
	_check(booth.can_dial(), "actual original booth becomes the real available interaction target")
	var calls_before := _checkpoint_calls
	await _send(&"interact")
	_check(booth.is_calling() or _checkpoint_calls > calls_before, "real interaction input starts the actual original phone call")

func _send(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await _frames(1)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _on_started(id: StringName, _kind: StringName) -> void:
	if id == RECORDING: _started = true

func _drive_recording() -> void:
	for frame in 3600:
		if _started and _before.is_empty():
			# Capture only after all real checkpoint subscribers mark navigation.
			_main.call("_flush_save")
			_before = FileAccess.get_file_as_bytes(_store.path)
			FileAccess.open(_out.path_join("entry-primary.json"), FileAccess.WRITE).store_buffer(_before)
			var decoded := RunSaveCodec.decode(_before.get_string_from_utf8())
			_check(decoded.has("data") and decoded.data.state.has_checkpoint, "actual checkpoint event has an intact saved whole-run entry")
			if decoded.has("data"): _checkpoint_entry = decoded.data
			if _mode == "intact": _check(DirAccess.make_dir_absolute(_store.path + ".tmp") == OK, "owned IO obstruction follows the complete actual checkpoint event")
		if _prompt() != null: return
		if is_instance_valid(Story._player) and Story._player.choice_active():
			_selected = true
			_capture_boundary()
			Story._player.choose(0)
		else:
			await _send(&"ui_accept")
		if _started and Story._current_cinematic == &"" and not Story._layer._radio_active: return
		await _frames(1)
	_check(false, "original checkpoint recording settles or refuses within its bounded frame guard")

func _capture_boundary() -> void:
	if _boundary_recorded: return
	_boundary_recorded = true
	# Ordinary old-state autosaves remain legitimate while corrupted radio is unfrozen.
	# Observe the exact current primary immediately before the unchanged real gate.
	_before = FileAccess.get_file_as_bytes(_store.path)
	FileAccess.open(_out.path_join("completion-entry-primary.json"), FileAccess.WRITE).store_buffer(_before)

func _on_flag(flag: StringName, _value: Variant) -> void:
	if flag not in [&"ch1_recording_heard", &"ch1_label_guitar_seen"]: return
	_notices += 1
	_check(flag == &"ch1_recording_heard" and GameState.has_flag(&"ch1_recording_heard") and Story._completed.has(RECORDING), "first recording observer sees exactly its installed real result and history")
	var raw := FileAccess.get_file_as_string(_store.path)
	var decoded := RunSaveCodec.decode(raw)
	_check(decoded.has("data") and decoded.get("issues", []).is_empty(), "recording publication primary has its complete original checksum")
	if not decoded.has("data"): return
	var disk: Dictionary = decoded.data
	_check(disk.story.flags.get("ch1_recording_heard", false) and disk.story.seen.has(String(RECORDING)), "first recording observer sees its real result and history already durable")
	_check(disk.state.has_checkpoint and disk.state.checkpoint_level_path == AREA, "first recording observer retains the real original checkpoint on disk")
	_check(disk.state.checkpoint_position == _checkpoint_entry.get("state", {}).get("checkpoint_position"), "recording publication preserves the actual saved checkpoint position")
	var filename := "publication-" + str(_events.size()) + ".json"
	FileAccess.open(_out.path_join(filename), FileAccess.WRITE).store_string(raw)
	_events.append({"flag": String(flag), "primary": filename})

func _prompt() -> Control:
	var owner: Node = _main.get("_story_completion")
	return owner.get("_prompt") as Control if is_instance_valid(owner) else null

func _done() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var file := FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"mode": _mode, "checks": _checks, "failures": _issues, "publications": _events}, "  "))
		file.close()
	else:
		_check(false, "original recording result receipt is writable")
	if _passive_gate.is_valid(): Story.passive_completion_gate = _passive_gate
	if _cinematic_gate.is_valid(): Story.cinematic_completion_gate = _cinematic_gate
	Story.reset_active_presentation(&"menu")
	_main.call("_quit", 0 if _issues.is_empty() else 1)
