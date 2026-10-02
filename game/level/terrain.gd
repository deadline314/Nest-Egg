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


func build(layout: LevelLayout) -> void:
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
	edges.build(_solid_rects, _platform_rects, Rect2(Vector2.ZERO, layout.pixel_size()))


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
