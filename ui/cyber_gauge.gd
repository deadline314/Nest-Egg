class_name CyberGauge
extends Control
## 義體電量：能力名稱、分段電量條（就緒時發亮脈動）、冷卻或持續進度的細線。

const SIZE := Vector2(120, 24)
const SEGMENTS := 10
const BAR_HEIGHT := 6.0

var _charge := 0.0
var _ready_to_use := false
var _name := ""
var _progress := 1.0
var _bar: SegmentBar
var _time := 0.0


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bar = SegmentBar.new()
	_bar.segments = SEGMENTS
	_bar.size = Vector2(SIZE.x, BAR_HEIGHT)
	_bar.custom_minimum_size = _bar.size
	_bar.position = Vector2(0, 13)
	add_child(_bar)
	set_process(false)


func update_state(charge: float, ready_now: bool, ability_name: String, progress: float) -> void:
	_charge = charge
	_ready_to_use = ready_now
	_name = ability_name
	_progress = progress
	_bar.color = LightKit.glow(Palette.CYAN, 1.5) if ready_now else Palette.UI_MUTED
	_bar.set_ratio(clampf(charge / 100.0, 0.0, 1.0))
	set_process(ready_now)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var font := UiKit.font()
	var color := Palette.CYAN if _ready_to_use else Palette.UI_MUTED
	var label := "%s%s" % [_name, "　就緒" if _ready_to_use else ""]
	var pulse := 0.8 + 0.2 * sin(_time * 6.0) if _ready_to_use else 1.0
	draw_string(font, Vector2(size.x - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY).x, 10), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY, Color(color, pulse))
	if _progress < 1.0:
		draw_line(Vector2(0, 22.0), Vector2(size.x * _progress, 22.0), Palette.MAGENTA, 1.0)
