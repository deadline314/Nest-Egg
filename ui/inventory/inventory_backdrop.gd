class_name InventoryBackdrop
extends Control
## 背包背景：深色底、緩慢捲動的格線、細雨與掃描線。用固定長度的陣列就地更新，不會每影格配置記憶體。

const RAIN_COUNT := 42
const RAIN_SPEED := 190.0
const GRID := 24.0
const SCANLINE_STEP := 3.0

var _time := 0.0
var _rain_x := PackedFloat32Array()
var _rain_y := PackedFloat32Array()
var _rain_len := PackedFloat32Array()
var _rain_speed := PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_rain_x.resize(RAIN_COUNT)
	_rain_y.resize(RAIN_COUNT)
	_rain_len.resize(RAIN_COUNT)
	_rain_speed.resize(RAIN_COUNT)
	for i in RAIN_COUNT:
		_rain_x[i] = rng.randf_range(0.0, 640.0)
		_rain_y[i] = rng.randf_range(0.0, 360.0)
		_rain_len[i] = rng.randf_range(8.0, 20.0)
		_rain_speed[i] = rng.randf_range(0.7, 1.3)


func _process(delta: float) -> void:
	_time += delta
	for i in RAIN_COUNT:
		_rain_y[i] += RAIN_SPEED * _rain_speed[i] * delta
		_rain_x[i] -= RAIN_SPEED * 0.12 * _rain_speed[i] * delta
		if _rain_y[i] > size.y + 24.0 or _rain_x[i] < -24.0:
			_rain_y[i] = -_rain_len[i]
			_rain_x[i] = fposmod(_rain_x[i] + size.x * 0.6, size.x + 24.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG_FAR, 0.97))
	# 上亮下暗的漸層感：疊三條半透明色帶。
	draw_rect(Rect2(0, 0, size.x, size.y * 0.35), Color(Palette.CYAN_DIM, 0.06))
	draw_rect(Rect2(0, size.y * 0.75, size.x, size.y * 0.25), Color(Palette.MAGENTA, 0.04))
	# 緩慢向上捲動的格線。
	var offset := fposmod(_time * 6.0, GRID)
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(Palette.CYAN, 0.05), 1.0)
		x += GRID
	var y := -offset
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(Palette.CYAN, 0.05), 1.0)
		y += GRID
	# 雨。
	for i in RAIN_COUNT:
		var from := Vector2(_rain_x[i], _rain_y[i])
		draw_line(from, from + Vector2(-_rain_len[i] * 0.12, _rain_len[i]), Color(Palette.RAIN, 0.22), 1.0)
	# 掃描線。
	var line_y := 0.0
	while line_y < size.y:
		draw_rect(Rect2(0, line_y, size.x, 1), Color(0, 0, 0, 0.16))
		line_y += SCANLINE_STEP
