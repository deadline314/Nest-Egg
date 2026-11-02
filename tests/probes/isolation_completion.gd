extends "res://tests/probes/channel_completion.gd"
## Original held isolation-box fixture; only prior choice/position/health arranged, never its results.
const YONG_LEVEL := "res://data/levels/ch2_ledger_office.tres"
const RESULT := &"yong_link_isolated"
const EXTRA := &"yong_link_revoked"
const CHANNEL := &"ch2_yong_isolation"

func _ready() -> void:
	super._ready()
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch2_heron"))

func _run() -> void:
	_main = load("res://game/main.gd").new()
	var store := RunSaveStore.new(_save_dir.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(8)
	if _mode.ends_with("_read"):
		_main.call("_on_continue_requested")
		await _frames(8)
		_check(_level() != null and _level().data.resource_path == YONG_LEVEL, "cold exact original primary restores its original second-chapter area")
		if _level() == null: await _done(); return
		var accepted := _mode == "accepted_read"
		_check([GameState.has_flag(RESULT), GameState.has_flag(EXTRA)] == [accepted, accepted], "cold original primary preserves both actually accepted box results together")
		var restored := _yong()
		_check(restored != null and restored.get("stage") == ("subdue" if accepted else "cut_box"), "cold box result restores its original living boss route")
		_check(not _player().is_dead() and GameState.deaths == 0, "cold action receipt retains its original living player and death count")
		_check(not GameState.has_flag(&"ch2_yong_subdued"), "isolation never grants the later power-cell result")
		await _shot("isolation-cold")
		await _done()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _frames(90)
	await _finish_story()
	await _wait_control()
	_main.call("_on_area_requested", YONG_LEVEL)
	await _frames(12)
	await _finish_story()
	await _wait_control()
	_actor = _yong()
	_check(_actor != null and _no_results(), "real Main owns the original uncompleted second-chapter boss")
	if _actor == null: await _done(); return
	_prepare_opening()
	var cell: BossHoldPoint = _actor.call("isolation_box")
	_check(cell.enabled and not cell.done, "declared cut-route fixture exposes the original isolation box")
	_main.call("_save_run")
	_before = FileAccess.get_file_as_bytes(store.path)
	FileAccess.open(_save_dir.path_join("original-primary.json"), FileAccess.WRITE).store_buffer(_before)
	_check(not _before.is_empty() and DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "owned real refusal begins after an ordinary complete original primary")
	var authored_extra: PackedStringArray = _level().data.channel_done_extra_flags[CHANNEL]
	if _mode == "overflow":
		var too_many := PackedStringArray()
		for i in LevelData.MAX_CHANNEL_RESULT_FLAGS + 1: too_many.append("fixture_isolation_extra_%d" % i)
		_level().data.channel_done_extra_flags[CHANNEL] = too_many
	elif _mode == "empty_flag":
		_level().data.channel_done_extra_flags[CHANNEL] = PackedStringArray([""])
	GameState.flag_changed.connect(func(flag: StringName, value: Variant) -> void:
		if flag not in [RESULT, EXTRA] or value != true: return
		var bytes := FileAccess.get_file_as_bytes(store.path)
		var saved := RunSaveCodec.decode(bytes.get_string_from_utf8())
		_observations.append(saved.has("data") and saved["data"]["story"]["flags"].get(String(RESULT), false) and saved["data"]["story"]["flags"].get(String(EXTRA), false) and cell.done and _actor.get("stage") == "subdue" and not _actor.is_dying())
		FileAccess.open(_save_dir.path_join("result-primary.json"), FileAccess.WRITE).store_buffer(bytes)
		var source := _level()
		_main.call("_show_main_menu")
		_check(_level() == source and _main.get("_active_run"), "a result notification cannot replace its publishing nonlethal source"))
	if _mode == "forged":
		EventBus.mechanism_toggled.emit(CHANNEL, true)
		await _frames(2)
		_check(_no_results() and _prompt() == null, "a raw nonlethal channel cannot authorize an unfinished original action")
		_actor.call("_on_box_completed")
		await _frames(2)
		_check(not cell.done and _no_results() and _prompt() == null, "a forged route change without the original completed box is refused")
		_prepare_opening()
	Input.action_press(&"interact")
	for i in 180:
		if cell.done: break
		await _frames(1)
	Input.action_release(&"interact")
	for i in 120:
		if _prompt() != null: break
		await get_tree().process_frame
	_check(cell.done and _actor.get("stage") == "subdue" and not _actor.is_dying(), "actual held interaction completes the original isolation box without killing the boss")
	_check(_prompt() != null and get_tree().paused and _level().channel_result_pending, "refused nonlethal result holds the original world with its retry prompt")
	_check(_no_results() and _observations.is_empty(), "refused nonlethal result cannot publish its story flag")
	_check(FileAccess.get_file_as_bytes(store.path) == _before, "refused original action retains exact whole primary bytes")
	await _shot("isolation-refused")
	if _prompt() == null: await _done(); return
	if _mode == "cancel":
		_main.call("_show_main_menu")
		await _frames(6)
		_check(_no_results() and FileAccess.get_file_as_bytes(store.path) == _before, "menu cancellation preserves the complete original unaccepted run")
		await _done()
		return
	if _mode in ["death", "stale", "contract", "overflow", "empty_flag"]:
		var original := _level()
		if _mode == "death":
			_player().health.kill(DamageInfo.create(_player().health.current, Combat.Team.ENEMY, &"probe_pending_action"))
			await _frames(3)
			_main.call("_on_retry_requested", original)
			_check(_level() == original, "pending nonlethal result rejects a partial-death retry")
		elif _mode in ["stale", "contract"]:
			if _mode == "stale": _actor.data = _actor.data.duplicate(true)
			else: _level().data.channel_done_extra_flags[CHANNEL] = PackedStringArray()
			_prompt().get("retry_button").pressed.emit()
			await _frames(3)
		_check(_no_results() and FileAccess.get_file_as_bytes(store.path) == _before, "interrupted or changed nonlethal source cannot accept or overwrite the original run")
		_check(_prompt() != null and _main.get("_channel_completion").get("_reload_original"), "interrupted nonlethal action requires original whole-run recovery")
		if _prompt() == null: await _done(); return
		_level().data.channel_done_extra_flags[CHANNEL] = authored_extra
		DirAccess.remove_absolute(store.path + ".tmp")
		_prompt().get("retry_button").pressed.emit()
		await _frames(12)
		_check(_level() != original and _no_results() and not _player().is_dead() and GameState.deaths == 0, "recovery restores the original complete living run without accepting the action")
		await _done()
		return
	_prompt().get("retry_button").pressed.emit()
	await _frames(3)
	_check(_no_results() and FileAccess.get_file_as_bytes(store.path) == _before, "a second refused nonlethal write preserves the same original primary")
	if _prompt() == null: await _done(); return
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only this test's owned obstruction")
	_prompt().get("retry_button").pressed.emit()
	await _frames(4)
	_check(_all_results() and _observations == [true, true], "one genuine nonlethal result notifies only after its original complete save")
	_check(_prompt() == null and not _level().channel_result_pending and not _actor.is_dying(), "accepted nonlethal result releases its pending world without an enemy death")
	await _shot("isolation-accepted")
	await _done()

func _prepare_opening() -> void:
	# Explicit prior cut choice, health and position; the held box action is real.
	GameState.set_flag(&"yong_link_choice", "cut", false)
	_actor.set_physics_process(false)
	_actor.call("_set_health_silent", _actor.call("_choice_hp"))
	_actor.call("_start_cut", false)
	_actor.contact.active = false
	_player().global_position = (_actor.call("isolation_box") as BossHoldPoint).global_position
	_player().velocity = Vector2.ZERO
	_player().set_physics_process(false)

func _no_results() -> bool:
	return not GameState.has_flag(RESULT) and not GameState.has_flag(EXTRA)

func _all_results() -> bool:
	return GameState.has_flag(RESULT) and GameState.has_flag(EXTRA)

func _yong() -> Node:
	for node: Node in _level().channel_sources:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node is PatternBoss and node.data.id == &"yong": return node
	return null
