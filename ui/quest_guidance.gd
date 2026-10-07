class_name QuestGuidance
extends Control
## 只讀故事旗標，探索取樣 5 Hz；關卡索引只在章節切換建立。

var catalog := QuestCatalog.new()
var maps := QuestMapIndex.new()
var state: QuestMapState
var level: Level
var _row: PanelContainer
var _label: Label
var _arrow: Label
var _time := 0.0
var _idle := 0.0
var _goal_key := ""
var _target: Dictionary = {}
var _sample_cell := Vector2i(-1, -1)
var _world_hash := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill_parent(self)
	level = get_parent().get_parent().get_parent() as Level
	if level == null:
		set_process(false)
		return
	state = QuestMapState.for_run()
	catalog.load_story_sources()
	maps = QuestMapIndex.for_chapter(level.data.chapter)
	_row = PanelContainer.new()
	_row.position = Vector2(145, 52)
	_row.size = Vector2(350, 24)
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_row.tooltip_text = "開啟任務目錄可以釘選目標，地圖會標出目的地。"
	_row.add_theme_stylebox_override(&"panel", UiTheme.tab_box(true))
	add_child(_row)
	_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_row.add_child(_label)
	_arrow = UiKit.label("", UiKit.FS_BODY, Palette.MAGENTA)
	_arrow.mouse_filter = Control.MOUSE_FILTER_PASS
	_arrow.tooltip_text = "依箭頭前往追蹤中的目標；跨區時先走向出口。"
	_arrow.add_theme_constant_override(&"outline_size", 3)
	_arrow.add_theme_color_override(&"font_outline_color", Color(0.01, 0.02, 0.04))
	add_child(_arrow)
	state.changed.connect(_refresh_target)
	EventBus.checkpoint_reached.connect(func(position: Vector2) -> void: state.activate(level.data.resource_path, position, level.data.tile_size))
	_refresh_target()


func _process(delta: float) -> void:
	if level == null or not is_instance_valid(level.player):
		return
	_time += delta
	_idle += delta
	if _time >= 0.2:
		_time = 0
		_sample()
		_refresh_target()
	_row.visible = _enabled("quest_objective") and not _target.is_empty() and not Story.is_cinematic_active()
	_row.modulate.a = 1.0 if _idle < 5 or not Settings.get_hud_auto_hide() else 0.4
	_update_arrow()


func _sample() -> void:
	var position := level.player.global_position + Vector2(0, -8)
	var cell := Vector2i(position / level.data.tile_size)
	var world := WorldState.capture(get_tree())
	var world_hash := hash(world)
	if cell != _sample_cell or world_hash != _world_hash:
		_sample_cell = cell
		_world_hash = world_hash
		state.reveal(level.data.resource_path, maps.visible_cells(level.data.resource_path, position, world))


func _refresh_target() -> void:
	_target = state.target(catalog, String(level.data.chapter), GameState.world_flags)
	var step := QuestCatalog.current_step(_target, GameState.world_flags)
	var key := str(step.get("complete_flag", "")) + state.pinned_id
	if key != _goal_key:
		_goal_key = key
		_idle = 0
		if not step.is_empty():
			EventBus.toast_requested.emit("接下來%s" % step["title"])
	if _label != null:
		_label.text = str(step.get("title", ""))


func _update_arrow() -> void:
	_arrow.visible = false
	if not _enabled("quest_arrows") or Story.is_cinematic_active():
		return
	var step := QuestCatalog.current_step(_target, GameState.world_flags)
	var location: Dictionary = step.get("location", {})
	if location.is_empty():
		return
	var path: String = location["level"]
	var position: Vector2
	var caption := ""
	if path == level.data.resource_path:
		var cell: Array = location["cell"]
		position = Vector2(cell[0] + 0.5, cell[1] + 1.0) * level.data.tile_size
	else:
		var exit := maps.next_exit(level.data.resource_path, path, GameState.world_flags)
		if exit.is_empty():
			return
		position = exit["position"]
		var target: LevelData = maps.areas[path]["data"]
		caption = "前往%s" % target.display_name
		_arrow.tooltip_text = maps.marker_text(exit, GameState.world_flags)
	var screen := level.get_viewport().get_canvas_transform() * position
	var bounds := Rect2(Vector2(18, 88), Vector2(604, 244))
	if bounds.has_point(screen) and path == level.data.resource_path:
		return
	var center := bounds.get_center()
	var direction := (screen - center).normalized()
	var scale := minf(bounds.size.x * 0.5 / maxf(absf(direction.x), 0.001), bounds.size.y * 0.5 / maxf(absf(direction.y), 0.001))
	var edge := center + direction * scale
	var symbols := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	_arrow.text = symbols[posmod(roundi(direction.angle() / (PI / 4)), 8)] + caption
	_arrow.position = Vector2(clampf(edge.x - _arrow.get_minimum_size().x * 0.5, 12, 628 - _arrow.get_minimum_size().x), clampf(edge.y, 88, 322))
	_arrow.visible = true


func _enabled(key: String) -> bool:
	var raw: Variant = Settings.get_value(Settings.DISPLAY_SECTION, key, true)
	return raw if raw is bool else true
