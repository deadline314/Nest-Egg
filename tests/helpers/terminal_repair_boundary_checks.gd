extends RefCounted
## Actual terminal writer and a real reader request; native separately runs its authored chain.
const PAWN := "res://data/levels/ch1_pawnshop.tres"
const FOOD := &"ch1_b_dinner_food"
const Labels := preload("res://tests/helpers/npc_terminal_save_checks.gd")

static func run(s: TestSuite, directory: String) -> void:
	var previous_auto := Story.auto_skip
	var previous_owner: Node = Story.result_completion
	Story.auto_skip = false
	var level := await s.start_level(load(PAWN))
	Story.reset_active_presentation(&"test_setup")
	GameState.story_autosave = false
	s.check(not GameState.has_flag(&"ch1_dinner_done") and not Story.progress_snapshot().has(FOOD) and not StoryItems.holds(&"ch1_data_disk"), "nonNPC repair fixture has neither dinner result nor unrelated disk")
	var main := Labels.BoundaryMain.new()
	main._active_run = true
	main._screen = level
	main._level_path = PAWN
	main._run_store = RunSaveStore.new(directory.path_join("food-repair-owner.json"))
	main._run_store.validator = RunSnapshot.prepare
	var gate := preload("res://game/story_result_completion.gd").new()
	gate.main = main
	main._result_completion = gate
	main.add_child(gate)
	s.runner.get_tree().root.add_child(main)
	s.check(main._run_store.write(RunSnapshot.capture(PAWN, level.run_snapshot()), true), "nonNPC repair fixture writes an actual unchanged original slot")
	var original := FileAccess.get_file_as_bytes(main._run_store.path)
	GameState.world_flags[&"ledger_disk_obtained"] = true # Unrelated malformed owner only.
	s.check(Story.play(FOOD, false), "actual nonNPC food reader starts from its loaded authored scene")
	var requests: Array = Story._passive_requests.get(FOOD, [])
	s.check(not requests.is_empty(), "real passive reader owns the terminal request")
	if not requests.is_empty():
		gate._id = FOOD
		gate._request = int(requests[0])
		var invalid_live := var_to_bytes([GameState._install_source(), Story._install_source(), StoryItems.snapshot(), Progression.snapshot()])
		var refused: Dictionary = gate._prepare_and_commit(Story._scenes[String(FOOD)])
		s.check(not refused.get("committed", false) and refused.has("error"), "nonNPC terminal refuses unrelated whole-run item repair")
		s.check(refused.get("reload_original", false), "uncommitted nonNPC repair requests original progress instead of an impossible retry")
		s.check(original == FileAccess.get_file_as_bytes(main._run_store.path) and invalid_live == var_to_bytes([GameState._install_source(), Story._install_source(), StoryItems.snapshot(), Progression.snapshot()]), "nonNPC repair refusal preserves exact disk and every live owner")
	Story.reset_active_presentation(&"test_teardown")
	GameState.world_flags[&"ledger_disk_obtained"] = false
	main._screen = null
	main.queue_free()
	await s.frames(2)
	Story.result_completion = previous_owner if is_instance_valid(previous_owner) else null
	await s.end_level(level)
	Story.auto_skip = previous_auto
