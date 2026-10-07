class_name QuestMapCanvas
extends Control
## 靜態地圖貼圖按探索版本快取；標記是可聚焦按鈕，手把也能閱讀說明。

signal marker_selected(text: String)
signal area_selected(path: String)
const SYMBOLS := {"player": "▲", "exit": "↔", "checkpoint": "◆", "shop": "＄", "pickup": "＋", "goal": "◎", "gate": "▣"}
const COLORS := {"player": Palette.CYAN, "exit": Palette.UI_TEXT, "checkpoint": Palette.NEON_YELLOW, "shop": Palette.NEON_YELLOW, "pickup": Palette.CYAN, "goal": Palette.MAGENTA, "gate": Palette.DANGER}
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
var _cache: Dictionary = {}
var _texture: Texture2D
var _map_rect := Rect2()
var _lines: Array[PackedVector2Array] = []
var _markers: Array[Button] = []


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
	_lines.clear()
	_texture = null
	if world_mode:
		_world_map()
	elif maps.areas.has(path):
		_region_map()
	queue_redraw()


func _region_map() -> void:
	var area: Dictionary = maps.areas[path]
	var layout: LevelLayout = area["layout"]
	var key := "%s:%d" % [path, state.revision]
	if not _cache.has(key):
		# 只保留目前畫面的貼圖，探索前進不會累積舊版本。
		_cache.clear()
		var image := Image.create(layout.width, layout.height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.04, 0.08, 0.12))
		for y in layout.height:
			for x in layout.width:
				if not state.knows(path, Vector2i(x, y)):
					continue
				var terrain := layout.cell(x, y)
				image.set_pixel(x, y, Color(0.24, 0.52, 0.61) if terrain == "#" or terrain == "=" else Color(0.08, 0.18, 0.24))
		_cache[key] = ImageTexture.create_from_image(image)
		builds += 1
	_texture = _cache[key]
	var factor := minf((size.x - 24) / layout.width, (size.y - 24) / layout.height) * zoom
	var display_size := Vector2(layout.width, layout.height) * factor
	var center := Vector2(layout.width, layout.height) * 0.5
	if zoom > 1 and path == player_path:
		center = player_position / layout.tile_size
	_map_rect = Rect2(size * 0.5 - center * factor, display_size)
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
		var button := _button(SYMBOLS.get(kind, "·"), text, point, Vector2(14, 14), COLORS.get(kind, Palette.CYAN))
		button.pressed.connect(marker_selected.emit.bind(text))
	if path == player_path:
		_button("▲", "主角目前在這裡。", _map_rect.position + player_position / layout.tile_size * factor, Vector2(14, 14), Palette.CYAN)
	if goal.get("level", "") == path:
		var cell: Array = goal.get("cell", [0, 0])
		_button("◎", "前往這裡完成追蹤中的步驟。", _map_rect.position + Vector2(cell[0] + 0.5, cell[1] + 1.0) * factor, Vector2(14, 14), Palette.MAGENTA)


func _world_map() -> void:
	var paths: Array = maps.areas.keys()
	paths.sort()
	var centers: Dictionary = {}
	var cols := 3
	var rows := ceili(float(paths.size()) / cols)
	var span := Vector2((size.x - 32) / cols, (size.y - 24) / maxi(1, rows))
	for i in paths.size():
		var level_path: String = paths[i]
		var data: LevelData = maps.areas[level_path]["data"]
		var position := Vector2(16, 12) + span * Vector2(i % cols + 0.5, i / cols + 0.5)
		centers[level_path] = position
		var known: bool = state.explored.has(level_path)
		var current := level_path == player_path
		var target: bool = goal.get("level", "") == level_path
		var label := ("▲ " if current else "◎ " if target else "") + data.display_name
		var activated_here := false
		for key: String in state.activated:
			if key.begins_with(level_path + "@"):
				activated_here = true
		if activated_here:
			label += " ◆"
		var tooltip := "前往%s的區域地圖。%s%s" % [data.display_name, "你已經探索過這裡。" if known else "這裡尚未探索。", "已啟用復原點；目前沒有傳送功能。" if activated_here else ""]
		var button := _button(label, tooltip, position, Vector2(minf(168, span.x - 12), 30), Palette.MAGENTA if target else Palette.CYAN if current or known else Palette.UI_MUTED)
		button.pressed.connect(area_selected.emit.bind(level_path))
	for level_path: String in paths:
		for edge in maps.edges(level_path):
			var target: String = edge["resource"].target_level
			_lines.append(PackedVector2Array([centers[level_path], centers[target]]))


func _button(label: String, tip: String, center: Vector2, dimensions: Vector2, accent: Color) -> Button:
	var button := UiKit.button(label, Callable(), tip)
	button.add_theme_color_override(&"font_color", accent)
	if dimensions.x < 20:
		for state_name in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.02, 0.05, 0.08, 0.98)
			style.set_content_margin_all(1)
			style.set_border_width_all(1 if state_name == "focus" or state_name == "hover" else 0)
			style.border_color = accent
			button.add_theme_stylebox_override(state_name, style)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.065))
	for line in _lines:
		draw_polyline(line, Color(Palette.CYAN_DIM, 0.7), 1)
	if _texture != null:
		draw_texture_rect(_texture, _map_rect, false)
		draw_rect(_map_rect, Palette.CYAN_DIM, false, 1)
