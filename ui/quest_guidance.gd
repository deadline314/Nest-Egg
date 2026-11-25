class_name QuestGuidance
extends Control
## 只讀故事旗標，探索取樣 5 Hz；關卡索引只在章節切換建立。

var catalog: QuestCatalog
var maps := QuestMapIndex.new()
var state: QuestMapState
var level: Level
const SYMBOLS := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
const COPY := {
	"zh": {"target": "在任務目錄釘選目標，地圖會標出目的地。", "route": "前往%s",
		"main": "主線任務", "side": "支線任務", "pinned": "已釘選"},
	"ja": {"target": "クエストをピン留めすると地図に目的地が表示されます。", "route": " %sへ",
		"main": "メインクエスト", "side": "サブクエスト", "pinned": "ピン留め"},
	"en": {"target": "Pin a quest to mark its destination on the map.", "route": " To %s",
		"main": "Main objective", "side": "Side objective", "pinned": "Pinned objective"},
}
const TRACKER_WIDTH := 208.0
const TRACKER_POSITION := Vector2(12, 28)
const FRAMING_MARGIN := 8.0
const REVEAL_TIME := 0.16
## 武器欄右緣（640×360 設計座標）；方向箭頭在這個範圍內時不壓到武器欄。
const WEAPON_BAR_RIGHT := 160.0
## 目標列恢復顯示時的淡入時間（秒）。
const YIELD_FADE := 0.15

