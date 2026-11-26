extends "res://tools/ch5_shelf_probe.gd"
## The once-only fare and the free route both go through the current Main.

const STREET := "res://data/levels/ch5_harbor_street.tres"
const ALLEY := "res://data/levels/ch5_back_alley.tres"
const STAIRS := "res://data/levels/ch5_basement_stair.tres"
const ARCHIVE := "res://data/levels/ch5_basement_archive.tres"
const PASSAGE := "res://data/levels/ch5_gray_path.tres"
const PHONE := "res://data/levels/ch5_phone_alley.tres"
const NOTICE := &"ch5_gray_wage_notice"
const LATCH := &"ch5_gray_return_latch"
const PAY := &"ch5_t_pay_first_gray_wage"
const PAID := &"ch5_gray_first_wage_paid"
const OPEN := &"ch5_gray_return_unlatched"
const RECEIPT := &"ch5_gray_wage_receipt"
const CONTRACT := "ch5.gray_path.first_wage"
const FUNDED_CREDITS := 850
const WAGE := 800


func _write() -> void:
	if not await _resume_to(SHOP):
		return
	_check(GameState.has_flag(&"ch5_ye_offer_declined"), "the original offer was settled before entering either route")
	if not await _portal(&"pawn_street", STREET) or not await _portal(&"street_phone", PHONE):
		return
	var return_latch := _level._portals.get(&"phone_gray") as Portal
	_check(return_latch != null and not return_latch.is_open()
			and not return_latch.try_use(), "the free street route works before payment and can't unlock the reverse latch")
	if not await _portal(&"phone_street", STREET) or not await _portal(&"street_back", ALLEY) \
			or not await _portal(&"alley_stair", STAIRS) or not await _portal(&"stair_basement", ARCHIVE):
		return
	_check(Progression.credits < WAGE, "the genuine pre-passage save starts below the offered cost")
	var old := Progression.credits
	var existing_items := StoryItems.snapshot()
	var archive_door := _level._portals.get(&"archive_gray") as Portal
	var slot := _main.get("_run_store") as RunSaveStore
	_check(archive_door != null and not archive_door.is_open(), "the fee gate starts closed")
	await _talk(NOTICE, ["street"])
	await _talk(NOTICE, ["pay"])
	await _talk(NOTICE, ["pay"])
	_check(_played.count("ch5_t_gray_wage_insufficient") == 2 and Progression.credits == old
			and not GameState.has_flag(PAID) and not StoryItems.owns(RECEIPT),
			"two ordinary attempts while short preserve the wallet, receipt, and passage")
	Progression.add_credits(FUNDED_CREDITS - old)
	await _cancel_talk(NOTICE, PAY, ["pay"])
	_check(Progression.credits == FUNDED_CREDITS and not GameState.has_flag(PAID),
			"cancelling the active payment leaves the whole intended debit without effect")
	if not await _refuse_then_retry(slot):
		return
	_check(Progression.credits == FUNDED_CREDITS - WAGE and GameState.has_flag(PAID)
			and StoryItems.holds(RECEIPT) and archive_door.is_open(),
			"actual Main publishes exactly one debit, its document, and the gate together")
	_check_receipt(slot.read())
	var held_now: Array = StoryItems.snapshot()["held"]
	_check(held_now.size() == existing_items["held"].size() + 1 \
			and existing_items["held"].all(func(id: StringName) -> bool: return id in held_now),
			"the service receipt preserves all old custody")
	await _talk(NOTICE)
	_check(Progression.credits == FUNDED_CREDITS - WAGE and _played.has("ch5_t_gray_wage_paid"),
			"rereading the wage receipt never bills a second time")
	if not await _portal(&"archive_gray", PASSAGE):
		return
	await _release_latch()
	var booth := _level._portals.get(&"gray_phone") as Portal
	_check(GameState.has_flag(OPEN) and booth != null and booth.is_open(),
			"the latch opens only from the paid passage and makes the actual shortcut available")
	await _portal(&"gray_phone", PHONE)


