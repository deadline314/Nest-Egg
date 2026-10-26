extends "res://tests/helpers/voice_completion_base.gd"
## Positive IO/retry/continuation matrix; only prerequisites are arranged.
var publications: Array = []
var settlements: Array = []
var _inject_auto := false
var _reading_capture := false
var _conversation_base_count := 0
func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = not _mode.ends_with("read")
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(5)
	if _mode.ends_with("read"):
		var raw := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
		_check(raw.has("data"), "cold process starts from checksum-valid original primary")
		var pending := StringName(raw.get("data", {}).get("cinematic", ""))
		var credits: int = raw.get("data", {}).get("progression", {}).get("credits", -1)
		_main.call("_on_continue_requested")
		await _room()
		await _until(func() -> bool: return not _main.get("_restore_publish_pending"))
		var original_counts := _counts(raw["data"])
		var previous_count := int(original_counts[0]) if original_counts.size() == 3 else -1
		_check(previous_count >= 0 and original_counts.all(func(count: Variant) -> bool: return count == previous_count) and _actor().talk_count == previous_count, "cold source counters match all three original raw-primary projections")
		var needs_answer := not GameState.has_flag(&"sq5_lamp_voice_noticed")
		if pending == &"" and needs_answer:
			_actor()._talk()
			await _drive_to_end("ask")
		if pending != &"":
			await _until(func() -> bool: return Story._current_cinematic == pending and _actor()._talking)
			_check(_actor().talk_count == previous_count, "cold pending source has no fabricated final NPC settlement")
			await _drive_to_end("ask")
		_check(GameState.has_flag(&"ch1_voice_accepted") and GameState.has_flag(&"ch1_lamp_voice_asked") and GameState.has_flag(&"sq5_lamp_voice_noticed"), "cold original continuation genuinely completes all three voice facts")
		_check(_actor().talk_count == previous_count + (1 if needs_answer else 0) and not _actor()._talking, "cold original NPC settles exactly once for any genuinely remaining answer")
		_check(Progression.credits == credits, "cold continuation never replays ordinary observer spending")
		await _capture("cold")
		await _finish()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _until(func() -> bool: return _main.get("_screen") is Level and not _main.call("_route_pending"))
	Story.reset_active_presentation(&"probe_setup")
	if _mode != "unheard":GameState.set_flag(&"ch1_recording_heard")
	Progression.add_credits(123)
	_main.call("_on_area_requested", ROOM)
	await _room()
	Story.auto_skip = false
	if _mode == "unheard":
		_check(_actor() == null or not _actor().is_present(), "unheard recording never exposes the authored headset source")
		_check(not Story.play(FIRST_PROMPT, false), "unheard recording cannot admit the authored optional question")
		await _finish()
		return
	var actor := _actor()
	_check(actor != null and actor.is_present(), "actual authored headset source is present")
	if actor == null:
		await _finish()
		return
	(_main.get("_screen") as Level).player.global_position = actor.global_position + Vector2(-20, 0)
	await _frames(8)
	GameState.flag_changed.connect(_observe)
	Story.scene_finished.connect(_settled)
	actor._talk()
	await _choice(FIRST_PROMPT)
	if _mode in ["return", "return_then_ask"]:
		_check(_select("return"), "actual first return is accepted")
		await _drive_to_end("return")
		_check(not GameState.has_flag(&"ch1_voice_accepted") and not GameState.has_flag(&"ch1_lamp_voice_asked") and not GameState.has_flag(&"sq5_lamp_voice_noticed"), "first return cannot fabricate optional acceptance or either answer")
		_check(not actor._talking and _prompt() == null and not GameplayLock.is_locked(), "first return releases its original presentation")
		if _mode == "return":
			await _finish()
			return
		_check(actor.talk_count == 1, "ordinary first return has exactly one actual prior conversation")
		_conversation_base_count = 1
		actor._talk()
		await _choice(FIRST_PROMPT)
	await _reject_choice("ask", FIRST_PROMPT)
	await _until(func() -> bool: return Story._current_cinematic == FIRST)
	await _frames(3)
	if _mode == "cancel":
		Story.reset_active_presentation(&"leave")
		await _frames(5)
		_check(GameState.has_flag(&"ch1_voice_accepted") and not GameState.has_flag(&"ch1_lamp_voice_asked") and actor.talk_count == 0, "accepted cancellation preserves real intent without inventing unread first answer or NPC count")
		_check(not actor._talking and _prompt() == null and not GameplayLock.is_locked() and Progression.credits == 122, "accepted cancellation releases ownership and preserves ordinary observer spending")
		_main.call("_save_run")
		var cancelled := _primary()
		_check(cancelled.get("story", {}).get("flags", {}).get("ch1_voice_accepted") == true and cancelled.get("progression", {}).get("credits") == 122, "cancelled accepted intent and fresh wallet are actually durable")
		await _capture("cancelled")
		await _finish()
		return
	_begin_fault()
	await _read_until(FIRST)
	await _refused(FIRST, "first-reading")
	_check(GameState.has_flag(&"ch1_voice_accepted") and not GameState.has_flag(&"ch1_lamp_voice_asked") and actor.talk_count == _conversation_base_count, "first reading rejection preserves accepted choice without premature reading or NPC result")
	if _mode == "skip_auto":
		_inject_auto = true
		Story.scene_started.connect(_auto_boundary)
	await _recover()
	if _mode == "skip_auto":
		await _until(func() -> bool: return _prompt() != null and Story._current_cinematic == SECOND_PROMPT)
		await _refused(SECOND_PROMPT, "auto-default")
		await _recover()
		await _drive_to_end("later")
	elif _mode == "skip_early":
		await _until(func() -> bool: return Story._current_cinematic == SECOND_PROMPT and is_instance_valid(Story._player) and Story._player.is_running())
		_check(not Story._player.choice_active(), "early skip occurs before the second question buttons appear")
		_begin_fault()
		Story.skip_cinematic()
		await _until(func() -> bool: return _prompt() != null)
		await _refused(SECOND_PROMPT, "early-default")
		await _recover()
		await _drive_to_end("later")
	else:
		await _choice(SECOND_PROMPT)
		if _mode in ["invalid", "invalid_skip"]:
			var authored: Dictionary = Story._scenes[String(SECOND_PROMPT)]
			var step: Dictionary = authored["steps"].back()
			var original_default: Variant = step["default"]
			step["default"] = "ask"
			if _mode == "invalid_skip":
				Story.skip_cinematic()
			else:
				_check(not _select("ask"), "mutated authored default cannot grant a different choice capability")
			await _frames(5)
			_check(not Story.is_cinematic_active() and not actor._talking and _prompt() == null and not GameplayLock.is_locked(), "invalid authored choice returns safely instead of waiting forever for a nonexistent retry")
			_check(GameState.has_flag(&"ch1_lamp_voice_asked") and not GameState.has_flag(&"sq5_lamp_voice_noticed") and actor.talk_count == 0 and Progression.credits == 121, "invalid authored choice preserves earlier committed facts and ordinary spending")
			step["default"] = original_default
			actor._talk()
			await _choice(SECOND_PROMPT)
			_check(_select("ask"), "restored actual authored source can be asked again")
			await _drive_to_end("ask")
		elif _mode == "skip_active":
			_begin_fault()
			Story.skip_cinematic()
			await _until(func() -> bool: return _prompt() != null)
			await _refused(SECOND_PROMPT, "visible-default")
			await _recover()
			await _drive_to_end("later")
		else:
			var option := "later" if _mode == "repeat" else "ask"
			await _reject_choice(option, SECOND_PROMPT)
			var leaf := LATER if option == "later" else SECOND
			await _until(func() -> bool: return Story._current_cinematic == leaf)
			await _frames(3)
			_begin_fault()
			await _read_until(leaf)
			await _refused(leaf, "terminal-reading")
			_check(not GameState.has_flag(&"sq5_lamp_voice_noticed") and actor.talk_count == _conversation_base_count, "terminal refusal cannot publish second answer or settle NPC")
			await _recover()
			await _drive_to_end(option)
	if _mode.begins_with("skip_") or _mode == "repeat":
		_check(GameState.has_flag(&"ch1_lamp_voice_asked") and not GameState.has_flag(&"sq5_lamp_voice_noticed") and actor.talk_count == 1, "default/later preserves first clue without inventing a second answer")
	else:
		_check(GameState.has_flag(&"sq5_lamp_voice_noticed") and actor.talk_count == _conversation_base_count + 1, "actual terminal answer completes source exactly once")
	if _mode == "repeat":
		await _frames(8)
		actor._talk()
		await _choice(SECOND_PROMPT)
		_check(_select("later"), "second genuine later visit is accepted")
		await _drive_to_end("later")
		_check(actor.talk_count == 2 and not GameState.has_flag(&"sq5_lamp_voice_noticed"), "result-free later reply can repeat without blocking or granting second answer")
		actor._talk()
		await _choice(SECOND_PROMPT)
		_check(_select("ask"), "third visit can genuinely ask the second question")
		await _drive_to_end("ask")
		_check(actor.talk_count == 3 and GameState.has_flag(&"sq5_lamp_voice_noticed"), "later return never locks out the genuine remaining answer")
	_check(_prompt() == null and not GameplayLock.is_locked() and not actor._talking, "all accepted operations release only their owned UI and locks")
	await _frames(5)
	var primary := _primary()
	_check(primary.get("progression", {}).get("credits") == Progression.credits, "fresh save preserves every ordinary observer spend")
	_check(publications.size() == (3 if GameState.has_flag(&"sq5_lamp_voice_noticed") else 2), "each actual objective publishes exactly once")
	await _capture("accepted")
	await _finish()
