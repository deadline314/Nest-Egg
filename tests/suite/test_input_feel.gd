class_name InputFeelSuite
extends TestSuite
## 輸入手感（NE-145）：緩衝與取消窗口來自資料、壞值退回預設；手把瞄準輔助只給手把、有錐形與距離限制、玩家輸入優先；
## 輸入延遲量測；衝刺提前按會排隊。

func run() -> void:
	_test_windows_from_data()
	_test_aim_assist()
	_test_latency()
	await _test_controller_flow()
	await _test_controller_ui_flow()
	await _test_dash_buffer()


func _test_controller_ui_flow() -> void:
	var probe := ControllerFlowProbe.new()
	await probe.run(runner, check)


func _joy_motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 999  # Synthetic device; never claim a physical controller test.
	event.axis = axis
	event.axis_value = value
	return event


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 999
	event.button_index = button
	event.pressed = true
	return event


func _test_controller_flow() -> void:
	var previous_path := Settings.storage_path()
	var previous_gamepad := InputBindings.using_gamepad
	var previous_device := InputBindings.active_device
	var previous_aim := AimInput.using_gamepad
	var test_path := "user://test_controller_options.cfg"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	Settings.use_storage(test_path)
	InputBindings.reload_from_settings()
	InputBindings._set_device(false)
	_test_controller_prompts()
	_test_controller_options(test_path)
	_test_controller_aim()
	await _test_controller_navigation()
	await _test_controller_interruption()
	Settings.use_storage(previous_path)
	InputBindings.reload_from_settings()
	InputBindings._set_device(previous_gamepad, previous_device)
	AimInput.using_gamepad = previous_aim
	DirAccess.remove_absolute(test_path)
	await runner.get_tree().process_frame


func _test_controller_prompts() -> void:
	InputBindings.observe_device(_joy_motion(JOY_AXIS_RIGHT_X, 0.15))
	check(not InputBindings.using_gamepad, "stick drift inside deadzone does not switch prompts")
	var notifications := [0]
	var changed := func() -> void: notifications[0] += 1
	InputBindings.bindings_changed.connect(changed)
	InputBindings.observe_device(_joy_motion(JOY_AXIS_RIGHT_X, 0.7))
	check(InputBindings.using_gamepad and AimInput.using_gamepad and notifications[0] == 1, "deliberate stick input switches aim and prompts once")
	var legend := InputBindings.format("{jump} {shoot} {ui_accept} {ui_cancel} {inventory_prev_tab} {inventory_next_tab}")
	check(not legend.contains("{") and legend.contains("RT") and legend.contains("LB") and legend.contains("RB"), "UI and fixed-action tokens use controller bindings")
	InputBindings.set_joy_button(&"jump", JOY_BUTTON_X)
	check(InputBindings.primary_label(&"jump").begins_with("X") and InputBindings.primary_label(&"interact").begins_with("A"), "controller rebinding swaps conflicts and refreshes actual prompts")
	check(InputBindings.set_joy_button(&"quests", -1) == &"" and InputBindings.get_joy_button(&"map") == -1, "clearing a controller slot does not swap other unbound actions")
	check(not InputBindings.joy_binding_error(&"map", JOY_BUTTON_X).is_empty(), "an optional shortcut cannot steal jump's only controller button")
	InputBindings.set_joy_button(&"map", JOY_BUTTON_X)
	check(InputBindings.get_joy_button(&"jump") == JOY_BUTTON_X and InputBindings.get_joy_button(&"map") == -1, "rejected controller conflicts preserve essential inputs")
	var old_button := InputBindings.get_joy_button(&"jump")
	InputBindings.set_joy_button(&"jump", JOY_BUTTON_MAX)
	check(InputBindings.get_joy_button(&"jump") == old_button, "invalid controller button indices are rejected")
	check(InputBindings.primary_label(&"map").contains("選單"), "unbound map shortcut directs the controller user to the menu")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(0.1, 0)
	InputBindings.observe_device(mouse)
	check(InputBindings.using_gamepad, "subpixel mouse noise does not switch devices")
	mouse.relative = Vector2(10, 0)
	InputBindings.observe_device(mouse)
	check(not InputBindings.using_gamepad and not AimInput.using_gamepad, "mouse movement switches both prompts and aim")
	InputBindings.observe_device(_joy_motion(JOY_AXIS_RIGHT_X, 0.7))
	check(not InputBindings.using_gamepad, "unchanged held stick does not reclaim control after mouse input")
	InputBindings.observe_device(_joy_motion(JOY_AXIS_RIGHT_X, 0.9))
	check(InputBindings.using_gamepad, "a deliberate new stick movement reclaims controller control")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_A
	key.pressed = true
	InputBindings.observe_device(key)
	check(not InputBindings.using_gamepad, "keyboard activity restores keyboard prompts")
	check(InputBindings.primary_label(&"ui_accept") == "Enter" and InputBindings.primary_label(&"jump") == "Space", "keyboard UI and action labels are unchanged by controller rebinding")
	InputBindings.bindings_changed.disconnect(changed)
	InputBindings.reset_to_defaults()
	check(_joy_button(JOY_BUTTON_A).is_action_pressed(&"ui_accept") and not _joy_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0).is_action_pressed(&"ui_accept"), "A confirms menus on any device index; gameplay triggers cannot accidentally confirm")
	check(_joy_motion(JOY_AXIS_LEFT_Y, 1.0).is_action_pressed(&"ui_down") and _joy_button(JOY_BUTTON_DPAD_DOWN).is_action_pressed(&"ui_down"), "analog and digital menu navigation are both mapped on any device index")


