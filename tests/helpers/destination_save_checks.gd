extends RefCounted
## Exercise the real Main route methods and real filesystem writer. Only the
## final level loader is observed, so a refused route cannot silently disappear.

const FIRST := "res://data/levels/ch1_pawnshop.tres"
const TARGET := "res://data/levels/ch1_rooftop.tres"

class RouteMain extends "res://game/main.gd":
	var loaded: Array[String] = []
	func _ready() -> void:
		pass
	func _load_level(_kind := Transition.Kind.IRIS, _caption := "", _hold := 0.0) -> void:
		loaded.append(_level_path)


class CaptureLevel extends Level:
	var captures := 0
	func run_snapshot() -> Dictionary:
		captures += 1
		return super.run_snapshot()


static func _owners() -> PackedByteArray:
	return var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])


static func run(s: TestSuite) -> void:
	var previous_auto := Story.auto_skip
	Story.auto_skip = true
	GameState.story_autosave = false
	var directory := "user://ne230-destination-refusal"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for kind: String in ["area", "retry_persistent", "retry_nonpersistent", "chapter"]:
		for refuse: bool in [true, false]:
			var source := "res://data/levels/level_01.tres" if kind == "retry_nonpersistent" else FIRST
			var level := await s.start_level(load(source))
			Story.reset_active_presentation(&"test_setup")
			GameState.story_autosave = false
			Progression.add_credits(100)
			GameState.set_checkpoint(level.player.global_position, level.player.checkpoint_snapshot(), {}, Progression.snapshot())
			GameState.checkpoint_level_path = TARGET
			Progression.add_credits(400)
			GameState.carried_health = 3
			GameState.carry_over(level.player.checkpoint_snapshot())
			Story.reset_active_presentation(&"test_setup")
			var main := RouteMain.new()
			main._screen = level
			main._active_run = true
			main._level_path = source
			main._chapter_complete = kind == "chapter"
			main._run_store = RunSaveStore.new(directory.path_join("%s-%s.json" % [kind, "refuse" if refuse else "success"]))
			main._run_store.validator = RunSnapshot.prepare
			var baseline := RunSnapshot.capture(source, level.run_snapshot())
			s.check(main._run_store.write(baseline, true), "destination fixture establishes a real source slot: " + kind)
			var primary := FileAccess.get_file_as_bytes(main._run_store.path)
			var backup := FileAccess.get_file_as_bytes(main._run_store.path + ".bak")
			var before := _owners()
			var before_chapter := main._chapter_complete
			if refuse:
				s.check(DirAccess.make_dir_absolute(main._run_store.path + ".tmp") == OK, "an actual owned directory blocks destination file creation: " + kind)
			match kind:
				"area":
					GameState.pending_portal = &"roof_prev"
					main._on_area_requested(TARGET)
				"retry_persistent", "retry_nonpersistent":
					main._on_retry_requested(level)
				"chapter":
					main._enter_next_level(load(TARGET), level.run_snapshot())
			if refuse:
				s.check(main.loaded.is_empty(), "IO refusal never calls the destination loader: " + kind)
				s.check(main._level_path == source and not main._destination_pending and main._chapter_complete == before_chapter, "IO refusal retains routing and chapter metadata: " + kind)
				s.check(before == _owners(), "IO refusal retains checkpoint, carried loadout, wallet, items and story: " + kind)
				s.check(FileAccess.get_file_as_bytes(main._run_store.path) == primary and FileAccess.get_file_as_bytes(main._run_store.path + ".bak") == backup, "IO refusal retains exact primary and backup: " + kind)
				s.check(DirAccess.remove_absolute(main._run_store.path + ".tmp") == OK, "remove only the fixture-owned blocking directory: " + kind)
			else:
				s.check(main.loaded == [TARGET] and main._destination_pending, "successful destination save permits exactly one load: " + kind)
				var saved := main._run_store.read()
				s.check(saved.get("level") == TARGET and RunSaveCodec.vector(saved.get("runtime", {}).get("position")) == Vector2(-1, -1), "actual reader sees the correct destination entry: " + kind)
				if kind == "retry_nonpersistent":
					s.check(Progression.credits == 100 and saved.get("progression", {}).get("credits") == 100, "nonpersistent retry restores the intended checkpoint wallet only after save")
				if kind == "chapter":
					s.check(not GameState.has_checkpoint and not main._chapter_complete and saved.get("state", {}).get("has_checkpoint") == false, "chapter handoff clears its checkpoint in both saved and live state")
			main._screen = null
			main.free()
			await s.end_level(level)
	await _test_invalid_portal(s, directory)
	await _test_dialogue_checkpoint(s)
	await _test_dialogue_frame_save(s, directory)
	Story.auto_skip = previous_auto

