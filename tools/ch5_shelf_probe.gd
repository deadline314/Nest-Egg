extends "res://tools/ch4_archive_probe.gd"
## Private focused scratch probe, using a genuine completed-homecoming slot.

const PREVIOUS := "res://data/levels/ch4_pawnshop.tres"
const SHOP := "res://data/levels/ch5_pawnshop.tres"
const GATE := &"pawnshop_next_day"
const HOME := &"ch4_pawnshop_homecoming_seen"
const INDEX_READ := &"ch5_pawnshop_index_read"
const LABELS_MATCHED := &"ch5_pawnshop_labels_matched"
const BOARD := &"ch5_inventory_board"
const INDEX_OBJECT := &"ch5_shelf_index"
const CATCH := &"ch5_t_lift_catch"
const CHOICE := &"ch5_t_choose_labels"
const EARLIER_NOTE := &"ch4_linden_witness_note"
const EARLIER_WITNESSES := &"ch4_linden_witnesses_noted"
const CH1_LABELS := [&"ch1_label_watch_seen", &"ch1_label_guitar_seen", &"ch1_label_fare_seen", &"ch1_label_raincoat_seen"]


func _write() -> void:
	if not await _resume_to(PREVIOUS):
		return
	_check(GameState.has_flag(HOME) and _level.data.chapter == &"ch4_hollow",
			"cold Chapter Four resume is still in the pawnshop after completing homecoming")
	var carry_note := OS.get_cmdline_user_args().has("--carry-ward-note")
	if carry_note and not await _bring_ward_note():
		return
	var story_before := StoryItems.snapshot()
	var gate := _level._portals.get(GATE) as Portal
	_check(gate != null and gate.is_open() and gate.data.mode == PortalData.Mode.INTERACT,
			"the completed homecoming enables the explicit transition")
	if gate == null:
		return
	GameState.world_flags[String(HOME)] = false
	_check(not gate.try_use() and not bool(_main.call("_route_pending")),
			"the actual transition cannot start before homecoming")
	GameState.world_flags[String(HOME)] = true
	var cumulative := CampaignEdition.new()
	cumulative.development = false
	cumulative.through = &"ch3_clearwater"
	cumulative.order.assign([&"prologue", &"ch1_kasa", &"ch2_heron", &"ch3_clearwater"])
	_check(not cumulative.includes_level(load(SHOP) as LevelData),
			"the cumulative edition's ordinary Main route gate excludes Chapter Five")
	if not await _portal(GATE, SHOP) or not await _wait_for_route_input():
		return
	_check(_level.data.chapter == &"ch5_paymaster" and StoryItems.snapshot() == story_before,
			"the real cross-chapter route preserves all prior inventory and enables Chapter Five")
	if carry_note:
		_check(GameState.has_flag(EARLIER_WITNESSES) and StoryItems.holds(EARLIER_NOTE),
				"Chapter Five retains the previously authorized letter note and flag")
	_check(_object(&"ch4_old_k") == null and _object(BOARD) != null,
			"Old K is downstairs and the inventory board is physically reachable")
	_check((_main.get("_run_store") as RunSaveStore).read().get("level") == SHOP,
			"the slot describes the Chapter Five entrance before investigation")
	await _talk(BOARD)
	_check(_played.has("ch5_t_need_index"), "the board guides a player without the index")
	await _cancel_talk(INDEX_OBJECT, &"ch5_t_read_index")
	_check(not GameState.has_flag(INDEX_READ), "skipping the index leaves it unread")
	await _talk(INDEX_OBJECT)
	await _talk(BOARD)
	_check(GameState.has_flag(INDEX_READ) and _played.has("ch5_t_need_labels"),
			"reading the index saves it, and the board still asks for labels")
	await _talk(&"ch5_fare")
	await _talk(&"ch5_raincoat")
	await _talk(&"ch5_watch")
	await _talk(&"ch5_guitar")
	_check(not _played.has("ch5_t_watch_compare") and not _played.has("ch5_t_guitar_compare"),
			"first-time players can read clues in any order without seeing unread Chapter One records")
	for previous: StringName in CH1_LABELS:
		_check(not GameState.has_flag(previous), "Chapter Five never writes %s" % previous)
	_check(not GameState.has_flag(&"sq8_first_labels_done"), "Chapter Five does not grant SQ8")
	await _talk(BOARD, ["watch_guitar"])
	await _talk(BOARD, ["raincoat_fare"])
	await _talk(BOARD, ["watch_guitar"])
	_check(_played.has("ch5_t_wrong_labels") and not GameState.has_flag(LABELS_MATCHED),
			"an incorrect choice shows advice without advancing")
	await _talk(BOARD, ["leave"])
	await _cancel_talk(BOARD, CHOICE)
	_check(not GameState.has_flag(LABELS_MATCHED), "leaving or skipping the menu never advances")
	await _cancel_talk(BOARD, CATCH, ["watch_raincoat"])
	_check(not GameState.has_flag(LABELS_MATCHED), "skipping before the catch action does not open it")
	if DisplayServer.get_name() != "headless":
		_shots[String(CHOICE) + ":choice"] = "shelf-labels"
	await _talk(BOARD, ["watch_raincoat"])
	_shots.clear()
	var saved := (_main.get("_run_store") as RunSaveStore).read()
	_check(GameState.has_flag(LABELS_MATCHED) and saved.get("level") == SHOP
			and saved.get("story", {}).get("flags", {}).get(String(LABELS_MATCHED)) == true,
			"the correct pair opens the catch and publishes at Main's durable boundary")
	await _talk(BOARD)
	_check(_played.has("ch5_t_labels_matched") and StoryItems.snapshot() == story_before,
			"the completed board is safely repeatable and leaves every item in place")
	_check_quest()


