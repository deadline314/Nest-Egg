class_name MapLayoutMigration
extends RefCounted
## Authored map revision 1→2 only. Work on copies before installing any save state.

const MAX_CELLS := 4096
const MAX_COORDINATE := 4096


static func read(data: LevelData) -> Dictionary:
	if data == null or data.layout_path.is_empty():
		return {"revision": 1}
	var json := load(data.layout_path) as JSON if ResourceLoader.exists(data.layout_path) else null
	if json == null or not json.data is Dictionary:
		return {"revision": 1}  # Existing LevelBuilder owns missing/invalid map diagnostics.
	var raw: Dictionary = json.data
	var revision: Variant = raw.get("layout_revision", 1)
	var where := data.layout_path + "/layout_revision"
	if not RunSaveCodec.valid_version(revision) or revision > 2:
		return {"error": where + "：不支援的版面修訂；原存檔保留"}
	if revision == 1:
		return {"revision": 1}
	var legacy: Variant = raw.get("legacy_layout")
	if not legacy is Dictionary or not RunSaveCodec.valid_version(legacy.get("revision")) or legacy.get("revision") != 1:
		return {"error": where + "：缺少第一版遷移描述"}
	var offset: Variant = _pair(legacy.get("cell_offset"))
	var cells: Variant = legacy.get("cells", {})
	if offset == null or not cells is Dictionary or cells.size() > MAX_CELLS:
		return {"error": data.layout_path + "/legacy_layout：位移或座標表無效"}
	var segments: Variant = raw.get("segments")
	if not segments is Array or segments.is_empty() or segments.size() > MAX_CELLS or data.height < 1 or data.height > MAX_COORDINATE:
		return {"error": data.layout_path + "/segments：新區域尺寸無效"}
	var width := 0
	for segment: Variant in segments:
		if not segment is Array or segment.is_empty() or not segment[0] is String:
			return {"error": data.layout_path + "/segments：新區域寬度無效"}
		width += segment[0].length()
	if width < 1 or width > MAX_COORDINATE:
		return {"error": data.layout_path + "/segments：新區域寬度超限"}
	var mapped: Dictionary = {}
	for key: Variant in cells:
		var source: Variant = _cell(key)
		var target: Variant = _pair(cells[key])
		if source == null or target == null or target.x < 0 or target.y < 0 or target.x >= width or target.y >= data.height:
			return {"error": "%s/legacy_layout/cells/%s：座標無效" % [data.layout_path, str(key).left(80)]}
		if key != "%d,%d" % [source.x, source.y]:
			return {"error": "%s/legacy_layout/cells/%s：座標不是標準格式" % [data.layout_path, key]}
		mapped[key] = target
	return {"revision": 2, "offset": offset, "cells": mapped, "tile": maxi(4, data.tile_size), "where": data.layout_path}


static func area(raw: Dictionary, definition: Dictionary) -> Dictionary:
	var version: Variant = raw.get("layout_revision", 1)
	if not RunSaveCodec.valid_version(version) or version > definition["revision"]:
		return {"error": "area/layout_revision：不支援的版面修訂；原存檔保留"}
	var result := raw.duplicate(true)
	for field in ["consumed", "damage", "world"]:
		if not result.get(field, {}) is Dictionary:
			return {"error": "area/%s：必須是物件" % field}
		result[field] = result.get(field, {})
		if version != definition["revision"]:
			var moved := keys(result.get(field, {}), definition)
			if moved.has("error"):
				return moved
			result[field] = moved["data"]
	if definition["revision"] > 1:
		result["layout_revision"] = definition["revision"]
	return {"data": result}


