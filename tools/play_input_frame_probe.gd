extends "res://tools/route_frame_time_probe.gd"
## Native gameplay timing on an isolated Main. Uses authored keyboard/mouse
## bindings and never moves the desktop pointer.
const CONTROLS: Array[StringName] = [&"melee", &"block", &"shoot", &"move_right"]

var _level_sample: Level
var _action := ""
var _previous_frame := 0
var _input_frames: Array[Array] = []
var _events: Array[Dictionary] = []
var _prompt: Node2D
var _dialogue_exit := ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("gameplay frame measurements require a native renderer")
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dialogue-exit="):
			_dialogue_exit = arg.trim_prefix("--dialogue-exit=")
			if _dialogue_exit not in ["pause", "leave"]:
				_fail("--dialogue-exit must be pause or leave")
				return
	super._ready()
	set_process(false)
	RenderingServer.frame_pre_draw.connect(_sample_frame)


func _run() -> void:
	Story.auto_skip = true
	_main = load("res://scenes/main.tscn").instantiate()
	_main.set("_run_store", RunSaveStore.new(_slot_path))
	add_child(_main)
	if not await _wait_menu():
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	if not await _level("ch1_prologue") or not await _portal("pawnshop", "ch1_pawnshop"):
		return
	_level_sample = _main.get("_screen") as Level
	_level_sample._next_story_trigger = _level_sample._layout.story_triggers.size()
	var old_k: NpcActor
	for actor: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if actor is NpcActor and actor.data.rig_id == "old_k":
			old_k = actor
			break
	if old_k == null:
		_fail("the pawnshop needs its authored Old K")
		return
	var player := _level_sample.player
	player.teleport_to(old_k.global_position + Vector2(-130, 0))
	_level_sample.camera.snap_to_target()
	await _wait(0.4)
	_previous_frame = Time.get_ticks_usec()
	for iteration in 4:
		for action: StringName in CONTROLS:
			if not await _press_binding(action, 0.12):
				return
			await _wait(0.45)
		_action = ""
		player.teleport_to(old_k.global_position + Vector2(-84, 0))
		player.velocity = Vector2.ZERO
		_level_sample.camera.snap_to_target()
		await _wait(0.18)
		_action = "approach"
		if not await _press_binding(&"move_right", 0.43, "approach"):
			return
		await _wait(0.35)
		if iteration == 0:
			if not await _measure_dialogue():
				return
	_previous_frame = 0
	var output := FileAccess.open(_out.path_join(_tag + ".json"), FileAccess.WRITE)
	if output == null:
		_fail("cannot write gameplay frame measurements")
		return
	var maxima: Dictionary[String, float] = {}
	for row: Array in _input_frames:
		maxima[row[0]] = maxf(maxima.get(row[0], 0.0), float(row[2]) / 1000.0)
	output.store_string(JSON.stringify({
		"columns": ["action", "time_us", "frame_us", "physics_frame", "player_x", "canvas_x", "guard", "melee_pose", "mag_rounds", "locked", "canvas_compilations"],
		"frames": _input_frames, "events": _events, "maximum_ms": maxima,
		"device": RenderingServer.get_video_adapter_name(), "refresh": DisplayServer.screen_get_refresh_rate(),
		"physics_hz": Engine.physics_ticks_per_second, "vsync": DisplayServer.window_get_vsync_mode(),
		"level": _level_sample.data.resource_path,
	}))
	output.close()
	print("PLAY_INPUT_COMPLETE ", _input_frames.size(), " frames ", JSON.stringify(maxima))
	_main.call("_quit", 0)


func _measure_dialogue() -> bool:
	Story.auto_skip = _dialogue_exit.is_empty()
	if not await _press_binding(&"interact", 0.10):
		return false
	await _wait(0.65)
	if _dialogue_exit.is_empty():
		return true
	if not Story.is_cinematic_active() or not GameplayLock.is_locked():
		_fail("the authored dialogue never opened; disable cinematic skipping for this probe")
		return false
	if _active_capture:
		_previous_frame = 0
		await RenderingServer.frame_post_draw
		var screenshot := CAPTURE.image(get_viewport())
		screenshot.save_jpg(_out.path_join(_tag + "-dialogue.jpg"), 0.82)
		_previous_frame = Time.get_ticks_usec()
	_action = "dialogue_exit"
	if _dialogue_exit == "pause":
		if not await _press_binding(&"pause", 0.10, "dialogue_exit"):
			return false
	else:
		_mark("cancel", "leave")
		Story.reset_active_presentation(&"leave")
	await _wait(0.30)
	if Story.is_cinematic_active() or GameplayLock.is_locked():
		_fail("exiting the dialogue left the gameplay lock active")
		return false
	Story.auto_skip = true
	return true


func _sample_frame() -> void:
	if _previous_frame == 0:
		return
	var now := Time.get_ticks_usec()
	var player := _level_sample.player
	var target := Story.framing.interaction_prompt_target()
	if target != _prompt:
		_prompt = target
		_mark("prompt", str(target.name) if is_instance_valid(target) else "")
	_input_frames.append([_action, now, now - _previous_frame, Engine.get_physics_frames(),
		player.global_position.x, get_viewport().get_canvas_transform().origin.x, player.is_blocking,
		player.melee_pose(), player.loadout.mag_in(0), GameplayLock.is_locked(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS)])
	_previous_frame = now


func _press_binding(action: StringName, seconds: float, label := "") -> bool:
	_action = String(action) if label.is_empty() else label
	for binding: InputEvent in InputMap.action_get_events(action):
		if not (binding is InputEventKey or binding is InputEventMouseButton):
			continue
		var event: InputEvent = binding.duplicate()
		if event is InputEventMouseButton:
			event.position = get_viewport().get_visible_rect().size * 0.75
		event.pressed = true
		_mark("press", String(action))
		Input.parse_input_event(event)
		await _wait(seconds)
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		_mark("release", String(action))
		return true
	_fail("missing keyboard or mouse binding for " + String(action))
	return false


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _mark(kind: String, detail: String) -> void:
	_events.append({"action": _action, "event": kind, "detail": detail, "at_us": Time.get_ticks_usec()})
