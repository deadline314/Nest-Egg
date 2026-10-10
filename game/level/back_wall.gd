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
## 背牆（含上面的窗光）整體比可玩層暗一階、略偏冷：角色、敵人與可走的地面才會從牆面前跳出來。
const RECEDE_TINT := Color(1.22, 1.22, 1.3)
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
## 環境主題（建築立面、室內牆面）；null 代表沿用程式繪製。
var _theme: EnvironmentTheme
## 每一欄的立面模組（由下往上）：{ "rect": Rect2, "path": String }。只在有立面主題時使用。
var _col_modules: Array[Array] = []
var geometry := BackWallGeometry.new()


func setup(layout: LevelLayout, p_seed := 1, theme: EnvironmentTheme = null) -> void:
	_tile = layout.tile_size
	_seed = p_seed
	_theme = theme
	z_index = WorldLayers.BACK_WALL
	modulate = RECEDE_TINT
	var size := layout.pixel_size()
	geometry.setup(layout, p_seed, theme)
	_columns = geometry.columns
	_rows = geometry.rows
	_holes = geometry.holes
	_outdoor = geometry.outdoor
	_facade_top = geometry.facade_top
	_ground = geometry.ground
	_col_modules = geometry.modules
	build_chunks(Rect2(Vector2.ZERO, size))
	if not _col_modules.is_empty():
		var glow := _FacadeGlow.new()
		glow.name = "FacadeGlow"
		glow.walls = self
		add_child(glow)
		glow.build_chunks(Rect2(Vector2.ZERO, size))


func _zone_of_col(col: int) -> EnvZone:
	return _theme.zone_at(col * PANEL_TILES) if _theme != null else null


func _hole_chance(col: int) -> float:
	var zone := _zone_of_col(col)
	return zone.hole_chance if zone != null else HOLE_CHANCE


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
	var zone := _zone_of_col(col)
	var texture: Texture2D = null
	if zone != null and not zone.interior.is_empty():
		texture = LitTextures.load_texture(zone.interior, Vector2i(256, 256))
	for row in _rows:
		if _holes[row * _columns + col] == 1:
			continue
		var cell := Rect2(col * panel, row * panel, panel, panel).intersection(rect)
		if cell.size.x <= 0.0:
			continue
		if texture != null:
			var texture_scale := float(zone.interior_scale)
			canvas.draw_texture_rect_region(texture, cell, Rect2(cell.position * texture_scale, cell.size * texture_scale))
			continue
		canvas.draw_rect(cell, WALL_COLOR)
		canvas.draw_rect(cell, SEAM_COLOR, false, 1.0)
	var x := col * panel
	if col % (PILLAR_EVERY / PANEL_TILES) == 0 and x >= rect.position.x and x < rect.end.x:
		canvas.draw_rect(Rect2(x, rect.position.y, _tile, rect.size.y), PILLAR_COLOR)
		canvas.draw_line(Vector2(x + 2, rect.position.y), Vector2(x + 2, rect.end.y), SEAM_COLOR, 1.0)


## 街邊建築立面：店面玻璃（帶反光）、鐵捲門、冷氣機、招牌底座。
func _draw_facade(canvas: CanvasItem, col: int, rect: Rect2) -> void:
	if col < _col_modules.size() and not _col_modules[col].is_empty():
		for module: Dictionary in _col_modules[col]:
			var area: Rect2 = module["rect"]
			if area.intersects(rect):
				var texture := LitTextures.load_texture(str(module["path"]), Vector2i(area.size) * 4)
				canvas.draw_texture_rect(texture, area, false)
		return
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


## 立面的自發光層（窗光、霓虹）：自發光材質，不受環境光壓暗。
class _FacadeGlow:
	extends ChunkedDrawer

	var walls: BackWall

	func _init() -> void:
		chunk_material = LightKit.window_life_material()

	func _draw_chunk(canvas: CanvasItem, rect: Rect2) -> void:
		for modules: Array in walls._col_modules:
			for module: Dictionary in modules:
				var area: Rect2 = module["rect"]
				if not area.intersects(rect):
					continue
				var glow := RigLibrary.optional_texture(FacadeData.glow_path(str(module["path"])))
				if glow != null:
					canvas.draw_texture_rect(glow, area, false, LightKit.glow(Color.WHITE, 1.25))
