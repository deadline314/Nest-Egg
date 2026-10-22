extends RefCounted
## A label cannot silently install unrelated whole-run inventory repairs.
const LEVEL := "res://data/levels/ch1_pawnshop.tres"
const Labels := preload("res://tests/helpers/npc_terminal_save_checks.gd")

static func run(s: TestSuite, directory: String) -> void:
	var previous_auto := Story.auto_skip
	var previous_owner: Node = Story.result_completion
	Story.auto_skip = false
	var level := await s.start_level(load(LEVEL))
	Story.reset_active_presentation(&"test_setup")
	GameState.story_autosave = false
	var actor: NpcActor
	for node: Node in level._entities.get_children():
		if node is NpcActor and node.data.resource_path == "res://data/npcs/ch1_label_watch.tres":
			actor = node
			break
	s.check(actor != null and not StoryItems.holds(&"ch1_data_disk"), "repair fixture owns an unread actual label without the vault disk")
	if actor == null:
		await s.end_level(level)
		Story.auto_skip = previous_auto
		return
	var main := Labels.BoundaryMain.new()
	main._active_run = true
	main._screen = level
	main._level_path = LEVEL
	main._run_store = RunSaveStore.new(directory.path_join("npc-repair-boundary.json"))
	main._run_store.validator = RunSnapshot.prepare
	var owner := preload("res://game/story_result_completion.gd").new()
	owner.main = main
	main._result_completion = owner
	main.add_child(owner)
	s.runner.get_tree().root.add_child(main)
	s.check(main._run_store.write(RunSnapshot.capture(LEVEL, level.run_snapshot()), true), "repair fixture establishes an unchanged real original slot")
	var before := FileAccess.get_file_as_bytes(main._run_store.path)
	var items := var_to_bytes(StoryItems.snapshot())
	# Explicit malformed live state; the normal full-run reader owns its repair.
	GameState.world_flags[&"ledger_disk_obtained"] = true
	actor._talk()
	for i in 30:
		if is_instance_valid(owner._prompt) or not actor._talking:
			break
		Story._layer.advance()
		await s.frames(1)
	s.check(is_instance_valid(owner._prompt) and actor._talking, "unrelated inventory repair retains the original label waiter for recovery")
	s.check(not GameState.has_flag(&"ch1_label_watch_seen") and not Story.progress_snapshot().has(&"ch1_t_label_watch") and actor.talk_count == 0 and var_to_bytes(StoryItems.snapshot()) == items, "label completion never publishes an unrelated inventory repair or partial objective")
	s.check(before == FileAccess.get_file_as_bytes(main._run_store.path) and not StoryItems.holds(&"ch1_data_disk"), "whole-run repair cannot be silently billed into the label's durable write")
	s.check(owner._reload_original and not owner._recovery, "uncommitted whole-run repair offers loading original progress rather than retrying an impossible write")
	Story.reset_active_presentation(&"test_teardown")
	GameState.world_flags[&"ledger_disk_obtained"] = false
	main._screen = null
	main.queue_free()
	await s.frames(2)
	Story.result_completion = previous_owner if is_instance_valid(previous_owner) else null
	await s.end_level(level)
	Story.auto_skip = previous_auto
