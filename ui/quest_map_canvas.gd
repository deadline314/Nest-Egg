class_name QuestMapCanvas
extends Control
## 靜態地圖貼圖按探索版本快取；標記是可聚焦按鈕，手把也能閱讀說明。
## 區域地圖：只畫已探索地形的邊（亮）與實心（暗），空中不填色；寬而矮的區域依高度放大並以主角（或目標）為中心，
## 底部附整區縮圖與目前視窗框；畫面外的出口與目標貼邊標出名稱。
## 世界地圖：依出入口在區域裡的方向（左右上下）排出相對位置，連線走直角。

signal marker_selected(text: String)
signal area_selected(path: String)
## 每次重建標記之後發出（畫面用來更新探索百分比等統計）。
signal refreshed
const SYMBOLS := {"player": "▲", "exit": "↔", "checkpoint": "◆", "shop": "＄", "pickup": "＋", "goal": "◎", "gate": "▣"}
const COLORS := {"player": Palette.CYAN, "exit": Palette.UI_TEXT, "checkpoint": Palette.NEON_YELLOW, "shop": Palette.NEON_YELLOW, "pickup": Palette.CYAN, "goal": Palette.MAGENTA, "gate": Palette.DANGER}
const EDGE := Color(0.37, 0.84, 0.93)
const ROCK := Color(0.07, 0.22, 0.27)
const PAD := 10.0
const MARKER := Vector2(12, 12)
## 區域地圖每格的最小與最大顯示尺寸：太小看不出地形，太大會把小房間撐滿整個畫面。
const MIN_CELL := 4.5
const MAX_CELL := 6.0
const OVERVIEW_H := 14.0
const WORLD_NODE := Vector2(104, 20)

var maps: QuestMapIndex
var state: QuestMapState
var path := ""
var player_path := ""
var player_position := Vector2.ZERO
var goal: Dictionary = {}
var flags: Dictionary = {}
var world: Dictionary = {}
var world_mode := false
var zoom := 1.0
var builds := 0
## 目前區域已探索的可通行格子比例（0～1），隨貼圖一起快取。
var explored_ratio := 0.0
var _cache: Dictionary = {}
var _texture: Texture2D
var _map_rect := Rect2()
var _view := Rect2()
var _overview := Rect2()
var _lines: Array[PackedVector2Array] = []
var _line_colors: PackedColorArray = []
var _markers: Array[Button] = []
var _labels: Array[Label] = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(refresh)


func refresh() -> void:
	if not is_inside_tree() or maps == null or state == null or size.x < 1 or size.y < 1:
		return
	for button in _markers:
		remove_child(button)
		button.queue_free()
	_markers.clear()
	for label in _labels:
		remove_child(label)
		label.queue_free()
	_labels.clear()
	_lines.clear()
	_line_colors.clear()
	_texture = null
	_overview = Rect2()
	if world_mode:
		_world_map()
	elif maps.areas.has(path):
		_region_map()
	queue_redraw()
	refreshed.emit()


# ---------------------------------------------------------------------------
# 區域地圖
# ---------------------------------------------------------------------------

