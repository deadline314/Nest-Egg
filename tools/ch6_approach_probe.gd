extends "res://tools/ch5_ledger_call_probe.gd"
## Use the genuine ST48 completed phone slot in an isolated save directory.

const PLAZA := "res://data/levels/ch6_harbor_plaza.tres"
const DECK := "res://data/levels/ch6_broadcast_overpass.tres"
const YARD := "res://data/levels/ch6_broadcast_outside.tres"
const SERVICE_PATH := "res://data/levels/ch5_gray_path.tres"
const APPROACHED := &"ch6_su_approach_confirmed"
const GAUGE := &"ch6_yard_gauge_read"
const INTERCOM := &"ch6_plaza_intercom"
const LINE := &"ch6_relay_signal"
const YARD_GAUGE := &"ch6_yard_gauge"
const APPROACH_RESULT := &"ch6_t_confirm_approach"
const GAUGE_RESULT := &"ch6_t_read_yard_gauge"


func _write() -> void:
	if not await _resume_to(PHONE):
		return
	var save := _main.get("_run_store") as RunSaveStore
	var from_paid_passage := GameState.has_flag(&"ch5_gray_first_wage_paid")
	if not GameState.has_flag(REQUESTED) and from_paid_passage:
		await _talk(BOOTH, ["call"])
		_check(_played.has(String(CALL)), "the authentic paid passage reaches Su through the original call")
	var before := save.read()
	_check(GameState.has_flag(REQUESTED) and before["story"]["flags"].get(String(REQUESTED)) == true,
			"the genuine Chapter Five call opens the Chapter Six route")
	var portal := _level._portals.get(&"phone_plaza") as Portal
	_check(portal != null and _level._portals.has(&"phone_street") and _level._portals.has(&"phone_gray"),
			"the new stair coexists with both former Chapter Five routes")
	if portal == null:
		return
	GameState.world_flags[String(REQUESTED)] = false
	_check(not portal.try_use() and not bool(_main.call("_route_pending")),
			"without a completed call the actual maintenance stair refuses travel")
	GameState.world_flags[String(REQUESTED)] = true
	if not await _portal(&"phone_plaza", PLAZA) or not await _wait_for_route_input():
		return
	_check(_level.data.chapter == &"ch6_unmooring" and _level._portals.has(&"plaza_phone"),
			"Main enters the new chapter through the independent return stair")
	var lift := _level._portals.get(&"plaza_overpass") as Portal
	_check(lift != null and not lift.try_use() and _object(INTERCOM) != null,
			"the service lift waits for Su and the intercom is physically present")
	if lift == null:
		return
	await _talk(INTERCOM, ["leave"])
	_check(not GameState.has_flag(APPROACHED) and not lift.is_open(), "staying in the plaza preserves the closed lift")
	await _cancel_talk(INTERCOM, APPROACH_RESULT, ["follow"])
	_check(not GameState.has_flag(APPROACHED) and not lift.is_open(), "cancelling before Su finishes writes no result")
	await _talk(INTERCOM, ["follow"])
	_check(lift.is_open() and GameState.has_flag(APPROACHED) and save.read()["story"]["flags"].get(String(APPROACHED)) == true,
			"the actual intercom completion publishes the lift result to Main's slot")
	await _talk(INTERCOM)
	_check(_played.has("ch6_t_approach_revisit"), "Su gives the shorter open-lift reply on revisit")
	if not await _portal(&"plaza_overpass", DECK) or not await _wait_for_route_input():
		return
	var upper := _object(LINE)
	var g := LevelBuilder.parse(_level.data)
	var deck := 16
	var floor := 20
	var lower_clear := true
	for column in range(1, g.width - 1):
		lower_clear = lower_clear and g.cell(column, floor) == "#" and g.cell(column, floor - 1) != "#"
	_check(upper != null and lower_clear and g.cell(34, deck) == "=",
			"the optional upper station has a deck and the lower route is continuous")
	if upper == null:
		return
	if DisplayServer.get_name() != "headless":
		_shots["ch6_t_read_line_status"] = "ST-50-overpass"
	await _talk(LINE)
	_shots.clear()
	_check(_level.player.is_on_floor() and absf(_level.player.global_position.y - float(deck * g.tile_size)) < 1.5
			and not GameState.has_flag(GAUGE), "the actual line station can be read on the upper walk")
	if not await _portal(&"overpass_relay", YARD) or not await _wait_for_route_input():
		return
	await _cancel_talk(YARD_GAUGE, GAUGE_RESULT)
	_check(not GameState.has_flag(GAUGE), "skipping the first gauge reading leaves the quest unfinished")
	await _talk(YARD_GAUGE)
	var after := save.read()
	_check(GameState.has_flag(GAUGE) and after["story"]["flags"].get(String(GAUGE)) == true
			and after.get("level") == YARD, "reading the actual gauge finishes the forecourt leg and saves it")
	var custody: Dictionary = before["story"]["items"]
	var receipts: Dictionary = before["progression"]["story_transactions"]["receipts"]
	_check(custody.get("held", []).has("ch4_original_ledger_copy")
			and custody.get("held", []).has("ch3_petition_receipt"),
			"the genuine caller carries the original ledger copy and the petition receipt")
	if from_paid_passage:
		_check(receipts.has("ch5.gray_path.first_wage"), "the paid route still has its actual wage transaction receipt")
	_check(after["story"]["items"] == custody and after["progression"] == before["progression"]
			and after["story"]["deaths"] == before["story"]["deaths"],
			"crossing into Chapter Six preserves original custody, receipts, death count and balance")
	_check_quest_and_scene()