static func _test_invalid_portal(s: TestSuite, directory: String) -> void:
	var level := await s.start_level(load(FIRST))
	Story.reset_active_presentation(&"test_setup")
	var main := RouteMain.new()
	main._screen = level
	main._active_run = true
	main._level_path = FIRST
	main._run_store = RunSaveStore.new(directory.path_join("bad-portal-source.json"))
	main._run_store.validator = RunSnapshot.prepare
	var save := RunSnapshot.capture(FIRST, level.run_snapshot())
	s.check(main._run_store.write(save, true), "portal rejection fixture has a durable source slot")
	var bytes := FileAccess.get_file_as_bytes(main._run_store.path)
	var portal := Portal.new()
	var definition := PortalData.new()
	definition.id = &"test_area_bad_destination"
	definition.target_level = directory.path_join("test_area_bad_destination.tres")
	definition.target_portal = &"another_area"
	definition.locked_text = "這條路暫時無法通行。"
	portal.data = definition
	s.check(ResourceSaver.save(WeaponData.new(), definition.target_level) == OK,
			"test destination exists but is not a campaign level")
	GameState.pending_portal = &"previous_portal"
	GameState.carried_health = 3
	var before := var_to_bytes([GameState.pending_portal, GameState.carried_health, GameState.checkpoint_loadout])
	var prior_controls := [level._pause_menu.allowed, level._inventory.allowed]
	var requests: Array[String] = []
	var toasts: Array[String] = []
	var collect_toast := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(collect_toast)
	level.area_requested.connect(func(path: String) -> void:
		requests.append(path)
		main._on_area_requested(path))
	level._on_portal_used(portal)
	EventBus.toast_requested.disconnect(collect_toast)
	s.check(requests == [definition.target_level] and main.loaded.is_empty(), "invalid destination is refused by the route before loading another level")
	s.check(not level._finished and prior_controls == [level._pause_menu.allowed, level._inventory.allowed],
			"refusing the destination restores the controls in the live area")
	s.check(var_to_bytes([GameState.pending_portal, GameState.carried_health, GameState.checkpoint_loadout]) == before,
			"refusing the destination restores the source portal and carried state")
	s.check(FileAccess.get_file_as_bytes(main._run_store.path) == bytes and toasts.has(definition.locked_text),
			"refusing the destination preserves the source save and reports the actual portal hint")
	portal.free()
	main._screen = null
	main.free()
	await s.end_level(level)

static func _test_dialogue_checkpoint(s: TestSuite) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := CaptureLevel.new()
	level.configure(load(FIRST) as LevelData)
	s.runner.get_tree().root.add_child(level)
	await s.frames(3)
	Story.reset_active_presentation(&"test_setup")
	var main := RouteMain.new()
	main._screen = level
	main._active_run = true
	main._level_path = FIRST
	main._cinematic = "ch1_t_oldk_1"
	main._cinematic_entry = RunSnapshot.capture(FIRST, level.run_snapshot())
	var position: Array = main._cinematic_entry["runtime"]["position"].duplicate()
	level.player.teleport_to(level.player.global_position + Vector2(32, 0))
	var checkpoint := main._snapshot_for_save()
	s.check(level.captures == 1 and checkpoint.get("cinematic") == main._cinematic
			and checkpoint.get("runtime", {}).get("position") == position,
			"dialogue checkpoint saves the captured entry without recapturing the live world")
	if not checkpoint.is_empty():
		checkpoint["runtime"]["position"][0] += 5.0
	s.check(main._cinematic_entry["runtime"]["position"] == position, "writing a dialogue checkpoint cannot mutate the stored entry")
	main._clear_cinematic()
	var current := main._snapshot_for_save()
	s.check(level.captures == 2 and current.get("runtime", {}).get("position") != position,
			"outside an active dialogue the save still captures the current world")
	main._screen = null
	main.free()
	await s.end_level(level)