func _region_map() -> void:
	var area: Dictionary = maps.areas[path]
	var layout: LevelLayout = area["layout"]
	var key := "%s:%d" % [path, state.revision]
	if not _cache.has(key):
		# 只保留目前畫面的貼圖，探索前進不會累積舊版本。
		_cache.clear()
		_cache[key] = _build_terrain(layout)
		builds += 1
	_texture = _cache[key]["texture"]
	explored_ratio = _cache[key]["ratio"]
	var cells := Vector2(layout.width, layout.height)
	var avail := size - Vector2(PAD, PAD) * 2
	var factor := _cell_size(cells, avail)
	if cells.x * factor > avail.x + 0.5:
		# 寬區域：底部留給整區縮圖，地圖再依剩下的高度放大。
		avail.y -= OVERVIEW_H + 4
		factor = _cell_size(cells, avail)
	_view = Rect2(Vector2(PAD, PAD), avail)
	var focus := cells * 0.5
	if path == player_path:
		focus = player_position / layout.tile_size
	elif goal.get("level", "") == path:
		var goal_cell: Array = goal.get("cell", [0, 0])
		focus = Vector2(goal_cell[0], goal_cell[1])
	var display := cells * factor
	var origin := _view.position + (avail - display) * 0.5
	if display.x > avail.x:
		origin.x = clampf(_view.get_center().x - focus.x * factor, _view.end.x - display.x, _view.position.x)
	if display.y > avail.y:
		origin.y = clampf(_view.get_center().y - focus.y * factor, _view.end.y - display.y, _view.position.y)
	_map_rect = Rect2(origin, display)
	if display.x > avail.x + 0.5:
		_overview = Rect2(PAD, size.y - PAD - OVERVIEW_H, avail.x, OVERVIEW_H)
	for marker: Dictionary in area["markers"]:
		var cell: Vector2i = marker["cell"]
		if not state.knows(path, cell) or marker["kind"] == "secret_wall":
			continue
		var kind := str(marker["kind"])
		var point: Vector2 = _map_rect.position + marker["position"] / layout.tile_size * factor
		var text := maps.marker_text(marker, flags)
		if kind == "gate":
			var resource := marker["resource"] as MechanismData
			var open: bool = world.get("gate@%d,%d" % [cell.x, cell.y], resource.arena_gate) == true
			if open:
				text = "這道閘門目前可以通行。"
				kind = "exit"
		var destination := _destination_name(marker) if kind == "exit" else ""
		if not _view.grow(1).has_point(point):
			if not destination.is_empty():
				_edge_label(point, destination, Palette.UI_TEXT)
			continue
		var button := _button(SYMBOLS.get(kind, "·"), text, point, MARKER, COLORS.get(kind, Palette.CYAN))
		button.pressed.connect(marker_selected.emit.bind(text))
		if not destination.is_empty():
			var arrow := "← %s" % destination if point.x < _view.get_center().x else "%s →" % destination
			_label(arrow, point + Vector2(0, -MARKER.y), Color("bfe9f5"))
	if path == player_path:
		_button("▲", "主角目前在這裡。", _map_rect.position + player_position / layout.tile_size * factor, MARKER, Palette.CYAN)
	if goal.get("level", "") == path:
		var cell: Array = goal.get("cell", [0, 0])
		var point := _map_rect.position + Vector2(cell[0] + 0.5, cell[1] + 1.0) * factor
		if _view.grow(1).has_point(point):
			_button("◎", "前往這裡完成追蹤中的步驟。", point, MARKER, Palette.MAGENTA)
		else:
			_edge_label(point, "◎ 目標", Palette.MAGENTA)


func _cell_size(cells: Vector2, avail: Vector2) -> float:
	var fit_h := avail.y / cells.y
	var fit_w := avail.x / cells.x
	return clampf(minf(fit_h, maxf(fit_w, MIN_CELL)), 0.5, MAX_CELL) * zoom


## 每格一個像素：已探索的實心格依是否鄰接空處分成亮邊與暗心；空中與未探索透明。
func _build_terrain(layout: LevelLayout) -> Dictionary:
	var image := Image.create(layout.width, layout.height, false, Image.FORMAT_RGBA8)
	var open_total := 0
	var open_known := 0
	for y in layout.height:
		for x in layout.width:
			var solid := _solid(layout, x, y)
			var known := state.knows(path, Vector2i(x, y))
			if not solid:
				open_total += 1
				if known:
					open_known += 1
				continue
			if not known:
				continue
			var edge := not _solid(layout, x - 1, y) or not _solid(layout, x + 1, y) or not _solid(layout, x, y - 1) or not _solid(layout, x, y + 1)
			image.set_pixel(x, y, EDGE if edge else ROCK)
	return {"texture": ImageTexture.create_from_image(image), "ratio": float(open_known) / maxf(1.0, float(open_total))}


