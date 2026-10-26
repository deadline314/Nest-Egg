extends "res://tests/helpers/ali_completion_base.gd"
## Reuse the refusal contract, then retry the same real source and cold-read its bytes.
var publications: Array = []
var starts := {}
var finishing := false

func _ready() -> void:
	GameState.flag_changed.connect(_observe)
	Story.scene_started.connect(func(id: StringName, _kind: StringName) -> void: starts[String(id)] = int(starts.get(String(id), 0)) + 1)
	super._ready()

func _run() -> void:
	if _mode.ends_with("read"):
		await _cold()
	else:
		await super._run()

## The inherited contract calls this after verifying refusal and removing its
## obstruction. Continue with a second real rejection, rather than quitting.
func _finish() -> void:
	if finishing:
		return
	finishing = true
	if not _failures.is_empty() or not faulted or _prompt() == null:
		_check(false, "positive continuation requires the original refused source and real prompt")
		await _exit()
		return
	var prompt := _prompt()
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "recreate only the owned obstruction for a second real rejection")
	prompt.retry_button.pressed.emit()
	await _frames(4)
	_check(_facts() == facts_before and FileAccess.get_file_as_bytes(store.path) == original and _prompt() == prompt, "second real rejection preserves every fact, original primary and prompt identity")
	_check(_actor().talk_count == before_count and _actor()._talking and Story._current_cinematic == target, "second rejection cannot settle or replace the original NPC waiter")
	_check(int(starts.get(String(target), 0)) == 1, "writer retry does not replay the authored animation")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the owned obstruction before successful retry")
	prompt.retry_button.pressed.emit()
	await _frames(5)
	if target in [ORDERED, SIT]:
		_check(GameState.has_flag(&"ch1_ali_evening_talk_done") and not GameState.has_flag(&"ch1_lounge_evening_done") and _actor().talk_count == before_count and _actor()._talking, "accepted middle reading preserves the real closing continuation without final settlement")
		_check(Story._current_cinematic == CLOSE and _actor().is_present(), "accepted middle reading starts its authored closing with the original visible source")
		_main.call("_save_run") # Verify the actual primary below; this API returns void.
		var pending := _primary()
		_check(pending.get("cinematic") == String(CLOSE) and pending.get("progression", {}).get("credits") == 234, "actual pending primary includes closing position and fresh wallet")
		FileAccess.open(_directory.path_join("pending-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
		if _mode == "cancel":
			Story.reset_active_presentation(&"leave")
			await _frames(6)
			_check(_actor().is_present() and not _actor()._talking and _actor().talk_count == before_count and not GameState.has_flag(&"ch1_lounge_evening_done"), "accepted-middle cancellation preserves the earlier flag without finishing, hiding or counting Ali")
			_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "accepted-middle cancellation releases only its original UI and locks")
			_main.call("_save_run") # Verify the actual primary below; this API returns void.
			_check(_primary().get("cinematic") == "" and _primary().get("progression", {}).get("credits") == 234 and Progression.credits == 234, "cancelled primary has no fabricated pending read or lost observer spend")
			await _capture("cancelled")
			await _exit()
			return
	await _settle()
	_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "accepted original request releases retry UI and pause")
	_check(int(starts.get(String(target), 0)) == 1, "successful writer retry never restarts the completed authored segment")
	var expected := before_count + 1
	_check(_actor().talk_count == expected and not _actor()._talking, "real NPC waiter settles exactly once after the actual terminal")
	if target == NAME:
		_check(GameState.has_flag(&"ch1_met_ali") and not GameState.has_flag(&"ch1_lounge_evening_done") and _actor().is_present(), "name completion does not invent the evening or remove the lounge source")
	else:
		_check(GameState.has_flag(&"ch1_ali_evening_talk_done") and GameState.has_flag(&"ch1_lounge_evening_done") and not _actor().is_present(), "only the accepted real closing hides lounge Ali and satisfies the original exit flag")
	_check(publications.size() == (2 if target in [ORDERED, SIT] else 1), "each newly accepted actual result publishes once")
	_check(Progression.credits == 235 - publications.size(), "ordinary notification spending remains live without proposal overwrite")
	_main.call("_save_run") # Verify the actual primary below; this API returns void.
	var final := _primary()
	_check(final.get("progression", {}).get("credits") == Progression.credits and _counts(final).all(func(count: Variant) -> bool: return count == expected), "final original primary keeps fresh wallet and all three true NPC counts")
	await _capture("accepted")
	await _exit()