static func _test_dialogue_frame_save(s: TestSuite, directory: String) -> void:
	const SCENE := &"ch1_t_oldk_1"
	var level := await s.start_level(load(FIRST))
	Story.reset_active_presentation(&"test_setup")
	var main := RouteMain.new()
	main._screen = level
	main._active_run = true
	main._level_path = FIRST
	main._run_store = RunSaveStore.new(directory.path_join("dialogue-frame-save.json"))
	main._run_store.validator = main._prepare_run_snapshot
	var tree := s.runner.get_tree()
	tree.root.add_child(main)
	var navigation := QuestMapState.for_run()
	const EARLIER_AREA := "res://data/levels/ch2_harbor_street.tres"
	var earlier := load(EARLIER_AREA) as LevelData
	var earlier_map := LevelBuilder.parse(earlier)
	s.check(not earlier_map.checkpoints.is_empty(), "the earlier area has an authored checkpoint")
	navigation.reveal(EARLIER_AREA, [Vector2i(1, 1)])
	for point: Vector2 in earlier_map.checkpoints:
		navigation.activate(EARLIER_AREA, point, earlier.tile_size)
	var catalog := navigation.catalog_copy()
	var pinned: String = catalog.quests[0]["id"]
	navigation.pin(pinned, catalog)
	s.check(not pinned.is_empty() and navigation.pinned_id == pinned,
			"dialogue regression starts with an authored pinned mission")
	s.check(main._run_store.write(main._snapshot_for_save(), true), "dialogue regression establishes the source slot")
	var original := FileAccess.get_file_as_bytes(main._run_store.path)
	var lock_token := GameplayLock.acquire(main, Input.MOUSE_MODE_VISIBLE)

	main._on_scene_started(SCENE, Story.MODE_CINEMATIC)
	await _process_frames(tree, 1)
	s.check(FileAccess.get_file_as_bytes(main._run_store.path) == original,
			"opening dialogue leaves the installed save intact during its first frame")
	await _process_frames(tree, 6)
	var opened := main._run_store.read()
	s.check(opened.get("cinematic") == String(SCENE), "locked dialogue reaches the real installed save in frames")
	var installed := FileAccess.get_file_as_bytes(main._run_store.path)
	main._queue_movement_autosave()
	await _process_frames(tree, 6)
	s.check(FileAccess.get_file_as_bytes(main._run_store.path) == installed and not main._save_queued,
			"routine discovery during a dialogue does not rewrite its checkpoint")

	GameState.run_time += 4.0
	var actual_clock := GameState.run_time
	navigation.reveal(EARLIER_AREA, [Vector2i(2, 1)])
	navigation.pin("", catalog)
	main._on_presentation_cancelled(SCENE, {}, &"leave", 0)
	GameplayLock.release(lock_token)
	s.check(QuestMapState.for_run().pinned_id == pinned
			and QuestMapState.for_run().knows(EARLIER_AREA, Vector2i(1, 1))
			and not QuestMapState.for_run().knows(EARLIER_AREA, Vector2i(2, 1))
			and QuestMapState.for_run().activated == opened.get("navigation", {}).get("activated")
			and QuestMapState.for_run().snapshot().get("layout_revisions", {}).get(EARLIER_AREA) == 2,
			"cancelling restores the entry's pin, explored cells and activated checkpoints across areas")
	s.check(GameState.run_time >= actual_clock and not Story.was_seen(SCENE),
			"cancellation keeps elapsed gameplay and does not complete the dialogue")
	s.check(FileAccess.get_file_as_bytes(main._run_store.path) == installed,
			"cancellation returns before publishing the rollback save")
	await _process_frames(tree, 6)
	var closed := main._run_store.read()
	s.check(closed.get("cinematic") == "" and closed.get("navigation", {}).get("pinned_id") == pinned,
			"the resumable slot loses the cancelled dialogue and keeps its restored pin")

	main._on_scene_started(SCENE, Story.MODE_CINEMATIC)
	await _process_frames(tree, 2)
	main._on_presentation_cancelled(SCENE, {}, &"leave", 0)
	main._save_run()  # Same authoritative save path used by quit.
	await _process_frames(tree, 6)
	s.check(main._run_store.read().get("cinematic") == "", "a pending open draft cannot replace a synchronous close save")

	var previous_skip := Story.auto_skip
	Story.auto_skip = false
	GameState.run_save_requested.connect(main._on_story_save_requested)
	Story.scene_started.connect(main._on_scene_started)
	Story.scene_finished.connect(main._on_scene_finished)
	Story.play(SCENE, false)
	await _process_frames(tree, 6)
	var before_close := FileAccess.get_file_as_bytes(main._run_store.path)
	s.check(Story.is_cinematic_active(), "the authored dialogue stays locked until the player dismisses it")
	Story.skip_cinematic()  # DialogueLayer uses the same completion from Escape.
	s.check(not main._save_queued and FileAccess.get_file_as_bytes(main._run_store.path) == before_close,
			"the story completion signal and Main share a staged dialogue save")
	await _process_frames(tree, 6)
	var completed := main._run_store.read()
	s.check(completed.get("cinematic") == "" and String(SCENE) in completed.get("story", {}).get("seen", []),
			"the staged completion stores the seen scene and retires the playback checkpoint")
	Story.auto_skip = previous_skip
	main._screen = null
	main.queue_free()
	await s.end_level(level)


static func _process_frames(tree: SceneTree, count: int) -> void:
	for frame in count:
		await tree.process_frame