func _test_controller_options(path: String) -> void:
	InputBindings.set_aim_deadzone(0.2)
	InputBindings.set_invert_aim_y(true)
	InputBindings.set_vibration_strength(0.25)
	check(InputBindings.filtered_aim(Vector2(0.1, 0.1)) == Vector2.ZERO, "radial deadzone suppresses diagonal stick drift")
	check(InputBindings.filtered_aim(Vector2(0.6, 0.8)).is_equal_approx(Vector2(0.6, -0.8)), "full-scale radial input stays normalized and Y inversion is applied once")
	check(InputBindings.vibration_for(0.8, 0.4).is_equal_approx(Vector2(0.2, 0.1)), "vibration strength scales both motors")
	Settings.save_now()
	Settings.use_storage(path)
	InputBindings.reload_from_settings()
	check(is_equal_approx(InputBindings.get_aim_deadzone(), 0.2) and InputBindings.get_invert_aim_y() and is_equal_approx(InputBindings.get_vibration_strength(), 0.25), "controller options survive a settings reload")
	InputBindings.set_vibration_strength(0.0)
	check(InputBindings.vibration_for(1.0, 1.0) == Vector2.ZERO, "zero vibration eliminates haptics without altering gameplay input")
	InputBindings.set_aim_deadzone(0.99)
	check(is_equal_approx(InputBindings.get_aim_deadzone(), 0.6) and is_equal_approx(InputMap.action_get_deadzone(&"aim_up"), 0.6), "aim deadzone range and InputMap stay synchronized")
	Settings.set_value("controller", "aim_deadzone", "broken")
	Settings.set_value("controller", "invert_aim_y", 7)
	Settings.set_value("controller", "vibration_strength", NAN)
	InputBindings.reload_from_settings()
	check(is_equal_approx(InputBindings.get_aim_deadzone(), 0.3) and not InputBindings.get_invert_aim_y() and is_equal_approx(InputBindings.get_vibration_strength(), 1.0), "malformed controller preferences use safe defaults")


