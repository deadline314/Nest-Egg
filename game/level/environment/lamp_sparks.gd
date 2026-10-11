class_name LampSparks
extends Node2D
## 快壞的燈亮起來那一下掉的火花（BG-36）：幾顆橘白色的小亮點往下掉、很快熄滅。取代原本光錐裡一直飄的假塵粒：
## 只在有理由的時候出現（接點打火）。固定數量、不配置新物件；沒有火花在飛的時候不處理也不重畫。

const COUNT := 6
const LIFE := 0.55
const GRAVITY := 260.0
const SPEED := Vector2(34.0, 46.0)
const HOT := Color(1.0, 0.86, 0.5)
const COOL := Color(1.0, 0.42, 0.12)
const GLOW := 2.4

var _position := PackedVector2Array()
var _velocity := PackedVector2Array()
var _life := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _alive := 0


func _ready() -> void:
	material = LightKit.additive_emissive_material()
	_position.resize(COUNT)
	_velocity.resize(COUNT)
	_life.resize(COUNT)
	_life.fill(0.0)
	set_process(false)


## 噴一次火花。seed_value 讓同一盞燈的火花每次都一樣。
func burst(seed_value: int) -> void:
	_rng.seed = seed_value
	for index in COUNT:
		_position[index] = Vector2(_rng.randf_range(-2.0, 2.0), 0.0)
		_velocity[index] = Vector2(_rng.randf_range(-SPEED.x, SPEED.x), _rng.randf_range(-SPEED.y * 0.4, SPEED.y))
		_life[index] = LIFE * _rng.randf_range(0.55, 1.0)
	_alive = COUNT
	set_process(true)
	queue_redraw()


func is_active() -> bool:
	return _alive > 0


func _process(delta: float) -> void:
	_alive = 0
	for index in COUNT:
		if _life[index] <= 0.0:
			continue
		_life[index] -= delta
		_velocity[index].y += GRAVITY * delta
		_position[index] += _velocity[index] * delta
		if _life[index] > 0.0:
			_alive += 1
	queue_redraw()
	if _alive == 0:
		set_process(false)


func _draw() -> void:
	for index in COUNT:
		if _life[index] <= 0.0:
			continue
		var heat := clampf(_life[index] / LIFE, 0.0, 1.0)
		var tail := _velocity[index] * 0.018
		draw_line(_position[index] - tail, _position[index], LightKit.glow(COOL.lerp(HOT, heat), GLOW * heat), 1.0)
