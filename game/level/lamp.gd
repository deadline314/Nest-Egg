class_name Lamp
extends Node2D
## 場景燈：投射陰影的動態光源，偶爾閃爍營造廢墟氛圍。風格（顏色、光池大小、閃爍、壞掉、脈動）
## 由所在區段的 LampStyle 決定；壞掉的燈不亮也不閃。

const FLICKER_CHANCE := 0.008

var color := Palette.CYAN
var radius := 190.0
var energy := 1.5
var flicker_chance := FLICKER_CHANCE
## 亮度脈動頻率（Hz，0 = 不脈動）。
var pulse_hz := 0.0
var dead := false

var _light: PointLight2D
## 供電門檻：供電低於它時這盞燈熄滅（讓停電時各盞燈依序熄滅）。
var _power_threshold := randf_range(0.1, 0.95)
var _gate := 1.0
var _flicker_left := 0.0
var _time := 0.0


## 套用區段的燈風格。seed_value 決定顏色與是否壞掉，所以同一盞燈每次進關卡都一樣。
func apply_style(style: LampStyle, seed_value: int) -> void:
	if style == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	color = style.color_for(rng)
	radius = style.radius
	energy = style.energy
	flicker_chance = style.flicker_chance
	pulse_hz = style.pulse_hz
	dead = rng.randf() < style.dead_chance
	_power_threshold = rng.randf_range(0.1, 0.95)


func _ready() -> void:
	LightKit.mark_emissive(self)
	_time = randf() * TAU
	if dead:
		set_process(false)
		return
	_light = LightKit.create_point_light(color, radius, energy, true)
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	var gate := LightKit.power_gate(LightKit.lamp_power, _power_threshold)
	if not is_equal_approx(gate, _gate):
		_gate = gate
		_light.enabled = gate > 0.0
		queue_redraw()
	if gate <= 0.0:
		return
	var level := energy * gate
	if pulse_hz > 0.0:
		level *= 0.55 + 0.45 * sin(_time * TAU * pulse_hz)
	if _flicker_left > 0.0:
		_flicker_left -= delta
		_light.energy = level * (0.2 if int(_flicker_left * 30.0) % 2 == 0 else 1.0)
	elif randf() < flicker_chance:
		_flicker_left = randf_range(0.1, 0.35)
	else:
		_light.energy = level
	if pulse_hz > 0.0:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-6, -2, 12, 3), Palette.TERRAIN_TOP)
	if dead:
		# 壞掉的燈：燈泡是暗的，沒有光錐。
		draw_rect(Rect2(-4, 1, 8, 2), Color(color.darkened(0.7), 0.5))
		return
	if _gate <= 0.0:
		draw_rect(Rect2(-4, 1, 8, 2), Color(color.darkened(0.7), 0.5))
		return
	var pulse := (1.0 if pulse_hz <= 0.0 else 0.55 + 0.45 * sin(_time * TAU * pulse_hz)) * _gate
	draw_rect(Rect2(-4, 1, 8, 2), LightKit.glow(color, 2.5 * pulse))
	# 光錐（純裝飾，非常淡）
	draw_colored_polygon(PackedVector2Array([Vector2(-4, 3), Vector2(4, 3), Vector2(40, 120), Vector2(-40, 120)]),
			Color(color, 0.035 * pulse))
