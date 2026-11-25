extends "res://tools/ch4_factory_probe.gd"
## Exercises archive branches through Main using an isolated, previously saved office run.
## write: --archive-branch=index (default) or direct; continue: ward or replay.
## The fixture starts with the original ledger saved and Ahan's Chapter 3 tape held.

const ARCHIVE_OFFICE := "res://data/levels/ch4_factory_office.tres"
const ARCHIVE_STATION := &"ch4_archive_recorder"
const BEDSIDE := &"ch4_voice_demo"
const INDEX_DOCUMENT := &"ch4_archive_31_index"
const TRANSCRIPT := &"ch4_archive_31_recording"
const INDEXED := &"ch4_archive_31_indexed"
const HEARD := &"ch4_archive_31_heard"
const AHAN := &"ch3_ahan_tape"
const OFFICE_PLAY := &"ch4_t_archive_play_office"
const WARD_PLAY := &"ch4_t_archive_play_ward"

var _archive_branch := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archive-branch="):
			_archive_branch = arg.trim_prefix("--archive-branch=")
	super._ready()


func _write() -> void:
	if not await _resume_to(ARCHIVE_OFFICE):
		return
	_check(GameState.has_flag(&"ch4_original_ledger_saved") and StoryItems.holds(AHAN),
			"the prior office save starts with the old ledger and separate Ahan tape")
	_check(not GameState.has_flag(INDEXED) and not StoryItems.owns(TRANSCRIPT),
			"a pre-archive save installs no completion for the new content")
	if _archive_branch == "direct":
		if DisplayServer.get_name() != "headless":
			await _frame_office_recorder()
			_shots[String(OFFICE_PLAY)] = "archive-31"
		await _talk(ARCHIVE_STATION, ["play"])
		_check(_played.has(String(OFFICE_PLAY)), "direct playback starts at the office recorder")
		_check_complete(false)
		return
	await _talk(ARCHIVE_STATION, ["leave"])
	_check(not StoryItems.owns(INDEX_DOCUMENT) and not GameState.has_flag(HEARD),
			"leaving the recorder publishes neither inventory item nor result")
	await _cancel_play(ARCHIVE_STATION, OFFICE_PLAY)
	_check(not StoryItems.owns(INDEX_DOCUMENT) and not StoryItems.owns(TRANSCRIPT)
			and not GameState.has_flag(INDEXED) and not GameState.has_flag(HEARD),
			"skipping the first subtitle publishes neither archive result")
	await _talk(ARCHIVE_STATION, ["index"])
	_check_index_only()
	var save := (_main.get("_run_store") as RunSaveStore).read()
	_check(save.get("story", {}).get("flags", {}).get(String(INDEXED)) == true,
			"index-only progress is already in the primary slot")


func _continue() -> void:
	if _archive_branch == "replay":
		if not await _resume_to(WARD):
			return
		_check_complete()
		await _talk(BEDSIDE, ["demo"])
		_check(_played.has("ch4_t_voice_demo_replay"), "the original bedside demonstration remains available")
		var before := StoryItems.snapshot()
		await _talk(BEDSIDE, ["replay"])
		_check(_played.has("ch4_t_archive_replay") and StoryItems.snapshot() == before,
				"replaying the archive never grants the same transcript twice")
		return
	if not await _resume_to(ARCHIVE_OFFICE):
		return
	_check_index_only()
	if _archive_branch == "office-after-index":
		await _talk(ARCHIVE_STATION, ["play"])
		_check_complete()
		return
	if not await _return_to_ward():
		return
	await _cancel_play(BEDSIDE, WARD_PLAY)
	_check_index_only()
	await _talk(BEDSIDE, ["play"])
	_check(_played.has(String(WARD_PLAY)), "the ward radio performs its own first playback")
	_check_complete()
	var save := (_main.get("_run_store") as RunSaveStore).read()
	_check(save.get("level") == WARD and save.get("story", {}).get("flags", {}).get(String(HEARD)) == true,
			"the ward result is published at the current destination")