func _bring_ward_note() -> bool:
	if not await _portal(&"pawn_ward", RECEPTION) or not await _portal(&"reception_ward", WARD):
		return false
	await _talk(&"ch4_cabinet", ["ask_letter", "read_aloud", "note"])
	var held := StoryItems.holds(EARLIER_NOTE) and GameState.has_flag(EARLIER_WITNESSES)
	_check(held, "the actual earlier ward scene grants its note before the new chapter")
	return held and await _portal(&"ward_entry", RECEPTION) and await _portal(&"reception_pawn", PREVIOUS)


func _check_quest() -> void:
	var index := QuestMapIndex.new()
	index.load_chapter(&"ch5_paymaster")
	var catalog := QuestMapState.for_run().catalog_for_chapter(&"ch5_paymaster", index)
	var quest := catalog.find("ch5_blank_labels")
	_check(catalog.issues.is_empty() and not quest.is_empty(), "the map loads the authored quest: %s" % [catalog.issues])
	if quest.is_empty():
		return
	_check(QuestCatalog.status(quest, GameState.world_flags) == "completed",
			"the chapter quest completes through both genuine flag writers")
	var steps: Array = quest["steps"]
	_check(Vector2i(int(steps[0]["location"]["cell"][0]), int(steps[0]["location"]["cell"][1])) == Vector2i(52, 19)
			and Vector2i(int(steps[1]["location"]["cell"][0]), int(steps[1]["location"]["cell"][1])) == Vector2i(56, 19),
			"the two quest markers match the drawer and inventory board")


func _continue() -> void:
	if not await _resume_to(SHOP):
		return
	if OS.get_cmdline_user_args().has("--carry-ward-note"):
		_check(GameState.has_flag(EARLIER_WITNESSES) and StoryItems.holds(EARLIER_NOTE),
				"the new chapter cold-loads the older ward note and its original flag")
	_check(GameState.has_flag(INDEX_READ) and GameState.has_flag(LABELS_MATCHED),
			"a separate process restores the index and catch")
	await _talk(BOARD)
	_check(_played.has("ch5_t_labels_matched") and not _played.has(String(CHOICE))
			and not GameState.has_flag(&"sq8_first_labels_done"),
			"resuming uses the read-only board and does not mark SQ8")
	GameState.world_flags[String(CH1_LABELS[0])] = true
	await _talk(&"ch5_watch")
	await _talk(&"ch5_guitar")
	_check(_played.has("ch5_t_watch_compare") and _played.has("ch5_t_guitar_revisit")
			and not _played.has("ch5_t_guitar_compare"),
			"mixed historical records show only the authentic Chapter One page")
	GameState.world_flags[String(CH1_LABELS[0])] = false
	_check_quest()
	for path in [PREVIOUS, SHOP]:
		var data := load(path) as LevelData
		var issues := SceneAudit.audit(data, LevelBuilder.parse(data))
		for issue: Dictionary in issues:
			print("AUDIT ", issue)
		_check(issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error").is_empty(),
				"the authored placements have no errors in %s" % path.get_file())


func _cancel_talk(source: StringName, target: StringName, options: Array = []) -> void:
	var station := _object(source)
	_check(station != null, "cancellable interaction has a live map source")
	if station == null:
		return
	_level.player.global_position = station.global_position + Vector2(-22, 0)
	await _settle(12)
	var done := [false]
	var talk := func() -> void:
		await station._talk()
		done[0] = true
	talk.call()
	await _drive(options, func() -> bool: return done[0] or Story._current_cinematic == target)
	_check(Story._current_cinematic == target, "requested skip runs at %s" % target)
	Story.skip_cinematic()
	await _drive([], func() -> bool: return done[0])
	_check(done[0], "the skipped interaction releases the map")


func _capture(name: String) -> void:
	var frame := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(frame.save_jpg(_out_dir.path_join(name + ".jpg"), 0.86) == OK, "captured the physical inventory board")
