extends RefCounted
## Actual failed Level -> Main publication/save/menu paths, with an isolated disk slot.

const LEVEL := "res://data/levels/ch1_street.tres"
const DESTINATION := "res://data/levels/ch1_vault.tres"
const ZONE := &"ch1_enc_street_plaza"


# Fault injection affects only the actual lookup inside production restoration.
# A synthetic boss boundary exercises pending-boss scheduling on the same failure.
class MissingMemberLevel:
	extends Level

	var missing_key := ""
	var reject_dynamic := false
	var restoring := false
	var boss_attempts: Array[int] = [0]

	func _restore_run_entities() -> bool:
		restoring = true
		_tracked.erase(missing_key)
		_layout.arena_x = 16.0
		return super._restore_run_entities()

	func _create_enemy(enemy_data: EnemyData) -> Enemy:
		if restoring and reject_dynamic:
			return null  # Real dynamic creation failure, after pure identity validation succeeds.
		return super._create_enemy(enemy_data)

	func _resume_pending_boss() -> void:
		boss_attempts[0] += 1
		await super._resume_pending_boss()

	func resume_directly() -> void:
		await super._resume_pending_boss()


# Main's production swap/save/menu methods run unchanged; transition timing and
# startup are controlled so the failed scene stays inspectable before menu entry.
class RoutingMain:
	extends "res://game/main.gd"

	func _ready() -> void:
		pass

	func _switch_to(screen: Node, _kind := Transition.Kind.FADE, _center := Vector2(0.5, 0.5),
			_caption := "", _hold := 0.0) -> void:
		_pending_screen = screen

	func finish_menu() -> void:
		_swap_screen(_pending_screen)


static func run(s: TestSuite) -> void:
	var previous_skip := Story.auto_skip
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	var data := load(LEVEL) as LevelData
	var source := Level.new()
	source.configure(data)
	source.set_physics_process(false)
	s.runner.get_tree().root.add_child(source)
	_freeze(source)
	await s.frames(2)
	var zone: EncounterZone = null
	for node in source._entities.get_children():
		if node is EncounterZone and node.data.id == ZONE:
			zone = node
	s.check(source.is_initialized() and zone != null, "guard fixture fully initializes the real authored street level")
	if zone == null:
		await s.end_level(source)
		Story.auto_skip = previous_skip
		return
	zone.begin()
	# An actual untracked enemy outside membership must also survive strict restore.
	var dynamic := source._spawn_reinforcement(load("res://data/enemies/sweeper.tres") as EnemyData, source.player.position + Vector2(48, 0))
	s.check(dynamic != null, "guard capture contains a real dynamic non-member enemy")
	_freeze(source)
	var captured := source.run_snapshot()
	var prepared := RunSnapshot.prepare(RunSnapshot.capture(LEVEL, captured))
	s.check(prepared.has("data"), "restore guard starts from an actual valid Level capture")
	if not prepared.has("data"):
		await s.end_level(source)
		Story.auto_skip = previous_skip
		return
	var valid: Dictionary = prepared["data"]
	var actual_members: Array = captured["encounters"][zone.state_key()]["members"]
	s.check(not actual_members.is_empty(), "guard capture retains living authored encounter membership")
	if actual_members.is_empty():
		await s.end_level(source)
		Story.auto_skip = previous_skip
		return
	var member_id: String = actual_members[0]
	var member_key := ""
	for enemy: Dictionary in captured["enemies"]:
		if enemy["snapshot_id"] == member_id:
			member_key = enemy["key"]
	s.check(member_key != "", "failure fixture targets a real authored encounter member")
	await s.end_level(source)
	for failure_kind in 3:
		await _failed_restore(s, data, valid, member_key, failure_kind)
	await _destination(s, valid)
	Story.auto_skip = previous_skip


static func _freeze(arena: Level) -> void:
	if is_instance_valid(arena.player):
		arena.player.set_physics_process(false)
	if is_instance_valid(arena._entities):
		for node in arena._entities.get_children():
			if node is Enemy:
				node.set_physics_process(false)


