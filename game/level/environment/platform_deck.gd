extends RefCounted
## Static, chunked visuals for ordinary one-way platforms. The collision surface
## is always at deck.position.y. Steel below it is scenery.

const DECK_DEPTH := 4.0
const BEAM_DEPTH := 12.0
const SHADOW_DEPTH := 17.0
const MOUNT_REACH := 14.0
const MOUNT_INSET := 11.0
const SUPPORT_SPACING := 76.0
const MODULE_SPACING := 36
const OUTLINE := Color("#151c25")
const STEEL := Color("#4c5869")
const STEEL_DARK := Color("#2e3845")
const STEEL_EDGE := Color("#8290a0")
const CONTACT_SHADOW := Color(0.018, 0.025, 0.039, 0.52)

enum SupportKind { WALL, HANGER, POST }


class Support:
	var x: float
	var top: float
	var end: float
	var reach: float
	var kind: SupportKind


var _decks_by_chunk: Dictionary[int, Array] = {}
var _supports_by_chunk: Dictionary[int, Array] = {}
var _tile: int
var _layout: LevelLayout
var _theme: EnvironmentTheme
var _material_boundaries := PackedFloat32Array()


func build(layout: LevelLayout, theme: EnvironmentTheme, walls: BackWallGeometry, decks: Array[Rect2]) -> void:
	_layout = layout
	_tile = layout.tile_size
	_theme = theme
	_material_boundaries.clear()
	if _theme != null:
		for zone in _theme.zones:
			if zone != null:
				_material_boundaries.append(float(zone.from_tile * _tile))
		_material_boundaries.sort()
	_decks_by_chunk.clear()
	_supports_by_chunk.clear()
	for deck in decks:
		for chunk in range(_chunk_at(deck.position.x), _chunk_at(deck.end.x - 1.0) + 1):
			if not _decks_by_chunk.has(chunk):
				_decks_by_chunk[chunk] = []
			_decks_by_chunk[chunk].append(deck)
		_add_supports(deck, walls)


func draw_supports(canvas: CanvasItem, area: Rect2) -> void:
	for support: Support in _supports_by_chunk.get(_chunk_at(area.position.x), []):
		match support.kind:
			SupportKind.WALL:
				_draw_wall_brace(canvas, support)
			SupportKind.HANGER:
				_draw_vertical_support(canvas, support, true)
			SupportKind.POST:
				_draw_vertical_support(canvas, support, false)


func draw_decks(canvas: CanvasItem, area: Rect2, texture_for: Callable) -> void:
	for full: Rect2 in _decks_by_chunk.get(_chunk_at(area.position.x), []):
		var left := maxf(area.position.x, full.position.x)
		var right := minf(area.end.x, full.end.x)
		var y := full.position.y
		_band(canvas, left, y + BEAM_DEPTH, right - left, SHADOW_DEPTH - BEAM_DEPTH, CONTACT_SHADOW)
		_band(canvas, left, y, right - left, BEAM_DEPTH, OUTLINE)
		_draw_material_faces(canvas, left, right, y, texture_for)
		var first_module := maxi(1, ceili((left - full.position.x - 1.0) / MODULE_SPACING))
		var first_seam := int(full.position.x) + first_module * MODULE_SPACING
		for seam in range(first_seam, mini(ceili(right), int(full.end.x) - 2), MODULE_SPACING):
			if seam >= left:
				_band(canvas, seam, y + DECK_DEPTH + 1.0, 1.0, BEAM_DEPTH - DECK_DEPTH - 2.0, OUTLINE)
			if seam + 1 < right:
				_band(canvas, seam + 1.0, y + DECK_DEPTH + 1.0, 1.0, BEAM_DEPTH - DECK_DEPTH - 2.0, STEEL_EDGE.darkened(0.22))
		var row := floori(y / _tile)
		if left == full.position.x:
			_draw_end(canvas, full, _layout.cell(floori(left / _tile) - 1, row) == LevelBuilder.SOLID, true)
		if right == full.end.x:
			_draw_end(canvas, full, _layout.cell(floori(right / _tile), row) == LevelBuilder.SOLID, false)


func _draw_material_faces(canvas: CanvasItem, left: float, right: float, y: float, texture_for: Callable) -> void:
	var x := left
	for boundary in _material_boundaries:
		if boundary <= x:
			continue
		if boundary >= right:
			break
		_draw_deck_face(canvas, Vector2(x, boundary), y, texture_for)
		x = boundary
	_draw_deck_face(canvas, Vector2(x, right), y, texture_for)


func _draw_deck_face(canvas: CanvasItem, span: Vector2, y: float, texture_for: Callable) -> void:
	var left := span.x
	var width := span.y - span.x
	var zone := _theme.zone_at(floori(left / _tile)) if _theme != null else null
	var material: TerrainMaterialData = zone.material if zone != null else null
	var trim := STEEL_EDGE
	_band(canvas, left, y, width, DECK_DEPTH, STEEL_EDGE)
	if material != null:
		var scale_factor := float(material.texture_scale)
		var texture: Texture2D = texture_for.call(material.top)
		var dest := Rect2(left, y, width, DECK_DEPTH)
		canvas.draw_texture_rect_region(texture, dest, Rect2(left * scale_factor, 0, width * scale_factor, DECK_DEPTH * scale_factor))
		if material.edge_color.a > 0.0:
			trim = trim.lerp(Color(material.edge_color, 1.0), 0.27)
	_band(canvas, left, y + DECK_DEPTH - 1.0, width, 1.0, trim)
	_band(canvas, left, y + DECK_DEPTH, width, BEAM_DEPTH - DECK_DEPTH - 2.0, STEEL)
	_band(canvas, left, y + DECK_DEPTH + 2.0, width, BEAM_DEPTH - DECK_DEPTH - 4.0, STEEL_DARK)
	_band(canvas, left, y + BEAM_DEPTH - 2.0, width, 1.0, STEEL)


