extends "res://tools/run_save_probe.gd"
## Arranged already-heard recording; original Main, headset NPC, UI and filesystem.
const ROOM := "res://data/levels/ch1_booth_alley.tres"
const FIRST_PROMPT := &"ch1_t_lamp_voice_prompt"
const FIRST := &"ch1_t_lamp_voice_first"
const SECOND_PROMPT := &"ch1_t_lamp_voice_second_prompt"
const SECOND := &"ch1_t_lamp_voice_second"
const LATER := &"ch1_t_lamp_voice_later"
var out := ""
var store: RunSaveStore
var original := PackedByteArray()
var before := PackedByteArray()
var target: StringName
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out = arg.trim_prefix("--out=")
	super._ready()
func _run() -> void:
	CampaignEdition.override_current(CampaignEdition.current().describe("through-ch1_kasa"))
	Transition.instant = true
	Story.auto_skip = true
	_main = MainScript.new()
	store = RunSaveStore.new(_directory.path_join("slot.json"))
	_main.set("_run_store", store)
	add_child(_main)
	await _frames(5)
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _until(func() -> bool: return _main.get("_screen") is Level and not _main.call("_route_pending"))
	Story.reset_active_presentation(&"probe_setup")
	# Explicit preexisting prerequisite; never inject any voice acceptance/result.
	GameState.set_flag(&"ch1_recording_heard")
	Progression.add_credits(123)
	_main.call("_on_area_requested", ROOM)
	await _until(func() -> bool: return _main.get("_level_path") == ROOM and _main.get("_screen") is Level and (_main.get("_screen") as Level).is_initialized() and not _main.call("_route_pending"))
	Story.auto_skip = false
	var actor := _actor()
	_check(actor != null and actor.is_present() and actor.talk_count == 0, "real authored headset source is present with no settled voice result")
	if actor == null:
		await _finish()
		return
	(_main.get("_screen") as Level).player.global_position = actor.global_position + Vector2(-20, 0)
	await _frames(8)
	actor._talk()
	await _choice(FIRST_PROMPT)
	if _mode == "ask":
		target = FIRST_PROMPT
	else:
		_check(_select("ask"), "actual first ask is accepted without an IO obstruction")
		await _until(func() -> bool: return Story._current_cinematic == FIRST)
		await _frames(4)
		target = FIRST
		if _mode != "first":
			Story.skip_cinematic()
			await _choice(SECOND_PROMPT)
			_check(GameState.has_flag(&"ch1_lamp_voice_asked") and not GameState.has_flag(&"sq5_lamp_voice_noticed") and actor._talking and actor.talk_count == 0, "first reading reaches second question without completing the entire conversation")
			target = SECOND_PROMPT
			if _mode in ["second", "later"]:
				_check(_select("ask" if _mode == "second" else "later"), "actual second decision is accepted without obstruction")
				target = SECOND if _mode == "second" else LATER
				await _until(func() -> bool: return Story._current_cinematic == target)
				await _frames(4)
	await _frames(3)
	original = FileAccess.get_file_as_bytes(store.path)
	before = _facts()
	_check(DirAccess.make_dir_absolute(store.path + ".tmp") == OK, "actual temp-directory obstruction refuses this boundary write")
	if _mode in ["ask", "second_choice"]:
		_check(not _select("ask"), "failed choice write cannot consume the current question")
	else:
		Story.skip_cinematic()
	await _frames(5)
	_check(_facts() == before, "refusal publishes no partial flag, history, custody or wallet result")
	_check(FileAccess.get_file_as_bytes(store.path) == original, "refusal preserves the exact original primary bytes")
	_check(Story._current_cinematic == target and actor._talking and actor.talk_count == 0, "refusal retains the actual source request without settling the NPC")
	var owner: Node = _main.get("_result_completion")
	_check(is_instance_valid(owner.get("_prompt")) and get_tree().paused, "refusal has an actual persistent retry modal and pause")
	if _mode in ["ask", "second_choice"]:
		_check(is_instance_valid(Story._player) and Story._player.choice_active(), "same unanswered choice remains available behind its recovery UI")
	await _shot()
	DirAccess.remove_absolute(store.path + ".tmp")
	await _finish()
func _actor() -> NpcActor:
	for node: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and node.data.id == &"ch1_lamp_voice" and (_main.get("_screen") as Level).is_ancestor_of(node):return node
	return null
func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Story.progress_snapshot(), StoryItems.snapshot(), Progression.snapshot()])
func _until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not predicate.call() and Time.get_ticks_msec() < deadline:await _frames(1)
	_check(predicate.call(), "actual authored boundary is reached within a bounded wait")
func _choice(id: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var player := Story._player as CutscenePlayer
		if Story._current_cinematic == id and is_instance_valid(player) and player.choice_active():
			_check(true, "real authored question appears: " + String(id))
			return
		if is_instance_valid(player) and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		await _frames(1)
	_check(false, "expected actual question appears: " + String(id))
func _select(id: String) -> bool:
	var player := Story._player as CutscenePlayer
	if not is_instance_valid(player) or not player.choice_active():return false
	var index := player._choice_options.find_custom(func(option: Dictionary) -> bool: return option.get("id") == id)
	return index >= 0 and player.choose(index)
func _shot() -> void:
	if DisplayServer.get_name() == "headless":return
	DirAccess.make_dir_recursive_absolute(out)
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var label := Label.new()
	label.text = "SOFTWARE FORWARD+ / ARRANGED HEARD RECORDING + REAL HEADSET NPC + IO FAULT"
	label.position = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 12)
	canvas.add_child(label)
	await _frames(10)
	await RenderingServer.frame_post_draw
	preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out.path_join("refused.png"))
	canvas.queue_free()
func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"mode":_mode,"checks":_checks,"failures":Array(_failures),"target":String(target)},"  "))
	await super._finish()
