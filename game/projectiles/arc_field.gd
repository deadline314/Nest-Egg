class_name ArcField
extends Node2D
## 電弧／閃電：每道弧是一條會閃爍抖動的折線（每秒約 30 次重新抖動），分三層畫：外圍柔光、中層色光、核心白線；
## 可以帶分支。全部弧共用這一個節點與固定容量，不產生新節點。用法：emit_arc(從, 到, 顏色, 壽命, 粗細, 抖動, 分支數)。

const CAPACITY := 48
const REJITTER := 1.0 / 30.0

var _from := PackedVector2Array()
var _to := PackedVector2Array()
var _color := PackedColorArray()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _width := PackedFloat32Array()
var _jag := PackedFloat32Array()
var _branches := PackedInt32Array()
var _seed := PackedInt32Array()
var _cursor := 0
var _alive := 0
var _tick := 0.0
var _frame_seed := 0


func _ready() -> void:
	LightKit.mark_emissive(self)
	_from.resize(CAPACITY)
	_to.resize(CAPACITY)
	_color.resize(CAPACITY)
	_life.resize(CAPACITY)
	_life.fill(0.0)
	_max_life.resize(CAPACITY)
	_width.resize(CAPACITY)
	_jag.resize(CAPACITY)
	_branches.resize(CAPACITY)
	_seed.resize(CAPACITY)
	var canvas_material := CanvasItemMaterial.new()
	canvas_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	canvas_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = canvas_material
	light_mask = 0


func emit_arc(from: Vector2, to: Vector2, color: Color, life := 0.18, width := 1.6, jag := 0.14, branches := 1) -> void:
	if _life.is_empty():
		return
	var i := _cursor
	_cursor = (_cursor + 1) % CAPACITY
	if _life[i] <= 0.0:
		_alive += 1
	_from[i] = from
	_to[i] = to
	_color[i] = color
	_life[i] = life
	_max_life[i] = maxf(0.02, life)
	_width[i] = width
	_jag[i] = jag
	_branches[i] = branches
	_seed[i] = randi()


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
		if _life[i] > 0.0:
			alive += 1
	_alive = alive
	_tick -= delta
	if _tick <= 0.0:
		_tick = REJITTER
		_frame_seed += 1
	queue_redraw()


func _draw() -> void:
	if _alive <= 0:
		return
	for i in CAPACITY:
		if _life[i] <= 0.0:
			continue
		var fade := clampf(_life[i] / _max_life[i] * 1.6, 0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed[i], _frame_seed])
		var points := _bolt(_from[i], _to[i], _jag[i], rng)
		_draw_bolt(points, _color[i], _width[i], fade)
		for b in _branches[i]:
			var at := int(rng.randi_range(1, maxi(1, points.size() - 2)))
			var dir := (_to[i] - _from[i]).normalized().rotated(rng.randf_range(-1.0, 1.0))
			var length := _from[i].distance_to(_to[i]) * rng.randf_range(0.25, 0.5)
			var branch := _bolt(points[at], points[at] + dir * length, _jag[i] * 1.2, rng)
			_draw_bolt(branch, _color[i], _width[i] * 0.6, fade * 0.8)


## 從 a 到 b 的折線：分成約每 6 像素一段，垂直方向隨機偏移（中間大、兩端小）。
func _bolt(a: Vector2, b: Vector2, jag: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var distance := a.distance_to(b)
	var count := clampi(int(distance / 6.0), 3, 24)
	var normal := (b - a).orthogonal().normalized()
	var points := PackedVector2Array()
	for k in count + 1:
		var t := float(k) / float(count)
		var swing := sin(t * PI) * distance * jag * rng.randf_range(-1.0, 1.0)
		points.append(a.lerp(b, t) + normal * swing)
	return points


func _draw_bolt(points: PackedVector2Array, color: Color, width: float, fade: float) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, Color(color.r, color.g, color.b, 0.16 * fade), width * 6.0, true)
	draw_polyline(points, Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 0.55 * fade), width * 2.2, true)
	draw_polyline(points, Color(2.2, 2.2, 2.4, fade), maxf(1.0, width * 0.8), true)