static func _failed_restore(s: TestSuite, data: LevelData, valid: Dictionary, member_key: String, failure_kind: int) -> void:
	var scenario: String = ["consumed_false_key", "missing_live_member", "dynamic_factory_failure"][failure_kind]
	var late_failure := failure_kind > 0
	var store := RunSaveStore.new("user://ne245-restore-guard/%s.json" % scenario)
	store.validator = RunSnapshot.prepare
	s.check(store.write(valid, true), "guard %s writes the valid original disk slot" % scenario)
	var original := FileAccess.get_file_as_string(store.path)
	RunSnapshot.apply(valid, false)
	var runtime: Dictionary = valid["runtime"].duplicate(true)
	var attempts: Array[int] = [0]
	var failed: Level
	if late_failure:
		var missing := MissingMemberLevel.new()
		missing.missing_key = member_key if failure_kind == 1 else ""
		missing.reject_dynamic = failure_kind == 2
		missing.boss_attempts = attempts
		failed = missing
		runtime["arena"] = true
		runtime["boss_pending"] = true
	else:
		runtime["area"]["consumed"][member_key] = false
		var corrupt := valid.duplicate(true)
		corrupt["runtime"] = runtime
		var rejected := RunSnapshot.prepare(corrupt)
		s.check(rejected.has("error") and rejected["error"].contains("/key"),
			"consumed key presence, including false, rejects a conflicting live authored identity before install")
		failed = Level.new()
	failed.configure(data)
	failed.configure_resume(runtime)
	var main := RoutingMain.new()
	main.set("_run_store", store)
	main.set("_level_path", LEVEL)
	main.set("_active_run", true)
	main.set("_restore_publish_pending", true)
	failed.menu_requested.connect(main._show_main_menu, CONNECT_DEFERRED)
	s.runner.get_tree().root.add_child(main)
	var published: Array[int] = [0]
	var observer := func(_lives: int) -> void: published[0] += 1
	EventBus.lives_changed.connect(observer)
	main._swap_screen(failed)
	_freeze(failed)
	s.check(not failed.is_initialized() and failed.run_snapshot().is_empty(),
		"failed %s Level refuses capture before complete initialization" % scenario)
	s.check(published[0] == 0 and not main.get("_restore_publish_pending"),
		"Main cannot publish restored state from failed %s initialization" % scenario)
	# This call runs while the run is still active, before the deferred menu callback.
	main._save_run()
	s.check(FileAccess.get_file_as_string(store.path) == original,
		"Main's existing empty-runtime rejection preserves original %s disk bytes" % scenario)
	if late_failure:
		await (failed as MissingMemberLevel).resume_directly()
	await s.frames(4)
	s.check(attempts[0] == 0, "failed restore neither schedules nor starts the pending boss")
	s.check(published[0] == 0 and not main.get("_active_run") and main.get("_pending_screen") is MainMenu,
		"failed %s restore reaches the real Main menu route without publishing" % scenario)
	s.check(FileAccess.get_file_as_string(store.path) == original and not store.read().is_empty(),
		"deferred menu save and reads retain a loadable original %s disk slot" % scenario)
	EventBus.lives_changed.disconnect(observer)
	main.finish_menu()
	await s.frames(2)
	s.check(main.get("_screen") is MainMenu, "failure route installs an actual main menu screen")
	s.runner.get_tree().root.remove_child(main)
	main.free()
	await s.frames(2)


static func _destination(s: TestSuite, valid: Dictionary) -> void:
	RunSnapshot.apply(valid, false)
	var store := RunSaveStore.new("user://ne245-restore-guard/destination.json")
	store.validator = RunSnapshot.prepare
	s.check(store.write(valid, true), "new-area regression starts with a valid isolated disk slot")
	var main := RoutingMain.new()
	main.set("_run_store", store)
	main.set("_level_path", DESTINATION)
	var entry: Dictionary = valid["runtime"].duplicate(true)
	entry["position"] = [-1, -1]
	var saved := main._save_destination(entry)
	var destination := store.read()
	s.check(saved and not destination.is_empty(), "Main saves a new-area entry with the current membership marker")
	if not destination.is_empty():
		s.check(destination["runtime"].has("encounter_members_version") and destination["runtime"]["enemies"].is_empty()
				and destination["runtime"]["encounters"].is_empty(), "empty destination membership is valid new-format data")
		var arena := Level.new()
		RunSnapshot.apply(destination, false)
		arena.configure(load(DESTINATION) as LevelData)
		arena.configure_resume(destination["runtime"])
		arena.set_physics_process(false)
		s.runner.get_tree().root.add_child(arena)
		_freeze(arena)
		s.check(arena.is_initialized() and not arena.run_snapshot().is_empty(),
			"a new-area empty runtime still creates and captures the full authored Level")
		await s.end_level(arena)
	main.free()
