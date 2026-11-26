extends RefCounted
## Real authored label actors and real writer; the native probe separately uses
## the complete Main menu/route and public input across independent processes.
const LEVEL := "res://data/levels/ch1_pawnshop.tres"
const WATCH_ALTERNATE := "ch1_t_label_watch_revisit"
const OTHER_NPC := "ch1_t_egret_1"


class SourceStore extends RunSaveStore:
	var after_prepare := Callable()

	func prepare_existing_write(raw: Variant, level: Level = null) -> Dictionary:
		var prepared := super.prepare_existing_write(raw, level)
		if prepared.has("data") and after_prepare.is_valid():
			var change := after_prepare
			after_prepare = Callable()
			change.call()
		return prepared


class BoundaryMain extends "res://game/main.gd":
	func _ready() -> void:
		pass

static func run(s: TestSuite, directory: String) -> void:
	var previous_auto := Story.auto_skip
	var previous_owner: Node = Story.result_completion
	Story.auto_skip = false
	var level := await s.start_level(load(LEVEL))
	Story.reset_active_presentation(&"test_setup")
	GameState.story_autosave = false
	var main := BoundaryMain.new()
	main._active_run = true
	main._screen = level
	main._level_path = LEVEL
	var store := SourceStore.new(directory.path_join("npc-terminal.json"))
	store.validator = RunSnapshot.prepare
	main._run_store = store
	var owner := preload("res://game/story_result_completion.gd").new()
	owner.main = main
	main._result_completion = owner
	main.add_child(owner)
	s.runner.get_tree().root.add_child(main)
	for name: String in ["watch", "guitar", "raincoat", "fare"]:
		var id := StringName("ch1_t_label_" + name)
		var flag := StringName("ch1_label_" + name + "_seen")
		var actor: NpcActor
		for node: Node in level._entities.get_children():
			if node is NpcActor and node.data.resource_path == "res://data/npcs/ch1_label_%s.tres" % name:
				actor = node
				break
		s.check(actor != null and not GameState.has_flag(flag), "durable label uses its actual unread authored source: " + name)
		if actor == null:
			continue
		s.check(actor.can_resume_presentation(id, 0), "unread authored dispatcher admits its exact saved terminal segment: " + name)
		s.check(not actor.can_resume_presentation(&"ch1_t_egret_1", 0), "a different authored producer cannot resume this NPC: " + name)
		s.check(main._run_store.write(RunSnapshot.capture(LEVEL, level.run_snapshot()), true), "durable label establishes old whole-run bytes: " + name)
		var before := FileAccess.get_file_as_bytes(main._run_store.path)
		var wallet := Progression.credits
		var observed := {}
		var listener := func(changed: StringName, _value: Variant) -> void:
			if changed != flag:
				return
			var disk := RunSaveCodec.decode(FileAccess.get_file_as_string(main._run_store.path))
			observed["consistent"] = disk.has("data") and disk["data"]["story"]["flags"][String(flag)] and disk["data"]["story"]["seen"].has(String(id)) and actor.talk_count == 1 and level._area["world"][actor.state_key()]["talks"] == 1
			Progression.add_credits(7) # Legitimate observer change must survive fresh capture.
		GameState.flag_changed.connect(listener)
		s.check(DirAccess.make_dir_absolute(main._run_store.path + ".tmp") == OK, "real temp directory refuses label save: " + name)
		actor._talk()
		for i in 30:
			if is_instance_valid(owner._prompt):
				break
			Story._layer.advance()
			await s.frames(1)
		s.check(is_instance_valid(owner._prompt) and owner.blocks_save() and actor._talking, "refused label retains original waiter and retry: " + name)
		s.check(not GameState.has_flag(flag) and not Story.progress_snapshot().has(id) and actor.talk_count == 0 and observed.is_empty(), "refused label publishes no flag, reading, count or observer: " + name)
		s.check(before == FileAccess.get_file_as_bytes(main._run_store.path) and level._area["world"][actor.state_key()]["talks"] == 0, "refused candidate leaves original disk and shared live world intact: " + name)
		s.check(DirAccess.remove_absolute(main._run_store.path + ".tmp") == OK, "remove only owned label obstruction: " + name)
		if not is_instance_valid(owner._prompt):
			GameState.flag_changed.disconnect(listener)
			continue
		if name == "watch":
			await _retry_watch_with_source_changes(s, store, owner, actor, before)
		else:
			owner._retry()
			await s.frames(3)
		s.check(observed.get("consistent", false) and actor.talk_count == 1 and not actor._talking, "durable label installs all facts before observers and settles once: " + name)
		s.check(not actor.can_resume_presentation(id, 0), "completed dispatcher cannot resume its already-settled terminal result: " + name)
		var reader := RunSaveStore.new(main._run_store.path)
		reader.validator = RunSnapshot.prepare
		var saved := reader.read()
		var key := actor.state_key()
		s.check(saved.get("story", {}).get("flags", {}).get(String(flag), false) and saved["story"]["seen"].has(String(id)), "new reader sees the actual completed label: " + name)
		s.check(saved["runtime"]["world"][key]["talks"] == 1 and saved["runtime"]["area"]["world"][key]["talks"] == 1 and saved["state"]["area_states"]["ch1_pawnshop"]["world"][key]["talks"] == 1, "every durable world view contains one settled NPC: " + name)
		s.check(saved["progression"]["credits"] == wallet + 7 and Progression.credits == wallet + 7, "fresh follow-up preserves legitimate completion-observer spending/rewards: " + name)
		GameState.flag_changed.disconnect(listener)
	main._screen = null
	main.queue_free()
	await s.frames(2)
	Story.result_completion = previous_owner if is_instance_valid(previous_owner) else null
	await s.end_level(level)
	Story.auto_skip = previous_auto


