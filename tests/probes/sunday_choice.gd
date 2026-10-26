extends "res://tools/run_save_probe.gd"
## Arranged prerequisites; real Main, authored NPC, choice UI and filesystem faults.
const ROOM := "res://data/levels/ch1_rooftop.tres"
const PROMPT := &"ch1_t_egret_sunday_prompt"
const LEAF := &"ch1_t_egret_sunday"
var _store: RunSaveStore
var _out := ""
var _publications: Array = []
var _original := PackedByteArray()
var _before := PackedByteArray()
var _leaf_fault := false
var _reading_shot := false
var _capture_index := 0

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_absolute_path():
		push_error("[SundayChoiceProbe] --out must be an absolute isolated directory")
		get_tree().quit(2)
		return
	super._ready()

func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = not _mode.ends_with("read")
	_main = MainScript.new()
	_store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", _store)
	add_child(_main)
	await _frames(5)
	if _mode.ends_with("read"):
		var original := RunSaveCodec.decode(FileAccess.get_file_as_string(_store.path))
		var pending: String = original.get("data", {}).get("cinematic", "")
		_main.call("_on_continue_requested")
		await _room()
		if _mode in ["pending_read", "accepted_read"]:
			await _until(func() -> bool: return not _main.get("_restore_publish_pending"))
			if _mode == "accepted_read" and pending.is_empty():
				_check(GameState.has_flag(&"ch1_sunday_accepted") and not GameState.has_flag(&"asked_egret_sunday") and _actor().talk_count == 0, "cold cancelled choice preserves accepted intent and requires genuinely unread conversation")
				_actor()._talk()
			await _until(func() -> bool: return Story._current_cinematic == LEAF and _actor()._talking)
			_check(Story._current_cinematic == LEAF and _actor()._talking, "cold pending continuation restores actual leaf and original NPC waiter")
			_check(GameState.has_flag(&"ch1_sunday_accepted") and not GameState.has_flag(&"asked_egret_sunday"), "cold pending choice retains intent without fabricating the unread result")
			await _drive(false)
			_check(Progression.credits == (123 if _mode == "pending_read" else 122) and StoryItems.is_new(&"ch1_grey_cloth") == (_mode == "pending_read"), "cold pending choice retains exactly its original durable wallet and NEW state")
		else:
			_check(Progression.credits == 121 and not StoryItems.is_new(&"ch1_grey_cloth"), "cold completed save retains both observer spends and NEW acknowledgement")
			_check(not Story.is_cinematic_active(), "cold completed continuation does not replay the question")
		_check(GameState.has_flag(&"ch1_sunday_accepted") and GameState.has_flag(&"asked_egret_sunday"), "cold Main restores both genuinely accepted Sunday facts")
		_check(_actor().talk_count == 1 and not _actor()._talking, "cold actual NPC settles exactly once")
		_check(Story.progress_snapshot().has(LEAF), "cold Main retains completed Sunday reading")
		await _shot("cold")
		await _finish()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _until(func() -> bool: return _main.get("_screen") is Level and not _main.call("_route_pending"))
	Story.reset_active_presentation(&"probe_setup")
	# Explicit preexisting brief/dinner; no Sunday result or target history injected.
	GameState.set_flag(&"ch1_dinner_done")
	GameState.set_flag(&"ch1_heard_brief")
	Progression.add_credits(123)
	_check(StoryItems.acquire(&"ch1_grey_cloth", false), "arrange an unrelated existing NEW item through its real owner")
	_main.call("_on_area_requested", ROOM)
	await _room()
	Story.auto_skip = false
	var actor := _actor()
	_check(actor != null and actor.talk_count == 0, "actual authored rooftop NPC starts without a settled Sunday conversation")
	(_main.get("_screen") as Level).player.global_position = actor.global_position + Vector2(-40, 0)
	await _frames(8)
	actor._talk()
	await _drive(true)
	var player := Story._player as CutscenePlayer
	_check(is_instance_valid(player) and player.choice_active() and Story._current_cinematic == PROMPT, "real authored Sunday choice is visible")
	await _frames(3)
	await _shot("question")
	if _mode == "return" or _mode == "skip":
		if _mode == "skip":
			Story.skip_cinematic()
		else:
			_check(player.choose(1), "actual return option is accepted")
		await _drive(false)
		_check(not GameState.has_flag(&"ch1_sunday_accepted") and not GameState.has_flag(&"asked_egret_sunday"), "return/default skip cannot accept or complete the optional question")
		_check(actor.talk_count == 1 and not actor._talking and _prompt() == null, "return/default retains ordinary waiter and releases presentation")
		await _shot(_mode)
		await _finish()
		return
	_original = FileAccess.get_file_as_bytes(_store.path)
	_before = _facts()
	GameState.flag_changed.connect(_observe)
	Story.scene_started.connect(_inject_leaf)
	_check(DirAccess.make_dir_absolute(_store.path + ".tmp") == OK, "actual temp-directory obstruction refuses choice persistence")
	_check(not player.choose(0), "failed save refuses to consume the actual ask option")
	await _frames(3)
	_check(_facts() == _before and _publications.is_empty(), "choice refusal publishes no flag, wallet, custody or completion changes")
	_check(FileAccess.get_file_as_bytes(_store.path) == _original, "choice refusal preserves exact original primary bytes")
	_check(is_instance_valid(player) and player.choice_active() and player._chosen == -1 and Story._current_cinematic == PROMPT, "choice refusal retains the same unanswered question and player")
	_check(actor._talking and actor.talk_count == 0, "choice refusal never settles the original NPC waiter")
	_check(_prompt() != null and get_tree().paused, "choice refusal keeps a real retry-only modal and gameplay pause")
	await _shot("choice-refused")
	if _mode == "negative":
		DirAccess.remove_absolute(_store.path + ".tmp")
		await _finish()
		return
	if _prompt() == null:
		DirAccess.remove_absolute(_store.path + ".tmp")
		_check(false, "required retry UI is absent")
		await _finish()
		return
	Story.skip_cinematic()
	player.skip()
	await _frames(2)
	_check(player.choice_active() and Story._current_cinematic == PROMPT and _facts() == _before, "skip cannot bypass the refused durable choice")
	_check(not player.choose(1), "another option cannot replace an unresolved durable choice attempt")
	_check(not _prompt().cancel_button.visible, "critical choice offers no misleading cancel action")
	_prompt().retry_button.pressed.emit()
	await _frames(2)
	_check(_facts() == _before and _publications.is_empty() and player.choice_active(), "second genuine IO rejection keeps the same unanswered option and facts")
	if _mode == "reset":
		DirAccess.remove_absolute(_store.path + ".tmp")
		Story.reset_active_presentation(&"leave")
		await _frames(4)
		_check(_facts() == _before and not actor._talking and actor.talk_count == 0, "external reset of refused choice cannot fabricate acceptance or NPC completion")
		_check(_prompt() == null and not GameplayLock.is_locked(), "external reset releases only owned modal and locks")
		await _finish()
		return
	_check(DirAccess.remove_absolute(_store.path + ".tmp") == OK, "remove only the owned choice obstruction")
	_prompt().retry_button.pressed.emit()
	if _mode == "observer_reset":
		await _frames(6)
		_check(GameState.has_flag(&"ch1_sunday_accepted") and not GameState.has_flag(&"asked_egret_sunday"), "observer-requested deferred reset preserves accepted choice without fabricating unread completion")
		_check(not actor._talking and actor.talk_count == 0 and not Story.is_cinematic_active(), "deferred reset retires the original waiter only after coherent publication")
		_check(_prompt() == null and not GameplayLock.is_locked(), "deferred reset releases its owned presentation and modal")
		_check(Progression.credits == 122 and not StoryItems.is_new(&"ch1_grey_cloth"), "accepted cancellation preserves ordinary observer spending and NEW acknowledgement")
		_main.call("_save_run")
		var pending := RunSaveCodec.decode(FileAccess.get_file_as_string(_store.path))
		_check(pending.has("data") and pending["data"]["cinematic"] in ["", String(LEAF)] and pending["data"]["story"]["flags"].get("ch1_sunday_accepted") == true and pending["data"]["story"]["flags"].get("asked_egret_sunday") == false and pending["data"]["progression"]["credits"] == 122, "accepted cancellation persists genuine accepted intent and fresh observer facts without completing unread dialogue")
		await _shot("accepted-reset")
		await _finish()
		return
	await _drive(false)
	_check(_leaf_fault and _prompt() != null, "actual accepted choice reaches the authored leaf and refuses its separate completion write")
	_check(GameState.has_flag(&"ch1_sunday_accepted") and not GameState.has_flag(&"asked_egret_sunday") and actor.talk_count == 0, "leaf refusal preserves durable choice without granting unread result or NPC count")
	_check(_publications.size() == 1 and Progression.credits == 122 and not StoryItems.is_new(&"ch1_grey_cloth"), "choice observer spending and NEW acknowledgement survive leaf refusal")
	await _shot("leaf-refused")
	_check(DirAccess.remove_absolute(_store.path + ".tmp") == OK, "remove only the owned leaf obstruction")
	if _prompt() != null:
		_prompt().retry_button.pressed.emit()
	await _drive(false)
	_check(GameState.has_flag(&"asked_egret_sunday") and actor.talk_count == 1 and not actor._talking, "genuine retry finishes the reading and original waiter exactly once")
	_check(_publications.size() == 2 and Progression.credits == 121, "both notifications preserve legal ordinary spending without proposal reinstall")
	_check(_prompt() == null and not GameplayLock.is_locked(), "successful choice and leaf release owned UI and locks")
	await _frames(5)
	var raw := RunSaveCodec.decode(FileAccess.get_file_as_string(_store.path))
	_check(raw.has("data") and raw["data"]["progression"]["credits"] == 121, "fresh queued save captures final observer wallet")
	_check(not raw["data"]["story"]["items"]["unseen"].has("ch1_grey_cloth"), "fresh queued save captures final observer NEW acknowledgement")
	await _shot("accepted")
	await _finish()