func _continue() -> void:
	if not await _resume_to(YARD):
		return
	_check(GameState.has_flag(REQUESTED) and GameState.has_flag(APPROACHED) and GameState.has_flag(GAUGE),
			"cold Continue restores all three boundaries from the original slot")
	if OS.get_cmdline_user_args().has("--deck-capture"):
		if not await _portal(&"relay_overpass", DECK) or not await _wait_for_route_input():
			return
		await _capture_upper_deck()
		_check_quest_and_scene()
		return
	await _talk(YARD_GAUGE)
	_check(_played.has("ch6_t_yard_gauge_revisit") and not _played.has(String(GAUGE_RESULT)),
			"cold revisiting the gauge uses the read-only line")
	_check_quest_and_scene()
	if not await _portal(&"relay_overpass", DECK) or not await _wait_for_route_input():
		return
	await _walk_lower_deck()
	if not await _portal(&"overpass_plaza", PLAZA):
		return
	if not await _portal(&"plaza_phone", PHONE):
		return
	_check(_level._portals.has(&"phone_street") and _level._portals.has(&"phone_gray") and GameState.has_flag(REQUESTED),
			"the actual return stair lands in the existing Chapter Five alley with both exits")
	var prior := Progression.snapshot()
	if GameState.has_flag(&"ch5_gray_return_unlatched"):
		if not await _portal(&"phone_gray", SERVICE_PATH) or not await _portal(&"gray_phone", PHONE):
			return
	if await _portal(&"phone_street", STREET):
		_check(Progression.snapshot() == prior and GameState.has_flag(GAUGE),
				"following the prior exits after returning keeps the ledger and Chapter Six progress")


func _capture_upper_deck() -> void:
	var station := _object(LINE)
	if station == null:
		_check(false, "the live bridge station is available for capture")
		return
	_level.player.global_position = station.global_position + Vector2(-28, 0)
	await get_tree().create_timer(2.6, true, false, true).timeout
	var screen := _level.player.get_global_transform_with_canvas().origin
	var safe := get_viewport().get_visible_rect().grow(-55.0)
	_check(safe.has_point(screen) and _level.player.is_on_floor(),
			"the live camera and actor settle on the upper deck before dialogue")
	var done := [false, false]
	var talk := func() -> void:
		done[1] = await station._talk()
		done[0] = true
	talk.call()
	await _drive([], func() -> bool:
		return done[0] or (is_instance_valid(Story._player) and Story._player._dialogue.visible))
	var movie: CutscenePlayer = Story._player
	_check(is_instance_valid(movie) and movie._dialogue.visible, "the actual line-status reading is open")
	if is_instance_valid(movie) and movie._dialogue.visible:
		movie._dialogue.complete()
		await _settle(5)
		_capture("ST-50-overpass")
	await _drive([], func() -> bool: return done[0])
	_check(done[0] and done[1], "finished the actual upper station interaction after capture")


func _walk_lower_deck() -> void:
	var exit := _level._portals.get(&"overpass_plaza") as Portal
	if exit == null:
		_check(false, "the overpass has a real exit on the plaza side")
		return
	var player := _level.player
	var start := player.position
	var target := exit.global_position.x + 8.0
	Input.action_press(&"move_left")
	for frame in 680:
		if player.global_position.x <= target:
			break
		await get_tree().physics_frame
	Input.action_release(&"move_left")
	_check(start.x - player.position.x > 800 and exit.contains_point(player.global_position)
			and absf(player.global_position.y - 320.0) < 1.5,
			"ordinary walking traverses the entire lower deck without a jump")


func _check_quest_and_scene() -> void:
	var index := QuestMapIndex.new()
	index.load_chapter(&"ch6_unmooring")
	var catalog := QuestMapState.for_run().catalog_for_chapter(&"ch6_unmooring", index)
	var quest := catalog.find("ch6_approach_relay")
	_check(catalog.issues.is_empty() and not quest.is_empty() and QuestCatalog.status(quest, GameState.world_flags) == "completed",
			"the real map recognizes the completed chapter quest")
	for path in [PHONE, PLAZA, DECK, YARD]:
		var data := load(path) as LevelData
		var issues := SceneAudit.audit(data, LevelBuilder.parse(data))
		for issue: Dictionary in issues:
			print("ST50_SCENE ", path, " ", issue)
		_check(issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error").is_empty(),
				"the authored placements have no errors in %s" % path.get_file())

func _capture(name: String) -> void:
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(image.get_size() == Vector2i(1280, 720), "the bridge frame uses the actual 720p viewport")
	_check(image.save_jpg(_out_dir.path_join(name + ".jpg"), 0.86) == OK,
			"captured the high station during its actual interaction")