static func runtime(raw: Dictionary, data: LevelData, layout: LevelLayout = null) -> Dictionary:
	var definition := read(data)
	if definition.has("error"):
		return definition
	var version: Variant = raw.get("layout_revision", 1)
	if not RunSaveCodec.valid_version(version) or version > definition["revision"]:
		return {"error": "run/runtime/layout_revision：不支援的版面修訂；原存檔保留"}
	var previous_area: Variant = raw.get("area", {})
	if not previous_area is Dictionary or previous_area.get("layout_revision", 1) != version:
		return {"error": "run/runtime/area/layout_revision：修訂不一致"}
	if version == definition["revision"]:
		return {"data": raw}
	var result := raw.duplicate(true)
	var moved_area := area(previous_area, definition)
	if moved_area.has("error"):
		return moved_area
	result["area"] = moved_area["data"]
	if result.get("cinematic_context") is Dictionary:
		result["cinematic_context"] = _presentation_context(result["cinematic_context"], definition)
	for field in ["world", "encounters"]:
		if not result.get(field, {}) is Dictionary:
			return {"error": "run/runtime/%s：必須是物件" % field}
		var moved := keys(result.get(field, {}), definition)
		if moved.has("error"):
			return moved
		result[field] = moved["data"]
	if layout == null:
		layout = LevelBuilder.parse(data)
	if not layout.is_valid():
		return {"error": "run/runtime/layout_revision：新區域無效"}
	var anchors: Dictionary = {}
	for spawn: Dictionary in layout.spawns:
		var resource: Resource = spawn["resource"]
		if resource is EnemyData:
			var at: Vector2i = spawn["cell"]
			anchors["%s@%d,%d" % [resource.id, at.x, at.y]] = spawn["position"]
	for field in ["enemies", "loose"]:
		if not result.get(field, []) is Array or result.get(field, []).size() > 1024:
			return {"error": "run/runtime/%s：必須是有界陣列" % field}
		for entry: Variant in result.get(field, []):
			if not entry is Dictionary:
				return {"error": "run/runtime/%s：項目必須是物件" % field}
			var at := layout.player_start
			if field == "enemies":
				if not entry.get("key", "") is String:
					return {"error": "run/runtime/enemies/key：必須是文字"}
				entry["key"] = spawn_key(entry.get("key", ""), definition)
				var enemy := RunSaveCodec.resource(entry.get("resource"), "enemy", "res://data/enemies/") as EnemyData
				if enemy == null:
					return {"error": "run/runtime/enemies/resource：無效敵人，原檔保留"}
				at = anchors.get(entry["key"], position(RunSaveCodec.vector(entry.get("position")), definition))
				if not layout.fits_body(at, enemy.body_size):
					var requested := at
					var nearest := INF
					for spawn: Dictionary in layout.spawns:
						if spawn["resource"] == enemy and layout.fits_body(spawn["position"], enemy.body_size):
							var distance := requested.distance_squared_to(spawn["position"])
							if distance < nearest:
								nearest = distance
								at = spawn["position"]
					if nearest == INF:
						return {"error": "run/runtime/enemies：找不到安全遷移位置；原檔保留"}
			entry["position"] = [at.x, at.y]
	# New geometry can put a formerly valid position beyond a newly authored gate.
	# Re-enter the same area safely; keep inventory, health and all durable outcomes.
	result["position"] = [layout.player_start.x, layout.player_start.y]
	result["velocity"] = [0, 0]
	result["layout_revision"] = definition["revision"]
	return {"data": result, "relocated": true}


static func prepare_run(snapshot: Dictionary, current: LevelData) -> Dictionary:
	var state: Dictionary = snapshot["state"]
	var areas: Dictionary = state["area_states"]
	for resource in ResourceCatalog.load_dir("res://data/levels", LevelData, "MapMigration"):
		var data := resource as LevelData
		var id := String(data.id)
		if not areas.has(id) and state.get("checkpoint_level_path", "") != data.resource_path:
			continue
		var definition := read(data)
		if definition.has("error"):
			return definition
		var previous: Dictionary = areas.get(id, {"consumed": {}, "damage": {}, "world": state["checkpoint_world"]})
		var version: Variant = previous.get("layout_revision", 1)
		var moved := area(previous, definition)
		if moved.has("error"):
			return moved
		if areas.has(id) or definition["revision"] > 1:
			areas[id] = moved["data"]
		if version != definition["revision"] and state.get("checkpoint_level_path", "") == data.resource_path:
			var restored := checkpoint(state["checkpoint_world"], RunSaveCodec.vector(state.get("checkpoint_position")), definition, LevelBuilder.parse(data))
			if restored.has("error"):
				return restored
			state["checkpoint_world"] = restored["world"]
			var at: Vector2 = restored["position"]
			state["checkpoint_position"] = [at.x, at.y]
	var migrated := runtime(snapshot["runtime"], current)
	if migrated.has("error"):
		return migrated
	snapshot["runtime"] = migrated["data"]
	if migrated.get("relocated", false) and snapshot.get("cinematic_context") is Dictionary:
		snapshot["cinematic_context"] = _presentation_context(snapshot["cinematic_context"], read(current))
	return {"relocated": migrated.get("relocated", false)}


