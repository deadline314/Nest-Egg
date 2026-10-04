class_name SoundLabTimelineView
extends Control
## 換彈時間軸的畫面：一條代表整段動畫的橫軸，每個聲音是一個標記加一條表示聲音長度的色條（超出動畫結尾變橘色），
## 還有目前進度的游標。標記可以用滑鼠拖動（吸附到 1%）。只負責畫與拖動，資料由 SoundLabReloadEditor 管理。

signal cue_dragged(index: int, at: float)
signal cue_picked(index: int)

const HEIGHT := 96.0
const PAD := 8.0
const GRAB_DISTANCE := 9.0
const COLOR_OK := Color(0.3, 0.8, 0.75, 0.55)
const COLOR_LONG := Color(0.95, 0.65, 0.2, 0.6)
const COLOR_MARK := Color(0.9, 0.95, 1.0)
const COLOR_SELECTED := Color(1.0, 0.85, 0.3)
const COLOR_HEAD := Color(1.0, 0.35, 0.35)

## 動畫長度（秒）。
var duration := 1.0
## 每個 cue：{at: 0..1, label: 顯示文字, length: 聲音長度（秒）}。
var cues: Array[Dictionary] = []
## 目前進度 0..1；小於 0 不畫游標。
var progress := -1.0
var selected := -1
var _dragging := -1


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "換彈動畫的時間軸：每個標記是一個聲音，色條是聲音的長度（橘色 = 超出動畫結尾）。拖動標記改位置，紅線是目前進度"


func set_cues(p_cues: Array[Dictionary], p_duration: float) -> void:
	cues = p_cues
	duration = maxf(0.01, p_duration)
	queue_redraw()


func set_progress(value: float) -> void:
	if not is_equal_approx(value, progress):
		progress = value
		queue_redraw()


func _x_of(at: float) -> float:
	return PAD + at * (size.x - PAD * 2.0)


func _at_of(x: float) -> float:
	return clampf((x - PAD) / maxf(1.0, size.x - PAD * 2.0), 0.0, 1.0)


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := 13
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.1, 0.9))
	var base_y := size.y - 22.0
	draw_line(Vector2(PAD, base_y), Vector2(size.x - PAD, base_y), Color(0.45, 0.55, 0.6), 2.0)
	# 刻度：每 0.5 秒一格（動畫短於 1 秒時每 0.1 秒）。
	var step := 0.5 if duration >= 1.0 else 0.1
	var t := 0.0
	while t <= duration + 0.0001:
		var x := _x_of(t / duration)
		draw_line(Vector2(x, base_y - 3.0), Vector2(x, base_y + 4.0), Color(0.45, 0.55, 0.6))
		draw_string(font, Vector2(x - 8.0, size.y - 4.0), "%.1f" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 0.75))
		t += step
	for i in cues.size():
		var cue := cues[i]
		var x := _x_of(float(cue["at"]))
		var length := float(cue.get("length", 0.0))
		var end_x := x + length / duration * (size.x - PAD * 2.0)
		var lane := 18.0 + float(i % 3) * 16.0
		var overflow := float(cue["at"]) * duration + length > duration + 0.001
		draw_rect(Rect2(x, lane, maxf(3.0, minf(end_x, size.x - PAD) - x), 12.0), COLOR_LONG if overflow else COLOR_OK)
		var color := COLOR_SELECTED if i == selected else COLOR_MARK
		draw_line(Vector2(x, 6.0), Vector2(x, base_y), color, 2.0)
		draw_circle(Vector2(x, base_y), 5.0, color)
		var text := str(cue.get("label", ""))
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		# 靠右邊的標記把文字放在標記左側，才不會超出畫面。
		var text_x := x + 4.0 if x + 4.0 + text_width <= size.x - PAD else maxf(PAD, x - 4.0 - text_width)
		draw_string(font, Vector2(text_x, lane + 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE if text_x < x else Color(0.02, 0.05, 0.07))
	if progress >= 0.0:
		var hx := _x_of(clampf(progress, 0.0, 1.0))
		draw_line(Vector2(hx, 2.0), Vector2(hx, base_y + 6.0), COLOR_HEAD, 2.0)


func _nearest(x: float) -> int:
	var best := -1
	var best_distance := GRAB_DISTANCE
	for i in cues.size():
		var distance := absf(_x_of(float(cues[i]["at"])) - x)
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = _nearest(event.position.x)
			if _dragging >= 0:
				selected = _dragging
				cue_picked.emit(_dragging)
				queue_redraw()
		else:
			_dragging = -1
	elif event is InputEventMouseMotion and _dragging >= 0:
		cue_dragged.emit(_dragging, snappedf(_at_of(event.position.x), 0.01))
