extends "res://tools/run_save_probe.gd"
## Arranged disk/credits, real Main Level and cabinet interactions. Not a playthrough.
var _target: StringName
var _faulted := false
var _original := PackedByteArray()
var _facts_before := PackedByteArray()
var _store: RunSaveStore
var _out := ""
var _records: Array = []
var _observer_count := 0
var _counter_records: Array[Dictionary] = []

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_empty() and not _out.is_absolute_path():
		push_error("[HandoffCompletionProbe] --out must be an absolute isolated output directory")
		get_tree().quit(2)
		return
	StoryItems.transferred.connect(_observe_transfer)
	super._ready()

func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = true
	_main = MainScript.new()
	_store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", _store)
	add_child(_main)
	await _frames(5)
	if _mode == "reset_read":
		_main.call("_on_continue_requested")
		await _room("res://data/levels/ch1_handoff.tres")
		var fixture := _fixture()
		_check(StoryItems.was_transferred(&"ch1_data_disk") and not StoryItems.holds(&"ch1_data_disk"), "cold reset restore keeps the previously accepted disk transferred")
		_check(not StoryItems.holds(&"ch1_delivery_receipt") and not GameState.has_flag(&"ch1_disk_receipt_taken"), "cold reset restore cannot complete the unaccepted receipt")
		_check(fixture != null and fixture.paper_ready() and fixture._paper_progress == 1.0, "cold reset restore reconstructs the waiting paper without replaying its feed")
		_check(_prompt() == null and not get_tree().paused, "cold reset restore has no stale save prompt or lock")
		await _shot("receipt-reset-cold")
		await _finish()
		return
	if _mode == "read":
		_main.call("_on_continue_requested")
		await _room("res://data/levels/ch1_handoff.tres")
		_check(StoryItems.was_transferred(&"ch1_data_disk") and not StoryItems.holds(&"ch1_data_disk"), "fresh process restores transferred original disk")
		_check(StoryItems.holds(&"ch1_delivery_receipt") and StoryItems.holds(&"ch1_market_summary"), "fresh process restores both actual acquired papers")
		_check(not StoryItems.is_new(&"ch1_delivery_receipt") and not StoryItems.is_new(&"ch1_market_summary"), "fresh process preserves observer NEW acknowledgements")
		_check(Progression.credits == 235, "fresh process preserves two ordinary observer spends without old proposal overwrite")
		_check(GameState.has_flag(&"ch1_handoff_done") and Story.progress_snapshot().has(&"ch1_t_handoff_summary"), "fresh process restores complete handoff facts")
		await _finish()
		return
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _room("")
	Story.reset_active_presentation(&"probe_setup")
	_check(StoryItems.acquire(&"ch1_data_disk", false), "arrange disk through public custody owner; this is not a pickup playthrough")
	Progression.add_credits(237)
	_main.call("_on_area_requested", "res://data/levels/ch1_handoff.tres")
	await _room("res://data/levels/ch1_handoff.tres")
	await _frames(10)
	Story.auto_skip = false
	Story.scene_started.connect(_inject)
	StoryItems.acquired.connect(_observe_acquire)
	for pair: Array in [["ch1_t_handoff_accept", "deliver"], ["ch1_t_handoff_receipt", "take"], ["ch1_t_handoff_summary", "save"]]:
		_target = StringName(pair[0])
		_faulted = false
		var npc := _cabinet()
		_check(npc != null, "real authored cabinet exists")
		if npc == null:
			break
		(_main.get("_screen") as Level).player.global_position = npc.global_position + Vector2(-16, 0)
		await _frames(12)
		var real_player := (_main.get("_screen") as Level).player
		var ground_deadline := Time.get_ticks_msec() + 10000
		while not real_player.is_on_floor() and Time.get_ticks_msec() < ground_deadline:
			await get_tree().physics_frame
		var before_count := npc.talk_count
		var done := [false, false]
		var talk := func() -> void:
			done[1] = await npc._talk()
			done[0] = true
		talk.call()
		await _drive(pair[1], done)
		_check(_faulted, "inject actual temp obstruction after target starts: " + String(_target))
		_check(_facts() == _facts_before, "refusal preserves all wallet/item/flag/completion facts: " + String(_target))
		_check(_original == FileAccess.get_file_as_bytes(_store.path), "refusal preserves exact original primary: " + String(_target))
		_check(not done[0] and npc.talk_count == before_count, "refusal keeps original NPC waiter and talk count")
		await _shot(String(_target) + "-refused")
		if _mode == "negative":
			_check(_prompt() != null and get_tree().paused, "failed write retains an actual retryable presentation")
			DirAccess.remove_absolute(_store.path + ".tmp")
			await _finish()
			return
		var same_action := (_main.get("_screen") as Level).player._visual.interaction_action
		var action_age := same_action._age if same_action != null else 0.0
		if _target in [&"ch1_t_handoff_accept", &"ch1_t_handoff_receipt"]:
			_check(same_action != null and same_action.done and not same_action.failed, "physical action finished before refusing the write")
		var prompt := _prompt()
		_check(prompt != null and get_tree().paused, "actual retry prompt owns persistent pause")
		if _mode == "reset_write" and _target == &"ch1_t_handoff_receipt":
			var paper_id := same_action.paper_instance if same_action != null else 0
			_check(DirAccess.remove_absolute(_store.path + ".tmp") == OK, "remove only the owned obstruction before external reset")
			if prompt != null:
				_check(not prompt.cancel_button.visible, "critical result retains its original retry-only UI")
				Story.reset_active_presentation(&"native_external_reset")
			await _frames(5)
			var fixture := _fixture()
			_check(done[0] and not done[1], "externally reset pending save returns the original NPC waiter without completing it")
			_check(not StoryItems.holds(&"ch1_delivery_receipt") and not GameState.has_flag(&"ch1_disk_receipt_taken"), "externally reset pending save cannot grant the receipt")
			_check(fixture != null and fixture.paper_ready() and fixture._paper_visual.get_instance_id() == paper_id,
					"resetting after paper stow restores the exact physical strip at the outlet")
			_check(StoryItems.was_transferred(&"ch1_data_disk") and Progression.credits == 237, "earlier accepted disk and wallet remain intact")
			_check(_prompt() == null and not get_tree().paused, "external reset releases its UI and lock")
			await _shot("receipt-save-reset")
			await _finish()
			return
		if prompt != null:
			prompt.retry_button.pressed.emit()
			await _frames(3)
			_check(_facts() == _facts_before and not done[0], "second genuine save rejection has no partial result")
			if same_action != null:
				_check((_main.get("_screen") as Level).player._visual.interaction_action == same_action and same_action._age == action_age,
						"second writer refusal retains the identical completed physical action without advancing it")
		_check(DirAccess.remove_absolute(_store.path + ".tmp") == OK, "remove only owned obstruction for retry")
		prompt = _prompt()
		if prompt != null:
			prompt.retry_button.pressed.emit()
		await _drive("", done)
		if _target in [&"ch1_t_handoff_accept", &"ch1_t_handoff_receipt"]:
			_check(same_action != null and same_action.done and not same_action.failed, "writer retries do not replay the same physical action")
		_check(done[0] and done[1] and npc.talk_count == before_count + 1, "same real request succeeds and settles waiter exactly once")
		await _frames(5)
		var saved := _store.read()
		_check(saved.get("story", {}).get("seen", []).has(String(_target)), "actual disk reader sees committed completion")
		_check(JSON.parse_string(JSON.stringify(saved.get("story", {}).get("items"))) == JSON.parse_string(JSON.stringify(StoryItems.snapshot())), "fresh autosave preserves live observer custody/NEW changes")
		_check(saved.get("progression", {}).get("credits") == Progression.credits, "fresh autosave preserves live observer wallet")
		_check(_prompt() == null and not get_tree().paused, "accepted operation releases retry UI and its lock")
		_records.append({"scene": String(_target), "wallet": Progression.credits, "items": StoryItems.snapshot(), "talks": npc.talk_count})
		await _shot(String(_target) + "-accepted")
	_check(_observer_count == 2 and Progression.credits == 235, "both real paper notifications preserve ordinary spending")
	Story.scene_started.disconnect(_inject)
	StoryItems.acquired.disconnect(_observe_acquire)
	await _finish()