func _room() -> void:
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
func _prompt() -> Control:
	return (_main.get("_result_completion") as Node).get("_prompt") as Control
func _begin_fault() -> void:
	original = FileAccess.get_file_as_bytes(store.path)
	before = _facts()
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "create real owned temp-file obstruction")
func _reject_choice(option: String, id: StringName) -> void:
	await _frames(3)
	_begin_fault()
	_check(not _select(option), "actual choice is refused until its durable target can be saved")
	await _refused(id, "choice-" + String(id))
	await _recover()
	var expected := FIRST if id == FIRST_PROMPT else (LATER if option == "later" else SECOND)
	var primary := _primary()
	_check(primary.get("cinematic") == String(expected) and _actor().talk_count == _conversation_base_count, "accepted choice durably records its exact target before completing any NPC conversation")
	if id == SECOND_PROMPT:
		FileAccess.open(_directory.path_join("second-choice-primary.json"), FileAccess.WRITE).store_string(FileAccess.get_file_as_string(store.path))
func _refused(id: StringName, name: String) -> void:
	await _frames(3)
	_check(_facts() == before and FileAccess.get_file_as_bytes(store.path) == original, "refusal preserves every fact and exact original primary: " + name)
	_check(_prompt() != null and get_tree().paused and Story._current_cinematic == id and _actor()._talking, "actual retry modal retains original source request: " + name)
	await _capture(name)
