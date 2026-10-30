extends "res://tools/prologue_play_probe.gd"
## Real Main/input actions and a real IO refusal; never arrange training flags.
var _checks := 0
var _issues: Array[String] = []
var _starts: Array[StringName] = []
var _before := PackedByteArray()
var _mode := "bench"
var _observations: Array[bool] = []

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): _mode = arg.trim_prefix("--mode=")
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	super._ready()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok: _issues.append(what)
	super._check(ok, what)

func _run() -> void:
	if _mode in ["fall", "guard", "dash"]:
		await super._run()
		return
	_main = load("res://game/main.gd").new()
	var store := RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(8)
	var reading := _mode in ["read", "cancel_read", "fall_read", "dash_read"]
	if reading: _main.call("_on_continue_requested")
	else: _main.call("_on_start_requested", GameState.difficulties[1])
	for i in 600:
		if _level() != null and _level().is_initialized(): break
		await _frames(1)
	_check(_level() != null, "real Main initializes its original prologue")
	if _level() == null: await _done(); return
	await _frames(90)
	var station_id := &"ch1_training_trainer" if _mode == "fall_read" else &"ch1_training_dash" if _mode == "dash_read" else &"ch1_training_workbench"
	var station := _station(station_id)
	if _mode in ["read", "fall_read", "dash_read"]:
		var completed := _mode != "fall_read"
		var flag := station.data.done_flag if completed else station.data.fail_flag
		var scene := station.data.done_scene if completed else station.data.fail_scene
		_check(GameState.has_flag(flag) and station.is_done() == completed, "cold original primary restores its genuine training result")
		_check(Story._current_cinematic == scene, "cold saved result preserves the unread original explanation")
		_check(_player().interaction.active and not _player()._visual.rig.weapon_root().visible, "cold original training dialogue restores the authored holster scope")
		await _finish_story()
		_check(GameState.has_flag(flag) and not Story.is_cinematic_active(), "cold explanation finishes without repeating the training action")
		await _done()
		return
	await _finish_story()
	for i in 600:
		if not GameplayLock.is_locked() and not Story.is_cinematic_active(): break
		await _frames(1)
	await _frames(8)
	_check(not GameState.has_flag(station.data.done_flag), "initial/cancelled original primary predates reaching the bench")
	if _mode == "cancel_read":
		await _walk_to(station.global_position.x)
		_check(GameState.has_flag(station.data.done_flag), "cold cancelled primary can complete the same real movement")
		await _done()
		return
	# A node added by a tool is not an original registered map source.
	var duplicate := TrainingStation.new()
	duplicate.configure(station.data)
	duplicate.position = station.position
	station.get_parent().add_child(duplicate)
	duplicate._complete()
	_check(not GameState.has_flag(station.data.done_flag) and not duplicate.is_done(), "unregistered duplicate cannot grant a genuine training result")
	duplicate.queue_free()
	await _frames(2)
	_begin_fault(station, true)
	var movement := &"move_right" if station.global_position.x > _player().global_position.x else &"move_left"
	for i in 600:
		if _prompt() != null or GameState.has_flag(station.data.done_flag): break
		Input.action_press(movement)
		await _frames(1)
	Input.action_release(movement)
	_check(absf(_player().global_position.x-station.global_position.x) <= station.data.reach.x+8, "original movement physically reaches its actual station")
	await _verify_fault(station, true)

func _stop_if(flag: StringName) -> bool:
	if (_mode in ["fall", "guard"] and flag == &"ch1_prologue_melee_done") or (_mode == "dash" and flag == &"ch1_prologue_guard_done"):
		_tail.call_deferred()
		return true
	return false

func _tail() -> void:
	await _finish_story()
	await _frames(8)
	var station := _station(&"ch1_training_dash" if _mode == "dash" else &"ch1_training_trainer")
	var success := _mode != "fall"
	if _mode == "dash":
		await _walk_to(station.global_position.x-40)
	_begin_fault(station, success)
	if _mode == "dash":
		Input.action_press(&"move_right")
		await _frames(2)
		await _press(&"dash", 3)
		Input.action_release(&"move_right")
	else:
		if success:
			_aim(Vector2.RIGHT)
			Input.action_press(&"block")
		await _walk_to(station.global_position.x-34)
	for i in 600:
		if _prompt() != null or GameState.has_flag(station.data.done_flag if success else station.data.fail_flag): break
		await _frames(1)
	Input.action_release(&"block")
	await _verify_fault(station, success)

