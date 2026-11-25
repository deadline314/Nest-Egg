extends "res://tools/ch4_factory_probe.gd"
## Uses real Main/Portal and rebinding-aware Godot input. The source save is a
## previously completed office ledger, copied into the isolated --save-dir.

const Memory = preload("res://game/cutscene/local_replay/last_sunday.gd")
const OFFICE := "res://data/levels/ch4_factory_office.tres"
const MEMORY_DOOR := &"office_sunday_replay"
const SHORTCUT := &"ch4_safety_shortcut_open"
const LEDGER := &"ch4_original_ledger_saved"

var _door: Portal
var _memory: Memory


func _write() -> void:
	if not await _resume_office():
		return
	await _settle_office_save()
	# The probe positioned Rin without walking here. Persist that source state
	# exactly as a real route checkpoint before comparing the replay bytes.
	_main.call("_save_run", true)
	var story := GameState.story_progress_snapshot()
	var money := Progression.snapshot()
	var areas := GameState.area_states.duplicate(true)
	var hp := _level.player.health.current
	var origin := _level.player.global_position
	var save_file := _save_dir.path_join("slot.json")
	var bytes := FileAccess.get_file_as_bytes(save_file)
	var loadout := _level.player.checkpoint_snapshot()
	var before_shortcut := GameState.has_flag(SHORTCUT)
	var uses: Array[int] = [0]
	_door.used.connect(func(_p: Portal) -> void: uses[0] += 1)
	var save_owner: WeakRef = weakref(_level)
	var cinematic := String(_main.get("_cinematic"))
	var save_request := int(_main.get("_cinematic_request"))
	_check(_main.call("_can_finish_autosave", save_owner, cinematic, save_request),
			"the real office allows an ordinary queued autosave")
	if not await _start_memory():
		return
	_check(not _main.call("_can_finish_autosave", save_owner, cinematic, save_request),
			"opening the replay prevents an in-flight office autosave from publishing")
	_main.call("_queue_movement_autosave")
	_check(not _main.get("_autosave_queued") and not _main.get("_save_queued"),
			"an office movement autosave cannot queue during the replay")
	var actor: CutsceneActor = _memory._stage.get_node("Egret")
	_check(actor.rig != null and actor.rig.skin_id == "egret", "the controllable historical figure uses Egret's actual skeleton")
	_check(_memory._stage.get_world_2d() != _level.get_world_2d() and get_tree().get_nodes_in_group(&"player").size() == 1,
			"the archive scene has a private World2D and adds no competing Player")
	await _tap(&"interact")
	_check(_memory._beat == Memory.Beat.PLACE_NOTE, "the short note cannot be left remotely")
	await _tap(&"shoot")
	await _tap(&"block")
	await _tap(&"inventory")
	_check(_memory._beat == Memory.Beat.PLACE_NOTE and _level.player.health.current == hp,
			"combat and trade inputs cannot take over the historical replay")
	await _walk_to(_memory._goal)
	await _tap(&"interact")
	_check(_memory._beat == Memory.Beat.EGRET_WARD and _memory._stage.has_node("PlacedLetter"),
			"real movement and interact leave a visible note at the upper drawer")
	_check(FileAccess.get_file_as_bytes(save_file) == bytes, "historical placement has no durable effects")
	await _tap(&"ui_cancel")
	await _settle(4)
	_check(not is_instance_valid(_door._local_replay) and not get_tree().paused and not GameplayLock.is_locked(),
			"skip releases just the replay pause and removes its scene")
	_check(_level.player.global_position.distance_to(origin) < 1.0, "skip returns Rin at the same office side door")
	_check(_main.call("_can_finish_autosave", save_owner, cinematic, save_request),
			"returning to the office releases the replay guard for normal autosaves")

	if not await _start_memory():
		return
	bytes = FileAccess.get_file_as_bytes(save_file)
	_check(_memory._beat == Memory.Beat.PLACE_NOTE and not _memory._stage.has_node("PlacedLetter"),
			"reopening begins on the ward walkway before leaving the note")
	await _walk_to(_memory._goal)
	await _tap(&"interact")
	await _tap(&"interact")
	_check(_memory._beat == Memory.Beat.LINDEN, "Linden answers at the same historical cabinet")
	await _tap(&"interact")
	await _walk_to(_memory._exit)
	await _tap(&"interact")
	for i in 60:
		if _memory._beat == Memory.Beat.RELEASE_LEVER:
			break
		await _settle(1)
	_check(_memory._beat == Memory.Beat.RELEASE_LEVER and _memory._stage.name == "MemorySafety",
			"the ward door leads into the separately playable safety platform")
	if _memory._beat != Memory.Beat.RELEASE_LEVER:
		return
	_check(_memory._stage.get_node("Egret").position.y == _memory._goal.y, "Egret starts on the real upper landing")
	await _walk_to(_memory._goal)
	await _tap(&"interact")
	await _settle(25)
	_check(_memory._beat == Memory.Beat.EGRET_FACTORY and is_instance_valid(_memory._door),
			"the local SC7 latch is visible and triggers Egret's explanation")
	_check(GameState.has_flag(SHORTCUT) == before_shortcut, "moving the historical latch leaves the actual shortcut unchanged")
	_check(FileAccess.get_file_as_bytes(save_file) == bytes, "no save, map or result publication occurs during the replay")
	await _tap(&"interact")
	await _walk_to(_memory._exit)
	_check(_memory._beat == Memory.Beat.FACTORY_EXIT and _memory._stage.is_near(_memory._exit), "the opened door offers the office return interaction")
	await _tap(&"interact")
	await _settle(6)
	if is_instance_valid(_door._local_replay):
		print("ST33 exit debug beat=%s paused=%s same_replay=%s" % [_door._local_replay.get("_beat"), get_tree().paused, is_instance_valid(_memory)])
	_check(not is_instance_valid(_door._local_replay) and not get_tree().paused and not GameplayLock.is_locked(),
			"the opened historical door ends playback and restores world input")
	_check(GameState.current_level_path == OFFICE and GameState.pending_portal == &"" and uses[0] == 0,
			"the real route was never used, remapped or rebuilt")
	_check(_level.player.global_position.distance_to(origin) < 1.0 and _level.player.health.current == hp
			and _level.player.checkpoint_snapshot() == loadout, "finish restores Rin's exact office position, health and equipment")
	_check(GameState.story_progress_snapshot() == story and Progression.snapshot() == money and GameState.area_states == areas,
			"finish and skip leave flags, documents, deaths, world and credits intact")