## 目前是否讓位給閱讀或戰鬥資訊（測試與工具讀它）。
var yielding := false
var _row: ObjectiveRow
var _label: Label
var _pulse: Tween
var _arrow_obstacles: Array[Rect2] = []
var _route_from := ""
var _route_to := ""
var _route_flags: Dictionary = {}
var _route_exit: Dictionary = {}
var _route_valid := false
var _arrow: Label
var _time := 0.0
var _idle := 0.0
var _goal_key := ""
var _target: Dictionary = {}
var _sample_cell := Vector2i(-1, -1)
var _world_hash := 0
var _framing_bottom := INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 暫停時也要跑：讀通訊或暫停時關掉這列的滑鼠提示，免得說明框蓋住通訊（NE-246）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Observe world text after its process callbacks, before this frame is drawn.
	process_priority = 100
	UiKit.fill_parent(self)
	level = get_parent().get_parent().get_parent() as Level
	if level == null:
		set_process(false)
		return
	state = QuestMapState.for_run()
	maps = QuestMapIndex.for_guidance(level.data.chapter)
	if catalog == null:
		catalog = state.catalog_for_chapter(level.data.chapter, maps)
	_row = ObjectiveRow.new()
	_row.position = TRACKER_POSITION
	_row.custom_minimum_size = Vector2(TRACKER_WIDTH, 0)
	_row.tooltip_text = _text("target")
	add_child(_row)
	PromptLayout.add_obstacle(_row, row_world_rect)
	_label = _row.label
	_arrow = UiKit.label("", UiKit.FS_CAPTION, Palette.UI_TEXT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_PASS
	var route_plate := StyleBoxFlat.new()
	route_plate.bg_color = Color(UiTheme.PANEL_BODY, 0.95)
	route_plate.border_color = Color(Palette.MAGENTA, 0.65)
	route_plate.border_width_left = 1
	route_plate.content_margin_left = 5
	route_plate.content_margin_right = 5
	route_plate.content_margin_top = 2
	route_plate.content_margin_bottom = 2
	_arrow.add_theme_stylebox_override(&"normal", route_plate)
	add_child(_arrow)
	Story.framing.safe_rect_changed.connect(_layout_framing)
	_layout_framing(Story.framing.safe_rect())
	state.changed.connect(_refresh_target)
	GameState.flag_changed.connect(_on_route_flag_changed)
	Settings.display_changed.connect(_apply_motion_preference)
	EventBus.checkpoint_reached.connect(func(position: Vector2) -> void: state.activate(level.data.resource_path, position, level.data.tile_size))
	_refresh_target()
	EventBus.radio_visibility_changed.connect(_on_radio_visibility_changed)
	_on_radio_visibility_changed()


func _layout_framing(rect: Rect2) -> void:
	_row.position.y = maxf(TRACKER_POSITION.y, rect.position.y + FRAMING_MARGIN)
	_framing_bottom = rect.end.y - FRAMING_MARGIN if rect.position.y > 0.0 else INF


func _process(delta: float) -> void:
	if level == null or not is_instance_valid(level.player):
		return
	if Story.is_cinematic_active():
		_row.hide()
		_arrow.hide()
		_set_pointer_covered(true)
		return
	if get_tree().paused:
		_set_pointer_covered(true)
		return
	var radio := DialogueLayer.radio_visible()
	_time += delta
	if not radio:
		_idle += delta
	if _time >= 0.2:
		_time = 0
		sample_exploration()
		_refresh_target()
	_row.visible = _enabled("quest_objective") and not _target.is_empty() and not radio
	if radio:
		_arrow.hide()
		_set_pointer_covered(true)
		return
	# 閱讀與戰鬥資訊立刻取得顯示優先權，任務欄回來時才淡入。
	var row_rect := row_world_rect()
	yielding = row_rect.has_area() and (PromptLayout.covers(row_rect) or _combat_hud_intersects(row_rect))
	_set_pointer_covered(DialogueLayer.radio_visible() or yielding)
	var target_alpha := 0.0 if yielding else (1.0 if _idle < 5 or not Settings.get_hud_auto_hide() else 0.4)
	_row.modulate.a = target_alpha if yielding or Settings.get_reduce_ui_motion() else move_toward(_row.modulate.a, target_alpha, delta / YIELD_FADE)
	_update_arrow()


## Visibility handoff is synchronous: frozen worlds skip ordinary HUD callbacks.
func _on_radio_visibility_changed() -> void:
	if _row == null or not is_inside_tree():
		return
	var covered := DialogueLayer.radio_visible()
	_row.visible = not covered and not get_tree().paused and _enabled("quest_objective") and not _target.is_empty() and not Story.is_cinematic_active()
	if covered:
		yielding = true
		_arrow.hide()
	_set_pointer_covered(covered or get_tree().paused or yielding)


func _set_pointer_covered(covered: bool) -> void:
	var filter := Control.MOUSE_FILTER_IGNORE if covered else Control.MOUSE_FILTER_PASS
	if _row.mouse_filter != filter:
		_row.mouse_filter = filter
		_arrow.mouse_filter = filter


## 目標列目前在世界座標的範圍（和世界提示比對用）；沒顯示時回傳空矩形。
func row_world_rect() -> Rect2:
	if _row == null or not _row.is_visible_in_tree() or level == null:
		return Rect2()
	return get_viewport().get_canvas_transform().affine_inverse() * _row.get_global_rect().grow(2.0)


func _combat_hud_intersects(row_rect: Rect2) -> bool:
	var hud := level.hud
	return row_rect.intersects(hud.vitals_tag.prompt_obstacle_rect()) \
		or row_rect.intersects(hud.ammo_tray.prompt_obstacle_rect())


## Run once the level is ready, then at the normal exploration cadence.
func sample_exploration() -> void:
	var path := level.data.resource_path
	if not maps.areas.has(path):
		return
	var position := level.player.global_position + Vector2(0, -8)
	var cell := Vector2i(position / level.data.tile_size)
	var world := WorldState.capture(get_tree())
	var world_hash := hash(world)
	if cell != _sample_cell or world_hash != _world_hash:
		_sample_cell = cell
		_world_hash = world_hash
		state.reveal(path, maps.visible_cells(path, position, world))


func _refresh_target() -> void:
	# Restores may replace the flag table without notifying each individual key.
	if _route_valid and GameState.world_flags != _route_flags:
		_route_valid = false
	_target = state.target(catalog, String(level.data.chapter), GameState.world_flags)
	var step := QuestCatalog.current_step(_target, GameState.world_flags)
	var quest_id := str(_target.get("id", ""))
	var pinned := not quest_id.is_empty() and quest_id == state.pinned_id
	var key := "%s/%s/%s" % [quest_id, step.get("complete_flag", ""), pinned]
	if key != _goal_key:
		_goal_key = key
		_idle = 0
		if not step.is_empty():
			_pulse_row.call_deferred()
	if _label != null:
		var objective := QuestCatalog.display_text(step, "title") if not step.is_empty() else ""
		if _label.text != objective:
			_label.text = objective
		var note := _text("target")
		var hover := objective + "\n\n" + note if not objective.is_empty() else note
		if _row.tooltip_text != hover:
			_row.tooltip_text = hover
		var category := "pinned" if pinned else str(_target.get("kind", "main"))
		_row.set_category(_text(category), Palette.MAGENTA if pinned else Palette.CYAN)


## Only the contents and accent animate, inside a fixed reading rectangle.
func _pulse_row() -> void:
	if _row == null or not _row.is_inside_tree():
		return
	_stop_reveal()
	if yielding or Settings.get_reduce_ui_motion():
		return
	_row.reveal = 0.0
	_pulse = create_tween()
	_pulse.tween_property(_row, "reveal", 1.0, REVEAL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _stop_reveal() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	_row.reveal = 1.0


func _apply_motion_preference() -> void:
	if Settings.get_reduce_ui_motion():
		_stop_reveal()


func _on_route_flag_changed(_flag: StringName, _value: Variant) -> void:
	_route_valid = false


func _first_exit(path: String) -> Dictionary:
	var from := level.data.resource_path
	if not _route_valid or _route_from != from or _route_to != path:
		_route_from = from
		_route_to = path
		_route_flags = GameState.world_flags.duplicate()
		_route_exit = maps.next_exit(from, path, _route_flags)
		_route_valid = true
	return _route_exit


func _update_arrow() -> void:
	_arrow.visible = _place_arrow()


func _place_arrow() -> bool:
	if not _enabled("quest_arrows") or Story.is_cinematic_active():
		return false
	var step := QuestCatalog.current_step(_target, GameState.world_flags)
	var location: Dictionary = step.get("location", {})
	if location.is_empty():
		return false
	var path: String = location["level"]
	var position: Vector2
	var caption := ""
	var hint: String
	if path == level.data.resource_path:
		var cell: Array = location["cell"]
		position = Vector2(cell[0] + 0.5, cell[1] + 1.0) * level.data.tile_size
		hint = QuestCatalog.display_text(step, "title")
	else:
		var exit := _first_exit(path)
		if exit.is_empty():
			return false
		position = exit["position"]
		var target: LevelData = maps.areas[path]["data"]
		caption = _text("route") % target.display_name_for(Story.language)
		hint = maps.marker_text(exit, GameState.world_flags, Story.language)
	var screen := level.get_viewport().get_canvas_transform() * position
	var bounds := Rect2(Vector2(18, 88), Vector2(604, 244))
	if bounds.has_point(screen) and path == level.data.resource_path:
		return false
	var center := bounds.get_center()
	var direction := (screen - center).normalized()
	var scale := minf(bounds.size.x * 0.5 / maxf(absf(direction.x), 0.001), bounds.size.y * 0.5 / maxf(absf(direction.y), 0.001))
	var edge := center + direction * scale
	var caption_text: String = SYMBOLS[posmod(roundi(direction.angle() / (PI / 4)), 8)] + caption
	# A shifted caption yields at its last displayed position, too.
	var previous_rect := (get_viewport().get_canvas_transform().affine_inverse() * _arrow.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, _arrow.size.max(_arrow.get_minimum_size()))
	if _arrow.text == caption_text and PromptLayout.covers(previous_rect.grow(2.0)):
		return false
	if _arrow.text != caption_text:
		_arrow.text = caption_text
	if _arrow.tooltip_text != hint:
		_arrow.tooltip_text = hint
	var extent := _arrow.get_combined_minimum_size()
	if not _arrow.size.is_equal_approx(extent):
		_arrow.size = extent
	# 左下角是武器欄與彈藥，箭頭靠左時不往下壓到它們。
	var bottom := 240.0 if edge.x < WEAPON_BAR_RIGHT else 322.0
	bottom = minf(bottom, _framing_bottom - extent.y)
	if bottom < 88.0:
		return false
	var origin := Vector2(clampf(edge.x - extent.x * 0.5, 12, 628 - extent.x), clampf(edge.y, 88, bottom))
	var to_world := get_viewport().get_canvas_transform().affine_inverse() * get_global_transform_with_canvas()
	var text_rect := to_world * Rect2(origin, extent)
	# Preserve reading priority at the original destination position.
	if PromptLayout.covers(text_rect.grow(2.0)):
		return false
	PromptLayout.collect_obstacles_except(null, _arrow_obstacles)
	var stride := ceilf(extent.y) + 4.0
	for i in 13:
		var row := int((i + 1) / 2)
		var candidate := origin + Vector2(0.0, row * stride * (-1.0 if i % 2 == 1 else 1.0))
		if candidate.y < 88.0 or candidate.y > bottom:
			continue
		var rect := (to_world * Rect2(candidate, extent)).grow(2.0)
		if PromptLayout.covers(rect):
			continue
		var blocked := false
		for obstacle in _arrow_obstacles:
			if rect.intersects(obstacle):
				blocked = true
				break
		if blocked:
			continue
		_arrow.position = candidate
		return true
	return false


func _text(key: String) -> String:
	return COPY.get(Story.language, COPY[StoryLocale.SOURCE_LANGUAGE])[key]


func _enabled(key: String) -> bool:
	var raw: Variant = Settings.get_value(Settings.DISPLAY_SECTION, key, true)
	return raw if raw is bool else true


## Compact edge tracker built from the same typography and palette as the journal.
class ObjectiveRow extends MarginContainer:
	var label: Label
	var _category: Label
	var _copy: VBoxContainer
	var _accent := Palette.CYAN
	var reveal := 1.0:
		set(value):
			reveal = value
			if _copy != null:
				_copy.modulate.a = lerpf(0.65, 1.0, reveal)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		add_theme_constant_override(&"margin_left", 19)
		add_theme_constant_override(&"margin_right", 12)
		add_theme_constant_override(&"margin_top", 5)
		add_theme_constant_override(&"margin_bottom", 6)
		_copy = VBoxContainer.new()
		_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_copy.add_theme_constant_override(&"separation", 2)
		add_child(_copy)
		_category = UiKit.label("", UiKit.FS_CAPTION, _accent)
		_category.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_copy.add_child(_category)
		label = UiKit.label("", UiKit.FS_BODY, Palette.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 3
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_copy.add_child(label)

	func _ready() -> void:
		resized.connect(queue_redraw)
		minimum_size_changed.connect(reset_size)
		reset_size()


	func set_category(title: String, accent: Color) -> void:
		if _category.text != title:
			_category.text = title
		if _accent != accent:
			_accent = accent
			_category.add_theme_color_override(&"font_color", _accent)
			queue_redraw()

	func _draw() -> void:
		var cut := 7.0
		var base := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y - cut),
			Vector2(size.x - cut, size.y), Vector2(0, size.y)])
		draw_colored_polygon(base, Color(UiTheme.PANEL_BODY, 0.96))
		draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), Color(UiTheme.PANEL_EDGE, 0.75))
		draw_line(Vector2(size.x, size.y - cut), Vector2(size.x - cut, size.y), Color(UiTheme.PANEL_EDGE, 0.8))
		draw_rect(Rect2(0, 0, 1, size.y * lerpf(0.33, 1.0, reveal)), Color(_accent, 0.86))
		var center := Vector2(9.5, _category.position.y + _copy.position.y + _category.size.y * 0.5)
		var mark := PackedVector2Array([center + Vector2(0, -3), center + Vector2(3, 0), center + Vector2(0, 3),
			center + Vector2(-3, 0), center + Vector2(0, -3)])
		draw_polyline(mark, _accent, 1.0, true)