func _observe(id: StringName, value: Variant) -> void:
	if id not in [&"ch1_sunday_accepted", &"asked_egret_sunday"] or value != true:
		return
	var raw := FileAccess.get_file_as_string(_store.path)
	var decoded := RunSaveCodec.decode(raw)
	_check(decoded.has("data"), "first notification reads checksum-valid original primary without read-time repairs")
	if not decoded.has("data"):
		return
	var data: Dictionary = decoded["data"]
	var choice := id == &"ch1_sunday_accepted"
	var expected := 0 if choice else 1
	var counts: Array = []
	for world: Dictionary in [data["runtime"]["world"], data["runtime"]["area"]["world"], data["state"]["area_states"][String((_main.get("_screen") as Level).data.id)]["world"]]:
		counts.append(world.get(_actor().state_key(), {}).get("talks", -1))
	_check(data["story"]["flags"].get(String(id)) == true, "first notification sees its flag already in original durable primary")
	_check(counts.size() == 3 and counts.all(func(count: Variant) -> bool: return count == expected) and _actor().talk_count == expected, "first notification sees matching live and all three durable NPC counters")
	if choice:
		_check(data["cinematic"] == String(LEAF) and data["cinematic_context"].get("source_id") == _actor().state_key(), "choice notification sees durable target and actual interaction source together")
		_check(not data["story"]["flags"].get("asked_egret_sunday") and not data["story"]["seen"].has(String(LEAF)), "choice durability cannot fabricate the unread leaf completion")
		FileAccess.open(_directory.path_join("pending-primary.json"), FileAccess.WRITE).store_string(raw)
	else:
		_check(data["story"]["seen"].has(String(LEAF)) and _actor()._durable_completed, "leaf notification sees complete durable reading and settled live NPC before waiter")
	if _mode == "negative":
		_publications.append({"flag": String(id), "counts": counts, "live": _actor().talk_count, "pending": data["cinematic"]})
		return
	_check(not Story.play(&"ch1_t_label_watch", false), "reentrant presentation is refused during result publication")
	_check(Story.call("apply_choice", {"set_flags": {"ch1_voice_accepted": true}}) == false, "reentrant choice cannot publish unrelated story intent")
	var path: String = _main.get("_level_path")
	var screen: Node = _main.get("_screen")
	_main.call("_on_area_requested", "res://data/levels/ch1_stall.tres")
	_check(_main.get("_level_path") == path and _main.get("_screen") == screen and _main.get("_pending_screen") == null, "reentrant route cannot replace publishing owners")
	_check(Progression.spend(1), "ordinary observer spending remains legal")
	StoryItems.mark_seen(&"ch1_grey_cloth")
	if _mode == "observer_reset" and choice:
		Story.reset_active_presentation(&"leave")
	_publications.append({"flag": String(id), "counts": counts, "live": _actor().talk_count, "pending": data["cinematic"], "context": data["cinematic_context"]})

