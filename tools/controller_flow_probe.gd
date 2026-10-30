class_name ControllerFlowProbe
extends RefCounted
## NE-229: actual UI routing driven only by synthetic controller events.
## This checks navigation and focus, not physical controllers or chapter completion.

var _host: Node
var _report: Callable
var _capture: Callable
var _game: Node
var checks := 0
var failures := PackedStringArray()


func run(host: Node, report: Callable, capture := Callable(),
		configure_profile := Callable(), settings_only := false) -> void:
	_host = host
	_report = report
	_capture = capture
	var owned_directory := _create_owned_directory()
	_check(not owned_directory.is_empty(), "controller probe owns an isolated settings and run directory")
	if owned_directory.is_empty(): return
	var original_settings := Settings.storage_path()
	var original_autosave := GameState.story_autosave
	var original_skip := Story.auto_skip
	var original_difficulty := GameState.difficulty
	GameState.story_autosave = false
	# Main enables autosave before start_new_run. Its synchronous life-count
	# notification disables it again before any deferred story-save flush.
	EventBus.lives_changed.connect(_disable_autosave)
	var probe_settings := owned_directory.path_join("settings.cfg")
	Settings.use_storage(probe_settings)
	if configure_profile.is_valid():
		configure_profile.call()
	InputBindings.reload_from_settings()
	Story.auto_skip = true
	InputBindings.clear_held_inputs()
	print("NE229_PHYSICAL_JOYPADS ", Input.get_connected_joypads(), " | probe uses synthetic device 999")
	if settings_only:
		await _walk_settings_only()
	else:
		_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		# Assign before Main._ready reads continue/import/overwrite state. Both
		# the slot and its sibling-edition search stay inside our fresh directory.
		_game.set("_run_store", RunSaveStore.new(owned_directory.path_join("run/slot.json")))
		_game.process_mode = Node.PROCESS_MODE_PAUSABLE
		_host.add_child(_game)
		await _walk_flow()
	GameState.story_autosave = false
	InputBindings.clear_held_inputs()
	if is_instance_valid(_game):
		_game.queue_free()
	GameplayLock.set_base_paused(false)
	Fx.reset_time()
	await _frames(3)
	EventBus.lives_changed.disconnect(_disable_autosave)
	Settings.use_storage(original_settings)
	InputBindings.reload_from_settings()
	GameState.story_autosave = original_autosave
	GameState.difficulty = original_difficulty
	Story.auto_skip = original_skip
	_check(_remove_owned_directory(owned_directory), "controller probe removes only its own temporary settings and saves")
	print("NE229_SYNTHETIC_FLOW checks=%d failures=%d" % [checks, failures.size()])


func _create_owned_directory() -> String:
	for attempt in 8:
		var path := "user://controller-flow-%d-%d-%d-%d" % [OS.get_process_id(), get_instance_id(), Time.get_ticks_usec(), attempt]
		if DirAccess.make_dir_absolute(path) == OK: return path
	return ""


func _remove_owned_directory(path: String) -> bool:
	var ok := true
	# Only these two directories were created by this probe. Unexpected nested
	# content causes cleanup failure instead of recursively following anything.
	for directory: String in [path.path_join("run"), path]:
		if not DirAccess.dir_exists_absolute(directory): continue
		for file: String in DirAccess.get_files_at(directory):
			if DirAccess.remove_absolute(directory.path_join(file)) != OK: ok = false
		if DirAccess.remove_absolute(directory) != OK: ok = false
	return ok


func _walk_settings_only() -> void:
	_game = SettingsScreen.new()
	_host.add_child(_game)
	_host.get_tree().paused = true
	await _frames(3)
	var settings := _game as SettingsScreen
	await _shot("settings-only-audio")
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(settings._tabs.current_tab == 1 and _visible_tab_focus(settings), "isolated paused settings enters bindings with real controller focus")
	await _probe_binding_capture(settings)
	await _shot("settings-only-bindings")
	await _probe_controller_options(settings)


func _disable_autosave(_lives: int) -> void:
	GameState.story_autosave = false


