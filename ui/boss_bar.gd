class_name BossBar
extends Control
## 頭目血條：名牌 + 分段血條 + 階段刻度。登場時從中間往兩側展開，跨過階段刻度時閃一下。
## 只認比例（0 到 1）與名稱，不持有頭目物件。階段刻度預設在一半血量（兩個頭目都是 50% 進入第二階段）。

const SIZE := Vector2(320, 30)
const SEGMENTS := 24
const OPEN_TIME := 0.5
const FLASH_TIME := 0.35
const CLOSE_TIME := 0.3
const BAR_TOP := 16.0
const BAR_HEIGHT := 7.0

## 階段刻度位置（血量比例）。
var phase_marks: PackedFloat32Array = PackedFloat32Array([0.5])

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
	tooltip_text = "頭目的血量；刻度是進入下一階段的位置"
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


func is_open() -> bool:
	return visible


func ratio() -> float:
	return _ratio


## 頭目登場：從中間往兩側展開。
func open(display_name: String, start_ratio := 1.0) -> void:
	_name = display_name
	_ratio = clampf(start_ratio, 0.0, 1.0)
	_bar.set_ratio(1.0)
	_bar.set_ratio(_ratio)
	_crossed.clear()
	_flash = 0.0
	visible = true
	_kill_tween()
	if Settings.get_reduce_flashes():
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
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	_tween.tween_callback(func() -> void: visible = false)


func set_ratio(value: float) -> void:
	var previous := _ratio
	_ratio = clampf(value, 0.0, 1.0)
	_bar.set_ratio(_ratio)
	for i in phase_marks.size():
		if previous > phase_marks[i] and _ratio <= phase_marks[i] and not _crossed.has(i):
			_crossed[i] = true
			_flash = 1.0
			set_process(true)
	_bar.set_pulse(_ratio <= 0.2 and _ratio > 0.0)
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
	var percent := "%d%%" % ceili(_ratio * 100.0)
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
