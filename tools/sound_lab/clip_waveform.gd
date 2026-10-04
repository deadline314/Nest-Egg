class_name ClipWaveform
extends Control
## 擷取介面的波形（NE-180）：畫出波形、依靜音找出的各段、選取範圍與播放游標。
## 滑鼠：拖動選取範圍兩端的把手微調起訖；在空白處拖曳框選新範圍；點一下某一段選用整段；滾輪縮放。

signal range_changed(start: float, end: float)
signal view_changed

const MIN_RANGE := 0.01
const HANDLE_GRAB := 8.0
const ZOOM_STEP := 1.25
const MIN_VIEW := 0.02
const RULER_HEIGHT := 18.0
const NICE_STEPS: Array[float] = [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 60.0, 120.0]
const COLOR_BACK := Color(0.02, 0.05, 0.08)
const COLOR_WAVE := Color(0.35, 0.8, 0.95)
const COLOR_SEGMENT := Color(0.9, 0.7, 0.2, 0.16)
const COLOR_RANGE := Color(0.2, 0.9, 0.6, 0.28)
const COLOR_HANDLE := Color(0.3, 1.0, 0.7)
const COLOR_CURSOR := Color(1.0, 0.4, 0.4)

var duration := 0.0
var peaks: Array = []
var segments: Array = []
var range_start := 0.0
var range_end := 0.0
## 播放游標的位置（秒）；負數代表不顯示。
var cursor := -1.0
var view_start := 0.0
var view_length := 0.0

var _drag := ""
var _anchor := 0.0
var _press_x := 0.0
var _moved := false


func _init() -> void:
	custom_minimum_size = Vector2(300, 150)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "拖動綠色把手調整起訖；在空白處拖曳框選；點一下黃色的段選用整段；滾輪縮放"


func set_data(p_peaks: Array, p_segments: Array, p_duration: float) -> void:
	peaks = p_peaks
	segments = p_segments
	duration = maxf(0.0, p_duration)
	range_start = 0.0
	range_end = 0.0
	cursor = -1.0
	view_start = 0.0
	view_length = duration
	queue_redraw()
	view_changed.emit()


func time_at_x(x: float) -> float:
	return view_start + clampf(x / maxf(1.0, size.x), 0.0, 1.0) * view_length


func x_at_time(t: float) -> float:
	return (t - view_start) / maxf(0.0001, view_length) * size.x


## 設定選取範圍（夾在 0 到總長之間，起點大於終點時對調）。
func set_range(start: float, end: float, emit := true) -> void:
	var low := clampf(minf(start, end), 0.0, duration)
	var high := clampf(maxf(start, end), 0.0, duration)
	if is_equal_approx(low, range_start) and is_equal_approx(high, range_end):
		return
	range_start = low
	range_end = high
	queue_redraw()
	if emit:
		range_changed.emit(range_start, range_end)


func set_view(start: float, length: float) -> void:
	view_length = clampf(length, minf(MIN_VIEW, duration), maxf(duration, MIN_VIEW))
	view_start = clampf(start, 0.0, maxf(0.0, duration - view_length))
	queue_redraw()
	view_changed.emit()


## 以 around（秒）為中心縮放；factor 大於 1 放大。
func zoom(factor: float, around: float) -> void:
	if duration <= 0.0:
		return
	var ratio := (around - view_start) / maxf(0.0001, view_length)
	var length := clampf(view_length / factor, minf(MIN_VIEW, duration), duration)
	set_view(around - ratio * length, length)


func zoom_all() -> void:
	set_view(0.0, duration)


func set_cursor(seconds: float) -> void:
	if not is_equal_approx(seconds, cursor):
		cursor = seconds
		queue_redraw()


## 含這個時間點的段（索引）；沒有回傳 -1。
func segment_at(t: float) -> int:
	for i in segments.size():
		if t >= float(segments[i][0]) and t <= float(segments[i][1]):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if duration <= 0.0:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin_drag(button.position.x)
			else:
				_end_drag(button.position.x)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(ZOOM_STEP, time_at_x(button.position.x))
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0 / ZOOM_STEP, time_at_x(button.position.x))
	elif event is InputEventMouseMotion:
		_drag_to((event as InputEventMouseMotion).position.x)


