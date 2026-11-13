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
	# A fresh destination entry belongs to its own map revision, never the source room's.
	var source_revision: Variant = entry.get("layout_revision", 1)
	if not RunSaveCodec.valid_version(source_revision) or source_revision > 2:
		return {"error": "run/runtime/layout_revision：不支援的來源修訂；原存檔保留"}
	var definition := MapLayoutMigration.read(destination)
	if definition.has("error"):
		return definition
	var id := String(destination.id)
	var prior: Variant = state["area_states"].get(id, {"consumed": {}, "damage": {}, "world": {}})
	if not prior is Dictionary:
		return {"error": "run/state/area_states/%s：必須是物件" % id}
	var migrated := MapLayoutMigration.area(prior, definition)
	if migrated.has("error"):
		return migrated
	var checkpoint_here: bool = state["has_checkpoint"] and (str(state["checkpoint_level_path"]).is_empty() or state["checkpoint_level_path"] == path)
	if checkpoint_here and prior.get("layout_revision", 1) != definition["revision"]:
		var checkpoint := MapLayoutMigration.checkpoint(state["checkpoint_world"], RunSaveCodec.vector(state["checkpoint_position"]), definition, LevelBuilder.parse(destination))
		if checkpoint.has("error"):
			return checkpoint
		state["checkpoint_world"] = checkpoint["world"]
		var at: Vector2 = checkpoint["position"]
		state["checkpoint_position"] = [at.x, at.y]
	var area: Dictionary = migrated["data"] if destination.persistent_world else MapLayoutMigration.area({}, definition)["data"]
	if not destination.persistent_world and checkpoint_here:
		area["world"] = state["checkpoint_world"].duplicate(true)
	# Keep checkpoint metadata and the saved area in the same revision so reads cannot translate twice.
	if destination.persistent_world or definition["revision"] > 1:
		state["area_states"][id] = area.duplicate(true)
	if definition["revision"] > 1:
		entry["layout_revision"] = definition["revision"]
	else:
		entry.erase("layout_revision")
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
