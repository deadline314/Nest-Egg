extends Node
## NE-229 synthetic controller flow screenshots; never physical hardware evidence.
const Capture := preload("res://tools/viewport_capture.gd")
var _out_dir := "res://pm/Nest-Egg/images"
var _capture_failed := false
var _width := 1280
var _height := 720
var _text_scale := 1.0
var _settings_only := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var profile := OS.get_environment("NE229_CONTROLLER_CAPTURE_PROFILE").replace("\\", "/").simplify_path().to_lower()
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	if profile.is_empty() or not user_dir.begins_with(profile + "/"):
		printerr("[ControllerFlowCapture] Use tools/run_controller_capture.ps1 to launch an isolated capture profile.")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
		elif arg.begins_with("--text-scale="):
			_text_scale = float(arg.trim_prefix("--text-scale="))
		elif arg == "--settings-only":
			_settings_only = true
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	print("NE229_RENDERER ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	print("NE229_RENDER_THREAD_MODEL ", ProjectSettings.get_setting("rendering/driver/threads/thread_model"))
	var probe := ControllerFlowProbe.new()
	await probe.run(self, _report, _capture, _configure_profile, _settings_only)
	print("NE229_PREFETCH_REQUESTS ", AssetPrefetch._requested.size())
	get_tree().quit(0 if probe.failures.is_empty() and not _capture_failed else 1)


func _report(passed: bool, message: String) -> void:
	if not passed:
		printerr("FAIL: ", message)


func _configure_profile() -> void:
	Settings.set_ui_text_scale(_text_scale)
	print("NE229_CAPTURE_SIZE ", _width, "x", _height, " | text scale ", Settings.get_ui_text_scale())


func _capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join("NE-229-synthetic-%s.png" % tag)
	var result := Capture.image(get_viewport()).save_png(path)
	if result != OK:
		_capture_failed = true
		push_error("[ControllerFlowCapture] %s: %s" % [path, error_string(result)])
	else:
		print("NE229_SYNTHETIC_CAPTURE ", path)
