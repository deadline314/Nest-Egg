extends "res://tools/ch1_flow_probe.gd"
## NE-229：正式序章關卡內合成斷線；不是實體拔插或整章通關。

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = true
	var language := "zh"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--language="):
			language = arg.trim_prefix("--language=")
		elif arg == "--text-scale=1.2":
			Settings.set_ui_text_scale(1.2)
	Story.set_language(language)
	await _enter("prologue")
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	Story.reset_active_presentation(&"probe")
	await _settle(10)
	var device := InputEventJoypadButton.new()
	device.device = 999
	device.button_index = JOY_BUTTON_X
	device.pressed = true
	InputBindings.observe_device(device)
	var mouse_before := Input.mouse_mode
	InputBindings._on_joy_connection_changed(999, false)
	var position := _level.player.global_position
	var clock := GameState.run_time
	await get_tree().create_timer(4.0, true).timeout
	_check(InputBindings.is_controller_interrupted() and get_tree().paused, "disconnect remains paused after notification timeout")
	_check(_level.player.global_position == position and GameState.run_time == clock, "actual player and clock remain frozen")
	if _route == "verify":
		_verify_prompt()
	await RenderingServer.frame_post_draw
	_capture("disconnected-" + language)
	await get_tree().process_frame
	InputBindings._on_joy_connection_changed(999, true)
	InputBindings.observe_device(device)
	await _settle(3)
	_check(InputBindings.is_controller_interrupted(), "reconnect does not auto resume")
	if _route == "verify":
		_verify_prompt()
	await RenderingServer.frame_post_draw
	_capture("reconnected-" + language)
	await get_tree().process_frame
	device.button_index = JOY_BUTTON_A
	Input.parse_input_event(device)
	await _settle(2)
	_check(not InputBindings.is_controller_interrupted() and not get_tree().paused and not Input.is_action_pressed(&"jump"), "confirm resumes without jump")
	_check(Input.mouse_mode == mouse_before, "recovery restores the gameplay cursor mode")
	device.pressed = false
	Input.parse_input_event(device)
	InputBindings.clear_held_inputs()
	Story.reset_active_presentation(&"probe")
	Story.auto_skip = false
	await _settle(3)
	_level.queue_free()
	await _settle(20)
	print("[ControllerRecoveryProbe] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _verify_prompt() -> void:
	var prompt := InputBindings._recovery_prompt
	_check(is_instance_valid(prompt) and prompt.is_visible_in_tree(), "recovery stays visible after four seconds or reconnection")
	_check(get_viewport().gui_get_focus_owner() == prompt.resume_button, "recovery owns focus")
	_check(prompt._title.get_line_count() == 1, "localized status title fits on one line")
	var area := get_viewport().get_visible_rect()
	for node: Node in prompt.find_children("*", "Control", true, false):
		if node is Label or node is Button:
			_check(area.encloses(node.get_global_rect()), "localized text and button fit viewport: " + node.get_class())
			if node is Label:
				_check(node.size.y + 0.1 >= node.get_minimum_size().y, "localized label has its full minimum height")
