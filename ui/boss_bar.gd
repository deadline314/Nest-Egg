class_name BossBar
extends Control
## 頭目血條：名牌 + 分段血條 + 階段刻度。登場時從中間往兩側展開，跨過階段刻度時閃一下。
## 接收比例、名稱與階段刻度，無須持有頭目物件。

const SIZE := Vector2(320, 30)
const SEGMENTS := 24
const OPEN_TIME := 0.5
const FLASH_TIME := 0.35
const CLOSE_TIME := 0.3
const BAR_TOP := 16.0
const BAR_HEIGHT := 7.0
const DEFAULT_PHASE_MARKS: PackedFloat64Array = [0.5]
const DEFAULT_HELP := "刻度標示頭目轉階的血量。"
const HELP: Dictionary[String, String] = {
	"ja": "目盛りはボスの次の段階に移る体力を示します。",
	"en": "Ticks mark the boss's phase changes.",
}

const NO_MARKS_HELP: Dictionary[String, String] = {
	"ja": "今の段階の残りを示します。",
	"en": "Shows the amount remaining in this phase.",
}


## 舊頭目用 50% 刻度，資料化頭目在開場時立即提供真正門檻。
var phase_marks := DEFAULT_PHASE_MARKS

var _bar: SegmentBar
var _name := ""
var _ratio := 1.0
var _flash := 0.0
var _crossed: Dictionary[int, bool] = {}
var _tween: Tween


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = DEFAULT_HELP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	pivot_offset = SIZE * 0.5
	_bar = SegmentBar.new()
	_bar.segments = SEGMENTS
	_bar.color = LightKit.glow(Palette.DANGER, 1.6)
	_bar.position = Vector2(2, BAR_TOP)
	_bar.size = Vector2(SIZE.x - 4.0, BAR_HEIGHT)
	_bar.custom_minimum_size = _bar.size
	add_child(_bar)
	set_process(false)


func _ready() -> void:
	Settings.display_changed.connect(_sync_display)


func _get_tooltip(_at_position: Vector2) -> String:
	if tooltip_text != DEFAULT_HELP:
		return tooltip_text
	if phase_marks.is_empty():
		return StoryLocale.optional_text(NO_MARKS_HELP, Story.language, "顯示目前階段剩餘量。")
	return StoryLocale.optional_text(HELP, Story.language, DEFAULT_HELP)


func is_open() -> bool:
	return visible


func ratio() -> float:
	return _ratio


func _displayed_percent() -> int:
	if _ratio <= 0.0:
		return 0
	# A whole percent can land a few bits above its integer boundary.
	return maxi(1, ceili(_ratio * 100.0 - 1.0e-9))


## 頭目登場：從中間往兩側展開。
func open(display_name: String, start_ratio := 1.0) -> void:
	_name = display_name
	_ratio = clampf(start_ratio, 0.0, 1.0)
	_bar.set_ratio(1.0)
	_bar.set_ratio(_ratio, not _quiet_feedback())
	_bar.set_pulse(false)
	_crossed.clear()
	_flash = 0.0
	set_process(false)
	visible = true
	_kill_tween()
	if Settings.get_reduce_ui_motion():
		scale = Vector2.ONE
		modulate.a = 1.0
	elif Settings.get_reduce_flashes():
		scale = Vector2.ONE
		modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, OPEN_TIME)
	else:
		scale = Vector2(0.04, 1.0)
		modulate.a = 1.0
		_tween = create_tween()
		_tween.tween_property(self, "scale:x", 1.0, OPEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


func close() -> void:
	if not visible:
		return
	_kill_tween()
	if Settings.get_reduce_ui_motion():
		hide()
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	_tween.tween_callback(func() -> void: visible = false)


func set_phase_marks(marks: PackedFloat64Array) -> void:
	if phase_marks == marks:
		return
	phase_marks = marks
	_crossed.clear()
	_flash = 0.0
	set_process(false)
	queue_redraw()


func set_ratio(value: float) -> void:
	var previous := _ratio
	_ratio = clampf(value, 0.0, 1.0)
	var quiet := _quiet_feedback()
	_bar.set_ratio(_ratio, not quiet)
	for i in phase_marks.size():
		if previous > phase_marks[i] and _ratio <= phase_marks[i] and not _crossed.has(i):
			_crossed[i] = true
			if not quiet:
				_flash = 1.0
				set_process(true)
	_bar.set_pulse(not quiet and _ratio <= 0.2 and _ratio > 0.0)
	queue_redraw()


func _quiet_feedback() -> bool:
	return Settings.get_reduce_ui_motion() or Settings.get_reduce_flashes()


func _sync_display() -> void:
	if Settings.get_reduce_ui_motion() and _tween != null and _tween.is_running():
		_tween.custom_step(OPEN_TIME + CLOSE_TIME)
	var quiet := _quiet_feedback()
	_bar.set_pulse(visible and not quiet and _ratio <= 0.2 and _ratio > 0.0)
	if quiet:
		_flash = 0.0
		set_process(false)
		_bar.set_ratio(_ratio, false)
	queue_redraw()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _flash <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var font := UiKit.font()
	# 名牌：小菱形 + 名稱；右側是血量百分比。
	draw_colored_polygon(PackedVector2Array([Vector2(2, 7), Vector2(7, 2), Vector2(12, 7), Vector2(7, 12)]), Palette.DANGER)
	draw_string(font, Vector2(18, 12), _name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY, LightKit.glow(Palette.DANGER, 1.4))
	var percent := "%d%%" % _displayed_percent()
	draw_string(font, Vector2(SIZE.x - 4.0 - font.get_string_size(percent, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY).x, 12), percent,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY, Palette.UI_MUTED)
	# 外框與階段刻度。
	draw_rect(Rect2(0, BAR_TOP - 2.0, SIZE.x, BAR_HEIGHT + 4.0), Color(Palette.CYAN_DIM, 0.8), false, 1.0)
	for mark in phase_marks:
		var x := 2.0 + (SIZE.x - 4.0) * mark
		var crossed := _ratio <= mark
		var color := Color(Palette.WHITE, 0.4) if crossed else Palette.UI_TEXT
		draw_line(Vector2(x, BAR_TOP - 5.0), Vector2(x, BAR_TOP + BAR_HEIGHT + 5.0), color, 1.0)
	if _flash > 0.0:
		draw_rect(Rect2(0, BAR_TOP - 3.0, SIZE.x, BAR_HEIGHT + 6.0), Color(1, 1, 1, 0.55 * _flash))