## The real first waiter's alternate stays ineligible while both retries run.
## Its source is still relevant, while the unrelated NPC's body is disjoint.
static func _retry_watch_with_source_changes(s: TestSuite, store: SourceStore, owner: Node, actor: NpcActor, original_slot: PackedByteArray) -> void:
	var previous: Dictionary = Story._scenes[WATCH_ALTERNATE]
	var alternate := previous.duplicate(true)
	var condition := {"flag": "ch1_label_watch_seen", "equals": true}
	for depth: int in 12:
		condition = {"all" if depth % 2 == 0 else "any": [condition]}
	s.check(StoryConditionTree.validate(condition, Story.outcomes.transactions).get("valid", false), "watch retry fixture uses legal authored condition depth")
	alternate["when"] = condition
	Story._scenes[WATCH_ALTERNATE] = alternate
	var original_source: String = Story._scene_sources[WATCH_ALTERNATE]
	store.after_prepare = func() -> void:
		Story._scene_sources[WATCH_ALTERNATE] = "res://data/story/changed_during_label_save.json"
	owner._retry()
	await s.frames(3)
	s.check(not store.after_prepare.is_valid() and is_instance_valid(owner._prompt) and actor._talking and actor.talk_count == 0
		and FileAccess.get_file_as_bytes(store.path) == original_slot, "inactive dispatcher source change retains the same unsettled waiter and old primary")
	Story._scene_sources[WATCH_ALTERNATE] = original_source

	var other: Dictionary = Story._scenes[OTHER_NPC]
	store.after_prepare = func() -> void:
		var changed := other.duplicate(true)
		changed["scope_fixture"] = true
		Story._scenes[OTHER_NPC] = changed
	owner._retry()
	await s.frames(3)
	s.check(not store.after_prepare.is_valid() and not is_instance_valid(owner._prompt) and actor.talk_count == 1,
		"deep alternate and disjoint authored edit allow the real watcher to settle once")
	Story._scenes[OTHER_NPC] = other
	Story._scenes[WATCH_ALTERNATE] = previous
