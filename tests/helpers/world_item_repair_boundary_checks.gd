extends RefCounted
## Contract-only writer unit; separate native probe uses actual sensor and buttons.
const VAULT := "res://data/levels/ch1_vault.tres"
class Context extends Node:
	var _level_path := VAULT
	var _chapter_complete := false
	var _run_store: RunSaveStore

static func run(s: TestSuite, directory: String) -> void:
	var previous_auto := Story.auto_skip
	Story.auto_skip = true
	var level := await s.start_level(load(VAULT))
	Story.reset_active_presentation(&"test_setup")
	GameState.story_autosave = false
	var pickup: CollectiblePickup
	var key := ""
	for source_key: String in level._tracked:
		var node: Variant = level._tracked[source_key]
		if node is CollectiblePickup and node.item.id == &"ch1_data_disk":
			pickup = node
			key = source_key
	s.check(pickup != null and not key.is_empty() and not StoryItems.owns(&"ch1_data_disk") and not GameState.has_flag(&"ledger_disk_obtained"), "whole-run repair fixture retains a real unacquired authored pickup")
	if pickup == null:
		await s.end_level(level)
		Story.auto_skip = previous_auto
		return
	var context := Context.new()
	context._run_store = RunSaveStore.new(directory.path_join("world-repair-owner.json"))
	context._run_store.validator = RunSnapshot.prepare
	var gate := preload("res://game/world_item_completion.gd").new()
	gate.main = context
	gate._pickup = pickup
	gate._player = level.player
	s.check(context._run_store.write(RunSnapshot.capture(VAULT, level.run_snapshot()), true), "pickup repair fixture establishes valid original whole-run bytes")
	var original := FileAccess.get_file_as_bytes(context._run_store.path)
	var credits := Progression.credits
	Progression.credits = -1 # Unrelated malformed live owner, no acquisition injection.
	var invalid_live := var_to_bytes([GameState._install_source(), Story._install_source(), StoryItems.snapshot(), Progression.snapshot()])
	var refused: Dictionary = gate._commit({"level": level, "key": key})
	s.check(not refused.get("committed", false) and refused.has("error"), "actual pickup writer refuses unrelated whole-run normalization")
	s.check(refused.get("reload_original", false), "uncommitted pickup repair requests original progress instead of an impossible retry")
	s.check(original == FileAccess.get_file_as_bytes(context._run_store.path) and invalid_live == var_to_bytes([GameState._install_source(), Story._install_source(), StoryItems.snapshot(), Progression.snapshot()]), "pickup repair refusal preserves exact disk and every live owner")
	Progression.credits = credits
	gate.free()
	context.free()
	await s.end_level(level)
	Story.auto_skip = previous_auto