func _walk_flow() -> void:
	if not await _wait(func() -> bool: return _game._screen is MainMenu and not GameplayLock.is_locked()):
		_check(false, "actual Main routes to the main menu")
		return
	var menu := _game._screen as MainMenu
	_check(_focus() == menu._start_button, "new-game entry has visible initial focus")
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_DPAD_UP)
	if not await _focus_button("開始任務", JOY_BUTTON_DPAD_DOWN):
		return
	await _shot("main-menu")
	await _button(JOY_BUTTON_A)
	_check(menu._difficulty_page.visible and not menu._main_page.visible, "A opens real difficulty selection")
	_check(_focus() != null and menu._difficulty_page.is_ancestor_of(_focus()), "difficulty page owns focus")
	await _button(JOY_BUTTON_A)  # Confirm the selected card through the real GUI.
	if not await _focus_control(menu._confirm_button):
		return
	await _shot("difficulty")
	await _button(JOY_BUTTON_A)
	if not await _wait(func() -> bool: return _game._screen is Level and not GameplayLock.is_locked()):
		_check(false, "difficulty confirmation enters a playable level")
		return
	var level := _game._screen as Level
	_check(level.data.resource_path == "res://data/levels/ch1_prologue.tres", "real first-area routing is preserved")
	_check(is_instance_valid(level.player) and not level.player.is_dead(), "new game exposes a live player")
	await _button(JOY_BUTTON_BACK)
	_check(level._inventory.is_open() and _host.get_tree().paused, "Back opens the real inventory")
	await _shot("inventory")
	var page := level._inventory._current
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(level._inventory._current != page, "RB changes the inventory page")
	await _button(JOY_BUTTON_LEFT_SHOULDER)
	_check(level._inventory._current == page, "LB restores the inventory page")
	await _button(JOY_BUTTON_B)
	_check(not level._inventory.is_open() and not _host.get_tree().paused, "B returns from inventory to gameplay")
	await _button(JOY_BUTTON_START)
	var pause := level._pause_menu
	_check(pause._root.visible and _host.get_tree().paused, "Start opens the real pause screen")
	await _shot("pause")
	if not await _focus_button("任務", JOY_BUTTON_DPAD_DOWN):
		return
	await _button(JOY_BUTTON_A)
	var navigation := pause._navigation
	_check(is_instance_valid(navigation) and navigation._page == "quests", "A opens the actual quest page from pause")
	if not is_instance_valid(navigation):
		return
	await _shot("quests")
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(navigation._page == "region", "RB changes quests to the real region map")
	await _shot("region-map")
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(navigation._page == "world", "RB changes region map to the real world map")
	await _shot("world-map")
	for attempt in 4:
		if not is_instance_valid(pause._navigation):
			break
		await _button(JOY_BUTTON_B)
	_check(not is_instance_valid(pause._navigation), "B unwinds map history and returns to pause")
	if not await _focus_button("設定", JOY_BUTTON_DPAD_DOWN):
		return
	await _button(JOY_BUTTON_A)
	var settings := pause._settings
	_check(is_instance_valid(settings), "A opens settings from the real pause screen")
	if not is_instance_valid(settings):
		return
	_check(_focus() != null and settings.is_ancestor_of(_focus()), "settings owns modal focus")
	await _shot("settings-audio")
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(settings._tabs.current_tab == 1, "RB changes the settings tab")
	_check(_focus() != null and settings._tabs.get_current_tab_control().is_ancestor_of(_focus()), "settings tab focus remains on visible controls")
	await _probe_binding_capture(settings)
	await _shot("settings-bindings")
	await _probe_controller_options(settings)
	await _button(JOY_BUTTON_B)
	_check(not is_instance_valid(pause._settings) and pause._root.visible, "B closes settings and restores pause")
	_check(_focus() is Button and (_focus() as Button).text == "設定", "settings return restores its opening button's focus")
	await _button(JOY_BUTTON_B)
	_check(not pause._root.visible and not _host.get_tree().paused and not GameplayLock.is_locked(), "B returns from pause to live gameplay")
	_check(not Input.is_action_pressed(&"dash") and not Input.is_action_pressed(&"jump"), "return actions do not leak into combat")
	await _shot("gameplay-return")


func _probe_binding_capture(settings: SettingsScreen) -> void:
	var joy_button := settings._binding_buttons.get("move_left:-1") as Button
	var key_button := settings._binding_buttons.get("move_left:0") as Button
	if not await _focus_control(joy_button):
		return
	var original_joy := InputBindings.get_joy_button(&"move_left")
	await _button(JOY_BUTTON_A)
	_check(settings._capturing, "controller focus and A enter joypad binding capture")
	await _shot("settings-joy-capture")
	await _hold_button(JOY_BUTTON_B, 0.7)
	_check(not settings._capturing and InputBindings.get_joy_button(&"move_left") == original_joy, "holding B cancels joy capture without changing a binding")
	_check(_focus() == joy_button, "joy capture cancellation retains its original button focus")
	await _shot("settings-joy-long-b-cancel")
	if not await _focus_control(key_button):
		return
	var original_key := InputBindings.get_code(&"move_left", 0)
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_B)
	_check(not settings._capturing and InputBindings.get_code(&"move_left", 0) == original_key, "B cancels keyboard capture without changing a binding")
	_check(_focus() == key_button, "keyboard capture cancellation retains its original button focus")
	await _shot("settings-key-b-cancel")
	if not await _focus_control(joy_button):
		return
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_B)
	_check(not settings._capturing and InputBindings.get_joy_button(&"move_left") == JOY_BUTTON_B, "short B remains bindable in joypad capture")