func _inject_leaf(id: StringName, _kind: StringName) -> void:
	if id == LEAF and not _leaf_fault and _mode == "write":
		_leaf_fault = true
		_check(DirAccess.make_dir_absolute(_store.path + ".tmp") == OK, "actual temp-directory obstruction refuses leaf completion")

func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])

func _actor() -> NpcActor:
	for node: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and node.data.id == &"ch1_egret" and (_main.get("_screen") as Level).is_ancestor_of(node):
			return node
	return null

func _prompt() -> Control:
	return (_main.get("_result_completion") as Node).get("_prompt") as Control

func _until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(predicate.call(), "actual Main transition settles within bounded wait")

func _room() -> void:
	await _until(func() -> bool: return _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and _main.get("_level_path") == ROOM and not _main.call("_route_pending"))

func _drive(stop_at_choice: bool) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if _prompt() != null or (not stop_at_choice and not _actor()._talking):
			return
		var player := Story._player as CutscenePlayer
		if is_instance_valid(player) and player.choice_active():
			if stop_at_choice:
				return
		elif is_instance_valid(player) and player._dialogue.visible:
			player._dialogue.complete()
			if Story._current_cinematic == LEAF and not _reading_shot:
				_reading_shot = true
				await _shot("reading")
			player._advance_requested = true
		await _frames(1)
	_check(false, "authored presentation reaches expected choice, retry or completion")

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var note := Label.new()
	note.text = "SOFTWARE FORWARD+ / ARRANGED BRIEF + REAL NPC + IO FAULT / NOT A PLAYTHROUGH"
	note.position = Vector2(10, 10)
	note.add_theme_font_size_override("font_size", 12)
	canvas.add_child(note)
	# A changing binary marker rejects a previous screenshot's delayed readback.
	# Repeated white text alone can accept an older frame while a new modal draws.
	_capture_index += 1
	var markers: Array[ColorRect] = []
	for bit in 4:
		var marker := ColorRect.new()
		marker.position = Vector2(600 + bit * 7, 8)
		marker.size = Vector2(6, 6)
		marker.color = Color.WHITE if (_capture_index & (1 << bit)) != 0 else Color.BLACK
		canvas.add_child(marker)
		markers.append(marker)
	var captured: Image
	var visible := false
	for attempt in 45:
		await _frames(1)
		await RenderingServer.frame_post_draw
		captured = preload("res://tools/viewport_capture.gd").image(get_viewport())
		var white := 0
		for y in range(26, 48, 2):
			for x in range(20, 1080, 2):
				var color := captured.get_pixel(x, y)
				if minf(color.r, minf(color.g, color.b)) > 0.8:
					white += 1
		var fresh := true
		for bit in markers.size():
			var marker := markers[bit]
			var pixel := get_viewport().get_final_transform() * marker.get_global_transform_with_canvas() * (marker.size * 0.5)
			var color := captured.get_pixel(int(pixel.x), int(pixel.y))
			var level := minf(color.r, minf(color.g, color.b))
			fresh = fresh and (level > 0.8 if (_capture_index & (1 << bit)) != 0 else maxf(color.r, maxf(color.g, color.b)) < 0.05)
		var laid_out := true
		var prompt := _prompt()
		if prompt != null:
			laid_out = _capture_text_visible(captured, prompt.get("_message") as Control) and _capture_text_visible(captured, prompt.retry_button)
		if white >= 64 and fresh and laid_out:
			visible = true
			break
	_check(visible, "capture contains its actually rendered diagnostic label: " + name)
	captured.save_png(_out.path_join(name + ".png"))
	canvas.queue_free()


func _capture_text_visible(captured: Image, control: Control) -> bool:
	if not is_instance_valid(control) or control.size.x <= 0 or control.size.y <= 0:
		return false
	var transform := get_viewport().get_final_transform() * control.get_global_transform_with_canvas()
	var origin := transform * Vector2.ZERO
	var rect := Rect2(origin, transform * control.size - origin).abs()
	rect = rect.intersection(Rect2(Vector2.ZERO, Vector2(captured.get_size())))
	# Containers initially report their minimum size at (0, 0). That rectangle
	# overlaps our diagnostic header and cannot prove the centered modal drew.
	if rect.position.y < captured.get_height() * 0.15 or rect.position.x < 8 or rect.end.x > captured.get_width() - 8:
		return false
	var white := 0
	for y in range(int(rect.position.y), int(rect.end.y), 2):
		for x in range(int(rect.position.x), int(rect.end.x), 2):
			var color := captured.get_pixel(x, y)
			if minf(color.r, minf(color.g, color.b)) > 0.8:
				white += 1
				if white >= 32:
					return true
	return false

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode": _mode, "checks": _checks, "failures": Array(_failures), "publications": _publications}, "  "))
	await super._finish()
