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
	await _capture_feedback(suite, settings)
	await _quality_hints(suite, settings)
	InputBindings.set_joy_button(&"jump", joy[&"jump"])
	InputBindings.set_code(&"jump", 0, codes[&"jump"][0])
	suite.check(InputBindings._codes == codes and InputBindings._joy == joy, "settings checks restore every original keyboard and controller binding")
	if is_instance_valid(settings): settings.close()
	await suite.frames(3)
	InputBindings.clear_held_inputs()
	InputBindings._set_device(previous_gamepad, previous_device)
	await _localized_av_copy(suite)


static func _exercise(suite: TestSuite, settings: SettingsScreen) -> bool:
	await _mouse(suite)
	var previous_label := InputBindings.primary_label(&"inventory_prev_tab")
	var next_label := InputBindings.primary_label(&"inventory_next_tab")
	suite.check(not InputBindings.using_gamepad and settings._controller_note.text.begins_with(previous_label + "/" + next_label), "settings initially shows real keyboard page bindings")
	suite.check(settings._controller_note.text.contains("PgUp") and settings._controller_note.text.contains("PgDn")
		and not settings._controller_note.text.contains("右搖桿"), "settings show only the keyboard scroll controls during keyboard use")
	suite.check(settings._controller_note.text.contains(InputBindings.joy_label(&"ui_cancel")), "controller note names the actual short/long B rule even with keyboard input")
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	suite.check(settings._tabs.current_tab == 1, "consumed RB changes exactly one settings page")
	suite.check(InputBindings.using_gamepad and InputBindings.active_device == 999, "consumed settings RB records the actual controller")
	suite.check(settings._hold_rule_labels[0].text.contains(InputBindings.joy_label(&"jump")), "settings hold rules immediately use the controller after RB")
	suite.check(_visible_focus(suite, settings), "settings page change retains focus in the visible tab")
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	suite.check(settings._tabs.current_tab == 3 and _visible_focus(suite, settings), "controller settings page is reachable with visible focus")
	suite.check(settings._controller_note.text.begins_with(InputBindings.joy_label(&"inventory_prev_tab") + "/" + InputBindings.joy_label(&"inventory_next_tab")), "controller page note follows consumed shoulder-key events")
	suite.check(settings._controller_note.text.contains("右搖桿") and not settings._controller_note.text.contains("PgDn")
		and not settings._controller_note.text.contains("Page Up"), "settings show only the right stick after controller navigation")
	await _mouse(suite)
	suite.check(settings._controller_note.text.contains("PgDn"), "settings restores the keyboard scroll controls after mouse input")
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


static func _capture_feedback(suite: TestSuite, settings: SettingsScreen) -> void:
	if not await _begin(suite, settings, 0, false):
		return
	var focus: Control = suite.runner.get_viewport().gui_get_focus_owner()
	var key: Button = settings._binding_buttons[settings._binding_key(&"jump", 1)]
	var pad: Button = settings._binding_buttons[settings._binding_key(&"jump", SettingsScreen.JOY_SLOT)]
	var instruction := settings._status.text
	await _hover(suite, key)
	suite.check(settings._capturing and focus.has_focus() and settings._status.text == instruction,
			"hover cannot overwrite the active keyboard capture instructions")
	await _key(suite, KEY_2)
	var error := settings._status.text
	suite.check(error != instruction and settings._capturing, "reserved key leaves capture active and explains the refusal")
	await _hover(suite, pad)
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	suite.check(settings._capturing and focus.has_focus() and settings._status.text == error
			and InputBindings.using_gamepad, "mouse hover and controller detection preserve the active refusal")
	await _key(suite, KEY_ESCAPE)
	await _hover(suite, key)
	suite.check(not settings._capturing and settings._status.text == key.tooltip_text,
			"hover resumes after capture is canceled")


static func _hover(suite: TestSuite, control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	motion.relative = Vector2(9, 0)
	suite.runner.get_viewport().push_input(motion, true)
	await suite.frames(3)


static func _quality_hints(suite: TestSuite, settings: SettingsScreen) -> void:
	var before := Settings.get_light_quality()
	var tab_before := settings._tabs.current_tab
	settings._tabs.current_tab = 2
	await suite.frames(2)
	var tier := LightQuality.Tier.HIGH if before == LightQuality.Tier.LOW else LightQuality.Tier.LOW
	var index := settings._quality_option.get_item_index(tier)
	settings._quality_option.select(index)
	settings._quality_option.item_selected.emit(index)
	settings._brightness_slider.grab_focus()
	await suite.frames(2)
	settings._quality_option.grab_focus()
	await suite.frames(2)
	suite.check(settings._status.text == LightQuality.DESCRIPTIONS[tier], "quality focus explains the current selection after a real selection signal")
	for point: Vector2 in [Vector2(2, 2), settings._quality_option.get_global_rect().get_center()]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		suite.runner.get_viewport().push_input(motion, true)
		await suite.frames(2)
	suite.check(settings._status.text == settings._quality_option.tooltip_text and settings._status.text == LightQuality.DESCRIPTIONS[tier], "quality hover and focus share the current description, not its construction-time copy")
	Settings.set_light_quality(before)
	settings._tabs.current_tab = tab_before

static func _localized_av_copy(suite: TestSuite) -> void:
	var previous_language := Story.language
	var previous_master := Settings.get_volume(&"Master")
	Settings.set_volume(&"Master", 0.0)
	for entry: Array in [["en", "Muted", "Fullscreen", "Low", "Restart to apply."],
			["ja", "ミュート", "フルスクリーン", "低", "再起動後に反映されます。"]]:
		Story.language = entry[0]
		var screen := SettingsScreen.new()
		suite.runner.add_child(screen)
		await suite.frames(3)
		suite.check(screen._slider_values[&"Master"].text == entry[1]
				and not screen._sliders[&"Master"].tooltip_text.is_empty(), "audio mute and hints use " + entry[0])
		screen._tabs.current_tab = 2
		await suite.frames(3)
		var tier := LightQuality.Tier.LOW
		var index := screen._quality_option.get_item_index(tier)
		suite.check(screen._fullscreen.text == entry[2] and screen._quality_option.get_item_text(index) == entry[3]
				and screen._story_language_option.tooltip_text == entry[4], "display captions and original option IDs use " + entry[0])
		screen.close()
		await suite.frames(3)
	Story.language = previous_language
	Settings.set_volume(&"Master", previous_master)
