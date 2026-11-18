extends "res://tools/ch1_flow_probe.gd"
## Arranged real object interactions; combat and human playthrough are separate.
var _samples: Array[Dictionary] = []
var _sampling := false

func _run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	action_shot_prefix = "NE-240-ch1"
	_shots = {"ch1_t_pump_check:choice": "NE-240-ch1-pump-choice"}
	await _enter("pawnshop")
	_watch_world_actions()
	_sampling = true
	_sample_actions()
	await _talk(&"ch1_ledger_box")
	_check(GameState.has_flag(&"ch1_ledger_checked"), "ledger inspection records only its completed flag")
	await _talk(&"ch1_ledger_box")
	await _settle(20)
	_capture("NE-240-ch1-ledger-restored")
	_sampling = false
	_watching_actions = false
	await _settle(2)
	GameState.set_flag(&"watchdog_defeated")
	await _enter("warehouse")
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	await _talk(&"ch1_pump_service", ["later"])
	_check(not GameState.has_flag(&"ch1_pump_case_reset"), "declining leaves casing unchanged")
	_watch_world_actions()
	_sampling = true
	_sample_actions()
	await _talk(&"ch1_pump_service", ["reset"])
	_check(GameState.has_flag(&"ch1_pump_case_reset") and not GameState.has_flag(&"ch1_flood_gate_open"), "casing repair leaves main flood gate unchanged")
	_check(not _object(&"ch1_pump_service").is_present(), "repaired casing keeps its indicator without repeating an interaction prompt")
	await _settle(20)
	_capture("NE-240-ch1-pump-restored")
	_sampling = false
	_watching_actions = false
	await _settle(2)
	var file := FileAccess.open(_out_dir.path_join("frames.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_samples, "\t"))
	for id: String in ["ledger_lock_check", "pump_case_reset"]:
		var contacts := 0
		var worst := 0.0
		for sample: Dictionary in _samples:
			if sample["id"] == id and sample["phase"] in ["turn", "recoil"]:
				contacts += 1
				worst = maxf(worst, sample["error"])
		_check(contacts > 8 and worst <= WorldPropAction.CONTACT_TOLERANCE, "actual prop hand contact %s: %d frames, worst %.6f" % [id, contacts, worst])
	Story.reset_active_presentation(&"probe_cleanup")
	if is_instance_valid(_level): _level.queue_free()
	await _settle(15)
	await AudioRelease.settle(get_tree())
	print("NE240_CH1 failures=%d samples=%d" % [_failures, _samples.size()])
	get_tree().quit(0 if _failures == 0 else 1)

func _sample_actions() -> void:
	while _sampling and is_instance_valid(_level):
		await get_tree().process_frame
		if not _sampling or not is_instance_valid(_level): break
		var visual := _level.player._visual
		var action: WorldPropAction = visual.interaction_action
		if action == null or action.done: continue
		var id := ""
		for key: String in ["ledger_lock_check", "pump_case_reset"]:
			if WorldPropAction.definition(key) == action._spec: id = key
		var palm := visual.rig.hand_contact_global(&"front")
		_samples.append({"id": id, "phase": action.phase, "error": action.contact_error,
			"palm": [palm.x, palm.y], "player": [ _level.player.position.x, _level.player.position.y],
			"crouch": visual._interaction_input.crouching, "grip": visual._interaction_input.hand_grip_front})