func _fixture() -> PropReaction:
	for node: Node in get_tree().get_nodes_in_group(PropNode.GROUP):
		var prop := node as PropNode
		if prop != null and prop.data.id == &"handoff__commission_cabinet":
			for child in prop.get_children():
				if child is PropReaction:
					return child
	return null

func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])

func _inject(id: StringName, _kind: StringName) -> void:
	if id != _target or _faulted:
		return
	_faulted = true
	_original = FileAccess.get_file_as_bytes(_store.path)
	_facts_before = _facts()
	_check(DirAccess.make_dir_absolute(_store.path + ".tmp") == OK, "create real failed-write obstruction")

func _observe_acquire(item: StoryItemData) -> void:
	if item.id in [&"ch1_delivery_receipt", &"ch1_market_summary"]:
		_observe_counter()
	if item.id not in [&"ch1_delivery_receipt", &"ch1_market_summary"]:
		return
	_observer_count += 1
	var saved := _store.read()
	_check(Story.progress_snapshot().has(_target) and saved.get("story", {}).get("seen", []).has(String(_target)), "first item observer sees live AND durable completed segment")
	_check(StoryItems.holds(item.id) and saved.get("story", {}).get("items", {}).get("held", []).has(String(item.id)), "first item observer sees full live AND durable custody")
	_check(not StoryItems.acquire(&"ch1_grey_cloth", false), "reentrant item producer is refused during publication")
	_check(Progression.apply_story_transaction(Story.outcomes.transaction(&"ch1.daily_dinner"))["status"] == "busy", "reentrant story transaction is explicitly busy")
	_check(not Story.play(&"ch1_t_label_watch", false), "reentrant new presentation is refused")
	var path: String = _main.get("_level_path")
	_main.call("_on_area_requested", "res://data/levels/ch1_stall.tres")
	_check(_main.get("_level_path") == path, "reentrant route cannot replace the publishing owners")
	StoryItems.mark_seen(item.id)
	_check(Progression.spend(1), "ordinary observer spending stays legal")

