extends RefCounted
## Real authored label actors and real writer; the native probe separately uses
## the complete Main menu/route and public input across independent processes.
const LEVEL := "res://data/levels/ch1_pawnshop.tres"
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
	main._run_store = RunSaveStore.new(directory.path_join("npc-terminal.json"))
	main._run_store.validator = RunSnapshot.prepare
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
