extends RefCounted
## Prepare an area entry without mutating the source run or routing metadata.
static func prepare(original: Dictionary, path: String, state_changes: Dictionary = {}, progression: Variant = null) -> Dictionary:
	var destination := RunSaveCodec.resource(path, "level", "res://data/levels/") as LevelData
	if destination == null: return {"error": "invalid destination: " + path}
	var snapshot := original.duplicate(true)
	snapshot["level"] = path
	var entry: Dictionary = snapshot["runtime"]
	var state: Dictionary = snapshot["state"]
	state["current_level_path"] = path
	for key: String in state_changes:
		state[key] = state_changes[key]
	if progression is Dictionary:
		snapshot["progression"] = progression.duplicate(true)
	var area := {"consumed": {}, "damage": {}, "world": {}}
	if destination.persistent_world:
		area = (state["area_states"].get(String(destination.id), area) as Dictionary).duplicate(true)
	elif state["has_checkpoint"] and (str(state["checkpoint_level_path"]).is_empty() or state["checkpoint_level_path"] == path):
		area["world"] = state["checkpoint_world"].duplicate(true)
	entry["world"] = area["world"].duplicate(true)
	entry["area"] = area
	entry["loose"] = []
	entry["enemies"] = []
	entry["encounters"] = {}
	entry["arena"] = false
	entry["boss_pending"] = false
	entry["velocity"] = [0, 0]
	entry["facing"] = 1
	entry["aim_dir"] = [1, 0]
	entry["crouching"] = false
	entry["guard"] = 100
	entry["dead"] = false
	entry["death_entry"] = {}
	entry["death_cause"] = "unknown"
	entry["ending"] = false
	return {"data": snapshot}