func _test_controller_aim() -> void:
	var node := Node2D.new()
	runner.add_child(node)
	InputBindings.set_aim_deadzone(0.2)
	InputBindings.set_invert_aim_y(true)
	InputBindings.observe_device(_joy_button(JOY_BUTTON_X))
	Input.action_press(&"aim_down", 1.0)
	var origin := Vector2(100, 100)
	var direction := AimInput.direction_from(node, origin, Vector2.RIGHT)
	check(direction.y < -0.99, "synthetic stick aim observes the configured vertical inversion")
	Input.action_release(&"aim_down")
	check(AimInput.direction_from(node, origin, Vector2.RIGHT).y < -0.99, "neutral stick retains its last aim direction")
	Input.action_press(&"aim_right", 1.0)
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(10, 0)
	InputBindings.observe_device(mouse)
	direction = AimInput.direction_from(node, origin, Vector2.LEFT)
	check(not AimInput.using_gamepad and direction.x < 0.0, "held right-stick action cannot override a later mouse source")
	InputBindings.clear_held_inputs()
	InputBindings.set_invert_aim_y(false)
	Input.action_press(&"aim_right")
	AimInput.set_virtual_gamepad(node, true)
	check(AimInput.direction_from(node, origin, Vector2.LEFT).x > 0.99 and not AimInput.using_gamepad and not InputBindings.using_gamepad, "virtual tool aim is node-scoped and does not alter recent real devices")
	AimInput.set_virtual_gamepad(node, false)
	check(AimInput.direction_from(node, origin, Vector2.LEFT).x < 0.0, "clearing a tool override restores the recent mouse source")
	InputBindings.clear_held_inputs()
	var layer := CanvasLayer.new()
	layer.transform = Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	runner.add_child(layer)
	var hidden := Node2D.new()
	layer.add_child(hidden)
	check(AimInput.direction_from(hidden, origin, Vector2.UP) == Vector2.UP, "singular canvas safely retains fallback aim without mouse inversion")
	check(AimInput.target_point(hidden, origin, Vector2.UP) == origin + Vector2.UP * 72.0, "singular canvas safely retains a fallback crosshair without mouse inversion")
	# 負控制已驗完；queue_free 延後執行前，不把奇異畫布留給下一個 UI 輸入事件求逆。
	layer.transform = Transform2D.IDENTITY
	layer.queue_free()
	node.queue_free()


