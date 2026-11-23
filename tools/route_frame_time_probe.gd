extends Node
## Runs the real Main routes with a fresh save under an explicit output directory.
## godot --path . res://tools/route_frame_time_probe.tscn -- --out=<absolute> --tag=<run> [--capture]
const LEVEL_DIR := "res://data/levels/"
const CAPTURE := preload("res://tools/viewport_capture.gd")

var _main: Node
var _out := ""
var _tag := ""
var _phase := ""
var _active_capture := false
var _last_usec := 0
var _slot_path := ""
var _frames: Array[Array] = []
var _routes: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg == "--capture":
			_active_capture = true
	if not _out.is_absolute_path() or not _tag.is_valid_filename() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("--out requires an absolute directory and --tag a new file name")
		return
	_slot_path = _out.path_join(_tag + "-slot.json")
	if RunSaveStore.new(_slot_path).exists() or FileAccess.file_exists(_out.path_join(_tag + ".json")):
		_fail("the output tag already exists")
		return
	Transition.covered.connect(func() -> void: _point("covered"))
	Transition.finished.connect(func() -> void: _point("revealed"))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_run.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_frames.append([_phase, now / 1000.0, (now - _last_usec) / 1000.0,
				Transition.is_active(), int(Performance.get_monitor(Performance.MEMORY_STATIC))])
	_last_usec = now


func _point(kind: String) -> void:
	_routes.append({"phase": _phase, "event": kind, "at": Time.get_ticks_usec() / 1000.0})


func _run() -> void:
	_phase = "startup"
	_point("request")
	_last_usec = Time.get_ticks_usec()
	Story.auto_skip = true
	_main = load("res://scenes/main.tscn").instantiate()
	_main.set("_run_store", RunSaveStore.new(_slot_path))
	add_child(_main)
	if not await _wait_menu():
		return
	_phase = "new-game"
	_point("request")
	_main.call("_on_start_requested", GameState.difficulties[1])
	if not await _level("ch1_prologue"):
		return
	if not await _portal("pawnshop", "ch1_pawnshop"):
		return
	if not await _portal("street", "ch1_street"):
		return
	if not await _portal("warehouse", "ch1_warehouse"):
		return
	_phase = "chapter-1-terminal-fixture"
	_point("request")
	_main.call("_on_area_requested", _path("ch1_pawnshop_dawn"))
	if not await _level("ch1_pawnshop_dawn"):
		return
	_phase = "chapter-1-to-2"
	_point("request")
	var terminal := _main.get("_screen") as Level
	terminal.completed.emit()
	if not await _level("ch2_pawnshop"):
		return
	_phase = "chapter-2-terminal-fixture"
	_point("request")
	_main.call("_on_area_requested", _path("ch2_rooftop"))
	if not await _level("ch2_rooftop"):
		return
	_phase = "chapter-2-to-3"
	_point("request")
	terminal = _main.get("_screen") as Level
	terminal.completed.emit()
	if not await _level("ch3_pawnshop"):
		return
	if _active_capture:
		await RenderingServer.frame_post_draw
		CAPTURE.image(get_viewport()).save_png(_out.path_join(_tag + ".png"))
	_last_usec = 0
	var file := FileAccess.open(_out.path_join(_tag + ".json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write metrics")
		return
	file.store_string(JSON.stringify({"routes": _routes, "frames": _frames}))
	file.close()
	print("ROUTE_COMPLETE ", _routes.size(), " points, ", _frames.size(), " frames, device ",
			RenderingServer.get_video_adapter_name())
	_main.call("_quit")


func _portal(phase: String, target: String) -> bool:
	_phase = phase
	var source := _main.get("_screen") as Level
	for portal: Node in source.find_children("*", "", true, false):
		if portal is Portal and portal.data.target_level == _path(target):
			_point("request")
			source.call("_on_portal_used", portal)
			return await _level(target)
	_fail("no authored portal to " + target)
	return false


func _wait_menu() -> bool:
	var until := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until:
		if _main.get("_screen") is MainMenu and not Transition.is_active():
			_point("ready")
			return true
		await get_tree().process_frame
	_fail("title menu never became interactive")
	return false


func _level(target: String) -> bool:
	var until := Time.get_ticks_msec() + 12000
	var observed := false
	while Time.get_ticks_msec() < until:
		var active := _main.get("_screen") as Level
		if active != null and active.is_initialized() and active.data.resource_path == _path(target):
			if not observed:
				_point("attached")
				observed = true
			if not Transition.is_active():
				_point("ready")
				await get_tree().create_timer(0.65, true, false, true).timeout
				return true
		await get_tree().process_frame
	_fail("target did not initialize " + target)
	return false


static func _path(level: String) -> String:
	return LEVEL_DIR + level + ".tres"


func _fail(reason: String) -> void:
	push_error("%s: %s" % [_phase, reason])
	get_tree().quit(2)
