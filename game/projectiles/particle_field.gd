class_name ParticleField
extends Node2D
## 高效能粒子場：所有火花／彈殼／揚塵／碎片都在「同一個節點」內以固定容量陣列模擬與繪製。
## 不產生任何新節點、不會隨戰鬥規模成長記憶體（環形緩衝，滿了覆蓋最舊的粒子）。

enum Shape { SPARK, SQUARE, CASING, DUST }

const CAPACITY := 1024

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _color := PackedColorArray()
var _shape := PackedByteArray()
var _cursor := 0
var _alive := 0


func _ready() -> void:
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_life.resize(CAPACITY)
	_life.fill(0.0)
	_max_life.resize(CAPACITY)
	_max_life.fill(1.0)
	_size.resize(CAPACITY)
	_gravity.resize(CAPACITY)
	_drag.resize(CAPACITY)
	_color.resize(CAPACITY)
	_shape.resize(CAPACITY)


func emit(position: Vector2, velocity: Vector2, color: Color, life: float, size: float,
		gravity := 300.0, drag := 2.0, shape := Shape.SPARK) -> void:
	if _pos.is_empty():
		return
	var i := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	if _life[i] <= 0.0:
		_alive += 1
	_pos[i] = position
	_vel[i] = velocity
	_life[i] = life
	_max_life[i] = maxf(0.01, life)
	_size[i] = size
	_gravity[i] = gravity
	_drag[i] = drag
	_color[i] = color
	_shape[i] = shape


func alive_count() -> int:
	return _alive


func _process(delta: float) -> void:
	if _alive <= 0:
		return
	var alive := 0
	for i in CAPACITY:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		alive += 1
		var v := _vel[i]
		v.y += _gravity[i] * delta
		v *= maxf(0.0, 1.0 - _drag[i] * delta)
		_vel[i] = v
		_pos[i] += v * delta
	_alive = alive
	queue_redraw()


func _draw() -> void:
	if _alive <= 0:
		return
	for i in CAPACITY:
		if _life[i] <= 0.0:
			continue
		var t := _life[i] / _max_life[i]
		var c := _color[i]
		c.a *= t
		var p := _pos[i]
		var s := _size[i]
		match _shape[i]:
			Shape.SPARK:
				# 火花沿速度方向拉長，速度感更強。
				var tail := _vel[i] * 0.025
				draw_line(p - tail, p, c, maxf(1.0, s * t))
			Shape.CASING:
				draw_rect(Rect2(p - Vector2(s, s * 0.5), Vector2(s * 2.0, s)), c)
			Shape.DUST:
				draw_circle(p, s * (1.6 - t * 0.6), c)
			_:
				var half := s * (0.5 + 0.5 * t)
				draw_rect(Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), c)
