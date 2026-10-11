class_name ParticleField
extends Node2D
## 高效能粒子場：所有火花／煙／餘燼／碎片都在「同一個節點」內以固定容量陣列模擬與繪製，貼圖共用 VfxAtlas 一張圖集（一次批次繪製）。
## 不產生任何新節點、不會隨戰鬥規模成長記憶體（環形緩衝，滿了覆蓋最舊的粒子）。
##
## 每顆粒子有：起訖大小、起訖顏色（含透明度）、旋轉與自轉、重力、阻力、閃爍、沿速度拉長（火花拖尾）、變色前停留的時間。
## additive＝true 時用加法混合（發光、光暈、火花、餘燼，顏色超過 1 會觸發泛光）；false 是一般混合（煙、灰塵、碎片）。
## 舊的 emit()（形狀 SPARK／SQUARE／CASING／DUST）仍可用，內部對應到新的貼圖。

enum Shape { SPARK, SQUARE, CASING, DUST }

const CAPACITY := 1536
## 起始顏色最多停留到生命的這個比例（之後一定要留時間漸變，不會整顆突然消失）。
const MAX_HOLD := 0.9

@export var additive := false

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size0 := PackedFloat32Array()
var _size1 := PackedFloat32Array()
var _col0 := PackedColorArray()
var _col1 := PackedColorArray()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _flicker := PackedFloat32Array()
var _stretch := PackedFloat32Array()
var _hold := PackedFloat32Array()
var _cell := PackedByteArray()
var _seed := PackedFloat32Array()
var _cursor := 0
var _alive := 0
var _atlas: Texture2D


func _ready() -> void:
	LightKit.mark_emissive(self)
	_atlas = VfxAtlas.texture()
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_life.resize(CAPACITY)
	_life.fill(0.0)
	_max_life.resize(CAPACITY)
	_max_life.fill(1.0)
	_size0.resize(CAPACITY)
	_size1.resize(CAPACITY)
	_col0.resize(CAPACITY)
	_col1.resize(CAPACITY)
	_rot.resize(CAPACITY)
	_spin.resize(CAPACITY)
	_gravity.resize(CAPACITY)
	_drag.resize(CAPACITY)
	_flicker.resize(CAPACITY)
	_stretch.resize(CAPACITY)
	_hold.resize(CAPACITY)
	_cell.resize(CAPACITY)
	_seed.resize(CAPACITY)
	var canvas_material := CanvasItemMaterial.new()
	canvas_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if additive else CanvasItemMaterial.BLEND_MODE_MIX
	canvas_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = canvas_material
	light_mask = 0


## 完整版：cell＝VfxAtlas.Cell；size0→size1 是直徑（像素）；col0→col1 隨生命漸變；rotation／spin（弧度、弧度／秒）；
## stretch＞0 時沿速度方向拉長（長度＝速度×stretch）；flicker＞0 時亮度隨機閃爍；
## hold＝生命的前多少比例維持起始顏色，之後才漸變（平塗色塊用：先保持實心，最後才退場）。
func emit_ex(position: Vector2, velocity: Vector2, life: float, cell: int, size0: float, size1: float, col0: Color, col1: Color,
		gravity := 0.0, drag := 1.5, rotation := 0.0, spin := 0.0, stretch := 0.0, flicker := 0.0, hold := 0.0) -> void:
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
	_size0[i] = size0
	_size1[i] = size1
	_col0[i] = col0
	_col1[i] = col1
	_rot[i] = rotation
	_spin[i] = spin
	_gravity[i] = gravity
	_drag[i] = drag
	_flicker[i] = flicker
	_stretch[i] = stretch
	_hold[i] = clampf(hold, 0.0, MAX_HOLD)
	_cell[i] = cell
	_seed[i] = randf() * TAU


## 舊介面：形狀對應到新貼圖（火花＝拖尾、方塊＝光點、彈殼＝碎片、揚塵＝煙團）。
func emit(position: Vector2, velocity: Vector2, color: Color, life: float, size: float,
		gravity := 300.0, drag := 2.0, shape := Shape.SPARK) -> void:
	var faded := Color(color.r, color.g, color.b, 0.0)
	match shape:
		Shape.SPARK:
			emit_ex(position, velocity, life, VfxAtlas.Cell.STREAK, maxf(5.0, size * 4.0), maxf(2.0, size * 1.5), color, faded, gravity, drag, 0.0, 0.0, 0.035)
		Shape.CASING:
			emit_ex(position, velocity, life, VfxAtlas.Cell.SHARD, size * 5.0, size * 5.0, color, faded, gravity, drag, randf() * TAU, randf_range(-12.0, 12.0))
		Shape.DUST:
			emit_ex(position, velocity, life, VfxAtlas.Cell.PUFF_A if randf() < 0.5 else VfxAtlas.Cell.PUFF_B, size * 4.0, size * 9.0, color, faded,
					gravity, drag, randf() * TAU, randf_range(-1.0, 1.0))
		_:
			emit_ex(position, velocity, life, VfxAtlas.Cell.EMBER, size * 4.0, size * 1.5, color, faded, gravity, drag)


## 顏色漸變到哪裡（0＝起始色、1＝結束色）：生命的前 hold 比例停在起始色，之後線性走完。
static func fade_ratio(age: float, hold: float) -> float:
	return age if hold <= 0.0 else maxf(0.0, (age - hold) / (1.0 - hold))


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
		_rot[i] += _spin[i] * delta
	_alive = alive
	queue_redraw()


func _draw() -> void:
	if _alive <= 0:
		return
	var time := Time.get_ticks_msec() * 0.001
	for i in CAPACITY:
		if _life[i] <= 0.0:
			continue
		var age := 1.0 - _life[i] / _max_life[i]  # 0 新生 → 1 將死
		var c := _col0[i].lerp(_col1[i], fade_ratio(age, _hold[i]))
		if _flicker[i] > 0.0:
			var f := 1.0 - _flicker[i] * (0.5 + 0.5 * sin(time * 38.0 + _seed[i] * 7.0))
			c = Color(c.r * f, c.g * f, c.b * f, c.a)
		var size := lerpf(_size0[i], _size1[i], 1.0 - pow(1.0 - age, 2.0))
		if size < 0.3 or c.a <= 0.003:
			continue
		var region := VfxAtlas.region(_cell[i])
		if _stretch[i] > 0.0:
			var velocity := _vel[i]
			var length := maxf(size, velocity.length() * _stretch[i])
			draw_set_transform(_pos[i], velocity.angle(), Vector2.ONE)
			draw_texture_rect_region(_atlas, Rect2(-length, -size * 0.5, length, size), region, c)
		else:
			draw_set_transform(_pos[i], _rot[i], Vector2.ONE)
			draw_texture_rect_region(_atlas, Rect2(-size * 0.5, -size * 0.5, size, size), region, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
