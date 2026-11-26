extends "res://tools/ch4_archive_probe.gd"
## Run from an isolated save written by the actual Pear testimony. The cold
## check starts in a separate process after the successful stair descent.

const SHOP := "res://data/levels/ch5_pawnshop.tres"
const STREET := "res://data/levels/ch5_harbor_street.tres"
const HALL := "res://data/levels/ch5_revival_lounge.tres"
const ALLEY := "res://data/levels/ch5_back_alley.tres"
const STAIR := "res://data/levels/ch5_basement_stair.tres"
const DATES := &"ch5_pear_dates_confirmed"
const OPEN := &"ch5_basement_voice_unlocked"
const PANEL := &"ch5_voice_lock"
const RELEASE := &"ch5_t_voice_lock_release"


func _write() -> void:
	if not await _resume_to(HALL):
		return
	_check(GameState.has_flag(DATES) and StoryItems.holds(&"ch5_pear_shift_dates"),
			"the continuation uses actual Pear testimony and its kept date clue")
	var before := StoryItems.snapshot()
	var credits_before := Progression.credits
	if not await _portal(&"hall_street", STREET):
		return
	_check(Story.play(RELEASE, false), "the renderer can execute the lock effect independently")
	await _drive([], func() -> bool: return bool(Story.result_completion.get("_reload_original")))
	_check(bool(Story.result_completion.get("_reload_original")) and not GameState.has_flag(OPEN),
			"an unowned rendering request requires recovery without opening the door")
	Story.reset_active_presentation(&"test")
	if not await _portal(&"street_back", ALLEY) or not await _wait_for_route_input():
		return
	var stair := _level._portals.get(&"alley_stair") as Portal
	_check(stair != null and not stair.is_open() and not stair.try_use(),
			"the actual stairs block descent until the voice lock is accepted")
	if stair == null:
		return
	_check_quest("active")
	await _talk(PANEL, ["leave"])
	await _talk(PANEL, ["answer", "leave"])
	await _talk(PANEL, ["answer", "umbrella"])
	await _talk(PANEL, ["answer", "wait"])
	_check(_played.has("ch5_t_voice_lock_try_again"), "both wrong replies route to retry advice")
	await _talk(PANEL, ["hint", "more", "replay"])
	_check(_played.has("ch5_t_voice_lock_hint_first") and _played.has("ch5_t_voice_lock_hint_second")
			and _played.has("ch5_t_voice_lock_recording"), "all hint levels and the source recording are playable")
	_check(not GameState.has_flag(OPEN) and not stair.is_open(), "leaving, hints, replay and wrong replies keep the gate locked")
	if DisplayServer.get_name() != "headless":
		_frame_panel()
		_shots["ch5_t_voice_lock_reply:choice"] = "voice-choices"
	await _talk(PANEL, ["answer", "water"])
	var slot := (_main.get("_run_store") as RunSaveStore).read()
	_check(stair.is_open() and GameState.has_flag(OPEN)
			and slot.get("story", {}).get("flags", {}).get(String(OPEN)) == true,
			"only the owner's correct answer opens and publishes the result")
	await _talk(PANEL, ["contact"])
	_check(_played.has("ch5_t_voice_lock_contact") and StoryItems.snapshot() == before
			and Progression.credits == credits_before, "the optional radio message leaves belongings and balance intact")
	_check_quest("completed")
	if DisplayServer.get_name() != "headless":
		await _settle(24)
		_capture("alley-open")
	if not await _portal(&"alley_pawnshop", SHOP) or not await _portal(&"pawnshop_back", ALLEY):
		return
	_check((_level._portals[&"alley_stair"] as Portal).is_open(), "the shop shortcut and its return preserve the unlocked landing")
	await _portal(&"alley_stair", STAIR)


func _continue() -> void:
	if not await _resume_to(STAIR):
		return
	_check(GameState.has_flag(OPEN) and StoryItems.holds(&"ch5_pear_shift_dates"),
			"the independent cold reader restores the open gate and Pear's clue")
	if not await _portal(&"stair_alley", ALLEY):
		return
	_check((_level._portals[&"alley_stair"] as Portal).is_open(), "the lower landing has a usable return")
	await _talk(PANEL, ["contact"])
	_check(_played.has("ch5_t_voice_lock_contact"), "the radio remains available after a cold reload")
	_check_quest("completed")
	for path: String in [ALLEY, STAIR, SHOP, STREET]:
		var data := load(path) as LevelData
		var issues := SceneAudit.audit(data, LevelBuilder.parse(data))
		for issue: Dictionary in issues:
			print("PLACEMENT ", issue)
		_check(issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error").is_empty(),
				"the authored placements have no errors in %s" % path.get_file())


func _check_quest(expected: String) -> void:
	var index := QuestMapIndex.new()
	index.load_chapter(&"ch5_paymaster")
	var catalog := QuestMapState.for_run().catalog_for_chapter(&"ch5_paymaster", index)
	var quest := catalog.find("ch5_voice_lock")
	_check(catalog.issues.is_empty() and not quest.is_empty(), "the chapter catalog has a valid voice-lock objective")
	if quest.is_empty():
		return
	var mark: Dictionary = quest["steps"][0]["location"]
	_check(mark["level"] == ALLEY and Vector2i(mark["cell"][0], mark["cell"][1]) == Vector2i(41, 19),
			"the map points to the physical voice lock")
	_check(QuestCatalog.status(quest, GameState.world_flags) == expected, "voice lock quest shows " + expected)


func _frame_panel() -> void:
	var camera := Camera2D.new()
	camera.position = _object(PANEL).position + Vector2(55, -42)
	camera.zoom = Vector2(1.4, 1.4)
	_level.add_child(camera)
	camera.make_current()


func _capture(name: String) -> void:
	if name not in ["voice-choices", "alley-open"] or DisplayServer.get_name() == "headless":
		return
	var captured := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(captured.save_jpg(_out_dir.path_join(name + ".jpg"), 0.88) == OK, "captured " + name)