func _continue() -> void:
	if not await _resume_office():
		return
	var disk := (_main.get("_run_store") as RunSaveStore).read()
	var original_shortcut: bool = disk.get("story", {}).get("flags", {}).get(String(SHORTCUT), false)
	_check(GameState.has_flag(SHORTCUT) == original_shortcut and GameState.has_flag(LEDGER),
			"the cold save has the original shortcut and ledger")
	if not await _start_memory():
		return
	_check(_memory._beat == Memory.Beat.PLACE_NOTE, "cold reopen still starts before the note")
	await _tap(&"pause")
	await _settle(4)
	_check(not get_tree().paused and not GameplayLock.is_locked(), "mapped pause also skips the memory")


func _resume_office() -> bool:
	var data := await _route_main.continue_game()
	_level = _route_main.level()
	if data.get("level") != OFFICE or _level == null or not await _wait_for_route_input():
		_check(false, "the old save arrives in the real office")
		return false
	_door = _level._portals.get(MEMORY_DOOR) as Portal
	_check(_door != null and _door.data.target_level.is_empty() and _door.data.validate().is_empty(), "the side door has no destination to a new area")
	if _door == null:
		return false
	_level.player.global_position = _door.global_position
	_level.player.velocity = Vector2.ZERO
	await _settle(10)
	return true


func _start_memory() -> bool:
	await _tap(&"interact")
	for i in 65:
		await _settle(1)
		_memory = _door._local_replay as Memory
		if is_instance_valid(_memory) and _memory._beat == Memory.Beat.PLACE_NOTE:
			break
	var ready := is_instance_valid(_memory) and _memory._beat == Memory.Beat.PLACE_NOTE
	_check(ready and GameplayLock.is_locked(), "interacting at the office door enters the playable ward memory")
	return ready


func _settle_office_save() -> void:
	# Exclude any pending autosave from positioning the real actor at the door.
	# Once replay begins, the primary bytes must remain identical.
	for i in 90:
		if not (_main.get("_save_queued") or _main.get("_autosave_queued") or _main.get("_writing_autosave")):
			return
		await get_tree().physics_frame
	_check(false, "the office save clears before replay starts")


func _walk_to(target: Vector2) -> void:
	var actor: Node2D = _memory._stage.get_node("Egret")
	var input := &"move_right" if target.x > actor.position.x else &"move_left"
	Input.action_press(input)
	# Movement advances by elapsed time. A fast renderer can use several
	# hundred process frames before Egret has crossed the room.
	var deadline := Time.get_ticks_msec() + 7000
	while absf(target.x - actor.position.x) >= 10.0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	Input.action_release(input)
	_check(absf(target.x - actor.position.x) < 10.0, "movement reaches the next location on the intended route")


func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _settle(2)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
