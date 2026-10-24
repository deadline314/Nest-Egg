extends RefCounted
## Consumed settings events still identify their real input device.

static func run(suite: TestSuite) -> void:
	var previous_gamepad := InputBindings.using_gamepad
	var previous_device := InputBindings.active_device
	var codes := InputBindings._codes.duplicate(true)
	var joy := InputBindings._joy.duplicate(true)
	var settings := SettingsScreen.new()
	suite.runner.add_child(settings)
	await suite.frames(4)
	suite.check(await _exercise(suite, settings), "all settings device/capture stages complete")
	InputBindings.set_joy_button(&"jump", joy[&"jump"])
	InputBindings.set_code(&"jump", 0, codes[&"jump"][0])
	suite.check(InputBindings._codes == codes and InputBindings._joy == joy, "settings checks restore every original keyboard and controller binding")
	if is_instance_valid(settings): settings.close()
	await suite.frames(3)
	InputBindings.clear_held_inputs()
	InputBindings._set_device(previous_gamepad, previous_device)


static func _exercise(suite: TestSuite, settings: SettingsScreen) -> bool:
	await _mouse(suite)
	var previous_label := InputBindings.primary_label(&"inventory_prev_tab")
	var next_label := InputBindings.primary_label(&"inventory_next_tab")
	suite.check(not InputBindings.using_gamepad and settings._controller_note.text.begins_with(previous_label + "/" + next_label), "settings initially shows real keyboard page bindings")
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	suite.check(settings._tabs.current_tab == 1, "consumed RB changes exactly one settings page")
	suite.check(InputBindings.using_gamepad and InputBindings.active_device == 999, "consumed settings RB records the actual controller")
	suite.check(settings._hold_rule_labels[0].text.contains(InputBindings.joy_label(&"jump")), "settings hold rules immediately use the controller after RB")
	suite.check(_visible_focus(suite, settings), "settings page change retains focus in the visible tab")
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	suite.check(settings._tabs.current_tab == 3 and _visible_focus(suite, settings), "controller settings page is reachable with visible focus")
	suite.check(settings._controller_note.text.begins_with(InputBindings.joy_label(&"inventory_prev_tab") + "/" + InputBindings.joy_label(&"inventory_next_tab")), "controller page note follows consumed shoulder-key events")
	await _mouse(suite)
	suite.check(not InputBindings.using_gamepad and settings._controller_note.text.begins_with(previous_label + "/" + next_label), "mouse restores keyboard settings hints without closing")
	var original_joy := InputBindings.get_joy_button(&"jump")
	if not await _begin(suite, settings, SettingsScreen.JOY_SLOT, false): return false
	await _joy(suite, JOY_BUTTON_B)
	suite.check(not settings._capturing and InputBindings.get_joy_button(&"jump") == JOY_BUTTON_B, "short B retains the original controller-binding behavior")
	suite.check(InputBindings.using_gamepad and settings._hold_rule_labels[0].text.contains(InputBindings.joy_label(&"jump")), "consumed short B refreshes controller identity and hold rules")
	InputBindings.set_joy_button(&"jump", original_joy)
	if not await _begin(suite, settings, SettingsScreen.JOY_SLOT, false): return false
	var capture_button := suite.runner.get_viewport().gui_get_focus_owner()
	_send(_button(JOY_BUTTON_B, true))
	suite.check(settings._binding_buttons[settings._binding_key(&"jump", SettingsScreen.JOY_SLOT)].text == "按下…" and settings._status.text.contains(InputBindings.joy_label(&"ui_cancel")), "device change preserves the active capture marker and truthful B instructions")
	await suite.runner.get_tree().create_timer(.75).timeout
	suite.check(not settings._capturing and InputBindings.get_joy_button(&"jump") == original_joy and suite.runner.get_viewport().gui_get_focus_owner() == capture_button, "long B cancels without changing the binding or losing focus")
	suite.check(InputBindings.using_gamepad, "consumed long B still records the controller")
	_send(_button(JOY_BUTTON_B, false))
	await suite.frames(2)
	var original_key := InputBindings.get_code(&"jump", 0)
	if not await _begin(suite, settings, 0, true): return false
	capture_button = suite.runner.get_viewport().gui_get_focus_owner()
	await _key(suite, KEY_ESCAPE)
	suite.check(not settings._capturing and InputBindings.get_code(&"jump", 0) == original_key and suite.runner.get_viewport().gui_get_focus_owner() == capture_button, "Escape cancels keyboard capture without changing its value or focus")
	suite.check(not InputBindings.using_gamepad, "consumed Escape immediately restores keyboard identity")
	if not await _begin(suite, settings, 0, true): return false
	await _key(suite, KEY_K)
	suite.check(not settings._capturing and InputBindings.get_code(&"jump", 0) == KEY_K, "public keyboard capture applies the actual new key")
	suite.check(not InputBindings.using_gamepad and settings._hold_rule_labels[0].text.begins_with("按住 K "), "consumed new keyboard binding immediately appears in the keyboard hold rules")
	return true


static func _begin(suite: TestSuite, settings: SettingsScreen, slot: int, controller: bool) -> bool:
	settings._cancel_capture()
	settings._tabs.current_tab = 1
	await suite.frames(3)
	var button: Button = settings._binding_buttons[settings._binding_key(&"jump", slot)]
	button.grab_focus()
	await suite.frames(2)
	if controller: await _joy(suite, JOY_BUTTON_A)
	else: await _key(suite, KEY_ENTER)
	var ready := settings._capturing and settings._capture_action == &"jump" and settings._capture_slot == slot
	suite.check(ready, "public confirm starts the arranged settings capture: slot %d controller %s" % [slot, controller])
	if ready:
		suite.check(settings._status.text.contains(InputBindings.joy_label(&"ui_cancel")) and settings._status.text.contains("Esc"), "capture instructions identify both the real controller button and Escape")
	return ready


static func _visible_focus(suite: TestSuite, settings: SettingsScreen) -> bool:
	var owner := suite.runner.get_viewport().gui_get_focus_owner()
	return owner != null and owner.is_visible_in_tree() and settings._tabs.get_current_tab_control().is_ancestor_of(owner)


static func _mouse(suite: TestSuite) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(2, 2)
	event.relative = Vector2(8, 0)
	_send(event)
	await suite.frames(2)


static func _key(suite: TestSuite, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	await _tap(suite, event)


static func _button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 999
	event.button_index = button
	event.pressed = pressed
	return event


static func _joy(suite: TestSuite, button: JoyButton) -> void:
	await _tap(suite, _button(button, true))


static func _tap(suite: TestSuite, event: InputEvent) -> void:
	_send(event)
	await suite.frames(2)
	var release := event.duplicate()
	release.set("pressed", false)
	_send(release)
	await suite.frames(2)


static func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
