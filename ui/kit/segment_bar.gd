class_name SegmentBar
extends Control
## 分段式切角條（生命、護盾、電量、頭目血條共用）。
## 數值下降時，掉落的段落先變白再淡出成殘影；數值只在改變時重繪，不每影格配置。

@export var segments: int = 10:
	set(v):
		segments = maxi(1, v)
		queue_redraw()
@export var color: Color = Palette.CYAN:
	set(v):
		color = v
		queue_redraw()
@export var segment_gap: int = 1
@export var slant: int = 2
## 殘影停留與淡出時間。
@export var trail_hold: float = 0.25
@export var trail_fade: float = 0.5

var _value: float = 1.0
var _shown: float = 1.0
var _trail: float = 1.0
var _trail_wait: float = 0.0
var _pulse: bool = false
var _t: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(60, 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## ratio：0 到 1。
func set_ratio(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _value):
		return
	if clamped < _value:
		if _trail <= _value:
			_trail = maxf(_trail, _value)
		_trail_wait = trail_hold
		set_process(true)
	else:
		_trail = clamped
	_value = clamped
	queue_redraw()


func ratio() -> float:
	return _value


## 低量警示：整條脈動。
func set_pulse(enabled: bool) -> void:
	if _pulse == enabled:
		return
	_pulse = enabled
	set_process(enabled or _trail > _value)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var animating := _pulse
	if _trail > _value:
		animating = true
		if _trail_wait > 0.0:
			_trail_wait -= delta
		else:
			_trail = maxf(_value, _trail - delta / maxf(trail_fade, 0.01))
	if not animating:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var gap := float(segment_gap)
	var seg_w := (size.x - gap * float(segments - 1)) / float(segments)
	if seg_w < 1.0:
		return
	var filled := _value * float(segments)
	var trail := _trail * float(segments)
	var pulse_k := 0.75 + 0.25 * sin(_t * 8.0) if _pulse else 1.0
	for i in segments:
		var x := roundf(float(i) * (seg_w + gap))
		var w := roundf(seg_w)
		var amount := clampf(filled - float(i), 0.0, 1.0)
		var ghost := clampf(trail - float(i), 0.0, 1.0)
		var back := Color(color, 0.14)
		_segment(x, w, 1.0, back)
		if ghost > amount:
			var a := 0.9 if _trail_wait > 0.0 else 0.5
			_segment(x, w, ghost, Color(1, 1, 1, a))
		if amount > 0.0:
			_segment(x, w, amount, Color(color, pulse_k))


## 單一段：平行四邊形（左右邊斜切），fill 為填滿比例。
func _segment(x: float, w: float, fill: float, c: Color) -> void:
	var s := float(slant)
	var fw := maxf(1.0, roundf(w * fill))
	var h := size.y
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + s, 0), Vector2(x + fw + s, 0), Vector2(x + fw, h), Vector2(x, h)]), c)
