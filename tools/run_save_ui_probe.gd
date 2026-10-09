extends Node
## 真實 Forward+ 視窗與控制項測量；設定只在記憶體覆寫，不動玩家設定。

const Capture := preload("res://tools/viewport_capture.gd")
var _directory := ""
var _scale := 1.0
var _failures := 0
var _started := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-dir="):
			_directory = argument.trim_prefix("--save-dir=")
		elif argument.begins_with("--text-scale="):
			_scale = argument.trim_prefix("--text-scale=").to_float()
	if not _directory.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[RunSaveUI] 需要真實視窗及絕對隔離輸出目錄")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	Settings.get("_config").set_value("display", "ui_text_scale", _scale)
	Settings.get("_config").set_value("display", "reduce_ui_motion", true)
	UiKit.apply_text_scale()
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	var menu := MainMenu.new()
	menu.continue_available = true
	menu.overwrite_required = true
	menu.start_requested.connect(func(_difficulty: DifficultyData) -> void: _started += 1)
	add_child(menu)
	await _frames(30)
	var page: Control = menu.get("_main_page")
	var hint: Label = menu.get("_hint")
	var last_end := 0.0
	var rows: Array = []
	for child in page.get_children():
		if child is VBoxContainer:
			for button: Button in child.get_children():
				last_end = maxf(last_end, button.get_global_rect().end.y)
				rows.append({"text": button.text, "logical": _rect(button.get_global_rect()), "viewport_bounds": _rect(_bounds(button))})
	_check(rows.size() == 5, "Continue menu actually has five rows")
	_check(last_end + 7 <= hint.get_global_rect().position.y, "actual button end leaves hint gap")
	_check(hint.get_global_rect().end.y < 334, "hint ends before footer at 334")
	await RenderingServer.frame_post_draw
	Capture.image(get_viewport()).save_png(_directory.path_join("menu.png"))
	menu.call("_open_difficulty")
	(menu.get("_confirm_button") as Button).grab_focus()
	menu.call("_on_start")
	await _frames(5)
	var prompt: RunOverwritePrompt = menu.get("_overwrite_dialog")
	_check(get_viewport().gui_get_focus_owner() == prompt.cancel_button, "Cancel is default focus")
	var panel := prompt.get_child(1) as PanelContainer
	_check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "solid prompt is fully inside viewport")
	await RenderingServer.frame_post_draw
	Capture.image(get_viewport()).save_png(_directory.path_join("overwrite.png"))
	var measurements := {"window": [get_window().size.x, get_window().size.y], "text_scale": _scale, "rows": rows, "hint": _rect(_bounds(hint)), "button_end_logical": last_end, "hint_logical": _rect(hint.get_global_rect()), "panel": _rect(_bounds(panel)), "cancel": _rect(_bounds(prompt.cancel_button))}
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(5)
	_check(not is_instance_valid(prompt) and _started == 0, "Esc returns without starting or overwriting")
	_check(get_viewport().gui_get_focus_owner() == menu.get("_confirm_button"), "focus restores to departure button")
	menu.call("_on_start")
	await _frames(5)
	prompt = menu.get("_overwrite_dialog")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	Input.parse_input_event(back)
	await _frames(5)
	_check(not is_instance_valid(prompt) and _started == 0, "synthetic gamepad B returns without starting")
	var file := FileAccess.open(_directory.path_join("bounds.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()
	menu.queue_free()
	await _frames(4)
	print("[RunSaveUI] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _bounds(control: Control) -> Rect2:
	return control.get_viewport().get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _rect(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _check(condition: bool, message: String) -> void:
	print("PASS " + message if condition else "FAIL " + message)
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