func _observe(id: StringName, value: Variant) -> void:
	if not faulted or id not in [&"ch1_met_ali", &"ch1_ali_evening_talk_done", &"ch1_lounge_evening_done"] or value != true:
		return
	var raw := _primary()
	var middle := id == &"ch1_ali_evening_talk_done"
	var expected := before_count if middle else before_count + 1
	var pending := String(CLOSE) if middle else ""
	_check(raw.get("story", {}).get("flags", {}).get(String(id)) == true, "first result observer reads the new flag in the actual checksum-valid primary")
	_check(raw.get("cinematic") == pending, "first result observer reads exact pending closing or actual terminal")
	var counts := _counts(raw)
	_check(counts.size() == 3 and counts.all(func(count: Variant) -> bool: return count == expected) and _actor().talk_count == expected, "first result observer sees three coherent durable NPC projections and live count")
	_check(_actor()._talking and _actor()._durable_completed == (not middle), "first result observer precedes the original waiter with the correct settlement marker")
	if middle:
		_check(raw.get("cinematic_context", {}).get("source_id") == _actor().state_key(), "middle primary retains its actual authored person source")
		FileAccess.open(_directory.path_join("first-notification-primary.json"), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(store.path))
	_check(not Story.play(&"ch1_t_label_watch", false), "result publication rejects a reentrant story producer")
	_check(Progression.spend(1), "ordinary observer spending remains legal")
	publications.append({"flag":String(id),"pending":pending,"counts":counts,"live":_actor().talk_count,"durable":_actor()._durable_completed})

func _counts(raw: Dictionary) -> Array:
	var rows: Array = []
	for world: Dictionary in [raw.get("runtime", {}).get("world", {}), raw.get("runtime", {}).get("area", {}).get("world", {}), raw.get("state", {}).get("area_states", {}).get("ch1_lounge", {}).get("world", {})]:
		rows.append(world.get(_actor().state_key(), {}).get("talks", -1))
	return rows

func _primary() -> Dictionary:
	var result := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
	_check(result.has("data"), "read original primary through its actual checksum envelope without repairs")
	return result.get("data", {})

func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while _actor()._talking and _prompt() == null and Time.get_ticks_msec() < deadline:
		if Story._current_cinematic != &"":
			Story.skip_cinematic()
		await _frames(1)
	_check(not _actor()._talking and _prompt() == null, "actual remaining closing settles within bounded time")

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
	var wallet: int = raw.get("progression", {}).get("credits", -1)
	_main.call("_on_continue_requested")
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	var counts := _counts(raw)
	var previous := int(counts[0]) if counts.size() == 3 else -1
	_check(previous >= 0 and counts.all(func(count: Variant) -> bool: return count == previous) and _actor().talk_count == previous, "cold actual source starts at all three original primary counters")
	var completes_closing := not pending.is_empty() or _mode == "cancel_read"
	if _mode == "cancel_read":
		_check(GameState.has_flag(&"ch1_ali_evening_talk_done") and not GameState.has_flag(&"ch1_lounge_evening_done") and not _actor()._talking, "cancelled cold progress retains only the previously read middle")
		_actor()._talk()
	if not pending.is_empty():
		_check(pending == String(CLOSE), "cold original pending bytes own exactly the authored closing")
		await _until(func() -> bool: return Story._current_cinematic == CLOSE and _actor()._talking)
	if completes_closing:
		await _settle()
	_check(GameState.has_flag(&"ch1_met_ali"), "cold process preserves the actual completed original meeting")
	_check(_actor().talk_count == previous + (1 if completes_closing else 0) and not _actor()._talking, "cold original NPC settles only a genuinely remaining closing once")
	_check(Progression.credits == wallet, "cold process keeps actual saved observer spending without replaying it")
	_check(_actor().is_present() == (not GameState.has_flag(&"ch1_lounge_evening_done")), "cold source presence matches its real authored ending flag")
	_check(_prompt() == null and not GameplayLock.is_locked() and not get_tree().paused, "cold source has no stale retry or pause")
	await _capture("cold")
	await _exit()

func _capture(name: String) -> void:
	var previous := out
	out = previous.path_join(name)
	await _shot()
	out = previous

func _exit() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":Array(_failures),"publications":publications,"wallet":Progression.credits,"starts":starts,"talks":_actor().talk_count if is_instance_valid(_actor()) else -1,"present":_actor().is_present() if is_instance_valid(_actor()) else false,"flags":[GameState.has_flag(&"ch1_met_ali"),GameState.has_flag(&"ch1_ali_evening_talk_done"),GameState.has_flag(&"ch1_lounge_evening_done")]},"  "))
	print("[AliCompletionProbe] %s checks=%d failures=%d" % [_mode,_checks,_failures.size()])
	_main.call("_quit", 0 if _failures.is_empty() else 1)
