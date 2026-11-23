extends RefCounted
## 第一個還原通知必須看到完整的故事、物品、世界與死亡事實。

const FIRST := "res://data/levels/ch1_pawnshop.tres"
const DISK := &"ch1_data_disk"


static func run_sliced_entry(s: TestSuite, directory: String) -> void:
	var old_instant := Transition.instant
	var old_skip := Story.auto_skip
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	Progression.restore({"credits": 731})
	var store := RunSaveStore.new(directory.path_join("sliced_entry.json"))
	store.validator = RunSnapshot.prepare
	var saved := RunSnapshot.capture(FIRST, {"health": 4, "position": [100, 160]})
	if not store.write(saved, true):
		s.check(false, "sliced entry fixture writes a valid slot")
		Story.auto_skip = old_skip
		return
	var main: Node = load("res://game/main.gd").new()
	main.set("_run_store", store)
	s.runner.get_tree().root.add_child(main)
	Transition.instant = false
	var publication: Array[bool] = []
	var observe := func(credits: int, _delta: int) -> void:
		var level := main.get("_screen") as Level
		publication.append(credits == 731 and level != null and level.is_initialized()
				and is_instance_valid(level.player) and GameplayLock.is_locked())
	Progression.credits_changed.connect(observe)
	var cover_seen := [false]
	var first_validation: Array[bool] = []
	var on_cover := func() -> void: cover_seen[0] = true
	Transition.covered.connect(on_cover)
	store.validator = func(raw: Dictionary) -> Dictionary:
		if first_validation.is_empty():
			first_validation.append(cover_seen[0] and GameplayLock.is_locked())
		return RunSnapshot.prepare(raw)
	var slot_digest := FileAccess.get_sha256(store.path)
	main.call("_on_continue_requested")
	var inspected := false
	var elapsed := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < elapsed and Transition.is_active():
		await s.runner.get_tree().process_frame
		var level := main.get("_screen") as Level
		if not inspected and level != null and level.is_building_entry():
			inspected = true
			s.check(not level.is_initialized() and publication.is_empty() and GameplayLock.is_locked(),
					"covered entry yields with input locked and no partially published save state")
			main.call("_save_run")
			main.call("_on_continue_requested")
			s.check(FileAccess.get_sha256(store.path) == slot_digest, "partial entry cannot write or reopen the current slot")
	s.check(inspected and publication == [true], "only the complete player and world are published during a sliced resume")
	s.check(first_validation == [true], "continue covers the screen before reading and validating the saved run")
	Transition.covered.disconnect(on_cover)
	var loaded := main.get("_screen") as Level
	s.check(loaded != null and loaded.is_initialized() and loaded.data.resource_path == FIRST
			and not Transition.is_active(), "sliced resume reveals the exact target area")
	Progression.credits_changed.disconnect(observe)
	Transition.abort()
	Transition.instant = old_instant
	Story.reset_active_presentation(&"sliced_entry_test")
	Story.auto_skip = old_skip
	main.queue_free()
	await s.frames(3)
	GameState.start_new_run(GameState.difficulties[1])


static func run(s: TestSuite) -> void:
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	Progression.restore({"credits": 731})
	StoryItems.acquire(DISK, false)
	StoryItems.transfer(DISK)
	GameState.world_flags["restore_observer_marker"] = "saved"
	GameState.area_state(&"restore_test")["consumed"]["disk@4,5"] = true
	GameState.deaths = 2
	GameState.run_time = 83.5
	var saved := RunSnapshot.capture(FIRST, {"health": 4, "position": [100, 160], "world": {}, "loadout": {}})
	GameState.start_new_run(GameState.difficulties[1])
	Progression.restore({"credits": 9})
	GameState.world_flags["restore_observer_marker"] = "live"
	var seen: Array[Dictionary] = []
	var on_credits := func(value: int, _delta: int) -> void:
		seen.append({"value": value, "marker": GameState.world_flags.get("restore_observer_marker"),
			"held": StoryItems.holds(DISK), "transferred": StoryItems.was_transferred(DISK),
			"consumed": GameState.area_states.get("restore_test", {}).get("consumed", {}).get("disk@4,5", false),
			"deaths": GameState.deaths, "time": GameState.run_time, "lives": GameState.lives_left})
	Progression.credits_changed.connect(on_credits)
	RunSnapshot.apply(saved)
	s.check(seen.size() == 1, "whole restore publishes one wallet snapshot without a temporary new-run reset")
	if seen.size() == 1:
		var first: Dictionary = seen[0]
		s.check(first["value"] == 731 and first["marker"] == "saved" and not first["held"] and first["transferred"] and first["consumed"], "first wallet observer sees restored story, transferred custody and world together")
		s.check(first["deaths"] == 2 and first["time"] == 83.5, "first wallet observer sees saved deaths and clock")
	seen.clear()
	GameState.deaths = 7
	GameState.lives_left = 3
	GameState.run_time = 127.5
	GameState.kills = 11
	GameState.finishers = 4
	GameState.last_death_clock = "12 點 03 分"
	GameState.world_flags["restore_observer_marker"] = "tentative"
	RunSnapshot.rollback_presentation(saved)
	s.check(seen.size() == 1, "presentation rollback publishes only the complete restored snapshot")
	if seen.size() == 1:
		s.check(seen[0]["deaths"] == 7 and seen[0]["lives"] == 3 and seen[0]["time"] == 127.5, "rollback observer retains actual deaths, lives and elapsed time")
		s.check(seen[0]["marker"] == "saved" and seen[0]["transferred"] and seen[0]["consumed"], "rollback observer sees restored custody and world before publication")
	s.check(GameState.kills == 11 and GameState.finishers == 4 and GameState.last_death_clock == "12 點 03 分", "rollback retains actual combat and death facts")
	seen.clear()
	RunSnapshot.apply(saved, false)
	s.check(seen.is_empty() and Progression.credits == 731 and StoryItems.was_transferred(DISK), "Main can finish route metadata before restore publication")
	RunSnapshot.publish_restored()
	s.check(seen.size() == 1, "explicit publication after Main metadata emits once")
	Progression.credits_changed.disconnect(on_credits)
	# 取消通知先看到舊的完整局，不是新旗標配舊錢包。
	var cancelled: Array[Dictionary] = []
	var scene := StringName(Story._scenes.keys()[0])
	Story._current_cinematic = scene
	Story._current_request = 9801
	GameState.world_flags["restore_observer_marker"] = "old"
	var on_cancel := func(_id: StringName, _context: Dictionary, _reason: StringName, _request: int) -> void:
		cancelled.append({"marker": GameState.world_flags.get("restore_observer_marker"), "credits": Progression.credits})
	Story.presentation_cancelled.connect(on_cancel)
	GameState.restore_story_progress(saved["story"])
	s.check(cancelled.size() == 1 and cancelled[0]["marker"] == "old" and cancelled[0]["credits"] == 731, "standalone story restore cancels the old presentation before replacing flags")
	Story.presentation_cancelled.disconnect(on_cancel)
	GameState.start_new_run(GameState.difficulties[1])