func _recover() -> void:
	var prompt := _prompt()
	if prompt == null:
		_check(false, "a required real retry prompt is present")
		return
	prompt.retry_button.pressed.emit()
	await _frames(2)
	_check(_facts() == before and FileAccess.get_file_as_bytes(store.path) == original and _prompt() == prompt, "second actual writer rejection preserves original request and all facts")
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the owned obstruction")
	prompt.retry_button.pressed.emit()
func _read_until(id: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Story._current_cinematic == id and _prompt() == null and Time.get_ticks_msec() < deadline:
		var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
		if is_instance_valid(player) and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			if not _reading_capture:
				_reading_capture = true
				await _capture("reading")
			player._advance_requested = true
		elif Story._layer.is_cinematic_active():
			if not _reading_capture:
				if Story._layer._text.visible_ratio < 1.0:Story._layer.advance()
				_reading_capture = true
				await _capture("reading")
			Story._layer.advance()
		await _frames(1)
	_check(_prompt() != null or Story._current_cinematic != id, "actual authored reading reaches its save boundary")
func _drive_to_end(option: String) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while _actor()._talking and _prompt() == null and Time.get_ticks_msec() < deadline:
		var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
		if is_instance_valid(player) and player.choice_active() and not player.skipping:
			_check(_select(option), "real follow-up choice accepts " + option)
		elif is_instance_valid(player) and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		elif Story._layer.is_cinematic_active():
			Story._layer.advance()
		await _frames(1)
	_check(not _actor()._talking and _prompt() == null, "original NPC conversation settles within bounded drive")
func _primary() -> Dictionary:
	var decoded := RunSaveCodec.decode(FileAccess.get_file_as_string(store.path))
	_check(decoded.has("data"), "original primary has valid checksum before any reader repair")
	return decoded.get("data", {})
func _observe(id: StringName, value: Variant) -> void:
	if id not in [&"ch1_voice_accepted", &"ch1_lamp_voice_asked", &"sq5_lamp_voice_noticed"] or value != true:return
	var primary := _primary()
	var expected := (_conversation_base_count + (3 if _mode == "repeat" else 1)) if id == &"sq5_lamp_voice_noticed" else _conversation_base_count
	_check(primary.get("story", {}).get("flags", {}).get(String(id)) == true, "first flag notification sees its result already in the actual primary")
	_check(_actor().talk_count == expected and _actor()._talking, "first flag notification sees coherent live NPC before waiter settles")
	var counts := _counts(primary)
	_check(counts.size() == 3 and counts.all(func(count: Variant) -> bool: return count == expected), "all original primary world counters agree at first flag notification")
	var pending := String(FIRST) if id == &"ch1_voice_accepted" else String(SECOND_PROMPT) if id == &"ch1_lamp_voice_asked" else ""
	_check(primary.get("cinematic") == pending, "first flag notification sees the exact durable continuation or true terminal")
	if pending != "":
		_check(primary.get("cinematic_context", {}).get("source_id") == _actor().state_key(), "durable continuation retains original actual headset source")
		FileAccess.open(_directory.path_join("accepted-choice-primary.json" if id == &"ch1_voice_accepted" else "first-reading-primary.json"), FileAccess.WRITE).store_string(FileAccess.get_file_as_string(store.path))
	_check(not Story.play(&"ch1_t_label_watch", false), "publication rejects a reentrant story producer")
	_check(Story.call("apply_choice", {"set_flags": {"ch1_sunday_accepted": true}}) == false, "publication rejects an unrelated reentrant choice")
	_check(Progression.spend(1), "ordinary observer spending remains legal")
	publications.append({"flag":String(id),"pending":pending,"counts":counts,"live":_actor().talk_count})
func _counts(primary: Dictionary) -> Array:
	var rows: Array = []
	for world: Dictionary in [primary.get("runtime", {}).get("world", {}), primary.get("runtime", {}).get("area", {}).get("world", {}), primary.get("state", {}).get("area_states", {}).get(String((_main.get("_screen") as Level).data.id), {}).get("world", {})]:rows.append(world.get(_actor().state_key(), {}).get("talks", -1))
	return rows
func _settled(id: StringName) -> void:
	if id not in [LATER, SECOND]:return
	var primary := _primary()
	var counts := _counts(primary)
	_check(counts.size() == 3 and counts.all(func(count: Variant) -> bool: return count == _actor().talk_count), "terminal scene observer sees matching durable/live NPC counters")
	_check(_actor()._durable_completed and _actor()._talking, "terminal scene observer sees final NPC settlement before original waiter")
	settlements.append({"scene":String(id),"count":_actor().talk_count,"disk":counts})
func _auto_boundary(id: StringName, _kind: StringName) -> void:
	if id != SECOND_PROMPT or not _inject_auto:return
	_inject_auto = false
	Story.auto_skip = true
	_begin_fault()
func _capture(name: String) -> void:
	var previous := out
	out = previous.path_join(name)
	await _shot()
	out = previous
func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":Array(_failures),"publications":publications,"settlements":settlements,"wallet":Progression.credits},"  "))
	print("[VoiceCompletionProbe] %s checks=%d failures=%d" % [_mode,_checks,_failures.size()])
	_main.call("_quit", 0 if _failures.is_empty() else 1)