func _resume_to(path: String) -> bool:
	var saved := await _route_main.continue_game()
	_level = _route_main.level()
	var arrived: bool = saved.get("level") == path and is_instance_valid(_level)
	_check(arrived, "cold load returns to " + path.get_file())
	return arrived and await _wait_for_route_input()


func _return_to_ward() -> bool:
	var route: Array = [
		[&"office_arena", "factory_cleaning"], [&"arena_work", "factory_work"], [&"work_safety", "factory_safety"],
	]
	if GameState.has_flag(&"ch4_safety_shortcut_open"):
		route.append([&"safety_service", "factory_loading"])
	else:
		route.append_array([[&"safety_relay", "factory_relay"], [&"relay_loading", "factory_loading"]])
	route.append_array([
		[&"loading_approach", "factory_approach"], [&"approach_lounge", "revival_lounge"],
		[&"lounge_reception", "ward_reception"], [&"reception_ward", "nursing_ward"],
	])
	for step: Array in route:
		if not await _portal(step[0], level_pattern % step[1]):
			return false
	return true


func _cancel_play(source: StringName, scene: StringName) -> void:
	var station := _object(source)
	_check(station != null and station.is_present(), "the selected playback station belongs to the current level")
	if station == null:
		return
	_level.player.global_position = station.global_position + Vector2(-22, 0)
	await _settle(12)
	var done := [false]
	var talk := func() -> void:
		await station._talk()
		done[0] = true
	talk.call()
	await _drive(["play"], func() -> bool: return done[0] or Story._current_cinematic == scene)
	var caption_ready := false
	for i in 120:
		var player: CutscenePlayer = Story._player
		caption_ready = Story._current_cinematic == scene and is_instance_valid(player) \
				and player.steps_run == 1 and player._dialogue.visible
		if caption_ready or done[0]:
			break
		await get_tree().physics_frame
	_check(caption_ready, "cancel starts after the playback cue and first subtitle")
	Story.skip_cinematic()
	await _drive([], func() -> bool: return done[0])
	_check(done[0], "the aborted playback releases the station for another interaction")


func _check_index_only() -> void:
	_check(GameState.has_flag(INDEXED) and StoryItems.holds(INDEX_DOCUMENT)
			and not GameState.has_flag(HEARD) and not StoryItems.owns(TRANSCRIPT) and StoryItems.holds(AHAN),
			"index-only progress preserves the separate borrowed tape without granting the transcript")


func _check_complete(index_card := true) -> void:
	var item := StoryItems.find(TRANSCRIPT)
	_check(GameState.has_flag(INDEXED) and GameState.has_flag(HEARD) and StoryItems.holds(INDEX_DOCUMENT) == index_card
			and StoryItems.holds(TRANSCRIPT) and StoryItems.holds(AHAN) and item != null
			and not item.is_collectible() and not item.body_text().is_empty(),
			"the completed transcript and prior borrowed tape are independent inventory entries")


func _frame_office_recorder() -> void:
	var station := _object(ARCHIVE_STATION)
	if station == null:
		return
	var camera := Camera2D.new()
	camera.position = station.position + Vector2(-84, -80)
	camera.zoom = Vector2(1.55, 1.55)
	_level.add_child(camera)
	camera.make_current()
	await get_tree().process_frame


func _capture(name: String) -> void:
	var player: CutscenePlayer = Story._player
	if name != "archive-31" or DisplayServer.get_name() == "headless" or not is_instance_valid(player):
		return
	_check(player._dialogue.visible, "the real archive subtitle is on-screen")
	if not player._dialogue.visible:
		return
	player._dialogue.complete()
	await RenderingServer.frame_post_draw
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(image.save_jpg(_out_dir.path_join(name + ".jpg"), 0.9) == OK, "captured the subtitled playback")
