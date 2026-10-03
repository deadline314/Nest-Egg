class_name LightShaft
extends Node2D
## 體積光：光錐（漸層）、光暈、錐內的雨絲與塵埃、地面的濕地倒影。
## 加法混合、自發光；由光源（場景燈、砲台…）當子節點使用。關閉體積光（品質低）、
## 或對應的光源被預算停用／熄滅時不繪製。設計見 design/08-lighting/DESIGN.md 的「架構」第 4 節。

const MOTES := 14
const MOTE_SPEED := 0.22
const RAIN_SPEED := 2.4
const REFLECTION_DEPTH := 30.0

var color := Color.WHITE
## 光錐長度與末端的半寬（像素）。
var length := 130.0
var half_width := 40.0
var direction := Vector2.DOWN
## 0~1.x：光源當下的亮度比例（閃爍、脈動、供電都反映在這裡）。
var intensity := 1.0
var halo_radius := 24.0
## 地面的世界 y 座標（畫濕地倒影用）；INF 代表不畫。
var floor_y := INF
## 光錐裡是否有雨絲（室內與沒雨的區段可關閉）。
var rain_streaks := true
## 跟隨這盞光源：它不可見（被預算停用）或熄滅時不繪製。
var source: PointLight2D

var _time := 0.0
var _since_redraw := 0.0
var _seeds := PackedFloat32Array()


func _ready() -> void:
	material = LightKit.additive_emissive_material()
	_time = randf() * 10.0
	_seeds.resize(MOTES * 2)
	for i in MOTES * 2:
		_seeds[i] = randf()
	Settings.display_changed.connect(_refresh_visibility)
	_refresh_visibility()


func _process(delta: float) -> void:
	if not _should_draw():
		visible = false
		return
	visible = true
	_time += delta
	_since_redraw += delta
	# 品質「中」每秒只重畫 30 次（光錐是體積光裡最貴的一項）；「高」每影格重畫。
	if LightQuality.shaft_detail() >= 1.0 or _since_redraw >= 1.0 / 30.0:
		_since_redraw = 0.0
		queue_redraw()


func _refresh_visibility() -> void:
	visible = _should_draw()


func _should_draw() -> bool:
	if not LightQuality.volumetrics() or intensity <= 0.01:
		return false
	return source == null or (source.visible and source.enabled)


func _draw() -> void:
	var perp := direction.orthogonal()
	var strength := clampf(intensity, 0.0, 1.5)
	_draw_cone(perp, strength)
	draw_circle(Vector2.ZERO, halo_radius, Color(color, 0.07 * strength))
	draw_circle(Vector2.ZERO, halo_radius * 0.5, Color(color, 0.14 * strength))
	_draw_particles(perp, strength)
	_draw_reflection(strength)


## 兩層錐形：寬而淡的外層與窄而亮的核心，頂點最亮、末端淡出。
func _draw_cone(perp: Vector2, strength: float) -> void:
	var tip := direction * length
	for layer in [[1.0, 0.1], [0.55, 0.12]]:
		var width: float = half_width * layer[0]
		var alpha: float = layer[1] * strength
		draw_polygon(PackedVector2Array([Vector2.ZERO, tip + perp * width, tip - perp * width]),
				PackedColorArray([Color(color, alpha), Color(color, 0.0), Color(color, 0.0)]))


## 錐內的雨絲（往下飄、越遠越淡）與緩慢漂浮的塵埃。
func _draw_particles(perp: Vector2, strength: float) -> void:
	for i in maxi(1, int(MOTES * LightQuality.shaft_detail())):
		var u := _seeds[i * 2] - 0.5
		var phase := _seeds[i * 2 + 1]
		if rain_streaks:
			var v := fposmod(phase + _time * RAIN_SPEED * 0.25, 1.0)
			var p := direction * (length * v) + perp * (u * 2.0 * half_width * v)
			draw_line(p, p + Vector2(-0.6, 4.5), Color(color.lightened(0.5), (1.0 - v) * 0.55 * strength), 1.0)
		var m := fposmod(phase * 3.0 + _time * MOTE_SPEED, 1.0)
		var mote := direction * (length * m) + perp * (u * 2.0 * half_width * m + sin(_time * 0.8 + phase * 6.0) * 4.0)
		draw_circle(mote, 0.9, Color(color.lightened(0.3), sin(m * PI) * 0.35 * strength))


## 濕地倒影：地面下方垂直拉長、輕微左右晃動的色帶。
func _draw_reflection(strength: float) -> void:
	if floor_y == INF:
		return
	var local_floor := floor_y - global_position.y
	if local_floor < 0.0 or local_floor > length * 2.5:
		return
	var steps := 5
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var wobble := sin(_time * 2.6 + float(i) * 1.7) * (1.0 + t0 * 2.0)
		var width := 7.0 * (1.0 - t0 * 0.5)
		var y0 := local_floor + 1.0 + REFLECTION_DEPTH * t0
		var y1 := local_floor + 1.0 + REFLECTION_DEPTH * t1
		var a0 := 0.32 * (1.0 - t0) * strength
		var a1 := 0.32 * (1.0 - t1) * strength
		draw_polygon(PackedVector2Array([Vector2(wobble - width, y0), Vector2(wobble + width, y0), Vector2(wobble + width * 0.8, y1), Vector2(wobble - width * 0.8, y1)]),
				PackedColorArray([Color(color, a0), Color(color, a0), Color(color, a1), Color(color, a1)]))
