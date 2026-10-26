extends "res://tests/helpers/reception_completion_base.gd"
## Real menu, atomic reception, original pending name, no arranged target flags.
const NEXT := &"ch1_t_ali_name"
const BILL := &"ch1_lounge_bill"
const ORDER := &"ch1.revival_meal.order"
var publications: Array = []
var target_starts := 0
var finishing := false

func _ready() -> void:
	GameState.flag_changed.connect(_flag)
	StoryItems.acquired.connect(func(item: StoryItemData) -> void:
		if faulted and item.id == BILL:
			_observe("item"))
	Progression.story_transaction_committed.connect(func(id: StringName) -> void:
		if faulted and id == ORDER:
			_observe("transaction"))
	Story.scene_started.connect(func(id: StringName, _kind: StringName) -> void:
		if id in [&"ch1_t_ali_order", &"ch1_t_ali_sit"]:
			target_starts += 1)
	super._ready()

func _run() -> void:
	if _mode.ends_with("read"):
		ordered = "ordered" in _mode
		await _cold()
	else:
		await super._run()

func _finish() -> void:
	if finishing:
		return
	finishing = true
	if not faulted or not _failures.is_empty() or _prompt() == null:
		_check(false, "positive reception requires the same valid refused original source")
		await _exit()
		return
	var prompt := _prompt()
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "second actual refusal uses only the owned temporary obstruction")
	prompt.retry_button.pressed.emit()
	await _frames(4)
	_check(_facts() == facts_before and FileAccess.get_file_as_bytes(store.path) == original and _prompt() == prompt, "second refusal keeps every original fact, primary byte and prompt")
	_check(_actor().talk_count == 0 and _actor()._talking and target_starts == 1, "refusal retry preserves the first actual source without replaying the segment")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove owned obstruction for actual success")
	prompt.retry_button.pressed.emit()
	await _frames(5)
	_check(GameState.has_flag(&"ch1_ali_reception_selected") and not GameState.has_flag(&"ch1_met_ali"), "accepted reception does not invent completed names")
	_check(Story._current_cinematic == NEXT and _actor().talk_count == 0 and _actor()._talking and not _actor()._durable_completed, "only the unread name owns the same unsettled original person")
	_check(publications == (["transaction", "item", "flag"] if ordered else ["flag"]), "authored results publish once and in original order")
	_check(Progression.credits == 234 and StoryItems.owns(BILL) == ordered, "order charges zero and preserves ordinary observer spend; sit has no bill")
	_check(_prompt() == null and target_starts == 1, "success closes its original prompt without replay")
	_main.call("_save_run")
	var pending := _primary()
	_check(pending.get("cinematic") == String(NEXT) and pending["progression"]["credits"] == 234, "fresh original primary retains unread name and observer wallet")
	_check(pending["story"]["items"] == JSON.parse_string(JSON.stringify(StoryItems.snapshot())), "fresh primary retains ordinary NEW dismissal")
	FileAccess.open(_directory.path_join("pending-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
	await _capture("pending")
	if "cancel" in _mode:
		Story.reset_active_presentation(&"leave")
		await _frames(5)
		_check(not _actor()._talking and _actor().talk_count == 0 and not GameState.has_flag(&"ch1_met_ali"), "accepted reception cancellation cannot settle an unread name")
		_main.call("_save_run")
		_check(_primary().get("cinematic") == "" and _primary()["progression"]["credits"] == 234, "cancel captures original choice with no fictitious pending read")
		await _capture("cancelled")
	else:
		await _settle()
		_check(_actor().talk_count == 1 and GameState.has_flag(&"ch1_met_ali") and _actor().is_present(), "only genuine name completion settles once and keeps Ali present")
		_main.call("_save_run")
		_check(_same_counts(_primary(), 1) and Progression.credits == 234, "final source has three coherent counts and no extra charge")
		await _capture("accepted")
	_check(_prompt() == null and not get_tree().paused and not GameplayLock.is_locked(), "accepted or cancelled source releases only its UI and lock")
	await _exit()

func _flag(id: StringName, value: Variant) -> void:
	if faulted and id == &"ch1_ali_reception_selected" and value == true:
		_observe("flag")
		_check(not Story.play(&"ch1_t_label_watch", false), "publication cannot reenter another story producer")
		_check(Progression.spend(1), "ordinary notification spending is retained")
		if ordered:
			StoryItems.mark_seen(BILL)

func _observe(kind: String) -> void:
	var raw := _primary()
	_check(raw["story"]["flags"].get("ch1_ali_reception_selected") == true and not raw["story"]["flags"].get("ch1_met_ali", false), "first " + kind + " observer reads only the accepted reception in original primary")
	_check(raw.get("cinematic") == String(NEXT) and raw.get("cinematic_context", {}).get("source_id") == _actor().state_key(), "first " + kind + " observer owns exact pending name and original NPC")
	_check(_same_counts(raw, 0) and _actor().talk_count == 0 and _actor()._talking and not _actor()._durable_completed, "first " + kind + " observer cannot settle the name waiter")
	_check(raw["progression"]["credits"] == 235 and Progression.credits == 235, "first " + kind + " observer confirms order deducts zero")
	_check(raw["story"]["items"]["held"].has(String(BILL)) == ordered and StoryItems.owns(BILL) == ordered, "first " + kind + " observer sees coherent whole bill batch")
	_check(raw["progression"]["story_transactions"]["receipts"].has(String(ORDER)) == ordered, "first " + kind + " observer sees original order receipt only if ordered")
	publications.append(kind)

func _primary() -> Dictionary:
	var decoded := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
	_check(decoded.has("data"), "read actual checksum envelope without repaired fixture")
	return decoded.get("data", {})

func _counts(raw: Dictionary) -> Array:
	var values: Array = []
	for world: Dictionary in [raw.get("runtime", {}).get("world", {}), raw.get("runtime", {}).get("area", {}).get("world", {}), raw.get("state", {}).get("area_states", {}).get("ch1_lounge", {}).get("world", {})]:
		values.append(world.get(_actor().state_key(), {}).get("talks", -1))
	return values

func _same_counts(raw: Dictionary, expected: int) -> bool:
	var values := _counts(raw)
	return values.size() == 3 and values.all(func(value: Variant) -> bool: return value == expected)

func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while _actor()._talking and _prompt() == null and Time.get_ticks_msec() < deadline:
		if Story._current_cinematic != &"":
			Story.skip_cinematic()
		await _frames(1)
	_check(not _actor()._talking and _prompt() == null, "real unread name completes within bounded time")

func _cold() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(5)
	var raw := _primary()
	var pending: String = raw.get("cinematic", "")
	var previous := -1
	_main.call("_on_continue_requested")
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	previous = int(_counts(raw)[0])
	_check(_same_counts(raw, previous) and _actor().talk_count == previous, "cold exact primary restores all three original counters")
	_check(GameState.has_flag(&"ch1_ali_reception_selected") and StoryItems.owns(BILL) == ordered and Progression.credits == 234, "cold reception preserves original bill ownership and spend")
	if "cancel" in _mode:
		_check(pending.is_empty() and previous == 0 and not _actor()._talking, "cancelled cold original has no invented read")
		_actor()._talk()
	if not pending.is_empty() or "cancel" in _mode:
		await _until(func() -> bool: return Story._current_cinematic == NEXT and _actor()._talking)
		_check(not GameState.has_flag(&"ch1_met_ali") and _actor().talk_count == 0, "cold continuation begins genuinely unread original name")
		await _settle()
	_check(GameState.has_flag(&"ch1_met_ali") and _actor().talk_count == 1 and _actor().is_present(), "cold actual source completes name exactly once")
	_check(publications.is_empty() and Progression.credits == 234, "cold source never replays reception notifications or observer spend")
	_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "cold original releases no stale prompt or lock")
	await _capture("cold")
	await _exit()

func _capture(name: String) -> void:
	var previous := out
	out = previous.path_join(name)
	await _shot()
	out = previous

func _exit() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":Array(_failures),"publications":publications,"wallet":Progression.credits,"bill":StoryItems.owns(BILL),"talks":_actor().talk_count if is_instance_valid(_actor()) else -1,"met":GameState.has_flag(&"ch1_met_ali"),"selected":GameState.has_flag(&"ch1_ali_reception_selected")},"  "))
	print("[ReceptionCompletion] %s checks=%d failures=%d" % [_mode,_checks,_failures.size()])
	_main.call("_quit", 0 if _failures.is_empty() else 1)