func _test_controller_interruption() -> void:
	var player := Node2D.new()
	runner.add_child(player)
	player.add_to_group(&"player")
	InputBindings.observe_device(_joy_button(JOY_BUTTON_X))
	Input.action_press(&"shoot")
	Input.action_press(&"jump")
	InputBindings._on_joy_connection_changed(123, false)
	check(not InputBindings.is_controller_interrupted(), "disconnecting an inactive controller does not pause")
	InputBindings._on_joy_connection_changed(999, false)
	check(InputBindings.is_controller_interrupted() and runner.get_tree().paused and GameplayLock.is_locked(), "disconnecting the active controller protects live gameplay")
	check(not Input.is_action_pressed(&"shoot") and not Input.is_action_pressed(&"jump"), "disconnect releases held gameplay actions")
	var prompt := InputBindings._recovery_prompt
	check(is_instance_valid(prompt) and prompt.is_visible_in_tree(), "disconnect has a persistent visible recovery prompt")
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	check(runner.get_viewport().gui_get_focus_owner() == prompt.resume_button and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "recovery owns visible focus and exposes the mouse")
	Input.parse_input_event(_joy_button(JOY_BUTTON_B))
	Input.parse_input_event(_joy_motion(JOY_AXIS_LEFT_Y, 0.8))
	await runner.get_tree().process_frame
	check(InputBindings.is_controller_interrupted() and runner.get_viewport().gui_get_focus_owner() == prompt.resume_button, "cancel and stick motion cannot resume or escape recovery focus")
	InputBindings._on_joy_connection_changed(999, true)
	check(InputBindings.is_controller_interrupted(), "reconnecting alone does not resume gameplay")
	check(prompt._title.text == prompt.copy("手把已重新連線", "再接続しました", "Controller reconnected"), "recovery visibly acknowledges reconnection")
	InputBindings._on_joy_connection_changed(999, false)
	check(InputBindings.is_controller_interrupted() and InputBindings._recovery_prompt == prompt and prompt._title.text == prompt.copy("手把已斷線", "接続が切れました", "Controller disconnected"), "repeated disconnect keeps one prompt and one pause")
	Input.parse_input_event(_joy_button(JOY_BUTTON_A))
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	check(not runner.get_tree().paused and not GameplayLock.is_locked() and not Input.is_action_pressed(&"jump"), "deliberate confirmation resumes without leaking a jump")
	check(InputBindings._recovery_prompt == null and InputBindings._recovery_layer == null and not is_instance_valid(prompt), "confirmation removes recovery UI without leaving an input blocker")
	var confirm_release := _joy_button(JOY_BUTTON_A)
	confirm_release.pressed = false
	Input.parse_input_event(confirm_release)
	runner.get_tree().paused = true
	InputBindings._on_joy_connection_changed(999, false)
	check(runner.get_tree().paused and not InputBindings.is_controller_interrupted(), "a pre-existing modal pause remains owned by its screen")
	runner.get_tree().paused = false
	Input.action_press(&"shoot")
	InputBindings._on_focus_exited()
	check(not Input.is_action_pressed(&"shoot"), "focus loss clears held actions")
	InputBindings.observe_device(_joy_button(JOY_BUTTON_X))
	InputBindings._on_joy_connection_changed(999, false)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await runner.get_tree().process_frame
	check(not InputBindings.is_controller_interrupted() and not runner.get_tree().paused and not InputBindings.using_gamepad, "keyboard confirmation resumes and restores keyboard prompts")
	check(not Input.is_action_pressed(&"jump") and not Input.is_action_pressed(&"interact"), "keyboard confirmation does not leak gameplay actions")
	key.pressed = false
	Input.parse_input_event(key)
	# 恢復不得放掉別人的暫停；按鈕也必須能用真實滑鼠事件操作。
	InputBindings.observe_device(_joy_button(JOY_BUTTON_X))
	InputBindings._on_joy_connection_changed(999, false)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	prompt = InputBindings._recovery_prompt
	var other_lock := GameplayLock.acquire(player)
	var point: Vector2 = prompt.resume_button.get_global_rect().get_center()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = prompt.get_viewport().get_final_transform() * point
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await runner.get_tree().process_frame
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	check(not InputBindings.is_controller_interrupted() and InputBindings._recovery_prompt == null, "mouse can deliberately activate recovery")
	check(runner.get_tree().paused and GameplayLock.held_only_by(other_lock), "recovery releases only its own lock")
	check(not Input.is_action_pressed(&"shoot"), "mouse recovery does not leak a shot")
	GameplayLock.release(other_lock)
	InputBindings.observe_device(_joy_button(JOY_BUTTON_X))
	InputBindings._on_joy_connection_changed(999, false)
	player.free()
	await runner.get_tree().process_frame
	check(not InputBindings.is_controller_interrupted() and not GameplayLock.is_locked() and InputBindings._recovery_layer == null, "removing the interrupted player releases the prompt and its pause")


func _test_controller_navigation() -> void:
	var column := VBoxContainer.new()
	runner.add_child(column)
	var buttons: Array[Button] = []
	for index in 3:
		var button := Button.new()
		button.text = "Navigation %d" % index
		column.add_child(button)
		buttons.append(button)
	for index in 3:
		buttons[index].focus_neighbor_bottom = buttons[(index + 1) % 3].get_path()
	await runner.get_tree().process_frame
	buttons[0].grab_focus()
	InputBindings.clear_held_inputs()
	InputBindings._input(_joy_motion(JOY_AXIS_LEFT_Y, 0.8))
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	check(runner.get_viewport().gui_get_focus_owner() == buttons[1], "analog menu direction moves focus once")
	InputBindings._input(_joy_motion(JOY_AXIS_LEFT_Y, 0.9))
	await runner.get_tree().process_frame
	check(runner.get_viewport().gui_get_focus_owner() == buttons[1], "axis motion noise does not rapidly advance menu selection")
	InputBindings._on_navigation_repeat()
	await runner.get_tree().process_frame
	check(runner.get_viewport().gui_get_focus_owner() == buttons[2], "held analog direction repeats through the shared timer")
	InputBindings._input(_joy_motion(JOY_AXIS_LEFT_Y, 0.0))
	check(InputBindings._navigation_action == &"" and InputBindings._navigation_timer.is_stopped(), "neutral analog stick stops menu repeat")
	InputBindings.clear_held_inputs()
	column.free()