func _begin_drag(x: float) -> void:
	_press_x = x
	_moved = false
	_anchor = time_at_x(x)
	if range_end > range_start and absf(x - x_at_time(range_start)) <= HANDLE_GRAB:
		_drag = "start"
	elif range_end > range_start and absf(x - x_at_time(range_end)) <= HANDLE_GRAB:
		_drag = "end"
	else:
		_drag = "new"


func _drag_to(x: float) -> void:
	if _drag.is_empty():
		mouse_default_cursor_shape = Control.CURSOR_HSIZE if range_end > range_start and (absf(x - x_at_time(range_start)) <= HANDLE_GRAB or absf(x - x_at_time(range_end)) <= HANDLE_GRAB) else Control.CURSOR_ARROW
		return
	if absf(x - _press_x) > 2.0:
		_moved = true
	var t := time_at_x(x)
	match _drag:
		"start":
			set_range(minf(t, range_end - MIN_RANGE), range_end)
		"end":
			set_range(range_start, maxf(t, range_start + MIN_RANGE))
		"new":
			if _moved:
				set_range(_anchor, t)


func _end_drag(x: float) -> void:
	if _drag == "new" and not _moved:
		var index := segment_at(time_at_x(x))
		if index >= 0:
			set_range(float(segments[index][0]), float(segments[index][1]))
	_drag = ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACK)
	if peaks.is_empty() or duration <= 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(12, size.y / 2.0), "（沒有波形資料）", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.7, 0.8))
		return
	var wave_height := size.y - RULER_HEIGHT
	var mid := wave_height / 2.0
	for i in segments.size():
		var left := x_at_time(float(segments[i][0]))
		var right := x_at_time(float(segments[i][1]))
		if right >= 0.0 and left <= size.x:
			draw_rect(Rect2(left, 0.0, maxf(1.0, right - left), wave_height), COLOR_SEGMENT)
			draw_string(ThemeDB.fallback_font, Vector2(maxf(left, 0.0) + 3.0, 13.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.85, 0.4))
	if range_end > range_start:
		var left := x_at_time(range_start)
		draw_rect(Rect2(left, 0.0, maxf(1.0, x_at_time(range_end) - left), wave_height), COLOR_RANGE)
	var per_second := float(peaks.size()) / duration
	for x in int(size.x):
		var first := clampi(int(time_at_x(float(x)) * per_second), 0, peaks.size() - 1)
		var last := clampi(maxi(first + 1, ceili(time_at_x(float(x + 1)) * per_second)), first + 1, peaks.size())
		var low := 0.0
		var high := 0.0
		for i in range(first, last):
			low = minf(low, float(peaks[i][0]))
			high = maxf(high, float(peaks[i][1]))
		draw_line(Vector2(x, mid - high * mid), Vector2(x, mid - low * mid + 1.0), COLOR_WAVE)
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.12))
	if range_end > range_start:
		for t in [range_start, range_end]:
			draw_line(Vector2(x_at_time(t), 0.0), Vector2(x_at_time(t), wave_height), COLOR_HANDLE, 3.0)
	if cursor >= 0.0:
		draw_line(Vector2(x_at_time(cursor), 0.0), Vector2(x_at_time(cursor), wave_height), COLOR_CURSOR, 2.0)
	_draw_ruler(wave_height)


func _draw_ruler(top: float) -> void:
	var step := NICE_STEPS[NICE_STEPS.size() - 1]
	for candidate in NICE_STEPS:
		if candidate / view_length * size.x >= 70.0:
			step = candidate
			break
	var t := ceilf(view_start / step) * step
	while t <= view_start + view_length:
		var x := x_at_time(t)
		draw_line(Vector2(x, top), Vector2(x, top + 5.0), Color(0.6, 0.7, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(x + 3.0, top + 15.0), "%.2f" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 0.8))
		t += step
