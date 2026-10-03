class_name Terrain
extends ChunkedDrawer
## 地形：碰撞（合併後的矩形）、遮光體（讓光源投射陰影）與外觀繪製。
## 外觀採分塊繪製且只在建立時畫一次，不佔每影格效能。

const PANEL_PATH := "res://art/materials/metal_panel.png"
## 面板貼圖的邊長（像素）。實心矩形與區塊邊界都落在這個格線上，平鋪不會有接縫。
const PANEL_TEXTURE_SIZE := 16

var _solid_rects: Array[Rect2] = []
var _platform_rects: Array[Rect2] = []
var _tile := 16
var _panel: Texture2D
var _layout: LevelLayout
## 環境主題（有地形材質時使用）；null 代表沿用單一金屬面板。
var _theme: EnvironmentTheme
## 材質貼圖快取（路徑 -> 受光貼圖）。
var _material_textures: Dictionary[String, Texture2D] = {}
## 材質覆蓋區：{ "rect": Rect2i（格）, "material": TerrainMaterialData }。例如貨櫃、天花板用不同於區段的材質。
var _regions: Array[Dictionary] = []


func build(layout: LevelLayout, theme: EnvironmentTheme = null, regions: Array[Dictionary] = []) -> void:
	_layout = layout
	_theme = theme
	_regions = _resolve_regions(regions)
	_tile = layout.tile_size
	_panel = LitTextures.load_texture(PANEL_PATH, Vector2i(PANEL_TEXTURE_SIZE, PANEL_TEXTURE_SIZE))
	var solid_body := StaticBody2D.new()
	solid_body.name = "Solid"
	solid_body.collision_layer = Layers.WORLD
	solid_body.collision_mask = 0
	add_child(solid_body)
	for cells in layout.solid_rects:
		var rect := layout.cells_to_pixels(cells)
		_solid_rects.append(rect)
		solid_body.add_child(_make_shape(rect, false))
		add_child(_make_occluder(rect))

	var platform_body := StaticBody2D.new()
	platform_body.name = "Platforms"
	platform_body.collision_layer = Layers.PLATFORM
	platform_body.collision_mask = 0
	add_child(platform_body)
	for cells in layout.platform_rects:
		var rect := layout.cells_to_pixels(cells)
		# 單向平台只用格子上緣的薄片做碰撞。
		var top := Rect2(rect.position, Vector2(rect.size.x, 6.0))
		_platform_rects.append(top)
		platform_body.add_child(_make_shape(top, true))
	build_chunks(Rect2(Vector2.ZERO, layout.pixel_size()))
	# 亮邊自成一層，自發光；本體的頂面線改由它負責。
	var edges := TerrainEdges.new()
	edges.name = "Edges"
	add_child(edges)
	edges.build(_solid_rects, _platform_rects, Rect2(Vector2.ZERO, layout.pixel_size()), _theme, _tile)


func _make_shape(rect: Rect2, one_way: bool) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var node := CollisionShape2D.new()
	node.shape = shape
	node.position = rect.get_center()
	node.one_way_collision = one_way
	return node


func _make_occluder(rect: Rect2) -> LightOccluder2D:
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	])
	var occluder := LightOccluder2D.new()
	occluder.occluder = polygon
	return occluder


func _draw_chunk(canvas: CanvasItem, area: Rect2) -> void:
	if _theme != null and not _theme.zones.is_empty():
		_draw_themed_chunk(canvas, area)
		return
	for full in _solid_rects:
		var rect := full.intersection(area)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		canvas.draw_texture_rect(_panel, rect, true)
		# 金屬面板接縫（每 2 格一條），讓大面積地形不單調。
		var x := full.position.x + _tile * 2.0
		while x < rect.end.x:
			if x > rect.position.x:
				canvas.draw_line(Vector2(x, rect.position.y + 3), Vector2(x, rect.end.y), Color(Palette.TERRAIN_EDGE, 0.5), 1.0)
			x += _tile * 2.0
		canvas.draw_rect(rect, Palette.TERRAIN_EDGE, false, 1.0)
	for full in _platform_rects:
		var rect := full.intersection(area)
		if rect.size.x <= 0.0:
			continue
		canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), Palette.PLATFORM)
		var x := full.position.x + 4.0
		while x < rect.end.x:
			if x > rect.position.x:
				canvas.draw_line(Vector2(x, rect.position.y + 4), Vector2(x - 3, rect.position.y + 9), Color(Palette.PLATFORM, 0.6), 1.0)
			x += 8.0


