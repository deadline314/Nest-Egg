extends RefCounted
## Real input ownership: opening/using the bag must update the active-device legend.

static func run(suite: TestSuite) -> void:
	var previous_gamepad := InputBindings.using_gamepad
	var previous_device := InputBindings.active_device
	var level := await suite.start_level(PropsSuite.level_data())
	var bag: InventoryScreen = level._inventory
	await _mouse(suite)
	var keyboard_name := InputBindings.primary_label(&"inventory")
	bag.open()
	await suite.frames(4)
	suite.check(bag.is_open() and not InputBindings.using_gamepad and bag._legend_label.text.begins_with(keyboard_name + " "), "mouse-opened bag shows actual keyboard inventory binding")
	var initial := bag._current
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	suite.check(bag._current == posmod(initial + 1, bag._pages.size()), "consumed controller RB still changes exactly one page")
	suite.check(InputBindings.using_gamepad and InputBindings.active_device == 999, "consumed bag event records the actual controller")
	suite.check(_pad_legend(bag), "consumed RB immediately replaces keyboard legend with controller bindings")
	await _mouse(suite)
	suite.check(not InputBindings.using_gamepad and bag._legend_label.text.begins_with(keyboard_name + " "), "mouse motion restores keyboard legend without closing or changing page")
	await _joy(suite, JOY_BUTTON_LEFT_STICK)
	suite.check(InputBindings.using_gamepad and _pad_legend(bag), "unconsumed controller event also refreshes the open bag legend")
	await _key(suite, KEY_RIGHT)
	suite.check(not InputBindings.using_gamepad and bag._legend_label.text.begins_with(keyboard_name + " "), "consumed keyboard navigation immediately restores keyboard bindings")
	await _joy(suite, JOY_BUTTON_B)
	suite.check(not bag.is_open() and not suite.runner.get_tree().paused, "controller Back still closes once and resumes play")
	await _mouse(suite)
	await _joy(suite, JOY_BUTTON_BACK)
	suite.check(bag.is_open() and InputBindings.using_gamepad and _pad_legend(bag), "first controller inventory press opens with matching device hints")
	var index := bag.page_index(UpgradesPage)
	bag.select_tab(index)
	await suite.frames(8)
	var page := bag._pages[index] as UpgradesPage
	suite.check(page._entries.size() >= 4, "stick navigation fixture contains at least four real upgrade choices")
	page._select(0)
	await _axis(suite, .8)
	suite.check(page._selected == 1, "left stick initially selects exactly one entry")
	await _axis(suite, .95)
	var pressure_selection := page._selected
	suite.check(pressure_selection == 1, "changing held-stick pressure does not add a navigation press")
	await suite.runner.get_tree().create_timer(InputBindings.NAVIGATION_REPEAT_DELAY + InputBindings.NAVIGATION_REPEAT_INTERVAL * 2.5).timeout
	suite.check(page._selected > pressure_selection, "holding the stick repeats navigation after the existing shared delay")
	await _axis(suite, 0)
	var released_selection := page._selected
	await suite.runner.get_tree().create_timer(InputBindings.NAVIGATION_REPEAT_DELAY + InputBindings.NAVIGATION_REPEAT_INTERVAL).timeout
	suite.check(page._selected == released_selection, "releasing the stick stops further selection changes")
	bag.close()
	await suite.frames(3)
	InputBindings.clear_held_inputs()
	await suite.end_level(level)
	InputBindings._set_device(previous_gamepad, previous_device)


static func _pad_legend(bag: InventoryScreen) -> bool:
	return bag._legend_label.text.contains(InputBindings.joy_label(&"ui_cancel")) and bag._legend_label.text.contains(InputBindings.joy_label(&"inventory_prev_tab")) and bag._legend_label.text.contains(InputBindings.joy_label(&"inventory_next_tab"))


static func _mouse(suite: TestSuite) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(2, 2)
	event.relative = Vector2(8, 0)
	Input.parse_input_event(event)
	await suite.frames(2)


static func _key(suite: TestSuite, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await suite.frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await suite.frames(1)


static func _joy(suite: TestSuite, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 999
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await suite.frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await suite.frames(1)


static func _axis(suite: TestSuite, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 999
	event.axis = JOY_AXIS_LEFT_Y
	event.axis_value = value
	Input.parse_input_event(event)
	await suite.frames(2)
