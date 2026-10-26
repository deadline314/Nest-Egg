extends "res://tools/run_save_probe.gd"
## Exact real handoff primary; actual authored Ali source and original UI decisions.
const ROOM := "res://data/levels/ch1_lounge.tres"
const NAME := &"ch1_t_ali_name"
const ORDERED := &"ch1_t_ali_2_ordered"
const SIT := &"ch1_t_ali_2_sit"
const CLOSE := &"ch1_t_ali_evening_close"
var store: RunSaveStore
var target: StringName
var out := ""
var original := PackedByteArray()
var facts_before := PackedByteArray()
var before_count := -1
var faulted := false
var skip_sent := false
var ordered := false

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	super._ready()

func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = false
	ordered = "ordered" in _mode
	target = NAME if _mode == "name" else CLOSE if _mode.begins_with("close") else ORDERED if ordered else SIT
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(5)
	var seed := FileAccess.get_file_as_bytes("res://tests/fixtures/ali_handoff_seed.json")
	_check(not seed.is_empty() and RunSaveCodec.decode(seed.get_string_from_utf8()).has("data"), "original produced handoff seed is checksum-valid without re-encoding")
	FileAccess.open(store.path, FileAccess.WRITE).store_buffer(seed)
	_main.call("_on_continue_requested")
	await _until(func() -> bool: return _main.get("_screen") is Level and not _main.call("_route_pending"))
	_check(GameState.has_flag(&"ch1_handoff_done") and not GameState.has_flag(&"ch1_met_ali") and not GameState.has_flag(&"ch1_ali_evening_talk_done") and not GameState.has_flag(&"ch1_lounge_evening_done"), "actual source progress has handoff but no injected Ali completion")
	_main.call("_on_area_requested", ROOM)
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	await _frames(8)
	var actor := _actor()
	_check(actor != null and actor.is_present() and actor.talk_count == 0, "actual authored lounge Ali exists with no completed encounter")
	if actor == null:
		await _finish()
		return
	(_main.get("_screen") as Level).player.global_position = actor.global_position + Vector2(-48, 0)
	await _frames(6)
	Story.scene_started.connect(_inject)
	actor._talk()
	await _drive()
	_check(faulted, "original source and choices reach the selected exact authored boundary")
	if not faulted:
		await _finish()
		return
	await _frames(5)
	_check(_facts() == facts_before, "actual write refusal cannot publish flags, history, items, wallet or receipts")
	_check(FileAccess.get_file_as_bytes(store.path) == original, "actual write refusal preserves exact original primary bytes")
	_check(actor.talk_count == before_count and actor._talking, "actual write refusal retains original NPC waiter and its previous count")
	_check(Story._current_cinematic == target, "actual write refusal retains the exact unaccepted segment")
	_check(_prompt() != null and get_tree().paused, "actual write refusal offers the real persistent retry modal")
	await _shot()
	_check(DirAccess.remove_absolute(store.path + ".tmp") == OK, "remove only the owned obstruction")
	await _finish()

func _inject(id: StringName, _kind: StringName) -> void:
	if id != target or faulted:
		return
	faulted = true
	original = FileAccess.get_file_as_bytes(store.path)
	facts_before = _facts()
	before_count = _actor().talk_count
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "create real filesystem temp-directory refusal at the authored boundary")

func _drive() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	var started_evening := false
	while Time.get_ticks_msec() < deadline:
		if faulted and (_prompt() != null or (skip_sent and Story._current_cinematic != target)):
			return
		var player: CutscenePlayer = Story._player if is_instance_valid(Story._player) else null
		if faulted and not skip_sent and is_instance_valid(player) and player.is_running():
			skip_sent = true
			Story.skip_cinematic()
		elif is_instance_valid(player) and player.choice_active():
			var wanted := "order" if ordered else "sit"
			if Story._current_cinematic == &"ch1_hub_ali_lounge":
				wanted = "evening"
			var index := player._choice_options.find_custom(func(option: Dictionary) -> bool: return option.get("id") == wanted)
			_check(index >= 0 and player.choose(index), "actual authored menu accepts " + wanted)
		elif is_instance_valid(player) and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		elif Story._layer.is_cinematic_active():
			Story._layer.advance()
		if not faulted and not _actor()._talking and GameState.has_flag(&"ch1_met_ali") and not started_evening:
			_check(_actor().talk_count == 1, "first genuine original meeting settles once before starting the evening encounter")
			_check(Progression.credits == 235, "original reception does not charge the unpaid 200 order")
			started_evening = true
			_actor()._talk()
		await _frames(1)
	_check(false, "authored encounter reaches its refused boundary within bounded time")

func _actor() -> NpcActor:
	for node: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and node.data.id == &"ch1_ali_lounge" and (_main.get("_screen") as Level).is_ancestor_of(node):
			return node
	return null

func _prompt() -> Control:
	return (_main.get("_result_completion") as Node).get("_prompt") as Control

func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Story.progress_snapshot(), StoryItems.snapshot(), Progression.snapshot()])

func _until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(predicate.call(), "actual Main room settles within bounded time")

func _shot() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var label := Label.new()
	label.text = "SOFTWARE FORWARD+ / ORIGINAL HANDOFF PRIMARY + REAL ALI SOURCE + IO FAULT"
	label.position = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 12)
	canvas.add_child(label)
	await _frames(10)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out.path_join("refused.png"))
	canvas.queue_free()

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":Array(_failures),"target":String(target),"before_count":before_count},"  "))
	print("[AliCompletionBoundary] %s checks=%d failures=%d" % [_mode,_checks,_failures.size()])
	_main.call("_quit", 0 if _failures.is_empty() else 1)