func _probe_controller_options(settings: SettingsScreen) -> void:
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(settings._tabs.current_tab == 2 and _visible_tab_focus(settings), "RB enters the display tab with visible current-page focus")
	await _button(JOY_BUTTON_RIGHT_SHOULDER)
	_check(settings._tabs.current_tab == 3 and _visible_tab_focus(settings), "RB enters the controller tab with visible current-page focus")
	var deadzone := settings._controller_sliders.get("aim_deadzone") as HSlider
	var vibration := settings._controller_sliders.get("vibration_strength") as HSlider
	var original_deadzone := InputBindings.get_aim_deadzone()
	var original_invert := InputBindings.get_invert_aim_y()
	var original_vibration := InputBindings.get_vibration_strength()
	if not await _focus_control(deadzone):
		return
	await _button(JOY_BUTTON_DPAD_RIGHT)
	_check(InputBindings.get_aim_deadzone() > original_deadzone and is_equal_approx(deadzone.value, InputBindings.get_aim_deadzone() * 100.0), "controller events adjust the real aim deadzone slider")
	await _button(JOY_BUTTON_DPAD_LEFT)
	_check(is_equal_approx(InputBindings.get_aim_deadzone(), original_deadzone), "controller events restore the original aim deadzone")
	if not await _focus_control(settings._controller_invert):
		return
	await _button(JOY_BUTTON_A)
	_check(InputBindings.get_invert_aim_y() != original_invert, "controller A toggles the actual vertical-aim option")
	await _button(JOY_BUTTON_A)
	_check(InputBindings.get_invert_aim_y() == original_invert, "controller A restores the original vertical-aim option")
	if not await _focus_control(vibration):
		return
	await _button(JOY_BUTTON_DPAD_LEFT)
	_check(InputBindings.get_vibration_strength() < original_vibration and is_equal_approx(vibration.value, InputBindings.get_vibration_strength() * 100.0), "controller events adjust the real vibration slider")
	await _button(JOY_BUTTON_DPAD_RIGHT)
	_check(is_equal_approx(InputBindings.get_vibration_strength(), original_vibration), "controller events restore the original vibration strength")
	await _shot("settings-controller")


func _visible_tab_focus(settings: SettingsScreen) -> bool:
	var current := _focus()
	return current != null and current.is_visible_in_tree() and settings._tabs.get_current_tab_control().is_ancestor_of(current)


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
	if _report.is_valid():
		_report.call(passed, "controller flow: " + message)


func _focus() -> Control:
	return _host.get_viewport().gui_get_focus_owner()


func _focus_button(text: String, direction: JoyButton) -> bool:
	for attempt in 16:
		if _focus() is Button and (_focus() as Button).text == text:
			return true
		await _button(direction)
	_check(false, "controller focus can reach '%s'" % text)
	return false


func _focus_control(target: Control) -> bool:
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		_check(false, "binding capture target exists in the visible settings tab")
		return false
	# Read layout only to choose a direction; every focus change still comes from
	# actual controller events, including ScrollContainer's native focus scrolling.
	for attempt in 48:
		var current := _focus()
		if current == target:
			return true
		if current == null:
			break
		var delta := target.get_global_rect().get_center() - current.get_global_rect().get_center()
		var direction: JoyButton
		if absf(delta.y) > 6.0:
			direction = JOY_BUTTON_DPAD_DOWN if delta.y > 0.0 else JOY_BUTTON_DPAD_UP
		else:
			direction = JOY_BUTTON_DPAD_RIGHT if delta.x > 0.0 else JOY_BUTTON_DPAD_LEFT
		await _button(direction)
		if _focus() == current:
			await _button(JOY_BUTTON_DPAD_RIGHT if delta.x > 0.0 else JOY_BUTTON_DPAD_LEFT)
	_check(false, "controller focus reaches the binding capture target")
	return false


func _wait(predicate: Callable) -> bool:
	for frame in 600:
		if predicate.call():
			await _frames(3)
			return true
		await _frames(1)
	return false


func _frames(count: int) -> void:
	for frame in count:
		await _host.get_tree().process_frame


func _button(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 999
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	# A tap must stay short even when rendering three frames takes >0.6 s.
	# Keep the same six settling frames after delivering the complete tap.
	await _frames(6)


func _hold_button(button: JoyButton, seconds: float) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 999
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	# Start the measured hold only after GUI delivery, including slow renderers.
	Input.flush_buffered_events()
	await _host.get_tree().create_timer(seconds, true, false, true).timeout
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(3)


func _shot(tag: String) -> void:
	if _capture.is_valid():
		await _capture.call(tag)
