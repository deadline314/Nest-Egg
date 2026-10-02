class_name BackWall
extends ChunkedDrawer
## 室內背牆：位於地形後方、與光源同一圖層，因此會被燈光照亮並顯示地形投下的陰影。
## 部分牆板破損鏤空，可看到後方的視差背景，增加景深。採分塊繪製（見 ChunkedDrawer）。

const PANEL_TILES := 4
const PILLAR_EVERY := 12
const HOLE_CHANCE := 0.22
const WALL_COLOR := Color("1c2631")
const SEAM_COLOR := Color("222d39")
const PILLAR_COLOR := Color("1d2833")

var _tile := 16
var _seed := 1
var _holes := PackedByteArray()
var _columns := 0


func setup(layout: LevelLayout, p_seed := 1) -> void:
	_tile = layout.tile_size
	_seed = p_seed
	z_index = -1
	var size := layout.pixel_size()
	var panel := float(_tile * PANEL_TILES)
	_columns = ceili(size.x / panel)
	var rows := ceili(size.y / panel)
	# 預先決定鏤空位置（與區塊切法無關，畫面穩定）。
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_holes.resize(_columns * rows)
	for row in rows:
		for col in _columns:
			var y := row * panel
			var hole := y > panel and y < size.y - panel * 2.0 and rng.randf() < HOLE_CHANCE
			_holes[row * _columns + col] = 1 if hole else 0
	build_chunks(Rect2(Vector2.ZERO, size))


func _draw_chunk(canvas: CanvasItem, rect: Rect2) -> void:
	var panel := float(_tile * PANEL_TILES)
	var first_col := int(rect.position.x / panel)
	var last_col := int(ceil(rect.end.x / panel))
	var rows := ceili(rect.size.y / panel)
	for row in rows:
		for col in range(first_col, mini(last_col, _columns)):
			if _holes[row * _columns + col] == 1:
				continue
			var cell := Rect2(col * panel, row * panel, panel, panel).intersection(rect)
			if cell.size.x <= 0.0:
				continue
			canvas.draw_rect(cell, WALL_COLOR)
			canvas.draw_rect(cell, SEAM_COLOR, false, 1.0)
	var pillar_step := float(_tile * PILLAR_EVERY)
	var x := ceilf(rect.position.x / pillar_step) * pillar_step
	while x < rect.end.x:
		canvas.draw_rect(Rect2(x, rect.position.y, _tile, rect.size.y), PILLAR_COLOR)
		canvas.draw_line(Vector2(x + 2, rect.position.y), Vector2(x + 2, rect.end.y), SEAM_COLOR, 1.0)
		x += pillar_step