# ---------------------------------------------------------------------------
# 材質繪製：本體平鋪 + 外露的頂端與左右邊緣各蓋一條材質條
# ---------------------------------------------------------------------------

func _draw_themed_chunk(canvas: CanvasItem, area: Rect2) -> void:
	for full in _solid_rects:
		var rect := full.intersection(area)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		# 依區段把矩形切成一段一段（每段同一種材質）。
		var x := rect.position.x
		while x < rect.end.x:
			var tile_x := int(floor(x / _tile))
			var zone := _theme.zone_at(tile_x)
			var next_x := rect.end.x
			for other in _theme.zones:
				if other != null and other.from_tile * _tile > x and other.from_tile * _tile < next_x:
					next_x = float(other.from_tile * _tile)
			if zone != null and zone.material != null:
				_draw_piece(canvas, zone.material, Rect2(x, rect.position.y, next_x - x, rect.size.y), full)
			x = next_x
	_draw_regions(canvas, area)
	_draw_themed_platforms(canvas, area)


## 把地圖 JSON 的覆蓋區（x0、x1、y0、y1 為格座標，material 為材質 id）換成材質資源；壞掉的略過並記錄。
func _resolve_regions(raw: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in raw:
		var id := str(entry.get("material", ""))
		var path := "res://data/environment/materials/%s.tres" % id
		var material: TerrainMaterialData = load(path) as TerrainMaterialData if ResourceLoader.exists(path) else null
		if material == null or not (entry.has("x0") and entry.has("x1") and entry.has("y0") and entry.has("y1")):
			push_warning("[Terrain] 材質覆蓋區無效（material=%s），已略過：%s" % [id, entry])
			continue
		var x0 := int(entry["x0"])
		var y0 := int(entry["y0"])
		result.append({"rect": Rect2i(x0, y0, int(entry["x1"]) - x0 + 1, int(entry["y1"]) - y0 + 1), "material": material})
	return result


## 覆蓋區：只蓋在實心格上（逐列找出連續的實心格），外露判斷用鄰格，所以疊在地面上的貨櫃只有外側才有邊條。
func _draw_regions(canvas: CanvasItem, area: Rect2) -> void:
	for region in _regions:
		var cells: Rect2i = region["rect"]
		var material: TerrainMaterialData = region["material"]
		for row in range(cells.position.y, cells.end.y):
			var start := -1
			for column in range(cells.position.x, cells.end.x + 1):
				var solid := column < cells.end.x and _is_solid(column, row)
				if solid and start < 0:
					start = column
				elif not solid and start >= 0:
					var run := Rect2(start * _tile, row * _tile, (column - start) * _tile, _tile)
					var piece := run.intersection(area)
					if piece.size.x > 0.0 and piece.size.y > 0.0:
						_draw_piece(canvas, material, piece, run)
					start = -1


## 單向平台：用所在區段材質的頂面條，底下加一道陰影，讓「可以站」一眼看得出來。
func _draw_themed_platforms(canvas: CanvasItem, area: Rect2) -> void:
	for full in _platform_rects:
		var rect := full.intersection(area)
		if rect.size.x <= 0.0:
			continue
		var zone := _theme.zone_at(int(floor(rect.position.x / _tile)))
		if zone == null or zone.material == null:
			continue
		var scale_factor := float(zone.material.texture_scale)
		var top_h := zone.material.top_height
		var dest := Rect2(rect.position, Vector2(rect.size.x, top_h))
		canvas.draw_texture_rect_region(_material_texture(zone.material.top), dest,
				Rect2(dest.position.x * scale_factor, 0.0, dest.size.x * scale_factor, top_h * scale_factor))
		canvas.draw_rect(Rect2(rect.position.x, rect.position.y + top_h, rect.size.x, 2.0), Color(0, 0, 0, 0.45))


func _draw_piece(canvas: CanvasItem, material: TerrainMaterialData, piece: Rect2, full: Rect2) -> void:
	var scale_factor := float(material.texture_scale)
	var body := _material_texture(material.body)
	canvas.draw_texture_rect_region(body, piece, Rect2(piece.position * scale_factor, piece.size * scale_factor))
	var top_h := material.top_height
	var side_w := material.side_width
	# 頂端：上方那一格不是實心的欄才有頂面。
	var top_tex := _material_texture(material.top)
	for run in _exposed_runs_x(piece, full):
		var dest := Rect2(run.x, piece.position.y, run.y - run.x, top_h)
		canvas.draw_texture_rect_region(top_tex, dest, Rect2(dest.position.x * scale_factor, 0.0, dest.size.x * scale_factor, top_h * scale_factor))
	# 左右邊緣：外側那一格不是實心的列才有側邊。
	var side_tex := _material_texture(material.side)
	for run in _exposed_runs_y(piece, full, true):
		var dest := Rect2(piece.position.x, run.x, side_w, run.y - run.x)
		canvas.draw_texture_rect_region(side_tex, dest, Rect2(0.0, dest.position.y * scale_factor, side_w * scale_factor, dest.size.y * scale_factor))
	for run in _exposed_runs_y(piece, full, false):
		var dest := Rect2(piece.end.x, run.x, -side_w, run.y - run.x)
		canvas.draw_texture_rect_region(side_tex, dest, Rect2(0.0, run.x * scale_factor, side_w * scale_factor, (run.y - run.x) * scale_factor))


func _material_texture(path: String) -> Texture2D:
	if not _material_textures.has(path):
		_material_textures[path] = LitTextures.load_texture(path, Vector2i(64, 64))
	return _material_textures[path]


func _is_solid(cell_x: int, cell_y: int) -> bool:
	return _layout.cell(cell_x, cell_y) == LevelBuilder.SOLID


func _is_exposed_above(piece: Rect2, x: float) -> bool:
	return not _is_solid(int(floor(x / _tile)), int(floor(piece.position.y / _tile)) - 1)


## 沿 piece 頂邊找出上方不是實心的連續範圍（回傳 Vector2(起點 x, 終點 x) 的陣列）。
func _exposed_runs_x(piece: Rect2, _full: Rect2) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	var row := int(floor(piece.position.y / _tile))
	var start := -1.0
	var x := piece.position.x
	while x < piece.end.x:
		var cell_x := int(floor(x / _tile))
		var segment_end := minf(float(cell_x + 1) * _tile, piece.end.x)
		var open := not _is_solid(cell_x, row - 1)
		if open and start < 0.0:
			start = x
		elif not open and start >= 0.0:
			runs.append(Vector2(start, x))
			start = -1.0
		x = segment_end
	if start >= 0.0:
		runs.append(Vector2(start, piece.end.x))
	return runs


## 沿 piece 的左（left = true）或右邊緣找出外側不是實心的連續範圍（y 起點、終點）。
func _exposed_runs_y(piece: Rect2, _full: Rect2, left: bool) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	var column := int(floor(piece.position.x / _tile)) - 1 if left else int(floor((piece.end.x - 0.01) / _tile)) + 1
	var start := -1.0
	var y := piece.position.y
	while y < piece.end.y:
		var cell_y := int(floor(y / _tile))
		var segment_end := minf(float(cell_y + 1) * _tile, piece.end.y)
		var open := not _is_solid(column, cell_y)
		if open and start < 0.0:
			start = y
		elif not open and start >= 0.0:
			runs.append(Vector2(start, y))
			start = -1.0
		y = segment_end
	if start >= 0.0:
		runs.append(Vector2(start, piece.end.y))
	return runs