static func run_deferred_writes(s: TestSuite, directory: String) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var store := RunSaveStore.new(directory.path_join("deferred_write.json"))
	store.validator = RunSnapshot.prepare
	var baseline := RunSnapshot.capture(FIRST, {"health": 4, "position": [100, 160]})
	baseline["progression"]["credits"] = 401
	s.check(store.write(baseline, true), "deferred write fixture establishes a valid primary")
	var unchanged := FileAccess.get_sha256(store.path)
	var statuses: Array[RunSaveStore.WriteStatus] = []
	var draft := baseline.duplicate(true)
	draft["progression"]["credits"] = 402
	_record_deferred(store, draft, s.runner.get_tree(), statuses)
	draft["progression"]["credits"] = 999
	s.check(await _wait_draft(s, store) and FileAccess.get_sha256(store.path) == unchanged,
			"a staged autosave leaves the previous primary untouched until verified")
	await _wait_deferred_status(s, statuses)
	s.check(statuses == [RunSaveStore.WriteStatus.SAVED] and store.read()["progression"]["credits"] == 402
			and FileAccess.get_sha256(store.path + ".bak") == unchanged,
			"the staged bytes are immutable and complete backup rotation happens only after validation")
	statuses.clear()
	draft["progression"]["credits"] = 403
	_record_deferred(store, draft, s.runner.get_tree(), statuses)
	s.check(await _wait_draft(s, store), "a competing autosave has reached temporary storage")
	var pending := store.get("_deferred_draft") as String
	draft["progression"]["credits"] = 404
	s.check(store.write(draft), "a synchronous critical save can commit during a staged autosave")
	await _wait_deferred_status(s, statuses)
	s.check(statuses == [RunSaveStore.WriteStatus.CANCELLED] and not FileAccess.file_exists(pending)
			and store.read()["progression"]["credits"] == 404,
			"a canceled autosave cannot overwrite the critical save or retain its temporary file")
	statuses.clear()
	var live := [true]
	draft["progression"]["credits"] = 405
	_record_deferred(store, draft, s.runner.get_tree(), statuses, func() -> bool: return live[0])
	s.check(await _wait_draft(s, store), "an abandoned route has a staged autosave to cancel")
	pending = store.get("_deferred_draft") as String
	live[0] = false
	await _wait_deferred_status(s, statuses)
	s.check(statuses == [RunSaveStore.WriteStatus.CANCELLED] and not FileAccess.file_exists(pending)
			and store.read()["progression"]["credits"] == 404,
			"a changed live route cancels publication without changing the previous primary")
	statuses.clear()
	draft["progression"]["credits"] = 406
	_record_deferred(store, draft, s.runner.get_tree(), statuses)
	s.check(await _wait_draft(s, store), "an ordinary draft can coexist with preparation of a durable story result")
	draft["progression"]["credits"] = 407
	var prepared := store.prepare_existing_write(draft)
	s.check(prepared.has("data"), "the established story writer prepares against the active primary")
	if prepared.has("data"):
		s.check(store.commit_existing_write(prepared["data"]).committed, "the durable result commits with its existing atomic writer")
	await _wait_deferred_status(s, statuses)
	s.check(statuses == [RunSaveStore.WriteStatus.CANCELLED] and store.read()["progression"]["credits"] == 407,
			"an ordinary draft cannot overwrite a later durable story result")
	GameState.start_new_run(GameState.difficulties[1])


static func _record_deferred(store: RunSaveStore, draft: Dictionary, tree: SceneTree,
		statuses: Array[RunSaveStore.WriteStatus], allowed := Callable()) -> void:
	var status: RunSaveStore.WriteStatus = await store.write_in_frames(draft, tree, allowed)
	statuses.append(status)


static func _wait_draft(s: TestSuite, store: RunSaveStore) -> bool:
	for frame in 8:
		var pending: String = store.get("_deferred_draft")
		if not pending.is_empty() and FileAccess.file_exists(pending):
			return true
		await s.runner.get_tree().process_frame
	return false


static func _wait_deferred_status(s: TestSuite, statuses: Array[RunSaveStore.WriteStatus]) -> void:
	for frame in 12:
		if not statuses.is_empty():
			return
		await s.runner.get_tree().process_frame
