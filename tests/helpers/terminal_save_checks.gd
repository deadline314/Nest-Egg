extends RefCounted
## The edition's real terminal Level and writer; only final Victory presentation
## is observed. A refused write must not claim durable completion.
const LAST := "res://data/levels/ch1_pawnshop_dawn.tres"

class TerminalMain extends "res://game/main.gd":
	var victories: Array[StringName] = []
	func _ready() -> void:
		pass
	func _show_victory(chapter: StringName) -> void:
		victories.append(chapter)

static func run(s: TestSuite) -> void:
	var original_edition := CampaignEdition.current()
	var original_auto := Story.auto_skip
	Story.auto_skip = true
	CampaignEdition.override_current(original_edition.describe("through-ch1_kasa"))
	var level := await s.start_level(load(LAST))
	Story.reset_active_presentation(&"test_setup")
	GameState.story_autosave = false
	Progression.add_credits(37)
	var main := TerminalMain.new()
	main._screen = level
	main._active_run = true
	main._level_path = LAST
	main._run_store = RunSaveStore.new("user://ne230-terminal-refusal.json")
	main._run_store.validator = RunSnapshot.prepare
	s.check(main._next_level(level.data) == null and CampaignEdition.current().is_last_chapter(level.data.chapter), "actual cumulative edition ends at the authored chapter boundary")
	s.check(main._run_store.write(RunSnapshot.capture(LAST, level.run_snapshot()), true), "terminal fixture establishes an actual uncompleted source slot")
	var primary := FileAccess.get_file_as_bytes(main._run_store.path)
	var backup := FileAccess.get_file_as_bytes(main._run_store.path + ".bak")
	var owners := var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()])
	s.check(DirAccess.make_dir_absolute(main._run_store.path + ".tmp") == OK, "owned directory blocks the actual terminal writer")
	main._on_level_completed(level.data)
	s.check(main.victories.is_empty() and not main._chapter_complete, "refused terminal save never shows saved Victory or commits live completion")
	s.check(owners == var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot(), Story.progress_snapshot()]), "refused terminal save retains all data owners")
	s.check(primary == FileAccess.get_file_as_bytes(main._run_store.path) and backup == FileAccess.get_file_as_bytes(main._run_store.path + ".bak"), "refused terminal save retains exact primary and backup bytes")
	s.check(DirAccess.remove_absolute(main._run_store.path + ".tmp") == OK, "remove only the terminal fixture's obstruction")
	main._on_level_completed(level.data)
	s.check(main.victories == [level.data.chapter] and main._chapter_complete, "same terminal operation shows Victory exactly once after a successful write")
	var reader := RunSaveStore.new(main._run_store.path)
	reader.validator = RunSnapshot.prepare
	var saved := reader.read()
	s.check(saved.get("chapter_complete") == true and saved.get("level") == LAST and saved.get("progression", {}).get("credits") == Progression.credits, "fresh reader sees the complete accepted ending with the same wallet")
	main._screen = null
	main.free()
	await s.end_level(level)
	CampaignEdition.override_current(original_edition)
	Story.auto_skip = original_auto