static func _presentation_context(raw: Dictionary, definition: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var source: Variant = result.get("source_id")
	# NPC origins use the same authored cell key as their durable world state.
	if result.get("framing_source") in ["person", "object"] and source is String and source.begins_with("npc:"):
		result["source_id"] = spawn_key(source, definition)
	return result


static func checkpoint(world: Dictionary, previous: Vector2, definition: Dictionary, layout: LevelLayout) -> Dictionary:
	var moved := keys(world, definition)
	if moved.has("error"):
		return moved
	if not layout.is_valid():
		return {"error": "run/state/checkpoint_position：新復原區域無效"}
	var original := position(previous, definition)
	var at := layout.player_start
	var nearest := INF
	for point in layout.checkpoints:
		var distance := original.distance_squared_to(point)
		if distance < nearest:
			nearest = distance
			at = point
	return {"world": moved["data"], "position": at}


static func keys(raw: Dictionary, definition: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in raw:
		if not key is String:
			return {"error": "layout migration：持久鍵必須是文字"}
		var moved := spawn_key(key, definition)
		if result.has(moved) and result[moved] != raw[key]:
			return {"error": "layout migration：持久鍵衝突 %s；原存檔保留" % moved.left(192)}
		result[moved] = raw[key]
	return {"data": result}


static func spawn_key(key: String, definition: Dictionary) -> String:
	var split := key.rfind("@")
	if split < 0 or definition["revision"] == 1:
		return key
	# Built-in health pickups alone persist pixel feet, not the layout's spawn cell.
	if key.substr(0, split) == "health":
		var feet: Variant = _cell(key.substr(split + 1), mini(RunSaveCodec.MAX_NUMBER, MAX_COORDINATE * int(definition["tile"])))
		if feet == null:
			return key
		var target := position(Vector2(feet), definition)
		return "health@%d,%d" % [roundi(target.x), roundi(target.y)]
	var source: Variant = _cell(key.substr(split + 1))
	if source == null:
		return key
	var target := cell(source, definition)
	return "%s@%d,%d" % [key.substr(0, split), target.x, target.y]


static func explored_key(key: String, definition: Dictionary) -> String:
	var source: Variant = _cell(key)
	if source == null:
		return key
	var target := cell(source, definition)
	return "%d,%d" % [target.x, target.y]


static func checkpoint_key(key: String, definition: Dictionary) -> String:
	var split := key.rfind("@")
	var source: Variant = _cell(key.substr(split + 1)) if split >= 0 else null
	if source == null or definition["revision"] == 1:
		return key
	var target := cell(source - Vector2i(0, 1), definition) + Vector2i(0, 1)
	return "%s@%d,%d" % [key.substr(0, split), target.x, target.y]


static func cell(source: Vector2i, definition: Dictionary) -> Vector2i:
	if definition["revision"] == 1:
		return source
	return definition["cells"].get("%d,%d" % [source.x, source.y], source + definition["offset"])


static func position(source: Vector2, definition: Dictionary) -> Vector2:
	if definition["revision"] == 1:
		return source
	var tile: int = definition["tile"]
	# Spawn cells describe the foot's row above its standable surface.
	var feet := Vector2i(floori(source.x / tile), ceili(source.y / tile) - 1)
	return source + Vector2(cell(feet, definition) - feet) * tile


static func _pair(raw: Variant) -> Variant:
	if not raw is Array or raw.size() != 2:
		return null
	for value: Variant in raw:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > MAX_COORDINATE or floorf(float(value)) != float(value):
			return null
	return Vector2i(int(raw[0]), int(raw[1]))


static func _cell(raw: Variant, limit := MAX_COORDINATE) -> Variant:
	if not raw is String or raw.length() > 24:
		return null
	var parts: PackedStringArray = raw.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	var x := int(parts[0])
	var y := int(parts[1])
	if x < 0 or y < 0 or x > limit or y > limit:
		return null
	return Vector2i(x, y)
