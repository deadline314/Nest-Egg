extends "res://tools/ch6_approach_probe.gd"
## Copies the completed ST50 slot to --save-dir before running this proof.

const RECORDING := "res://data/levels/ch6_recording_booth.tres"
const DIVERT := &"ch6_relay_diverter"
const DRAIN := &"ch6_relay_drain"
const BACKUP := &"ch6_relay_backup"
const DIVERTED := &"ch6_relay_water_diverted"
const DRAINED := &"ch6_relay_water_drained"
const POWERED := &"ch6_relay_powered"


func _write() -> void:
	if not await _resume_to(YARD):
		return
	var store := _main.get("_run_store") as RunSaveStore
	var before := store.read()
	_check(GameState.has_flag(GAUGE) and GameState.has_flag(REQUESTED) and GameState.has_flag(APPROACHED),
			"the authenticated Chapter Six approach is already complete")
	_check(before["progression"]["story_transactions"]["receipts"].has("ch5.gray_path.first_wage"),
			"the genuine paid fixture carries its first-wage receipt")
	var door := _level._portals.get(&"relay_recording") as Portal
	_check(door != null and not door.try_use(), "the recording room is locked while water is high")
	if door == null:
		return
	await _service(DRAIN)
	await _service(BACKUP)
	_check(_played.count("ch6_t_drain_need_diversion") == 2
			and not GameState.has_flag(DRAINED) and not door.is_open(),
			"out-of-order controls give their specific guidance and do not advance")
	await _service(DIVERT, [], &"ch6_t_relay_divert")
	_check(not GameState.has_flag(DIVERTED), "cancelling the valve does not move the saved diverter")
	await _service(DIVERT)
	_check(_flag_is_saved(store, DIVERTED) and not GameState.has_flag(DRAINED), "turning the real valve saves only diversion")
	await _service(BACKUP)
	_check(_played.has("ch6_t_backup_need_drain") and not door.is_open(), "partial service still asks the player to drain")
	var before_blocked_drain := _result_snapshot(store.read())
	await _service(DRAIN, [], &"", Vector2(-36, 16), false)
	_check(not GameState.has_flag(DRAINED) and not door.is_open(), "blocked drain leaves memory and gate untouched")
	await _check_blocked_save(store, before_blocked_drain, "drain")
	if OS.get_cmdline_user_args().has("--relay-image"):
		await _settle(210)
	await _service(DRAIN)
	_check(_flag_is_saved(store, DRAINED) and not door.is_open(), "draining from the first step saves the safe gauge alone")
	await _service(YARD_GAUGE)
	_check(_played.has("ch6_t_yard_gauge_safe"), "the existing gauge now reports the low reading")
	await _service(BACKUP, ["leave"])
	await _service(BACKUP, ["connect"], &"ch6_t_relay_connect")
	_check(not GameState.has_flag(POWERED) and not door.is_open(),
			"leaving or skipping the final confirmation keeps power off")
	var before_blocked_backup := _result_snapshot(store.read())
	await _service(BACKUP, ["connect"], &"", Vector2(-7, 48), false)
	_check(not GameState.has_flag(POWERED) and not door.is_open(), "blocked backup leaves memory and gate untouched")
	await _check_blocked_save(store, before_blocked_backup, "backup")
	var blocked_dir := _save_dir.get_base_dir().path_join("blocked-slot")
	_check(DirAccess.make_dir_recursive_absolute(blocked_dir) == OK
			and DirAccess.copy_absolute(store.path, blocked_dir.path_join("slot.json")) == OK,
			"captured the genuine post-cancel slot before attempting the successful retry")
	await _service(BACKUP, ["connect"])
	_check(door.is_open() and _flag_is_saved(store, POWERED), "real backup contact publishes power and enables the door")
	var after := store.read()
	_check(after.get("level") == YARD and before["story"]["items"] == after["story"]["items"]
			and before["progression"] == after["progression"] and before["story"]["deaths"] == after["story"]["deaths"]
			and before["runtime"]["loadout"] == after["runtime"]["loadout"], "servicing the relay preserves custody, money, receipts, deaths and equipment")
	_check_audit()
	if not await _portal(&"relay_recording", RECORDING):
		return
	_check(_level.data.intro_scene == &"" and _level._portals.has(&"recording_relay")
			and not GameState.has_flag(&"ch6_broadcast_started"), "the actual room has a return door and stays off air")
	_check_audit()
	if await _portal(&"recording_relay", YARD):
		_check(_level._portals.has(&"relay_overpass") and _level._portals.has(&"relay_recording"),
				"recording room returns to the unchanged approach and the open station")
		_check_repair_quest()