static func _solid(layout: LevelLayout, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= layout.width or y >= layout.height:
		return true
	var terrain := layout.cell(x, y)
	return terrain == "#" or terrain == "="


func _destination_name(marker: Dictionary) -> String:
	var portal := marker.get("resource") as PortalData
	if portal == null or not maps.areas.has(portal.target_level):
		return ""
	return (maps.areas[portal.target_level]["data"] as LevelData).display_name


## 畫面外的出口或目標：貼在視窗左右邊緣，寫出名稱與方向。
func _edge_label(point: Vector2, text: String, color: Color) -> void:
	var left := point.x < _view.get_center().x
	var label := _label("◀ " + text if left else text + " ▶", Vector2.ZERO, color)
	var width := label.get_minimum_size().x
	label.position = Vector2(_view.position.x + 2 if left else _view.end.x - width - 2, clampf(point.y, _view.position.y + 8, _view.end.y - 8) - label.get_minimum_size().y * 0.5)


# ---------------------------------------------------------------------------
# 世界地圖
# ---------------------------------------------------------------------------

func _world_map() -> void:
	var grid := _world_grid()
	if grid.is_empty():
		return
	var avail := size - Vector2(PAD, PAD) * 2
	# 一欄至少要放得下最長的區域名稱；橫向放不下時把整張圖折成幾列（蛇形，相鄰區域仍靠在一起）。
	var name_width := 0.0
	for level_path: String in grid:
		var data: LevelData = maps.areas[level_path]["data"]
		name_width = maxf(name_width, UiKit.font().get_string_size("▲ %s ◆" % data.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.caption_size()).x)
	var column_width := minf(name_width + 14.0, WORLD_NODE.x) + 8.0
	grid = _fold_grid(grid, maxi(1, floori(avail.x / column_width)))
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for cell: Vector2i in grid.values():
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var span := Vector2(hi - lo) + Vector2.ONE
	var step := Vector2(avail.x / span.x, minf(avail.y / span.y, WORLD_NODE.y * 2.4))
	var top := PAD + (avail.y - step.y * span.y) * 0.5
	var node := Vector2(minf(WORLD_NODE.x, step.x - 8), WORLD_NODE.y)
	var centers: Dictionary = {}
	for level_path: String in grid:
		centers[level_path] = Vector2(PAD, top) + (Vector2(grid[level_path] - lo) + Vector2(0.5, 0.5)) * step
	var drawn: Dictionary = {}
	for level_path: String in centers:
		for edge in maps.edges(level_path):
			var target: String = edge["resource"].target_level
			var pair := [level_path, target]
			pair.sort()
			if not centers.has(target) or drawn.has(str(pair)):
				continue
			drawn[str(pair)] = true
			var a: Vector2 = centers[level_path]
			var b: Vector2 = centers[target]
			# 直角連線：先水平再垂直，避免斜線交叉。
			_lines.append(PackedVector2Array([a, Vector2(b.x, a.y), b]))
			var known := state.explored.has(level_path) and state.explored.has(target)
			_line_colors.append(Color(Palette.CYAN_DIM, 0.85) if known else Color(Palette.UI_LINE_OFF, 0.9))
	for level_path: String in centers:
		var data: LevelData = maps.areas[level_path]["data"]
		var known: bool = state.explored.has(level_path)
		var current := level_path == player_path
		var target: bool = goal.get("level", "") == level_path
		var activated_here := false
		for key: String in state.activated:
			if key.begins_with(level_path + "@"):
				activated_here = true
		var label := ("▲ " if current else "◎ " if target else "") + data.display_name + (" ◆" if activated_here else "")
		var tooltip := "前往%s的區域地圖。%s%s" % [data.display_name, "你已經探索過這裡。" if known else "這裡尚未探索。", "已啟用復原點；目前沒有傳送功能。" if activated_here else ""]
		var accent := Palette.MAGENTA if target else Palette.CYAN if current or known else Palette.UI_MUTED
		var button := _button(label, tooltip, centers[level_path], node, accent)
		_world_node_style(button, current, target, known)
		button.pressed.connect(area_selected.emit.bind(level_path))


## 依出入口在區域裡的位置推算相對方向：靠左、靠右的出口往左右放，中段的出口依高低往上下放。
## 位置衝突時沿同方向往外找空格；沒有連到的區域排在最右側。只在開地圖時計算一次。
func _world_grid() -> Dictionary:
	var paths: Array = maps.areas.keys()
	paths.sort()
	if paths.is_empty():
		return {}
	var grid: Dictionary = {}
	var taken: Dictionary = {}
	var start: String = player_path if maps.areas.has(player_path) else paths[0]
	var queue: Array[String] = []
	for root: String in [start] + paths:
		if grid.has(root):
			continue
		var origin := Vector2i(0, 0)
		if not taken.is_empty():
			var right := 0
			for cell: Vector2i in taken:
				right = maxi(right, cell.x)
			origin = Vector2i(right + 1, 0)
		grid[root] = origin
		taken[origin] = root
		queue.append(root)
		while not queue.is_empty():
			var current: String = queue.pop_front()
			for edge in maps.edges(current):
				var target: String = edge["resource"].target_level
				if grid.has(target) or not maps.areas.has(target):
					continue
				var direction := _edge_direction(current, edge)
				var cell: Vector2i = grid[current] + direction
				var tries := 0
				while taken.has(cell) and tries < 8:
					tries += 1
					cell = grid[current] + direction * (tries + 1) if tries < 4 else grid[current] + direction + Vector2i(direction.y, direction.x) * (tries - 3)
				grid[target] = cell
				taken[cell] = target
				queue.append(target)
	return grid


## 欄數超過 columns 時，依欄分段往下折：第二段從右往左排，第三段再從左往右（蛇形），段與段之間空一列。
static func _fold_grid(grid: Dictionary, columns: int) -> Dictionary:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for cell: Vector2i in grid.values():
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	if hi.x - lo.x + 1 <= columns:
		return grid
	var band_height := hi.y - lo.y + 2
	var folded: Dictionary = {}
	for key: String in grid:
		var cell: Vector2i = grid[key] - lo
		var band := cell.x / columns
		var column := cell.x % columns
		if band % 2 == 1:
			column = columns - 1 - column
		folded[key] = Vector2i(column, cell.y + band * band_height)
	return folded


func _edge_direction(level_path: String, edge: Dictionary) -> Vector2i:
	var layout: LevelLayout = maps.areas[level_path]["layout"]
	var tile: float = maxf(1.0, float(layout.tile_size))
	var position: Vector2 = edge["position"] / tile
	var x := position.x / maxf(1.0, float(layout.width))
	if x < 0.3:
		return Vector2i.LEFT
	if x > 0.7:
		return Vector2i.RIGHT
	return Vector2i.UP if position.y / maxf(1.0, float(layout.height)) < 0.5 else Vector2i.DOWN


func _world_node_style(button: Button, current: bool, target: bool, known: bool) -> void:
	FlatStyle.row(button, target)
	var normal := StyleBoxFlat.new()
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.bg_color = FlatStyle.ROW_INVERTED_BG if current else Color(0.05, 0.09, 0.12, 0.95)
	normal.set_border_width_all(1)
	normal.border_color = Palette.MAGENTA if target else Color(Palette.CYAN_DIM, 0.8) if known else Palette.UI_LINE_OFF
	for state_name in [&"normal", &"pressed"]:
		button.add_theme_stylebox_override(state_name, normal)
	button.add_theme_color_override(&"font_color", FlatStyle.ROW_INVERTED_TEXT if current else Palette.MAGENTA if target else Palette.UI_TEXT if known else Palette.UI_MUTED)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.set_text_role(button, &"caption")


# ---------------------------------------------------------------------------
# 共用
# ---------------------------------------------------------------------------

func _label(text: String, center: Vector2, color: Color) -> Label:
	var label := UiKit.caption(text, color)
	label.add_theme_constant_override(&"outline_size", 3)
	label.add_theme_color_override(&"font_outline_color", Color(0.01, 0.02, 0.035))
	add_child(label)
	var dimensions := label.get_minimum_size()
	label.position = center - Vector2(dimensions.x * 0.5, dimensions.y)
	_labels.append(label)
	return label


func _button(label: String, tip: String, center: Vector2, dimensions: Vector2, accent: Color) -> Button:
	var button := UiKit.button(label, Callable(), tip)
	button.add_theme_color_override(&"font_color", accent)
	if dimensions.x < 20:
		for state_name in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.02, 0.05, 0.08, 0.92)
			style.set_content_margin_all(0)
			style.set_border_width_all(1 if state_name == "focus" or state_name == "hover" else 0)
			style.border_color = accent
			button.add_theme_stylebox_override(state_name, style)
		UiKit.set_text_role(button, &"caption")
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.position = center - dimensions * 0.5
	button.custom_minimum_size = dimensions
	button.size = dimensions
	# 聚焦時也顯示 tooltip 的同一句話，無需滑鼠。
	button.focus_entered.connect(marker_selected.emit.bind(tip))
	button.mouse_entered.connect(marker_selected.emit.bind(tip))
	add_child(button)
	_fit_marker.call_deferred(button, center, dimensions)
	_markers.append(button)
	return button


