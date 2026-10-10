class_name NeonSign
extends Node2D
## 霓虹招牌：發光字樣（直式或橫式）、偶爾閃爍或單字故障、投射彩色光，並在下方濕地面畫出倒影。

const FONT_SIZE := 11
const CHAR_STEP := 12.0
const PADDING := 5.0
## 重新點亮的瞬間：持續秒數與額外亮度倍率（合計仍在 Fx.HDR_PEAK_MAX 內）。
const RESTRIKE_TIME := 0.07
const RESTRIKE_BOOST := 1.25

var text := "拉麵"
var color := Palette.MAGENTA
var vertical := true
## 亮度倍率（光源能量與字的發光強度），由區段的霓虹亮度決定。
var intensity := 1.0
## 招牌下方地面的世界 y 座標（用來畫倒影）；INF 代表不畫。
var floor_y := INF

var _font: Font
var _light: PointLight2D
var _gate := 1.0
var _time := 0.0
var _off_left := 0.0
## 閃爍連發：這一輪還要再閃幾次、兩次之間的間隔；重新點亮的瞬間亮度衝高一下（有上限）。
var _burst_flicks := 0
var _gap_left := 0.0
var _restrike_left := 0.0
## 供電門檻：供電低於它時這塊招牌熄滅。
var _power_threshold := randf_range(0.1, 0.95)
var _broken_index := -1
var _size := Vector2.ZERO


func _ready() -> void:
	LightKit.mark_emissive(self)
	_font = UiKit.font()
	var count := text.length()
	_size = Vector2(FONT_SIZE + PADDING * 2.0, count * CHAR_STEP + PADDING * 2.0) if vertical \
			else Vector2(count * CHAR_STEP + PADDING * 2.0, FONT_SIZE + PADDING * 2.0)
	_light = LightKit.create_point_light(color, maxf(_size.x, _size.y) * 1.6, 0.9 * intensity)
	_light.position = _size * 0.5
	add_child(_light)
	_time = randf() * 10.0
	if count > 1 and randf() < 0.35:
		_broken_index = randi() % count


func _process(delta: float) -> void:
	_time += delta
	if _off_left > 0.0:
		_off_left -= delta
		if _off_left <= 0.0:
			_restrike_left = RESTRIKE_TIME
			if _broken_index >= 0:
				Fx.sparks(global_position + _size * 0.5, color, 2, 90.0, 0.22, Vector2.UP, 1.2, 240.0)
			if _burst_flicks > 0:
				_gap_left = randf_range(0.03, 0.08)
	elif _gap_left > 0.0:
		_gap_left -= delta
		if _gap_left <= 0.0 and _burst_flicks > 0:
			_burst_flicks -= 1
			_off_left = randf_range(0.03, 0.09)
	elif randf() < 0.004:
		_off_left = randf_range(0.04, 0.25)
		_burst_flicks = randi_range(0, 2)
	_restrike_left = maxf(0.0, _restrike_left - delta)
	_gate = LightKit.power_gate(LightKit.lamp_power, _power_threshold)
	_light.enabled = _gate > 0.0
	_light.energy = (0.15 if _off_left > 0.0 else 0.9 + sin(_time * 30.0) * 0.05) * intensity * _gate
	queue_redraw()


func _draw() -> void:
	var lit := _off_left <= 0.0 and _gate > 0.0
	# 外框與背板
	draw_rect(Rect2(Vector2.ZERO, _size), Color("0b0d16"))
	draw_rect(Rect2(Vector2.ZERO, _size), Color(color, 0.35 if lit else 0.12), false, 1.0)
	for i in text.length():
		var ch := text[i]
		var pos := Vector2(PADDING, PADDING + FONT_SIZE + i * CHAR_STEP - 2.0) if vertical \
				else Vector2(PADDING + i * CHAR_STEP, PADDING + FONT_SIZE - 2.0)
		var on := lit and not (i == _broken_index and fmod(_time, 1.7) < 0.9)
		var boost := RESTRIKE_BOOST if _restrike_left > 0.0 else 1.0
		var glow := Fx.hdr(color, 2.6 * intensity * boost) if on else Color(color.darkened(0.6), 0.6)
		if on:
			draw_string_outline(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color(color, 0.35))
		draw_string(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, glow)
	_draw_reflection(lit)


## 招牌打在地面上的反光：落在地形頂面的一條亮帶，寬度與招牌相同。
func _draw_reflection(lit: bool) -> void:
	if floor_y == INF or not lit:
		return
	LightShaft.draw_floor_sheen(self, 0.0, _size.x, floor_y - global_position.y, LightKit.glow(color, 1.4), 0.35)