func _check_blocked_save(store: RunSaveStore, entry: Dictionary, name: String) -> void:
	await _settle(30)
	var saved := store.read()
	_check(_result_snapshot(saved) == entry and saved.get("cinematic") == "",
			"blocked %s clears cold-resume marker and leaves durable results untouched" % name)


func _result_snapshot(saved: Dictionary) -> Dictionary:
	var story: Dictionary = saved.get("story", {})
	return {"level": saved.get("level"), "flags": story.get("flags"), "items": story.get("items"),
			"deaths": story.get("deaths"), "progression": saved.get("progression"),
			"loadout": saved.get("runtime", {}).get("loadout")}


func _continue() -> void:
	if not await _resume_to(YARD):
		return
	if OS.get_cmdline_user_args().has("--after-blocked-contact"):
		await _continue_from_blocked()
		return
	_check(GameState.has_flag(DIVERTED) and GameState.has_flag(DRAINED) and GameState.has_flag(POWERED),
			"cold Continue restores each genuine maintenance result")
	await _service(BACKUP)
	_check(_played.has("ch6_t_backup_revisit") and not _played.has("ch6_t_relay_connect"),
			"cold Continue reads power status without replaying the connection")
	_check_repair_quest()
	if await _portal(&"relay_recording", RECORDING):
		_check(not GameState.has_flag(&"ch6_broadcast_started"), "the cold recording-room route remains off air")


func _continue_from_blocked() -> void:
	await _settle(45)
	var door := _level._portals.get(&"relay_recording") as Portal
	_check(GameState.has_flag(DRAINED) and not GameState.has_flag(POWERED) and door != null and not door.is_open(),
			"cold post-cancel slot preserves drained water and an unpowered locked door")
	_check(not _played.has("ch6_t_relay_connect") and not Story.is_cinematic_active(),
			"cold post-cancel slot plays no failed contact dialogue or choice")
	var store := _main.get("_run_store") as RunSaveStore
	await _service(BACKUP, ["connect"])
	_check(_played.count("ch6_t_relay_connect") == 1 and _flag_is_saved(store, POWERED) and door.is_open(),
			"after cold Continue the player can retry a single real contact and unlock the door")


func _service(id: StringName, choices: Array = [], skip_at := &"", offset := Vector2(-7, 0), expect_success := true) -> void:
	var object := _object(id)
	_check(object != null, "physical station %s is present" % id)
	if object == null:
		return
	_level.player.global_position = object.global_position + offset
	await _settle(12)
	_check(_level.player.is_on_floor() and absf(_level.player.global_position.y - object.global_position.y - offset.y) < 1.5,
			"player is on the expected test tread near %s" % id)
	var done := [false, false]
	if id == DRAIN and expect_success and DisplayServer.get_name() != "headless" 			and OS.get_cmdline_user_args().has("--relay-image"):
		_capture_drain_press(done)
	var talk := func() -> void:
		done[1] = await object._talk()
		done[0] = true
	talk.call()
	await _drive(choices, func() -> bool: return done[0] or (skip_at != &"" and Story._current_cinematic == skip_at))
	if skip_at != &"":
		_check(Story._current_cinematic == skip_at, "cancellation reaches %s" % skip_at)
		Story.skip_cinematic()
		await _drive([], func() -> bool: return done[0])
	_check(done[0] and (skip_at != &"" or done[1] == expect_success), "station %s finishes its observed route" % id)



func _capture_drain_press(done: Array) -> void:
	while not done[0] and is_instance_valid(_level):
		await get_tree().process_frame
		var action: WorldPropAction = _level.player._visual.interaction_action
		if action != null and action.phase == "press" and action._elapsed >= action._duration * 0.8:
			_capture("ST-51-drain")
			return

func _flag_is_saved(store: RunSaveStore, flag_id: StringName) -> bool:
	return GameState.has_flag(flag_id) and store.read()["story"]["flags"].get(String(flag_id)) == true


func _check_audit() -> void:
	var audited := SceneAudit.split(SceneAudit.audit(_level.data, LevelBuilder.parse(_level.data)))
	for issue: Dictionary in audited.get("errors", []):
		print("ST51_SCENE ", issue)
	_check(audited.get("errors", []).is_empty(), "placed fixtures and exits are grounded in %s" % _level.data.id)


func _check_repair_quest() -> void:
	var map := QuestMapIndex.for_chapter(&"ch6_unmooring")
	var catalog := QuestMapState.for_run().catalog_for_chapter(&"ch6_unmooring", map)
	var quest := catalog.find("ch6_relay_water")
	_check(catalog.issues.is_empty() and not quest.is_empty(), "the repair quest loads: %s" % [catalog.issues])
	if not quest.is_empty():
		_check(QuestCatalog.status(quest, GameState.world_flags) == "completed",
				"the three physical stations complete the repair quest")
