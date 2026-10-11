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
## 每一段立面要往下蓋到哪裡（世界 y）：這一段裡最低的空格底緣。有裂縫、下一層或懸空平台底下的空間時會比 ground 低。
var deep := PackedFloat32Array()
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
	var follow_platforms := theme != null and theme.facades_follow_platforms
	outdoor.resize(columns)
	facade_top.resize(columns)
	ground.resize(columns)
	deep.resize(columns)
	modules.resize(columns)
	support_rects.clear()
	for col in columns:
		var covered := 0
		var surface := INF
		for x in range(col * PANEL_TILES, mini((col + 1) * PANEL_TILES, layout.width)):
			covered += layout.covered_columns[x]
			# 建築站在實心地面上：單向平台是架在樓前的走道，不能把整棟樓墊到半空中（舊主題保留跟著平台長高的規則）。
			var top := layout.surface_heights[x] if follow_platforms else _solid_top(layout, x)
			if top > 0.0:
				surface = minf(surface, top)
		outdoor[col] = 1 if covered * 2 < PANEL_TILES else 0
		ground[col] = surface if surface != INF else size.y
		deep[col] = maxf(ground[col], _lowest_open_bottom(layout, col * PANEL_TILES, mini((col + 1) * PANEL_TILES, layout.width)))
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
			support_rects.append(Rect2(left, facade_top[col], panel, deep[col] - facade_top[col]))
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
			# 地面以下還有看得到的空間（屋頂的裂縫、下一層、平台底下）：同一棟樓往下多蓋幾層標準樓層，
			# 從縫裡看到的是這棟樓的牆，不是遠景。實心地形會蓋住多畫的部分。
			var below := ground[col]
			var lower_floor := 0
			while below < deep[col] - 0.5:
				parts.append({"rect": Rect2(left, below, panel, FacadeData.BODY_HEIGHT),
						"path": FacadeData.pick(facade.body, key + 101 + lower_floor * 3 + col % 2)})
				below += FacadeData.BODY_HEIGHT
				lower_floor += 1
			modules[col] = parts
			for part in parts:
				support_rects.append(_opaque_wall_rect(part))


## 第 x 欄最上面那個實心格的頂面（世界 y）；整欄沒有實心格回傳 INF。
static func _solid_top(layout: LevelLayout, x: int) -> float:
	for y in layout.height:
		if layout.cell(x, y) == LevelBuilder.SOLID:
			return float(y * layout.tile_size)
	return INF


## 第 from～to 欄（不含 to）裡最低的空格底緣（世界 y）；整段都是實心就回傳 0。
static func _lowest_open_bottom(layout: LevelLayout, from: int, to: int) -> float:
	var lowest := 0
	for x in range(from, to):
		for y in range(layout.height - 1, -1, -1):
			if layout.cell(x, y) != LevelBuilder.SOLID:
				lowest = maxi(lowest, y + 1)
				break
	return float(lowest * layout.tile_size)


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
