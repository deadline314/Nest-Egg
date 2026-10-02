class_name BackWall
extends ChunkedDrawer
## 背景牆面（與光源同一圖層，會被燈光照亮並顯示地形陰影）。
##   室內（有屋頂的欄）：完整的金屬牆板，部分破損鏤空露出後方夜景。
##   室外（沒有屋頂的欄）：只畫街邊建築的低樓層立面（店面玻璃、鐵捲門、冷氣機），
##   上方保持透空，讓城市天際線透出來。
## 採分塊繪製（見 ChunkedDrawer），只在建立時繪製一次。

const PANEL_TILES := 4
const PILLAR_EVERY := 12
const HOLE_CHANCE := 0.22
const WALL_COLOR := Color("1a2030")
const SEAM_COLOR := Color("262e42")
const PILLAR_COLOR := Color("1d2436")
const FACADE_COLOR := Color("171b2b")
const GLASS_COLOR := Color("0d1424")
const SHUTTER_COLOR := Color("232838")

var _tile := 16
var _seed := 1
var _columns := 0
var _rows := 0
var _holes := PackedByteArray()
var _outdoor := PackedByteArray()
var _facade_top := PackedFloat32Array()
var _ground := PackedFloat32Array()


func setup(layout: LevelLayout, p_seed := 1) -> void:
	_tile = layout.tile_size
	_seed = p_seed
	z_index = -1
	var size := layout.pixel_size()
	var panel := float(_tile * PANEL_TILES)
	_columns = ceili(size.x / panel)
	_rows = ceili(size.y / panel)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_holes.resize(_columns * _rows)
	for row in _rows:
		for col in _columns:
			var y := row * panel
			var hole := y > panel and y < size.y - panel * 2.0 and rng.randf() < HOLE_CHANCE
			_holes[row * _columns + col] = 1 if hole else 0
	_outdoor.resize(_columns)
	_facade_top.resize(_columns)
	_ground.resize(_columns)
	for col in _columns:
		var first := col * PANEL_TILES
		var covered := 0
		var ground := INF
		for x in range(first, mini(first + PANEL_TILES, layout.width)):
			covered += layout.covered_columns[x]
			ground = minf(ground, layout.surface_heights[x]) if layout.surface_heights[x] > 0.0 else ground
		_outdoor[col] = 1 if covered * 2 < PANEL_TILES else 0
		_ground[col] = ground if ground != INF else size.y
		# 立面高度以「每兩塊牆板一棟樓」變化。
		if col % 2 == 0:
			_facade_top[col] = _ground[col] - rng.randf_range(4.0, 9.0) * _tile
		else:
			_facade_top[col] = _facade_top[col - 1]
	build_chunks(Rect2(Vector2.ZERO, size))


func _draw_chunk(canvas: CanvasItem, rect: Rect2) -> void:
	var panel := float(_tile * PANEL_TILES)
	var first_col := int(rect.position.x / panel)
	var last_col := mini(int(ceil(rect.end.x / panel)), _columns)
	for col in range(first_col, last_col):
		if _outdoor[col] == 1:
			_draw_facade(canvas, col, rect)
		else:
			_draw_interior(canvas, col, rect)


func _draw_interior(canvas: CanvasItem, col: int, rect: Rect2) -> void:
	var panel := float(_tile * PANEL_TILES)
	for row in _rows:
		if _holes[row * _columns + col] == 1:
			continue
		var cell := Rect2(col * panel, row * panel, panel, panel).intersection(rect)
		if cell.size.x <= 0.0:
			continue
		canvas.draw_rect(cell, WALL_COLOR)
		canvas.draw_rect(cell, SEAM_COLOR, false, 1.0)
	var x := col * panel
	if col % (PILLAR_EVERY / PANEL_TILES) == 0 and x >= rect.position.x and x < rect.end.x:
		canvas.draw_rect(Rect2(x, rect.position.y, _tile, rect.size.y), PILLAR_COLOR)
		canvas.draw_line(Vector2(x + 2, rect.position.y), Vector2(x + 2, rect.end.y), SEAM_COLOR, 1.0)


## 街邊建築立面：店面玻璃（帶反光）、鐵捲門、冷氣機、招牌底座。
func _draw_facade(canvas: CanvasItem, col: int, rect: Rect2) -> void:
	var panel := float(_tile * PANEL_TILES)
	var left := col * panel
	var top := _facade_top[col]
	var ground := _ground[col]
	var body := Rect2(left, top, panel, ground - top).intersection(rect)
	if body.size.x <= 0.0 or body.size.y <= 0.0:
		return
	canvas.draw_rect(body, FACADE_COLOR)
	canvas.draw_line(Vector2(left, top), Vector2(left + panel, top), SEAM_COLOR, 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 31 + col
	var kind := rng.randi() % 3
	var door := Rect2(left + 8, ground - _tile * 2.5, panel - 16, _tile * 2.5)
	if kind == 0:
		# 店面玻璃
		canvas.draw_rect(door, GLASS_COLOR)
		canvas.draw_line(door.position + Vector2(4, 4), door.position + Vector2(14, 16), Color(1, 1, 1, 0.08), 2.0)
		canvas.draw_rect(door, SEAM_COLOR, false, 1.0)
	elif kind == 1:
		# 鐵捲門
		canvas.draw_rect(door, SHUTTER_COLOR)
		var y := door.position.y + 3.0
		while y < door.end.y:
			canvas.draw_line(Vector2(door.position.x, y), Vector2(door.end.x, y), Color("1a1e2b"), 1.0)
			y += 4.0
	# 上層窗戶與冷氣機
	var wy := top + 8.0
	while wy < door.position.y - 14.0:
		canvas.draw_rect(Rect2(left + 8, wy, panel - 16, 10), GLASS_COLOR)
		if rng.randf() < 0.4:
			canvas.draw_rect(Rect2(left + 10, wy + 2, panel - 20, 6), Color(rng.randf_range(0.5, 1.0), 0.75, 0.5, 0.12))
		if rng.randf() < 0.5:
			canvas.draw_rect(Rect2(left + panel - 22, wy + 11, 12, 7), SHUTTER_COLOR)
		wy += 24.0
