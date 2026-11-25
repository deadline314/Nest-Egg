extends Resource
## Build-time projection of authored levels for the live HUD and map.
## A runtime record uses the real layout document and only the metadata its map needs.

const PATH := "res://data/navigation/quest_map_metadata.tres"
const VERSION := 1
const LEVEL_FIELDS := [&"id", &"chapter", &"display_name", &"localized_names", &"tile_size",
	&"height", &"layout_path", &"hints", &"decor", &"story_triggers", &"next_level"]
const MARKER_FIELDS := {
	&"PortalData": [&"id", &"target_level", &"target_portal", &"mode", &"prompt", &"localized_prompts",
		&"requires_flag", &"locked_text", &"localized_locked_text", &"style", &"width", &"height",
		&"cinematic_preview_scene"],
	&"MechanismData": [&"id", &"kind", &"display_name", &"hint", &"arena_gate", &"lock_combat_area"],
	&"BreakableData": [&"id", &"look", &"size_tiles", &"hint"],
	&"NpcData": [&"id"],
	&"ShopData": [&"id", &"display_name"],
	&"WeaponData": [&"id", &"display_name"],
	&"ConsumableData": [&"id", &"display_name"],
	&"StoryItemData": [&"id", &"display_name"],
	&"CreditPileData": [&"id"],
}

@export var version := 0
@export var levels: Dictionary[String, LevelData] = {}
@export var digests: Dictionary[String, String] = {}


func add_level(source: LevelData) -> void:
	version = VERSION
	var metadata := LevelData.new()
	for field: StringName in LEVEL_FIELDS:
		metadata.set(field, source.get(field))
	_record_source(source.resource_path)
	var placeholder := Resource.new()
	for symbol: String in source.legend:
		var resource: Resource = source.legend[symbol]
		metadata.legend[symbol] = _marker_projection(resource, placeholder)
	levels[source.resource_path] = metadata


func _marker_projection(resource: Resource, placeholder: Resource) -> Resource:
	if resource == null:
		return null
	var script := resource.get_script() as Script
	_record_source(resource.resource_path.get_slice("::", 0))
	while script != null and not MARKER_FIELDS.has(script.get_global_name()):
		script = script.get_base_script()
	if script == null:
		return placeholder
	var marker: Resource = script.new()
	for field: StringName in MARKER_FIELDS[script.get_global_name()]:
		marker.set(field, resource.get(field))
	return marker


func _record_source(path: String) -> void:
	if not path.is_empty() and not digests.has(path):
		digests[path] = FileAccess.get_sha256(path)


func validation_error() -> String:
	if version != VERSION or levels.is_empty():
		return "版本不符或沒有區域"
	if OS.has_feature("editor"):
		for path: String in digests:
			if FileAccess.get_sha256(path) != digests[path]:
				return "%s 已變更" % path
	return ""


## ResourceSaver can choose new subresource IDs. Compare the authored content.
func definition() -> Dictionary:
	var result := {}
	for path: String in levels:
		var level := levels[path]
		var legend := {}
		for symbol: String in level.legend:
			var marker: Resource = level.legend[symbol]
			if marker == null:
				legend[symbol] = null
				continue
			var script := marker.get_script() as Script
			var kind := script.get_global_name() if script != null else &""
			legend[symbol] = [kind, _fields(marker, MARKER_FIELDS.get(kind, []))]
		result[path] = [_fields(level, LEVEL_FIELDS), legend]
	return {"version": version, "digests": digests, "levels": result}


static func _fields(resource: Resource, names: Array) -> Dictionary:
	var values := {}
	for field: StringName in names:
		values[field] = resource.get(field)
	return values