func _begin_fault(station: TrainingStation, success: bool) -> void:
	_main.call("_save_run")
	var store: RunSaveStore = _main.get("_run_store")
	_before = FileAccess.get_file_as_bytes(store.path)
	_check(not _before.is_empty(), "original live action has a real previous primary")
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "real write obstruction is an owned empty directory")
	Story.scene_started.connect(func(id: StringName, _kind: StringName) -> void: _starts.append(id))
	var target := station.data.done_flag if success else station.data.fail_flag
	GameState.flag_changed.connect(func(flag: StringName, _value: Variant) -> void:
		if flag == target:
			var saved := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
			_observations.append(saved.has("data") and saved["data"]["story"]["flags"].get(String(target), false)
				and (not success or station.is_done())))

func _verify_fault(station: TrainingStation, success: bool) -> void:
	await _frames(4)
	var store: RunSaveStore = _main.get("_run_store")
	var flag := station.data.done_flag if success else station.data.fail_flag
	var scene := station.data.done_scene if success else station.data.fail_scene
	_check(not GameState.has_flag(flag) and not station.is_done(), "refused training write cannot publish its result or mark the station done")
	_check(not _starts.has(scene), "refused write cannot start its original follow-up explanation")
	_check(FileAccess.get_file_as_bytes(store.path) == _before, "refused write retains exact original primary bytes")
	_check(_prompt() != null and get_tree().paused, "refused actual action holds the world and offers retry")
	_check(_observations.is_empty(), "refusal cannot notify any observer of success")
	if _mode == "bench":
		var banner := _level().hud.toast_banner
		_check(banner.is_showing() and banner._label.text == "存檔未成功，原進度仍保留。", "real autosave refusal has produced its original failure notice")
	await _shot("training-refused")
	if _mode == "cancel":
		_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only this test's owned IO obstruction")
		FileAccess.open(_save_dir.path_join("original-primary.json"), FileAccess.WRITE).store_buffer(_before)
		Transition.instant = false
		_main.call("_show_main_menu")
		await _frames(8)
		_check(FileAccess.get_file_as_bytes(store.path) == _before and not GameState.has_flag(flag), "menu cancellation leaves original unread progress and no result")
		await _done()
		return
	if _prompt() != null:
		_prompt().get("retry_button").pressed.emit()
		await _frames(4)
		_check(not GameState.has_flag(flag) and not _starts.has(scene), "second refusal does not publish or replay anything")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only this test's owned IO obstruction")
	if _prompt() != null:
		_prompt().get("retry_button").pressed.emit()
		await _frames(4)
		_check(GameState.has_flag(flag) and station.is_done() == success, "successful retry accepts exactly the genuine original result")
		_check(_starts.count(scene) == 1, "retry starts its original explanation exactly once")
		if Story.scene_mode(scene) == Story.MODE_DIALOGUE:
			_check(_player().interaction.active and not _player()._visual.rig.weapon_root().visible and not _player()._weapon_light.is_lit(), "actual authored training dialogue holsters the equipped gun and light")
		_check(_observations == [true], "one observer sees the durable primary and matching station state")
		_check(_player().health.current == _player().health.max_health and GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"), "training failure/guard never spends health, death or first registration")
		if _mode == "bench":
			var banner := _level().hud.toast_banner
			_check(not banner.is_showing() or banner._label.text != "存檔未成功，原進度仍保留。", "successful real save retires its old failure notice immediately")
		FileAccess.open(_save_dir.path_join("result-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
		await _shot("training-saved")
	await _done()

func _prompt() -> Control:
	var owner: Variant = _main.get("_training_completion")
	return owner.get("_prompt") as Control if owner is Node else null

func _done() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":_issues},"  "))
	Story.reset_active_presentation(&"menu")
	_main.call("_quit", 0 if _issues.is_empty() else 1)
