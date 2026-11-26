extends "res://tools/ch6_studio_trial_probe.gd"
## Copies an actual ST52 completed slot into --save-dir. --keep-line picks the second leaf.

const LINK := &"ch6_control_link"
const DIAGNOSTICS := &"ch6_t_control_diag"
const DECISION := &"ch6_t_control_decision"
const FORWARD_SCENE := &"ch6_t_relay_ali_call"
const KEEP_SCENE := &"ch6_t_keep_relay_feed"
const DECIDED := &"ch6_control_call_decided"
const RELAYED := &"ali_call_relayed"
const TUNE := ["relay", "filter", "listen"]


func _write() -> void:
	if not await _resume_to(RECORDING):
		return
	var store := _main.get("_run_store") as RunSaveStore
	var before := store.read()
	_check(GameState.has_flag(TRIAL) and GameState.has_flag(MET) and not GameState.has_flag(DECIDED)
			and StoryItems.holds(ORIGINAL), "actual ST52 slot has private trial, custody and a pending decision")
	var keep := OS.get_cmdline_user_args().has("--keep-line")
	if keep:
		await _service(LINK, TUNE + ["keep"])
	else:
		await _service(LINK, ["leave"])
		await _service(LINK, ["relay", "leave"])
		_check(not _played.has(String(DECISION)) and not GameState.has_flag(DECIDED),
				"leaving diagnosis at either step keeps the caller pending")
		await _service(LINK, TUNE + ["review"])
		await _service(LINK, TUNE + ["leave"])
		_check(not GameState.has_flag(DECIDED), "review and defer choices preserve the undecided state")
		await _service(LINK, TUNE + ["forward"], FORWARD_SCENE)
		_check(not GameState.has_flag(DECIDED) and not GameState.has_flag(RELAYED),
				"skipping a selected leaf preserves the actual pending state")
		if not await _refuse_call_save(store):
			return
	var after := store.read()
	var flags: Dictionary = after["story"]["flags"]
	_check(_flag_is_saved(store, DECIDED) and flags.has(String(RELAYED)) and flags[String(RELAYED)] == (not keep)
			and GameState.has_flag(RELAYED) == (not keep), "the selected true/false outcome and the resolution marker persist together")
	_check(after["level"] == RECORDING and before["story"]["items"] == after["story"]["items"]
			and before["progression"] == after["progression"] and before["runtime"]["loadout"] == after["runtime"]["loadout"]
			and before["story"]["deaths"] == after["story"]["deaths"], "the remote control leaves Rin's area, custody, receipts and equipment intact")
	_check(not GameState.has_flag(&"ch6_broadcast_started"), "monitoring leaves the public broadcast pending")
	await _service(LINK)
	var revisit := "ch6_t_control_revisit_keep" if keep else "ch6_t_control_revisit_forward"
	_check(_played.has(revisit), "the same terminal reads back the saved route")
	_check_audit()


func _refuse_call_save(store: RunSaveStore) -> bool:
	var link := _object(LINK)
	if link == null:
		return false
	_level.player.global_position = link.global_position + Vector2(-7, 0)
	await _settle(12)
	var anchor := _level.player.global_position
	var done := [false]
	var talk := func() -> void:
		done[0] = await link._talk()
	talk.call()
	await _drive(TUNE, func() -> bool: return Story._current_cinematic == DECISION)
	await _settle(16)
	var active := Story._player as CutscenePlayer
	_check(is_instance_valid(active) and active._stage != null and active._stage.prop_node("call_alarm").visible
			and active._stage.prop_node("relay_active").visible and active._stage.prop_node("clear_display").visible,
			"the incoming-call view restores distinct clear signal, active relay and call lamp")
	if OS.get_cmdline_user_args().has("--control-proof") and DisplayServer.get_name() != "headless":
		await _capture("ST-53-control")
	await _drive(["forward"], func() -> bool: return Story._current_cinematic == FORWARD_SCENE)
	await _settle(12)
	var retained := FileAccess.get_file_as_bytes(store.path)
	var obstruction := store.path + ".tmp"
	if DirAccess.make_dir_absolute(obstruction) != OK:
		_check(false, "cannot create isolated save obstruction")
		return false
	await _drive([], func() -> bool: return is_instance_valid(Story.result_completion.get("_prompt")))
	_check(not done[0] and not GameState.has_flag(DECIDED) and not GameState.has_flag(RELAYED)
			and FileAccess.get_file_as_bytes(store.path) == retained,
			"a refused write leaves both flags and previous live checkpoint intact")
	_check(DirAccess.remove_absolute(obstruction) == OK, "isolated refusal removed")
	Story.result_completion.call("_retry")
	await _drive([], func() -> bool: return done[0])
	_check(done[0] and _level.player.global_position.is_equal_approx(anchor),
			"retry commits once and returns to Rin's exact booth position")
	return done[0]


func _continue() -> void:
	if not await _resume_to(RECORDING):
		return
	var keep := OS.get_cmdline_user_args().has("--keep-line")
	_check(GameState.has_flag(TRIAL) and GameState.has_flag(DECIDED)
			and GameState.has_flag(RELAYED) == (not keep) and not GameState.has_flag(&"ch6_broadcast_started"),
			"cold Continue restores the selected tri-state leaf and the private feed")
	_check(not _played.has(String(DIAGNOSTICS)) and not _played.has(String(DECISION)),
			"cold Continue does not reopen an already resolved console")
	await _service(LINK)
	var revisit := "ch6_t_control_revisit_keep" if keep else "ch6_t_control_revisit_forward"
	_check(_played.has(revisit) and not _played.has(String(DIAGNOSTICS)), "the original terminal restores the same readback")