func _fit_marker(button: Button, center: Vector2, dimensions: Vector2) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	# 主題的最小尺寸更新會延後；在更新後縮回圖示尺寸，避免沿用 180px 按鈕互相遮住。
	button.reset_size()
	button.size = dimensions
	button.position = center - button.size * 0.5


func _draw() -> void:
	for i in _lines.size():
		draw_polyline(_lines[i], _line_colors[i] if i < _line_colors.size() else Color(Palette.CYAN_DIM, 0.7), 1)
	if _texture == null:
		return
	# 區域外框：未探索的地方只看得到範圍，不洩漏地形與秘密。
	draw_rect(_map_rect, Color(Palette.CYAN_DIM, 0.35), false, 1)
	draw_texture_rect(_texture, _map_rect, false)
	if _overview.has_area():
		# 整區縮圖與目前視窗框：寬區域一眼看到全貌、主角與目標的相對位置。
		draw_rect(_overview, Color(0.0, 0.015, 0.03, 0.95))
		draw_texture_rect(_texture, _overview, false, Color(1, 1, 1, 0.8))
		var scale_x := _overview.size.x / maxf(1.0, _map_rect.size.x)
		var window := Rect2(_overview.position.x + (_view.position.x - _map_rect.position.x) * scale_x, _overview.position.y - 1, _view.size.x * scale_x, _overview.size.y + 2)
		draw_rect(window, Color(Palette.UI_TEXT, 0.7), false, 1)
