class_name BackWallGeometry
extends RefCounted
## The exact wall rectangles and holes used by both drawing and scenery placement.

const PANEL_TILES := 4
static var _facade_support: Dictionary = {}
var columns := 0
var rows := 0
var holes := PackedByteArray()
var outdoor := PackedByteArray()
var facade_top := PackedFloat32Array()
var ground := PackedFloat32Array()
var modules: Array[Array] = []
var support_rects: Array[Rect2] = []

func setup(layout: LevelLayout, seed_value: int, theme: EnvironmentTheme) -> void:
	var tile := layout.tile_size
	var panel := float(tile * PANEL_TILES)
	var size := layout.pixel_size()
	columns = ceili(size.x / panel)
	rows = ceili(size.y / panel)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	holes.resize(columns * rows)
	for row in rows:
		for col in columns:
			var zone := theme.zone_at(col * PANEL_TILES) if theme != null else null
			var chance := zone.hole_chance if zone != null else 0.22
			var y := row * panel
			holes[row * columns + col] = 1 if y > panel and y < size.y - panel * 2.0 and rng.randf() < chance else 0
	outdoor.resize(columns)
	facade_top.resize(columns)
	ground.resize(columns)
	modules.resize(columns)
	support_rects.clear()
	for col in columns:
		var covered := 0
		var surface := INF
		for x in range(col * PANEL_TILES, mini((col + 1) * PANEL_TILES, layout.width)):
			covered += layout.covered_columns[x]
			if layout.surface_heights[x] > 0.0:
				surface = minf(surface, layout.surface_heights[x])
		outdoor[col] = 1 if covered * 2 < PANEL_TILES else 0
		ground[col] = surface if surface != INF else size.y
		facade_top[col] = ground[col] - rng.randf_range(4.0, 9.0) * tile if col % 2 == 0 else facade_top[col - 1]
		facade_top[col] = minf(facade_top[col], ground[col] - 2.0 * tile)
	for col in columns:
		var zone := theme.zone_at(col * PANEL_TILES) if theme != null else null
		var left := col * panel
		if outdoor[col] == 0:
			for row in rows:
				if holes[row * columns + col] == 0:
					support_rects.append(Rect2(left, row * panel, panel, panel).intersection(Rect2(Vector2.ZERO, size)))
		elif zone == null or zone.facades.is_empty():
			support_rects.append(Rect2(left, facade_top[col], panel, ground[col] - facade_top[col]))
		else:
			var group := col / 2
			var facade: FacadeData = zone.facades[(seed_value + group * 7) % zone.facades.size()]
			var key := seed_value + group * 13
			var y := ground[col] - FacadeData.GROUND_HEIGHT
			var parts: Array[Dictionary] = []
			parts.append({"rect": Rect2(left, y, panel, FacadeData.GROUND_HEIGHT), "path": FacadeData.pick(facade.ground, key)})
			var floors := maxi(1, int((ground[col] - facade_top[col] - FacadeData.GROUND_HEIGHT - FacadeData.CAP_HEIGHT) / FacadeData.BODY_HEIGHT))
			for i in floors:
				y -= FacadeData.BODY_HEIGHT
				parts.append({"rect": Rect2(left, y, panel, FacadeData.BODY_HEIGHT), "path": FacadeData.pick(facade.body, key + i * 3 + col % 2)})
			y -= FacadeData.CAP_HEIGHT
			parts.append({"rect": Rect2(left, y, panel, FacadeData.CAP_HEIGHT), "path": FacadeData.pick(facade.cap, key)})
			modules[col] = parts
			for part in parts:
				support_rects.append(_opaque_wall_rect(part))


static func _opaque_wall_rect(part: Dictionary) -> Rect2:
	if _facade_support.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/environment/facade_wall_support.json"))
		if raw is Dictionary:
			_facade_support = raw
	var rect: Rect2 = part["rect"]
	var fraction := float(_facade_support.get(part["path"], 1.0))
	rect.position.y += rect.size.y * fraction
	rect.size.y *= 1.0 - fraction
	return rect


func covers(rect: Rect2) -> bool:
	var uncovered: Array[Rect2] = [rect]
	for support in support_rects:
		var next: Array[Rect2] = []
		for area in uncovered:
			var overlap := area.intersection(support)
			if not overlap.has_area():
				next.append(area)
				continue
			if overlap.position.y > area.position.y:
				next.append(Rect2(area.position, Vector2(area.size.x, overlap.position.y - area.position.y)))
			if overlap.end.y < area.end.y:
				next.append(Rect2(Vector2(area.position.x, overlap.end.y), Vector2(area.size.x, area.end.y - overlap.end.y)))
			if overlap.position.x > area.position.x:
				next.append(Rect2(Vector2(area.position.x, overlap.position.y), Vector2(overlap.position.x - area.position.x, overlap.size.y)))
			if overlap.end.x < area.end.x:
				next.append(Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(area.end.x - overlap.end.x, overlap.size.y)))
		uncovered = next
		if uncovered.is_empty():
			return true
	return false
