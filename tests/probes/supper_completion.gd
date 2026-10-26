extends "res://tests/helpers/supper_completion_base.gd"
const Sources := preload("res://game/story_result_sources.gd")
const Supper := preload("res://game/story_result_supper.gd")
var case_name := ""
var publications: Array = []
var starts := {}
var expected_next := &""
var selected_option := ""
var initial_wallet := 0
var observer_spends := 0
var batch_spends := {}
var finishing := false

func _ready() -> void:
	GameState.flag_changed.connect(_observe_flag)
	Progression.story_transaction_committed.connect(func(id: StringName) -> void:
		if faulted and String(id).begins_with("ch1.revival_meal."):
			_observe("transaction:" + String(id)))
	StoryItems.acquired.connect(func(item: StoryItemData) -> void:
		if faulted and item.id == &"ch1_lounge_tab":
			_observe("item:" + String(item.id)))
	Story.scene_started.connect(func(id: StringName, _kind: StringName) -> void: starts[String(id)] = int(starts.get(String(id),0)) + 1)
	super._ready()

func _run() -> void:
	case_name = _mode
	if case_name.ends_with("read"):
		await _cold()
	elif case_name.begins_with("normal_"):
		await _normal()
	else:
		_mode = "host" if case_name == "cancel_host" else "pay" if case_name == "insufficient" else case_name
		await super._run()

func _inject(id: StringName, kind: StringName) -> void:
	if case_name.begins_with("normal_"):
		if id == target and not faulted:
			faulted = true
			before_count = _actor().talk_count
			initial_wallet = Progression.credits
			expected_next = StringName(Supper.BOUNDARIES[String(target)]["then"])
		return
	if id == target and case_name == "insufficient" and not faulted:
		_check(Progression.spend(40) and Progression.credits == 193, "ordinary pre-payment spend creates actual insufficient cash without editing the wallet")
	super._inject(id, kind)

func _fault() -> void:
	selected_option = _wanted() if choosing else ""
	if choosing:
		for option: Dictionary in Supper.CHOICES[String(target)]["options"]:
			if option["id"] == selected_option:
				expected_next = StringName(option["target"])
	else:
		expected_next = Sources.failure(String(target), "insufficient_credits", Story._scenes, Story._scene_sources) if case_name == "insufficient" else StringName(Supper.BOUNDARIES[String(target)]["then"])
	initial_wallet = Progression.credits
	super._fault()

func _finish() -> void:
	if finishing:
		return
	finishing = true
	if not faulted or not _failures.is_empty() or _prompt() == null:
		_check(false, "success requires the same valid refused original supper source")
		await _exit()
		return
	var prompt := _prompt()
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "repeat only the owned IO obstruction")
	prompt.retry_button.pressed.emit()
	await _frames(4)
	_check(_facts() == facts_before and FileAccess.get_file_as_bytes(store.path) == original and _prompt() == prompt, "second genuine refusal keeps every fact, primary and same retry modal")
	_check(_actor().talk_count == before_count and _actor()._talking and int(starts.get(String(target),0)) == 1, "writer retries preserve original waiter and never replay its segment")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only owned obstruction before actual commit")
	prompt.retry_button.pressed.emit()
	await _frames(5)
	_check(_prompt() == null and int(starts.get(String(target),0)) == 1, "successful retry retires original modal without animation replay")
	if expected_next != &"":
		_check(Story._current_cinematic == expected_next and _actor()._talking and _actor().talk_count == before_count and not _actor()._durable_completed, "accepted middle keeps exact unread segment and same original unsettled source")
		_main.call("_save_run")
		var raw := _primary()
		_check(raw.get("cinematic") == String(expected_next) and raw.get("cinematic_context",{}).get("source_id") == _actor().state_key(), "fresh original pending primary retains exact next scene and source identity")
		_check(raw["progression"]["credits"] == Progression.credits, "fresh pending capture retains all ordinary observer spending")
		FileAccess.open(_directory.path_join("pending-primary.json"),FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
		await _capture("pending")
	if case_name == "cancel_host":
		Story.reset_active_presentation(&"leave")
		await _frames(5)
		_check(GameState.has_flag(&"ch1_supper_host_accepted") and not GameState.has_flag(&"ch1_supper_meal_done") and not GameState.has_flag(&"knows_ali_address") and _actor().talk_count == 0 and not _actor()._talking, "accepted-host cancellation cannot invent eating, address or settled count")
		_main.call("_save_run")
		_check(_primary().get("cinematic") == "", "cancelled primary retains accepted gift without fabricated pending reading")
		await _capture("cancelled")
	else:
		await _settle()
		_check(_actor().talk_count == before_count + 1 and not _actor()._talking, "actual complete original interaction settles once only at its terminal")
		_check(GameState.has_flag(&"ch1_supper_done") == (case_name != "return"), "only genuinely completed chosen supper finishes its outcome")
		_main.call("_save_run")
		_check(_same_counts(_primary(),before_count + 1), "final original primary preserves three coherent actual terminal counts")
		await _capture("accepted")
	var paid: bool = Progression.story_receipt_status(&"ch1.revival_meal.paid").get("status") == "recorded"
	_check(Progression.credits == initial_wallet - (200 if paid else 0) - observer_spends, "actual monetary outcome retains every ordinary observer spend without reinstall")
	_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "success or cancellation releases only owned UI and locks")
	await _exit()

