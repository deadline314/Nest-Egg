extends "res://tools/ch2_flow_probe.gd"
## Authored radio NPC, original choices; native frame samples supplement CPU tests.
var _samples: Array[Dictionary] = []
var _sampling := false

func _run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	_carry_ch1_results()
	level_pattern = "res://data/levels/ch2_%s.tres"
	action_shot_prefix = "NE-240-radio"
	_shots = {"ch2_t_s02_tune:choice": "NE-240-radio-choice", "ch2_t_s02_broadcast:choice": "NE-240-radio-broadcast"}
	await _enter("pawnshop")
	_watch_world_actions()
	_sampling = true
	_sample_actions()
	await _talk(&"ch2_radio", ["power", "antenna", "speaker", "edge", "middle", "off"])
	_check(GameState.has_flag(&"ch2_radio_repaired") and not StoryItems.holds(&"ch2_radio_clip"), "original off route repairs radio without granting the saved clip")
	var after := OS.get_cmdline_user_args().has("--expect-action")
	if after:
		_check(_action_phases.has("radio_tune_noise:turn") and _action_phases.has("radio_tune_noise:recoil"), "wrong tuning visibly turns and recoils")
		_check(_action_phases.has("radio_tune_clear:reach") and _action_phases.has("radio_tune_clear:turn") and _action_phases.has("radio_tune_clear:release"), "correct tuning reaches, turns and lets go")
	await _settle(24)
	_capture("NE-240-radio-restored")
	_sampling = false
	var file := FileAccess.open(_out_dir.path_join("frames.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_samples, "\t"))
	var contacts := 0
	var worst := 0.0
	for sample: Dictionary in _samples:
		if sample["phase"] in ["turn", "recoil"]:
			contacts += 1
			worst = maxf(worst, sample["error"])
	_check(contacts > 10 and worst <= WorldPropAction.CONTACT_TOLERANCE, "continuous active knob contact is bounded (%d frames, worst %.6f)" % [contacts, worst])
	_watching_actions = false
	Story.reset_active_presentation(&"probe_cleanup")
	if is_instance_valid(_level): _level.queue_free()
	await _settle(15)
	print("NE240_RADIO failures=%d phases=%s" % [_failures, _action_phases.keys()])
	get_tree().quit(0 if _failures == 0 else 1)

func _sample_actions() -> void:
	var last: WorldPropAction
	var tail := 0
	var frame := 0
	while _sampling and is_instance_valid(_level):
		await get_tree().process_frame
		if not _sampling or not is_instance_valid(_level): break
		var visual := _level.player._visual
		var action: WorldPropAction = visual.interaction_action
		if action != null and not action.done:
			last = action
			tail = 16
		elif tail > 0:
			tail -= 1
		else:
			continue
		frame += 1
		var phase := action.phase if action != null and not action.done else "restored"
		var sample := {"frame": frame, "scene": String(Story._current_cinematic), "phase": phase, "crouch": visual._interaction_input.crouching, "hand_grip": visual._interaction_input.hand_grip_front, "error": last.contact_error, "player": [_level.player.position.x, _level.player.position.y]}
		for bone: StringName in [&"foot_front", &"foot_back", &"pelvis"]:
			if visual.rig._bones.has(bone):
				var point: Vector2 = visual.rig._bones[bone].global_position
				sample[String(bone)] = [point.x, point.y]
		var palm := visual.rig.hand_contact_global(&"front")
		sample["palm"] = [palm.x, palm.y]
		_samples.append(sample)
		if frame % 6 == 0:
			_capture("NE-240-radio-sequence-%03d-%s" % [frame, phase])