func _cabinet() -> NpcActor:
	for node: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and node.data.id == &"ch1_handoff_cabinet":
			return node
	return null

func _prompt() -> Control:
	var owner: Node = _main.get("_result_completion")
	return owner.get("_prompt") as Control if is_instance_valid(owner) else null

func _room(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		var level := _main.get("_screen") as Level
		if level != null and level.is_initialized() and (path.is_empty() or level.data.resource_path == path) and not _main.call("_route_pending"):
			return
		await _frames(1)
	_check(false, "Main room settles within time budget")

func _drive(choice: String, done: Array) -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not done[0] and _prompt() == null:
		var player: CutscenePlayer = Story._player
		if is_instance_valid(player) and player.choice_active():
			var index := player._choice_options.find_custom(func(option: Dictionary) -> bool: return str(option.get("id", "")) == choice)
			_check(index >= 0, "real cabinet offers explicit choice " + choice)
			if index < 0:
				return
			player.choose(index)
		elif is_instance_valid(player) and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		elif Story._current_cinematic != &"" and Story.scene_mode(Story._current_cinematic) != Story.MODE_ANIMATED:
			Story.skip_cinematic()
		await _frames(1)
	_check(done[0] or _prompt() != null, "real interaction completes or explicitly refuses within time budget")

func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var note := Label.new()
	note.text = "SOFTWARE FORWARD+ / ARRANGED DISK + CABINET CALL + IO FAULT / NOT A PLAYTHROUGH"
	note.position = Vector2(10, 10)
	note.add_theme_font_size_override("font_size", 12)
	canvas.add_child(note)
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
		if white >= 64:
			visible = true
			break
	_check(visible, "screenshot contains actually rendered diagnostic label: " + name)
	captured.save_png(_out.path_join(name + ".png"))
	canvas.queue_free()

func _finish() -> void:
	if _mode == "read":
		var npc := _cabinet()
		_check(npc != null and npc.talk_count == 3, "fresh process restores the original cabinet counter exactly once for all three completions")
		if npc != null:
			var primary := _primary_counter_snapshot(npc)
			for count: Variant in primary.get("counts", []):
				_check(count == 3, "fresh process keeps the same NPC counter in each raw primary world")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var file := FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"mode": _mode, "checks": _checks, "failures": Array(_failures), "operations": _records, "counter_publications": _counter_records, "engine": Engine.get_version_info().string}, "  "))
		file.close()
	await super._finish()


func _observe_transfer(item: StoryItemData) -> void:
	if item.id == &"ch1_data_disk":
		_observe_counter()


func _primary_counter_snapshot(npc: NpcActor) -> Dictionary:
	var raw := FileAccess.get_file_as_string(_store.path)
	# Decode the actual primary envelope without the reader's repair/validation.
	var decoded := RunSaveCodec.decode(raw)
	_check(not decoded.has("error"), "publication primary has a valid original checksum before any read-time repair")
	if decoded.has("error"):
		return {}
	var disk: Dictionary = decoded["data"]
	var key := npc.state_key()
	var area := String((_main.get("_screen") as Level).data.id)
	var counts: Array = []
	for world: Dictionary in [disk.get("runtime", {}).get("world", {}), disk.get("runtime", {}).get("area", {}).get("world", {}), disk.get("state", {}).get("area_states", {}).get(area, {}).get("world", {})]:
		counts.append(world.get(key, {}).get("talks", -1))
	return {"raw": raw, "counts": counts}


func _observe_counter() -> void:
	var npc := _cabinet()
	var expected: int = {&"ch1_t_handoff_accept": 1, &"ch1_t_handoff_receipt": 2, &"ch1_t_handoff_summary": 3}.get(_target, -1)
	_check(npc != null and expected > 0, "counter observer has the real publishing cabinet and authored segment")
	if npc == null or expected < 0:
		return
	_check(npc._talking and npc._durable_completed, "first result observer precedes the original waiter and sees its durable settlement")
	_check(npc.talk_count == expected, "first result observer sees the complete live NPC counter")
	var primary := _primary_counter_snapshot(npc)
	for count: Variant in primary.get("counts", []):
		_check(count == expected, "first result observer sees the same durable NPC counter in each raw primary world")
	var filename := String(_target) + "-publication-primary.json"
	if not _out.is_empty() and not primary.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var file := FileAccess.open(_out.path_join(filename), FileAccess.WRITE)
		_check(file != null, "publication primary evidence can be preserved in the isolated output directory")
		if file != null:
			file.store_string(primary["raw"])
			file.close()
	_counter_records.append({"scene": String(_target), "expected": expected, "live_count": npc.talk_count,
		"talking": npc._talking, "durable": npc._durable_completed, "world_counts": primary.get("counts", []),
		"primary_file": filename if not _out.is_empty() else ""})
