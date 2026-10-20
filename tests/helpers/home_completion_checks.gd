extends RefCounted
## Canonical arranged pre-home facts, real Story request and durable writer.
## The separate native probe owns real Main/Level/quit/cold-process coverage.
const Gate := preload("res://game/radio_completion.gd")
const HOME := &"ch1_c14_home"
const LAST := "res://data/levels/ch1_pawnshop_dawn.tres"

class Context extends Node:
	var _active_run := true
	var _level_path := LAST
	var _chapter_complete := false
	var _screen: Level
	var _run_store: RunSaveStore
	var _cinematic := String(HOME)
	var _cinematic_entry: Dictionary
	var _cinematic_context: Dictionary = {}
	var _cinematic_request := 0
	func _route_pending(_ignore_completion := false) -> bool:
		return false
	func _queue_save() -> void:
		pass
	func _clear_cinematic() -> void:
		_cinematic = ""
		_cinematic_entry = {}
		_cinematic_context = {}
		_cinematic_request = 0

static func _watch(result: Array) -> void:
	result[0] = await Story.play_and_wait(HOME, false)
	result[1] = true

static func _facts() -> PackedByteArray:
	return var_to_bytes([GameState.world_flags, Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])

static func run(s: TestSuite) -> void:
	var original_auto := Story.auto_skip
	Story.auto_skip = true
	GameState.story_autosave = false
	var level := await s.start_level(load(LAST))
	Story.reset_active_presentation(&"test_setup")
	# Arrange prerequisites via loaded, canonical result operations, including the
	# actual market document; this is a boundary fixture, not a chapter playthrough.
	s.check(Story._apply_scene_results(&"ch1_t_handoff_summary")["ok"] and Story._apply_scene_results(&"ch1_t_supper_leave_none")["ok"], "home fixture uses canonical prerequisite results and actual item ownership")
	var context := Context.new()
	context._screen = level
	context._run_store = RunSaveStore.new("user://st9-home-completion.json")
	context._run_store.validator = RunSnapshot.prepare
	context._cinematic_entry = RunSnapshot.capture(LAST, level.run_snapshot())
	s.check(context._run_store.write(context._cinematic_entry, true), "home fixture establishes an actual old whole-run slot")
	var gate := Gate.new()
	gate.main = context
	s.runner.add_child(context)
	context.add_child(gate)
	var finished := [0]
	var on_finished := func(id: StringName) -> void:
		if id == HOME:
			finished[0] += 1
	var on_started := func(id: StringName, _mode: StringName) -> void:
		if id == HOME:
			context._cinematic_request = Story.current_presentation_request()
	Story.scene_finished.connect(on_finished)
	Story.scene_started.connect(on_started)
	var observations: Array[bool] = []
	var on_flag := func(id: StringName, _value: Variant) -> void:
		if id in [&"ch1_home_done", &"ch1_complete"]:
			var saved := context._run_store.read()
			observations.append(GameState.has_flag(&"ch1_home_done") and GameState.has_flag(&"ch1_complete") and Story.progress_snapshot().has(HOME) and bool(saved.get("story", {}).get("flags", {}).get("ch1_home_done", false)) and bool(saved.get("story", {}).get("flags", {}).get("ch1_complete", false)))
	GameState.flag_changed.connect(on_flag)
	var before := _facts()
	var primary := FileAccess.get_file_as_bytes(context._run_store.path)
	var backup := FileAccess.get_file_as_bytes(context._run_store.path + ".bak")
	s.check(DirAccess.make_dir_absolute(context._run_store.path + ".tmp") == OK, "actual owned temp-directory obstruction refuses home completion before file rotation")
	var waited := [false, false]
	_watch(waited)
	await s.frames(5)
	s.check(before == _facts() and finished[0] == 0 and not waited[1] and observations.is_empty(), "refused home completion retains flags/items/wallet/seen and never publishes or settles success")
	s.check(primary == FileAccess.get_file_as_bytes(context._run_store.path) and backup == FileAccess.get_file_as_bytes(context._run_store.path + ".bak"), "refused home completion retains exact primary and backup")
	s.check(gate._prompt != null and GameplayLock.is_locked(), "automatic home completion exposes persistent retry while held paused")
	s.check(DirAccess.remove_absolute(context._run_store.path + ".tmp") == OK, "remove only the home fixture-owned obstruction before retry")
	if gate._prompt != null:
		gate._prompt.retry_button.pressed.emit()
	await s.frames(4)
	var accepted := context._run_store.read()
	s.check(waited == [true, true] and finished[0] == 1 and accepted.get("story", {}).get("flags", {}).get("ch1_home_done") == true and accepted.get("story", {}).get("flags", {}).get("ch1_complete") == true, "same home request publishes and settles exactly once after actual durable retry")
	s.check(not observations.is_empty() and observations.all(func(value: bool) -> bool: return value), "every home flag observer sees both installed owners and durable flags")
	s.check(context._cinematic.is_empty() and gate._prompt == null and not GameplayLock.is_locked(), "home success retires the old presentation entry and only its own recovery")
	var original_scene: Dictionary = Story._scenes[String(HOME)]
	var unsupported := original_scene.duplicate(true)
	unsupported["completion_policy"] = "unsupported-policy"
	Story._scenes[String(HOME)] = unsupported
	var accepted_bytes := FileAccess.get_file_as_bytes(context._run_store.path)
	var unsupported_result: Dictionary = gate.complete(HOME, 12345)
	s.check(unsupported_result.get("handled", false) and not unsupported_result.get("ready", true) and accepted_bytes == FileAccess.get_file_as_bytes(context._run_store.path), "declared unsupported policy never falls through to legacy completion or changes disk")
	s.check(not Story.outcomes.result_contract_problem(HOME, unsupported).is_empty(), "content validation also diagnoses an unsupported completion policy")
	gate._clear()
	Story._scenes[String(HOME)] = original_scene
	GameState.flag_changed.disconnect(on_flag)
	Story.scene_finished.disconnect(on_finished)
	Story.scene_started.disconnect(on_started)
	Story.reset_active_presentation(&"test_cleanup")
	context.queue_free()
	await s.frames(2)
	await s.end_level(level)
	Story.auto_skip = original_auto