## No IO obstruction: the preceding player's skip must still own its unread
## finite continuation, rather than prematurely settling its original waiter.
func _normal() -> void:
	_mode = case_name.trim_prefix("normal_")
	var actor := await _open_source()
	if actor == null:
		await _exit()
		return
	actor._talk()
	await _drive()
	await _frames(5)
	_check(faulted and skip_sent and expected_next != &"", "normal actual player skips the selected original middle without an IO fault")
	_check(Story._current_cinematic == expected_next and actor._talking and actor.talk_count == before_count and not actor._durable_completed, "normal direct skip preserves exact unread next and original unsettled waiter")
	_check(_prompt() == null, "normal direct skip requires no retry modal")
	_main.call("_save_run")
	var raw := _primary()
	_check(raw.get("cinematic") == String(expected_next) and _same_counts(raw,before_count), "normal skipped middle is durable in all original source projections")
	FileAccess.open(_directory.path_join("pending-primary.json"),FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
	await _capture("pending")
	await _settle()
	_check(actor.talk_count == before_count + 1 and GameState.has_flag(&"ch1_supper_done"), "normal remaining original interaction completes exactly once")
	var paid: bool = Progression.story_receipt_status(&"ch1.revival_meal.paid").get("status") == "recorded"
	_check(Progression.credits == initial_wallet - (200 if paid else 0) - observer_spends, "normal direct skip retains actual payment and every ordinary observer spend")
	_main.call("_save_run")
	_check(_same_counts(_primary(),before_count + 1), "normal terminal original primary has three correct final counts")
	await _capture("accepted")
	await _exit()

func _observe_flag(id: StringName, _value: Variant) -> void:
	if not faulted or id not in [&"ch1_supper_choice", &"ch1_supper_host_accepted", &"ch1_supper_meal_done", &"knows_ali_address", &"sq1_first_supper_done", &"ch1_supper_done"]:
		return
	_observe("flag:" + String(id))
	_check(not Story.play(&"ch1_t_label_watch",false), "coherent result publication rejects reentrant story")
	_check(Progression.spend(1), "ordinary observer spending remains legal")
	observer_spends += 1
	var producer := String((_main.get("_result_completion") as Node).get("_id"))
	batch_spends[producer] = int(batch_spends.get(producer,0)) + 1
	if StoryItems.owns(&"ch1_lounge_tab"):
		StoryItems.mark_seen(&"ch1_lounge_tab")

func _observe(event: String) -> void:
	var raw := _primary()
	var pending: String = raw.get("cinematic","")
	var expected := before_count + (1 if pending.is_empty() else 0)
	_check(_same_counts(raw,expected) and _actor().talk_count == expected and _actor()._talking, "first " + event + " observer reads matching original/live NPC projections")
	_check(_actor()._durable_completed == pending.is_empty(), "first " + event + " observer sees correct source settlement marker")
	_check(raw["story"]["flags"] == JSON.parse_string(JSON.stringify(GameState.world_flags)), "first " + event + " observer sees entire original flag batch")
	_check(raw["story"]["items"] == JSON.parse_string(JSON.stringify(StoryItems.snapshot())) and raw["progression"]["story_transactions"] == JSON.parse_string(JSON.stringify(Progression.snapshot()["story_transactions"])), "first " + event + " observer sees original whole custody and transaction batch")
	var producer := String((_main.get("_result_completion") as Node).get("_id"))
	_check(raw["progression"]["credits"] == Progression.credits + int(batch_spends.get(producer,0)), "notification reads committed wallet plus ordinary spends earlier in this same batch")
	if not pending.is_empty():
		_check(raw.get("cinematic_context",{}).get("source_id") == _actor().state_key(), "first " + event + " observer owns exact same original person")
	publications.append({"event":event,"pending":pending,"counts":_counts(raw),"live":_actor().talk_count,"wallet":Progression.credits})

func _primary() -> Dictionary:
	var decoded := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
	_check(decoded.has("data"), "read actual checksum-valid primary without repair or re-encoding")
	return decoded.get("data",{})

func _counts(raw: Dictionary) -> Array:
	var values: Array = []
	for world: Dictionary in [raw.get("runtime",{}).get("world",{}),raw.get("runtime",{}).get("area",{}).get("world",{}),raw.get("state",{}).get("area_states",{}).get("ch1_stall",{}).get("world",{})]:
		values.append(world.get(_actor().state_key(),{}).get("talks",-1))
	return values

func _same_counts(raw: Dictionary, expected: int) -> bool:
	var values := _counts(raw)
	return values.size() == 3 and values.all(func(value: Variant) -> bool: return value == expected)

func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while _actor()._talking and _prompt() == null and Time.get_ticks_msec() < deadline:
		var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
		if is_instance_valid(player) and player.choice_active():
			var wanted := "defer" if (case_name == "insufficient" or _mode == "insufficient") and Story._current_cinematic == &"ch1_t_supper_insufficient" else _wanted()
			var index := player._choice_options.find_custom(func(option: Dictionary) -> bool: return option.get("id") == wanted)
			_check(index >= 0 and player.choose(index), "remaining genuine authored option accepts " + wanted)
		elif is_instance_valid(player) and player.is_running():
			if Story.offers_choice(Story._scenes.get(String(Story._current_cinematic),{})):
				if player._dialogue.visible:
					player._dialogue.complete()
					player._advance_requested = true
			else:
				Story.skip_cinematic()
		elif Story._layer.is_cinematic_active():
			Story._layer.advance()
		await _frames(1)
	_check(not _actor()._talking and _prompt() == null, "remaining original authored supper settles within bounded time")

func _cold() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store",store)
	add_child(_main)
	await _frames(5)
	var raw := _primary()
	var pending: String = raw.get("cinematic","")
	var wallet: int = raw["progression"]["credits"]
	_mode = case_name.trim_suffix("_pending_read").trim_suffix("_read").trim_prefix("normal_")
	_main.call("_on_continue_requested")
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	var count := int(_counts(raw)[0])
	_check(_same_counts(raw,count) and _actor().talk_count == count, "cold exact bytes retain all three original source counters")
	if _mode == "cancel_host":
		_check(pending.is_empty() and not _actor()._talking and not GameState.has_flag(&"ch1_supper_meal_done"), "cold accepted-host cancellation is still genuinely unread")
		_actor()._talk()
	elif not pending.is_empty():
		await _until(func() -> bool: return Story._current_cinematic == StringName(pending) and _actor()._talking)
		_check(_actor().talk_count == count, "cold pending original source remains unsettled")
	if not pending.is_empty() or _mode == "cancel_host":
		await _settle()
	_check(_actor().talk_count == 1 and not _actor()._talking, "cold source settles only its actual remaining reading once")
	_check(GameState.has_flag(&"ch1_supper_done") == (_mode != "return"), "cold explicit authored choices reach the intended actual outcome")
	_check(Progression.credits == wallet and publications.is_empty(), "cold original cannot replay payment, gift or notification spending")
	_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "cold continuation retains no stale UI or pause")
	await _capture("cold")
	await _exit()

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var label := Label.new()
	label.text = "SOFTWARE FORWARD+ / ORIGINAL EVENING PRIMARY + ACTUAL STALL SOURCE"
	label.position = Vector2(10,10)
	label.add_theme_font_size_override("font_size",12)
	canvas.add_child(label)
	await _frames(10)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out.path_join(name))
	preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out.path_join(name).path_join("frame.png"))
	canvas.queue_free()

func _exit() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"mode":case_name,"checks":_checks,"failures":Array(_failures),"publications":publications,"wallet":Progression.credits,"spends":observer_spends,"talks":_actor().talk_count if is_instance_valid(_actor()) else -1,"flags":GameState.world_flags,"items":StoryItems.snapshot(),"progression":Progression.snapshot()},"  "))
	print("[SupperCompletion] %s checks=%d failures=%d" % [case_name,_checks,_failures.size()])
	_main.call("_quit",0 if _failures.is_empty() else 1)