func _test_windows_from_data() -> void:
	var errors: PackedStringArray = InputFeel.validate()
	check(errors.is_empty(), "input feel data has no errors: %s" % ", ".join(errors))
	for key in InputFeel.KNOWN_BUFFERS:
		check(InputFeel.window(key, -1.0) >= 0.0, "window %s is defined in data" % key)
	check(is_equal_approx(MeleeData.buffer_time(), InputFeel.window("melee_buffer", 0.0)), "the melee buffer comes from the input data")
	check(InputFeel.window("test_no_such_window", 0.07) == 0.07, "a missing window falls back to the given default")


func _targets(positions: Array) -> Array:
	var nodes: Array = []
	for pos: Vector2 in positions:
		var node := Node2D.new()
		runner.get_tree().root.add_child(node)
		node.global_position = pos
		nodes.append(node)
	return nodes


func _free(nodes: Array) -> void:
	for node: Node in nodes:
		node.queue_free()


func _test_aim_assist() -> void:
	var origin := Vector2(0.0, 0.0)
	# 目標在搖桿方向微偏處（敵人瞄點是腳底往上 20）：往目標拉一點。
	var near := _targets([Vector2(200.0, 20.0 + 14.0)])
	var pulled := InputFeel.assist(origin, Vector2.RIGHT, near, 0.0, true)
	var target_angle := Vector2(200.0, 14.0).angle()
	check(pulled.angle() > 0.0 and pulled.angle() < target_angle + 0.001, "the assist pulls the aim toward a target inside the cone (%.3f of %.3f rad)" % [pulled.angle(), target_angle])
	# 只給手把。
	check(InputFeel.assist(origin, Vector2.RIGHT, near, 0.0, false) == Vector2.RIGHT, "the mouse is never assisted")
	# 錐形與距離之外不拉。
	var outside := _targets([Vector2(200.0, 20.0 + 120.0), Vector2(900.0, 20.0)])
	check(InputFeel.assist(origin, Vector2.RIGHT, outside, 0.0, true) == Vector2.RIGHT, "targets outside the cone or too far away do not pull")
	# 玩家輸入優先：搖桿快速轉動時輔助關閉。
	check(InputFeel.assist(origin, Vector2.RIGHT, near, 99.0, true) == Vector2.RIGHT, "fast stick turns switch the assist off")
	# 拉力有上限：最多只拉到目標，而且遠小於整個錐形。
	var assisted_angle := absf(pulled.angle())
	check(assisted_angle <= absf(target_angle) and assisted_angle >= 0.0, "the assist never overshoots the target")
	check(InputFeel.assist(origin, Vector2.ZERO, near, 0.0, true) == Vector2.ZERO, "no stick input means no assist")
	_free(near)
	_free(outside)


func _test_latency() -> void:
	InputFeel.reset_latency()
	check(InputFeel.resolve(&"shoot") == -1.0, "resolving an action that was never pressed gives nothing")
	InputFeel.mark(&"shoot")
	OS.delay_msec(5)
	var elapsed := InputFeel.resolve(&"shoot")
	check(elapsed >= 4.0 and elapsed < 500.0 and is_equal_approx(InputFeel.last_ms, elapsed), "the latency is the time from the press to the effect (%.1f ms)" % elapsed)
	check(InputFeel.samples == 1 and is_equal_approx(InputFeel.average_ms, elapsed), "the running average follows the samples")
	check(Feel.read_counters().has("input_latency_ms"), "the diagnostics expose the input latency")
	InputFeel.reset_latency()


func _test_dash_buffer() -> void:
	var level := await start_level(PropsSuite.level_data())
	var player := level.player
	await physics_frames(10)
	player._dash_cooldown_left = 0.08
	player._try_dash(1.0)
	check(player.state != Player.State.DASH and player._dash_buffer_left > 0.0, "a dash pressed during the cooldown is queued")
	await physics_frames(12)
	check(player._dash_buffer_left == 0.0 and (player.state == Player.State.DASH or player._dash_cooldown_left > 0.0), "the queued dash fires when the cooldown ends")
	await physics_frames(3)
	await end_level(level)