func _continue() -> void:
	if not await _resume_to(PHONE):
		return
	_check(GameState.has_flag(OPEN) and StoryItems.holds(RECEIPT)
			and Progression.credits == FUNDED_CREDITS - WAGE,
			"separate cold read restores the receipt, exact wallet, and inner latch")
	_check_receipt((_main.get("_run_store") as RunSaveStore).read())
	if not await _portal(&"phone_gray", PASSAGE) or not await _portal(&"gray_archive", ARCHIVE):
		return
	await _talk(NOTICE)
	_check(Progression.credits == FUNDED_CREDITS - WAGE, "reverse loop and replay have no repeated debit")
	for path: String in [ARCHIVE, PASSAGE, PHONE, STREET]:
		var data := load(path) as LevelData
		var issues := SceneAudit.audit(data, LevelBuilder.parse(data))
		for issue: Dictionary in issues:
			print("PLACEMENT ", issue)
		_check(issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error").is_empty(),
				"the staging has no placement issue in " + path.get_file())


func _refuse_then_retry(slot: RunSaveStore) -> bool:
	var station := _object(NOTICE)
	_level.player.global_position = station.global_position + Vector2(-22, 0)
	await _settle(12)
	var done := [false]
	var dialog := func() -> void:
		await station._talk()
		done[0] = true
	dialog.call()
	await _drive(["pay"], func() -> bool: return done[0] or Story._current_cinematic == PAY)
	if done[0] or Story._current_cinematic != PAY:
		_check(false, "the authored choice reached the actual payment result")
		return false
	var retained := FileAccess.get_file_as_bytes(slot.path)
	var temporary := slot.path + ".tmp"
	_check(DirAccess.make_dir_absolute(temporary) == OK, "the isolated slot can simulate a file-system refusal")
	await _drive([], func() -> bool: return is_instance_valid(Story.result_completion.get("_prompt")))
	_check(not done[0] and FileAccess.get_file_as_bytes(slot.path) == retained and Progression.credits == FUNDED_CREDITS
			and not GameState.has_flag(PAID) and not StoryItems.owns(RECEIPT),
			"the refused durable write leaves the old slot and all live results intact")
	_check(DirAccess.remove_absolute(temporary) == OK, "the isolated temporary obstruction is removed")
	Story.result_completion.call("_retry")
	await _drive([], func() -> bool: return done[0])
	_check(done[0], "the actual retry resumes and releases the original notice")
	return done[0]


func _release_latch() -> void:
	var station := _object(LATCH)
	_check(station != null, "the release station is mounted inside the gray path")
	if station == null:
		return
	if DisplayServer.get_name() != "headless":
		await _settle(210)
	_level.player.global_position = station.global_position + Vector2(-22, 0)
	await _settle(12)
	var done := [false]
	var talk := func() -> void:
		await station._talk()
		done[0] = true
	talk.call()
	var contacted := false
	for frame in 340:
		var action: WorldPropAction = _level.player._visual.interaction_action
		if action != null and not contacted and action.contacts_completed == 1:
			contacted = true
			if DisplayServer.get_name() != "headless":
				var shot := preload("res://tools/viewport_capture.gd").image(get_viewport())
				_check(shot.save_jpg(_out_dir.path_join("gray-return.jpg"), 0.86) == OK,
						"captured the registered hand contact at the return latch")
		var player: CutscenePlayer = Story._player
		if done[0] or (is_instance_valid(player) and player._dialogue.visible):
			break
		await get_tree().physics_frame
	_check(contacted, "the front hand reaches the release before the return opens")
	await _drive([], func() -> bool: return done[0])


func _check_receipt(save: Dictionary) -> void:
	var progression: Dictionary = save.get("progression", {})
	var ledger: Dictionary = progression.get("story_transactions", {})
	var rows: Dictionary = ledger.get("receipts", {})
	_check(rows.has(CONTRACT) and int(rows[CONTRACT]["credits_delta"]) == -WAGE
			and int(progression.get("credits", -1)) == FUNDED_CREDITS - WAGE
			and save["story"]["flags"][String(PAID)] == true,
			"the canonical transaction receipt matches the amount and gate in the saved bundle")
