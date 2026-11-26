extends "res://tools/ch5_shelf_probe.gd"

const STREET := "res://data/levels/ch5_harbor_street.tres"
const PHONE := "res://data/levels/ch5_phone_alley.tres"
const BOOTH := &"ch5_paymaster_phone"
const CALL_OFFER := &"ch5_t_offer_ledger_call"
const CALL := &"ch5_t_make_ledger_call"
const REQUESTED := &"ch5_ledger_broadcast_requested"


func _write() -> void:
	var paid_entry := OS.get_cmdline_user_args().has("--paid-entry")
	if not await _resume_to(PHONE if paid_entry else SHOP):
		return
	_check(GameState.has_flag(&"ch5_ye_offer_declined"), "the caller comes from the actual refused offer")
	if paid_entry:
		_check(GameState.has_flag(&"ch5_gray_return_unlatched") and StoryItems.holds(&"ch5_gray_wage_receipt"),
				"the chapter's real paid shortcut remains open at the same booth")
	elif not await _portal(&"pawn_street", STREET) or not await _portal(&"street_phone", PHONE):
		return
	var documents := StoryItems.snapshot()
	var balance := Progression.credits
	var health := _level.player.health.current
	await _talk(BOOTH, ["leave"])
	_check(not GameState.has_flag(REQUESTED), "the phone can be left without a new request")
	await _cancel_talk(BOOTH, CALL, ["call"])
	_check(not GameState.has_flag(REQUESTED), "hanging up early leaves the request incomplete")
	var slot := _main.get("_run_store") as RunSaveStore
	if not await _retry_call(slot):
		return
	_check(GameState.has_flag(REQUESTED) and slot.read()["story"]["flags"].get(String(REQUESTED)) == true,
			"the published request exists in the saved world")
	var starts := _played.count(String(CALL))
	await _talk(BOOTH)
	_check(_played.has("ch5_t_ledger_call_revisit") and _played.count(String(CALL)) == starts,
			"the next interaction only checks in after the one successful call")
	_check(StoryItems.snapshot() == documents and Progression.credits == balance
			and _level.player.health.current == health,
			"making the call preserves document custody, the wallet, and health")
	var map_index := QuestMapIndex.new()
	map_index.load_chapter(&"ch5_paymaster")
	var catalog := QuestMapState.for_run().catalog_for_chapter(&"ch5_paymaster", map_index)
	var quest := catalog.find("ch5_ledger_call")
	_check(catalog.issues.is_empty() and not quest.is_empty()
			and QuestCatalog.status(quest, GameState.world_flags) == "completed",
			"the actual saved request completes the telephone booth map objective")


func _continue() -> void:
	if not await _resume_to(PHONE):
		return
	_check(GameState.has_flag(REQUESTED), "a separate process sees the finished call after continue")
	await _talk(BOOTH)
	_check(_played.has("ch5_t_ledger_call_revisit") and not _played.has(String(CALL_OFFER)),
			"the restored telephone uses the recorded follow-up")
	await _portal(&"phone_street", STREET)


func _retry_call(slot: RunSaveStore) -> bool:
	var station := _object(BOOTH)
	_check(station != null, "the existing booth has a live interaction")
	if station == null:
		return false
	_level.player.global_position = station.global_position + Vector2(-22, 0)
	await _settle(12)
	var done := [false]
	var talk := func() -> void:
		await station._talk()
		done[0] = true
	talk.call()
	if DisplayServer.get_name() != "headless":
		_shots[String(CALL_OFFER) + ":choice"] = "ledger-call"
	await _drive(["call"], func() -> bool: return done[0] or Story._current_cinematic == CALL)
	_shots.clear()
	_check(not done[0] and Story._current_cinematic == CALL, "the real call outcome is queued")
	if done[0] or Story._current_cinematic != CALL:
		return false
	var contacts := 0
	var captured := false
	for frame in 360:
		var action: WorldPropAction = _level.player._visual.interaction_action
		if action != null:
			contacts = maxi(contacts, action.contacts_completed)
			if DisplayServer.get_name() != "headless" and not captured and contacts == 1:
				captured = true
				_capture("ledger-call-contact")
		var player: CutscenePlayer = Story._player
		if done[0] or (is_instance_valid(player) and player._dialogue.visible):
			break
		await get_tree().physics_frame
	_check(contacts == 1, "Rin's front hand reaches the telephone hook before the first line")
	var retained := FileAccess.get_file_as_bytes(slot.path)
	var temporary := slot.path + ".tmp"
	if DirAccess.make_dir_absolute(temporary) != OK:
		_check(false, "the isolated slot cannot simulate a write refusal")
		return false
	await _drive([], func() -> bool: return is_instance_valid(Story.result_completion.get("_prompt")))
	_check(not done[0] and FileAccess.get_file_as_bytes(slot.path) == retained
			and not GameState.has_flag(REQUESTED), "a refused write preserves the request and previous slot")
	_check(DirAccess.remove_absolute(temporary) == OK, "the isolated write obstruction was removed")
	Story.result_completion.call("_retry")
	await _drive([], func() -> bool: return done[0])
	_check(done[0], "retry finishes and releases the original call")
	return done[0]


func _capture(name: String) -> void:
	var frame := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(frame.save_jpg(_out_dir.path_join(name + ".jpg"), 0.86) == OK,
			"the active physical booth and choices were captured")