func _draw_end(canvas: CanvasItem, deck: Rect2, joins_solid: bool, left: bool) -> void:
	var width := minf(6.0 if joins_solid else 4.0, deck.size.x * 0.5)
	var x := deck.position.x if left else deck.end.x - width
	var y := deck.position.y + DECK_DEPTH
	_band(canvas, x, y, width, BEAM_DEPTH - DECK_DEPTH, OUTLINE)
	_band(canvas, x, y, width - 1.0, BEAM_DEPTH - DECK_DEPTH - 1.0, STEEL)
	if width >= 4.0:
		_bolt(canvas, Vector2(x + 2.0, y + 2.0))
		if joins_solid:
			_bolt(canvas, Vector2(x + 2.0, y + 5.0))


func _add_supports(deck: Rect2, walls: BackWallGeometry) -> void:
	var inset := minf(MOUNT_INSET, deck.size.x * 0.5)
	var span := deck.size.x - inset * 2.0
	var count := ceili(span / SUPPORT_SPACING) + 1
	for i in count:
		var ratio := float(i) / maxf(1.0, count - 1)
		var support := Support.new()
		support.x = floorf(deck.position.x + inset + ratio * span)
		support.top = deck.position.y + BEAM_DEPTH - 1.0
		var direction := 1.0 if ratio <= 0.5 else -1.0
		support.reach = direction * minf(MOUNT_REACH, deck.size.x - inset)
		var mount := Rect2(support.x - 2.0, support.top, 4.0, 16.0)
		if walls != null and walls.covers(mount):
			support.kind = SupportKind.WALL
			support.end = mount.end.y
		elif not _resolve_open_support(support, floori(deck.position.y / _tile)):
			continue
		var chunk := _chunk_at(support.x)
		if not _supports_by_chunk.has(chunk):
			_supports_by_chunk[chunk] = []
		_supports_by_chunk[chunk].append(support)


func _resolve_open_support(support: Support, deck_row: int) -> bool:
	var column := floori(support.x / _tile)
	for row in range(deck_row - 1, -1, -1):
		match _layout.cell(column, row):
			LevelBuilder.SOLID:
				support.kind = SupportKind.HANGER
				support.end = float((row + 1) * _tile)
				return true
			LevelBuilder.PLATFORM:
				support.kind = SupportKind.HANGER
				support.end = minf(support.top - 1.0, row * _tile + BEAM_DEPTH - 1.0)
				return true
	for row in range(deck_row + 1, _layout.height):
		match _layout.cell(column, row):
			LevelBuilder.SOLID:
				support.kind = SupportKind.POST
				support.end = float(row * _tile)
				return support.end > support.top
			LevelBuilder.PLATFORM:
				break
	# No structural anchor is visible above or below this span. Keep the
	# suspension going out of frame instead of inventing a floor contact.
	support.kind = SupportKind.HANGER
	support.end = 0.0
	return true


func _draw_wall_brace(canvas: CanvasItem, support: Support) -> void:
	var x := support.x
	var top := support.top
	var end := support.end
	var tip := x + support.reach
	_band(canvas, x - 3.0, top + 2.0, 7.0, end - top, CONTACT_SHADOW)
	_band(canvas, x - 2.0, top, 5.0, end - top, OUTLINE)
	_band(canvas, x - 1.0, top, 3.0, end - top - 1.0, STEEL_DARK)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(x, top), Vector2(tip, top), Vector2(tip, top + 2.0), Vector2(x, end - 3.0),
	]), STEEL)
	canvas.draw_line(Vector2(tip, top + 2.0), Vector2(x, end - 3.0), OUTLINE, 2.0)
	canvas.draw_line(Vector2(lerpf(tip, x, 0.12), top + 2.0), Vector2(x, end - 5.0), STEEL_EDGE, 1.0)
	_bolt(canvas, Vector2(x, end - 3.0))


func _draw_vertical_support(canvas: CanvasItem, support: Support, hanging: bool) -> void:
	var x := support.x
	var from := minf(support.top, support.end)
	var to := maxf(support.top, support.end)
	var width := 3.0 if hanging else 5.0
	_band(canvas, x - 1.0, from, width, to - from, OUTLINE)
	_band(canvas, x - 1.0, from, 1.0, to - from, STEEL)
	var mount_y := from if hanging else maxf(from, to - 3.0)
	_band(canvas, x - 3.0, mount_y, width + 4.0, minf(3.0, to - from), STEEL_DARK)


static func _chunk_at(x: float) -> int:
	return floori(x / ChunkedDrawer.CHUNK_WIDTH)


static func _band(canvas: CanvasItem, x: float, y: float, width: float, height: float, color: Color) -> void:
	if width > 0.0 and height > 0.0:
		canvas.draw_rect(Rect2(x, y, width, height), color)


static func _bolt(canvas: CanvasItem, at: Vector2) -> void:
	canvas.draw_rect(Rect2(at + Vector2(0.0, 1.0), Vector2(2.0, 1.0)), OUTLINE)
	canvas.draw_rect(Rect2(at, Vector2(2.0, 1.0)), STEEL_EDGE)
