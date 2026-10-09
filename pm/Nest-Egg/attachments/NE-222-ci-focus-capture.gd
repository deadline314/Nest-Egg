extends "res://tools/screenshot.gd"
func _run_menus() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(30)
	var pause := level._pause_menu
	pause.open()
	await _wait(0.6)
	var button := pause._menu_panel.body.get_children().filter(func(child: Node) -> bool: return child is Button and (child as Button).text == "設定")[0] as Button
	button.grab_focus()
	assert(pause.get_viewport().gui_get_focus_owner() == button)
	pause._open_settings()
	await _wait(0.6)
	_capture("settings_open")
	var settings := pause._settings
	for key in [&"ui_down", &"ui_up", &"ui_down"]:
		var event := InputEventAction.new()
		event.action = key
		event.pressed = true
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame
		var release := event.duplicate() as InputEventAction
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().process_frame
	settings.close()
	await settings.tree_exited
	await get_tree().process_frame
	await get_tree().process_frame
	assert(pause.get_viewport().gui_get_focus_owner() == button)
	await RenderingServer.frame_post_draw
	_capture("settings_restored_focus")
	print("native GUI input/layout/focus assertions passed; original settings button restored")
	pause.close()
	level.queue_free()
