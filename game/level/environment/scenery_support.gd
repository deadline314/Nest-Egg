class_name ScenerySupport
extends RefCounted
## Contact checks for authored props and ASCII decor. Wall support uses rendered geometry.

const TOLERANCE := 2.0
static var _contacts: Dictionary = {}
static var _contacts_loaded := false

static func check_prop(entry: Dictionary, prop: PropData, rect: Rect2, layout: LevelLayout, walls: BackWallGeometry, entries: Array[Dictionary], dirs: PackedStringArray, ancestors := PackedStringArray()) -> String:
	if rect.position.x < -TOLERANCE or rect.end.x > layout.pixel_size().x + TOLERANCE or rect.position.y < -TOLERANCE or rect.end.y > layout.pixel_size().y + TOLERANCE:
		return "prop_outside"
	var key := "%s:%s" % [entry.get("id", ""), entry.get("x", "")]
	if ancestors.has(key):
		return "prop_anchor_cycle"
	var mode := str(entry.get("support", "ground"))
	match mode:
		"wall":
			return "" if walls.covers(visible_rect(rect, prop.id, bool(entry.get("flip", false)))) else "prop_wall_missing"
		"ceiling":
			return "" if has_ceiling(layout, rect) else "prop_hanging"
		"prop", "hang_prop":
			for other in entries:
				if str(other["id"]) != str(entry.get("support_id", "")) or int(other["x"]) != int(entry.get("support_x", -1)):
					continue
				var support := PropLibrary.find_in(StringName(str(other["id"])), dirs)
				if support == null:
					continue
				var placed := PropPlacement.resolve(other, support, layout)
				if placed.is_empty():
					continue
				var parent: Rect2 = placed["rect"]
				var chain := ancestors.duplicate()
				chain.append(key)
				if not check_prop(other, support, parent, layout, walls, entries, dirs, chain).is_empty():
					continue
				var contact_y := rect.position.y if mode == "hang_prop" else rect.end.y
				var target_y := parent.position.y + float(entry.get("support_dy", 0))
				var contact_x := rect.get_center().x
				if absf(contact_y - target_y) <= TOLERANCE and contact_x >= parent.position.x and contact_x <= parent.end.x:
					return ""
			return "prop_anchor_missing"
		"ground":
			return "" if has_ground(layout, rect, prop.id, bool(entry.get("flip", false))) else "prop_floating"
		_:
			return "prop_support_unknown"


static func has_ground(layout: LevelLayout, rect: Rect2, id: StringName = &"", flip := false) -> bool:
	var bottom := rect.end.y - ground_offset(id, rect.size.y)
	var row := roundi(bottom / layout.tile_size)
	if absf(row * layout.tile_size - bottom) > TOLERANCE:
		return false
	var contact: Variant = _contacts.get(String(id), [[0, 1]])
	var spans: Array = contact.get("spans", [[0, 1]]) if contact is Dictionary else contact
	for span: Array in spans:
		if flip:
			span = [1.0 - float(span[1]), 1.0 - float(span[0])]
		var margin := minf(TOLERANCE, rect.size.x * (float(span[1]) - float(span[0])) * 0.45)
		var from_x := floori((rect.position.x + rect.size.x * float(span[0]) + margin) / layout.tile_size)
		var to_x := floori((rect.position.x + rect.size.x * float(span[1]) - margin - 0.01) / layout.tile_size)
		for x in range(from_x, maxi(from_x, to_x) + 1):
			if layout.cell(x, row) not in ["#", "=", "~"] or layout.cell(x, row - 1) == "#":
				return false
	return true


static func ground_offset(id: StringName, height: float) -> float:
	if not _contacts_loaded:
		_contacts_loaded = true
		var path := "res://data/environment/scenery_contacts.json"
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if raw is Dictionary:
			_contacts = raw
		else:
			push_warning("[ScenerySupport] %s 遺失或損毀，使用完整物件寬度檢查地面接觸" % path)
	var contact: Variant = _contacts.get(String(id), {})
	return height * float(contact.get("bottom_margin", 0.0)) if contact is Dictionary else 0.0


static func visible_rect(rect: Rect2, id: StringName, flip := false) -> Rect2:
	ground_offset(id, rect.size.y)
	var contact: Variant = _contacts.get(String(id), {})
	var bounds: Array = contact.get("bounds", [0, 0, 1, 1]) if contact is Dictionary else [0, 0, 1, 1]
	var left := 1.0 - float(bounds[2]) if flip else float(bounds[0])
	return Rect2(rect.position + rect.size * Vector2(left, float(bounds[1])), rect.size * Vector2(float(bounds[2]) - float(bounds[0]), float(bounds[3]) - float(bounds[1])))


static func has_ceiling(layout: LevelLayout, rect: Rect2) -> bool:
	var row := roundi(rect.position.y / layout.tile_size)
	if absf(row * layout.tile_size - rect.position.y) > TOLERANCE:
		return false
	for x in range(floori(rect.position.x / layout.tile_size), ceili(rect.end.x / layout.tile_size)):
		if layout.cell(x, row - 1) != "#" or layout.cell(x, row) == "#":
			return false
	return true


static func decor_rect(entry: Dictionary, data: LevelData) -> Rect2:
	var cell: Vector2i = entry["cell"]
	var key := absi(cell.x * 73856093 ^ cell.y * 19349663)
	var text := data.sign_texts[key % data.sign_texts.size()] if not data.sign_texts.is_empty() else "OPEN"
	var size := Vector2(21, text.length() * 12 + 10) if entry["kind"] == "neon_sign" else Vector2(text.length() * 12 + 10, 21)
	if entry["kind"] == "billboard":
		size = Vector2(112, 64)
	return Rect2(entry["position"], size)


## Authored stage anchors refer to a visible baked surface, or a real stage layer id.
static func stage_anchor_issue(layer: Dictionary, definition: Dictionary) -> String:
	if not layer.has("support_rect") and not layer.has("support_id"):
		return ""
	var texture := RigLibrary.optional_texture(str(layer.get("path", "")))
	if texture == null:
		return "stage_prop_missing"
	var size := texture.get_size() * StageLayers.sprite_scale(layer, texture)
	var position := StageLayers.vec2_of(layer.get("pos"))
	if bool(layer.get("centered", false)):
		position -= size * 0.5
	var rect := Rect2(position, size)
	var support := Rect2()
	if layer.has("support_rect"):
		support = StageLayers.rect_of(layer["support_rect"])
	else:
		for candidate: Dictionary in definition.get("layers", []):
			if candidate.get("id", "") == layer["support_id"] and candidate.get("kind", "") == "rect":
				support = StageLayers.rect_of(candidate.get("rect"))
	if not support.has_area():
		return "stage_anchor_missing"
	if absf(rect.end.y - support.position.y) > TOLERANCE or rect.position.x < support.position.x - TOLERANCE or rect.end.x > support.end.x + TOLERANCE:
		return "stage_prop_floating"
	return ""
