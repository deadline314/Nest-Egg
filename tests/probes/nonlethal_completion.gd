extends "res://tests/probes/channel_completion.gd"
## Original final-action fixture, not a natural full boss fight. No result flags set.
const YONG_LEVEL := "res://data/levels/ch2_ledger_office.tres"
const RESULT := &"ch2_yong_subdued"

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
		_check(GameState.has_flag(RESULT) == (_mode == "accepted_read"), "cold original primary preserves only its actually accepted nonlethal result")
		_check((_yong() == null) == (_mode == "accepted_read"), "cold accepted completion retires the original boss without inventing an enemy death")
		_check(not _player().is_dead() and GameState.deaths == 0, "cold action receipt retains its original living player and death count")
		if _mode == "accepted_read":
			_check(not _level().hud.boss_bar.is_open(), "cold accepted completion cannot wake a retired boss bar")
		await _shot("nonlethal-cold")
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
	_check(_actor != null and not GameState.has_flag(RESULT), "real Main owns the original uncompleted second-chapter boss")
	if _actor == null: await _done(); return
	_prepare_opening()
	var cell: BossHoldPoint = _actor.call("power_cell")
	_check(cell.enabled and not cell.done, "declared final disarm and health opening exposes the original power cell")
	_main.call("_save_run")
	_before = FileAccess.get_file_as_bytes(store.path)
	FileAccess.open(_save_dir.path_join("original-primary.json"), FileAccess.WRITE).store_buffer(_before)
	_check(not _before.is_empty() and DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "owned real refusal begins after an ordinary complete original primary")
	GameState.flag_changed.connect(func(flag: StringName, value: Variant) -> void:
		if flag != RESULT or value != true: return
		var bytes := FileAccess.get_file_as_bytes(store.path)
		var saved := RunSaveCodec.decode(bytes.get_string_from_utf8())
		_observations.append(saved.has("data") and saved["data"]["story"]["flags"].get(String(RESULT), false) and cell.done and _actor.call("is_subdued") and not _actor.is_dying())
		FileAccess.open(_save_dir.path_join("result-primary.json"), FileAccess.WRITE).store_buffer(bytes)
		var source := _level()
		_main.call("_show_main_menu")
		_check(_level() == source and _main.get("_active_run"), "a result notification cannot replace its publishing nonlethal source"))
	if _mode == "forged":
		EventBus.mechanism_toggled.emit(&"ch2_yong_down", true)
		await _frames(2)
		_check(not GameState.has_flag(RESULT) and _prompt() == null, "a raw nonlethal channel cannot authorize an unfinished original action")
		_actor.call("_on_pull_completed")
		await _frames(2)
		_check(not cell.done and not GameState.has_flag(RESULT) and _prompt() == null, "a forged subdued state without the original completed cell is refused")
		_prepare_opening()
	Input.action_press(&"interact")
	for i in 120:
		if cell.done: break
		await _frames(1)
	Input.action_release(&"interact")
	await _frames(4)
	_check(cell.done and _actor.call("is_subdued") and not _actor.is_dying(), "actual held interaction completes the original cell without killing the boss")
	_check(_prompt() != null and get_tree().paused and _level().channel_result_pending, "refused nonlethal result holds the original world with its retry prompt")
	_check(not GameState.has_flag(RESULT) and _observations.is_empty(), "refused nonlethal result cannot publish its story flag")
	_check(FileAccess.get_file_as_bytes(store.path) == _before, "refused original action retains exact whole primary bytes")
	await _shot("nonlethal-refused")
	if _prompt() == null: await _done(); return
	if _mode == "cancel":
		_main.call("_show_main_menu")
		await _frames(6)
		_check(not GameState.has_flag(RESULT) and FileAccess.get_file_as_bytes(store.path) == _before, "menu cancellation preserves the complete original unaccepted run")
		await _done()
		return
	if _mode in ["death", "stale"]:
		var original := _level()
		if _mode == "death":
			_player().health.kill(DamageInfo.create(_player().health.current, Combat.Team.ENEMY, &"probe_pending_action"))
			await _frames(3)
			_main.call("_on_retry_requested", original)
			_check(_level() == original, "pending nonlethal result rejects a partial-death retry")
		else:
			_actor.data = _actor.data.duplicate(true)
			_prompt().get("retry_button").pressed.emit()
			await _frames(3)
		_check(not GameState.has_flag(RESULT) and FileAccess.get_file_as_bytes(store.path) == _before, "interrupted or changed nonlethal source cannot accept or overwrite the original run")
		_check(_prompt() != null and _main.get("_channel_completion").get("_reload_original"), "interrupted nonlethal action requires original whole-run recovery")
		if _prompt() == null: await _done(); return
		DirAccess.remove_absolute(store.path + ".tmp")
		_prompt().get("retry_button").pressed.emit()
		await _frames(12)
		_check(_level() != original and not GameState.has_flag(RESULT) and not _player().is_dead() and GameState.deaths == 0, "recovery restores the original complete living run without accepting the action")
		await _done()
		return
	_prompt().get("retry_button").pressed.emit()
	await _frames(3)
	_check(not GameState.has_flag(RESULT) and FileAccess.get_file_as_bytes(store.path) == _before, "a second refused nonlethal write preserves the same original primary")
	if _prompt() == null: await _done(); return
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only this test's owned obstruction")
	_prompt().get("retry_button").pressed.emit()
	await _frames(4)
	_check(GameState.has_flag(RESULT) and _observations == [true], "one genuine nonlethal result notifies only after its original complete save")
	_check(_prompt() == null and not _level().channel_result_pending and not _actor.is_dying(), "accepted nonlethal result releases its pending world without an enemy death")
	await _shot("nonlethal-accepted")
	await _done()

func _prepare_opening() -> void:
	# Explicit terminal battle-state/position fixture; the held action below is real.
	_actor.set_physics_process(false)
	_actor.call("_enter_subdue", "subdue", false)
	_actor.call("_disarm")
	_actor.health.current = 1
	_actor.fsm.transition(&"recover")
	_actor.contact.active = false
	_player().global_position = _actor.global_position + Vector2(-_actor.facing * 4, 0)
	_player().velocity = Vector2.ZERO
	_player().set_physics_process(false)
	var cell: BossHoldPoint = _actor.call("power_cell")
	cell.enabled = _actor.call("can_pull_cell")

func _yong() -> Node:
	for node: Node in _level().channel_sources:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node is PatternBoss and node.data.id == &"yong": return node
	return null
