class_name QuestGuidance
extends Control
## 只讀故事旗標，探索取樣 5 Hz；關卡索引只在章節切換建立。

var catalog := QuestCatalog.new()
var maps := QuestMapIndex.new()
var state: QuestMapState
var level: Level
const PULSE_SCALE := 1.12
## 武器欄右緣（640×360 設計座標）；方向箭頭在這個範圍內時不壓到武器欄。
const WEAPON_BAR_RIGHT := 160.0
const PULSE_TIME := 0.35
## 目標列讓位給世界提示時淡出／淡入的時間（秒）。
const YIELD_FADE := 0.15

## 目標列與任務頁的「目前步驟」同一種斜切橫幅；換目標時本身短暫放大，不再另外彈一條中央提示。
## 目前因為世界提示壓到而淡出讓位（測試與工具讀它）。
var yielding := false
var _row: SlantBanner
var _label: Label
var _pulse: Tween
var _arrow: Label
var _time := 0.0
var _idle := 0.0
var _goal_key := ""
var _target: Dictionary = {}
var _sample_cell := Vector2i(-1, -1)
var _world_hash := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 暫停時也要跑：讀通訊或暫停時關掉這列的滑鼠提示，免得說明框蓋住通訊（NE-246）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.fill_parent(self)
	level = get_parent().get_parent().get_parent() as Level
	if level == null:
		set_process(false)
		return
	state = QuestMapState.for_run()
	catalog.load_story_sources()
	maps = QuestMapIndex.for_chapter(level.data.chapter)
	_row = SlantBanner.new("", Palette.CYAN)
	_row.fill_strength = 0.14
	_row.position = Vector2(145, 52)
	_row.custom_minimum_size = Vector2(350, 0)
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_row.tooltip_text = "開啟任務目錄可以釘選目標，地圖會標出目的地。"
	add_child(_row)
	_label = _row.label
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_row.resized.connect(func() -> void: _row.pivot_offset = Vector2(0, _row.size.y * 0.5))
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
	var covered := get_tree().paused or DialogueLayer.radio_visible()
	var filter := Control.MOUSE_FILTER_IGNORE if covered else Control.MOUSE_FILTER_PASS
	if _row.mouse_filter != filter:
		_row.mouse_filter = filter
		_arrow.mouse_filter = filter
	if get_tree().paused:
		return
	_time += delta
	_idle += delta
	if _time >= 0.2:
		_time = 0
		_sample()
		_refresh_target()
	_row.visible = _enabled("quest_objective") and not _target.is_empty() and not Story.is_cinematic_active()
	# 世界提示（訓練站、告示）是當下要做的動作，優先讀得到：提示框壓到目標列時，目標列先淡出讓位，提示框不動。
	yielding = _row.visible and PromptLayout.covers(row_world_rect())
	var target_alpha := 0.0 if yielding else (1.0 if _idle < 5 or not Settings.get_hud_auto_hide() else 0.4)
	_row.modulate.a = move_toward(_row.modulate.a, target_alpha, delta / YIELD_FADE) if not Settings.get_reduce_ui_motion() else target_alpha
	_update_arrow()


## 目標列目前在世界座標的範圍（和世界提示比對用）；沒顯示時回傳空矩形。
func row_world_rect() -> Rect2:
	if _row == null or not _row.is_visible_in_tree() or level == null:
		return Rect2()
	return get_viewport().get_canvas_transform().affine_inverse() * _row.get_global_rect().grow(2.0)


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
			_pulse_row.call_deferred()
	if _label != null:
		_label.text = "◎ " + str(step["title"]) if not step.is_empty() else ""
		_row.accent = Palette.MAGENTA if not state.pinned_id.is_empty() else Palette.CYAN


## 換目標時目標列放大再回到原尺寸並亮一下；減少介面動態時只亮不縮放。
func _pulse_row() -> void:
	if _row == null or not _row.is_inside_tree() or yielding:
		return
	if _pulse != null:
		_pulse.kill()
	_row.modulate = Color(1.3, 1.3, 1.3, 1.0)
	_pulse = create_tween().set_parallel(true)
	_pulse.tween_property(_row, "modulate", Color.WHITE, PULSE_TIME)
	if not Settings.get_reduce_ui_motion():
		_row.scale = Vector2.ONE * PULSE_SCALE
		_pulse.tween_property(_row, "scale", Vector2.ONE, PULSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	# 左下角是武器欄與彈藥，箭頭靠左時不往下壓到它們。
	var bottom := 240.0 if edge.x < WEAPON_BAR_RIGHT else 322.0
	_arrow.position = Vector2(clampf(edge.x - _arrow.get_minimum_size().x * 0.5, 12, 628 - _arrow.get_minimum_size().x), clampf(edge.y, 88, bottom))
	_arrow.visible = true


func _enabled(key: String) -> bool:
	var raw: Variant = Settings.get_value(Settings.DISPLAY_SECTION, key, true)
	return raw if raw is bool else true
