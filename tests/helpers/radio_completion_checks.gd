extends RefCounted
## Owner regressions complement the separate real-Main fault/retry/cold-process probe.
const Gate := preload("res://game/radio_completion.gd")
const FIRST := "res://data/levels/ch1_pawnshop.tres"
const SCENE := &"ch1_t_booth_recording"

class Context extends Node:
	var _level_path := FIRST
	var _chapter_complete := false
	var _run_store: RunSaveStore

class FaultStore extends RunSaveStore:
	var reject := false
	var mutate := false
	var reject_rollback := false
	func _durable_rename(absolute: String, phase: DurablePhase) -> Error:
		if reject and phase == DurablePhase.PRIMARY_COMMITTED:
			return ERR_CANT_CREATE
		return super._durable_rename(absolute, phase)
	func _durable_rollback(absolute: String) -> Error:
		return ERR_CANT_CREATE if reject_rollback else super._durable_rollback(absolute)
	func _durable_phase(phase: DurablePhase, _absolute: String) -> void:
		if mutate and phase == DurablePhase.PRIMARY_COMMITTED:
			GameState.set_flag(&"ch1_street_route_open", true, false)


static func run(s: TestSuite) -> void:
	GameState.story_autosave = false
	var level := await s.start_level(load(FIRST))
	Story.reset_active_presentation(&"test")
	var context := Context.new()
	context._run_store = FaultStore.new("user://ne246-completion/slot.json")
	var store := context._run_store as FaultStore
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ne246-completion"))
	var gate := Gate.new()
	gate.main = context
	var snapshot := RunSnapshot.capture(FIRST, level.run_snapshot())
	var fresh := FaultStore.new("user://ne246-completion/first-save.json")
	DirAccess.make_dir_absolute(fresh.path + ".tmp")
	s.check(not fresh.write(snapshot, true) and fresh.overwrite_authorized, "actual first-save IO refusal retains the user's existing new-run authorization")
	context._run_store = fresh
	var opening := &"ch1_g06_tip_slide"
	var first_refused := gate._commit(opening, Story._scenes[String(opening)], level)
	s.check(not first_refused.get("committed", false) and not Story.progress_snapshot().has(opening), "first-slot retry keeps the radio unfinished while actual IO is still refused")
	DirAccess.remove_absolute(fresh.path + ".tmp")
	var first_committed := gate._commit(opening, Story._scenes[String(opening)], level)
	s.check(first_committed.get("committed", false) and not fresh.overwrite_authorized, "first-slot retry completes the authorized baseline before durable radio completion")
	s.check(fresh.read().get("story", {}).get("seen", []).has(String(opening)), "actual reader sees the first-slot radio only after successful commit")
	context._run_store = store
	s.check(store.write(snapshot, true), "radio owner fixture writes through the actual whole-run store")
	var old := FileAccess.get_file_as_bytes(store.path)
	var live := var_to_bytes([GameState._install_source(), Story._install_source(), Progression.snapshot(), StoryItems.snapshot()])
	store.reject = true
	var refused := gate._commit(SCENE, Story._scenes[String(SCENE)], level)
	s.check(not refused.get("committed", false), "radio refuses a real pre-commit rename failure")
	s.check(FileAccess.get_file_as_bytes(store.path) == old, "radio refusal keeps exact previous primary bytes")
	s.check(live == var_to_bytes([GameState._install_source(), Story._install_source(), Progression.snapshot(), StoryItems.snapshot()]), "radio refusal leaves all four owners unchanged")
	var areas := GameState.area_states
	var nav := QuestMapState.for_run()
	var nav_bytes := var_to_bytes(nav.snapshot())
	var wallet := Progression.snapshot()
	var items := StoryItems.snapshot()
	store.reject = false
	var committed := gate._commit(SCENE, Story._scenes[String(SCENE)], level)
	s.check(committed.get("committed", false) and not committed.get("recovery", false), "radio retry commits and silently installs a prepared result")
	s.check(GameState.has_flag(&"ch1_recording_heard") and Story.progress_snapshot().has(SCENE), "radio installs flags and completed history together")
	s.check(committed.get("changed", []).has("ch1_recording_heard"), "radio prepares flag notifications only for changed values")
	s.check(is_same(areas, GameState.area_states) and is_same(nav, QuestMapState.for_run()) and var_to_bytes(nav.snapshot()) == nav_bytes, "radio preserves actual area and navigation identities and exploration")
	s.check(Progression.snapshot() == wallet and StoryItems.snapshot() == items, "flag-only completion never replaces money or item owners")
	var saved := store.read()
	s.check(saved["story"]["flags"]["ch1_recording_heard"] and saved["story"]["seen"].has(String(SCENE)), "fresh actual reader sees the same completed facts")
	var unsafe: Dictionary = Story._scenes[String(SCENE)].duplicate(true)
	unsafe["set_flags"] = ["undeclared_radio_flag"]
	old = FileAccess.get_file_as_bytes(store.path)
	s.check(not gate._commit(SCENE, unsafe, level).get("committed", false) and FileAccess.get_file_as_bytes(store.path) == old, "undeclared result is refused before disk mutation")
	var original_flags := GameState.world_flags.duplicate(true)
	GameState.set_flag(&"ledger_disk_obtained", true, false)  # Explicit inconsistent legacy fixture; no disk granted.
	old = FileAccess.get_file_as_bytes(store.path)
	var invalid_live := var_to_bytes([GameState._install_source(), Story._install_source(), StoryItems.snapshot(), Progression.snapshot()])
	var repair_refused := gate._commit(SCENE, Story._scenes[String(SCENE)], level)
	s.check(not repair_refused.get("committed", false), "flag-only radio refuses a candidate requiring an unowned item repair")
	s.check(repair_refused.get("reload_original", false), "uncommitted radio repair offers original progress instead of an impossible retry")
	s.check(FileAccess.get_file_as_bytes(store.path) == old and invalid_live == var_to_bytes([GameState._install_source(), Story._install_source(), StoryItems.snapshot(), Progression.snapshot()]), "unowned repair refusal leaves exact disk and all live owners unchanged")
	GameState.world_flags = original_flags
	store.mutate = true
	var recovery := gate._commit(SCENE, Story._scenes[String(SCENE)], level)
	s.check(recovery.get("committed", false) and recovery.get("recovery", false), "post-commit source change preserves durable fact and demands reload")
	store.mutate = false
	var broken := FaultStore.new("user://ne246-completion/rollback.json")
	s.check(broken.write(RunSnapshot.capture(FIRST, level.run_snapshot()), true), "rollback fixture has a real complete primary")
	var original := FileAccess.get_file_as_bytes(broken.path)
	context._run_store = broken
	broken.reject = true
	broken.reject_rollback = true
	var rolled_back := gate._commit(&"ch1_g06_tip_collector", Story._scenes["ch1_g06_tip_collector"], level)
	s.check(not rolled_back.get("committed", false) and rolled_back.get("reload_original", false), "failed commit plus failed rollback requests original-save recovery, never committed recovery")
	s.check(FileAccess.get_file_as_bytes(broken.path + ".bak") == original and not Story.progress_snapshot().has(&"ch1_g06_tip_collector"), "rollback failure retains exact old backup without marking the new radio complete")
	broken.reject_rollback = false
	gate.free()
	context.free()
	await s.end_level(level)
