extends Node
## Runs the real Main routes with a fresh save under an explicit output directory.
## godot --path . res://tools/route_frame_time_probe.tscn -- --out=<absolute> --tag=<run> [--capture]
## --visible-budget-ms checks input to cover; --autosave-budget-ms adds real movement and saves.
const LEVEL_DIR := "res://data/levels/"
const CAPTURE := preload("res://tools/viewport_capture.gd")

var _main: Node
var _out := ""
var _tag := ""
var _phase := ""
var _active_capture := false
var _last_usec := 0
var _slot_path := ""
var _visible_budget_ms := 0.0
var _autosave_budget_ms := 0.0
var _autosave: Dictionary = {}
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
		elif arg.begins_with("--visible-budget-ms="):
			_visible_budget_ms = arg.trim_prefix("--visible-budget-ms=").to_float()
			if not _valid_budget(_visible_budget_ms):
				return
		elif arg.begins_with("--autosave-budget-ms="):
			_autosave_budget_ms = arg.trim_prefix("--autosave-budget-ms=").to_float()
			if not _valid_budget(_autosave_budget_ms):
				return
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
	if _autosave_budget_ms > 0.0 and not await _drive_autosaves():
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
	var visible := _visible_frame_maxima()
	file.store_string(JSON.stringify({"routes": _routes, "frames": _frames, "visible_max_ms": visible,
			"autosave": _autosave}))
	file.close()
	var status := 0
	if _visible_budget_ms > 0.0:
		for phase: String in visible:
			if visible[phase] > _visible_budget_ms:
				push_error("%s exceeded the visible frame budget: %.1f > %.1f ms" % [phase, visible[phase], _visible_budget_ms])
				status = 2
	if _autosave_budget_ms > 0.0 and _autosave["max_ms"] > _autosave_budget_ms:
		push_error("Autosave run exceeded the frame budget: %.1f > %.1f ms" % [_autosave["max_ms"], _autosave_budget_ms])
		status = 2
	print("ROUTE_COMPLETE ", _routes.size(), " points, ", _frames.size(), " frames, device ",
			RenderingServer.get_video_adapter_name())
	_main.call("_quit", status)


func _valid_budget(value: float) -> bool:
	if not is_finite(value) or value <= 0.0 or DisplayServer.get_name() == "headless":
		_fail("frame budgets require a positive value and a native renderer")
		return false
	return true


func _drive_autosaves() -> bool:
	var level := _main.get("_screen") as Level
	var until := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < until and GameplayLock.is_locked():
		await get_tree().process_frame
	if GameplayLock.is_locked():
		_fail("prologue stayed locked before the autosave probe")
		return false
	_phase = "autosave"
	_point("request")
	var from := _frames.size()
	var previous := FileAccess.get_sha256(_slot_path)
	var saved := 0
	var distance := 0.0
	for leg in 6:
		var start := level.player.position.x
		var move := &"move_right" if leg % 2 == 0 else &"move_left"
		Input.action_press(move)
		await get_tree().create_timer(0.9, true, true).timeout
		Input.action_release(move)
		if not is_instance_valid(level) or level != _main.get("_screen"):
			_fail("prologue changed during the autosave probe")
			return false
		distance += absf(level.player.position.x - start)
		var checksum := FileAccess.get_sha256(_slot_path)
		if not checksum.is_empty() and checksum != previous:
			saved += 1
			previous = checksum
	var maximum := 0.0
	for index in range(from, _frames.size()):
		maximum = maxf(maximum, _frames[index][2])
	_autosave = {"max_ms": maximum, "saved": saved, "distance": distance}
	_point("ready")
	print("AUTOSAVE ", JSON.stringify(_autosave))
	if saved == 0 or distance < 16.0:
		_fail("movement did not produce a completed prologue autosave")
		return false
	return true


func _visible_frame_maxima() -> Dictionary[String, float]:
	var covers: Dictionary[String, float] = {}
	for event: Dictionary in _routes:
		if event["phase"] != "startup" and event["event"] == "covered":
			covers[event["phase"]] = event["at"]
	var result: Dictionary[String, float] = {}
	for frame: Array in _frames:
		var phase: String = frame[0]
		if covers.has(phase) and frame[1] <= covers[phase]:
			result[phase] = maxf(result.get(phase, 0.0), frame[2])
	return result


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
