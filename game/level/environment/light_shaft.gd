class_name LightShaft
extends Node2D
## 體積光：光錐（漸層）、光暈、錐內的雨絲與塵埃、地面的反光。光錐照到地面為止，不穿過地板。
## 加法混合、自發光；由光源（場景燈、砲台…）當子節點使用。關閉體積光（品質低）、
## 或對應的光源被預算停用／熄滅時不繪製。設計見 design/08-lighting/DESIGN.md 的「架構」第 4 節。

const MOTES := 14
const MOTE_SPEED := 0.22
const RAIN_SPEED := 2.4
## 地面反光的深度：只落在地形頂面那一條（預設 6 像素厚），不畫進地面的剖面。
const SHEEN_DEPTH := 5.0
## 地面比光錐遠多少（光錐長度的倍數）以內還看得到反光。
const SHEEN_REACH := 0.6

var color := Color.WHITE
## 光錐長度與末端的半寬（像素）。
var length := 130.0
var half_width := 40.0
var direction := Vector2.DOWN
## 0~1.x：光源當下的亮度比例（閃爍、脈動、供電都反映在這裡）。
var intensity := 1.0
var halo_radius := 24.0
## 地面的世界 y 座標（光錐到此為止，並在上面畫反光）；INF 代表沒有地面。
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
	_draw_sheen(strength)


## 光實際照得到的長度：往下照時到地面為止。
func _reach() -> float:
	if floor_y == INF or direction.y <= 0.01:
		return length
	return clampf((floor_y - global_position.y) / direction.y, 0.0, length)


## 兩層錐形：寬而淡的外層與窄而亮的核心，頂點最亮、末端淡出；被地面截斷時末端保留當下的亮度。
func _draw_cone(perp: Vector2, strength: float) -> void:
	var reach := _reach()
	if reach <= 0.0:
		return
	var ratio := reach / length
	var tip := direction * reach
	for layer in [[1.0, 0.1], [0.55, 0.12]]:
		var width: float = half_width * layer[0] * ratio
		var alpha: float = layer[1] * strength
		var end_alpha := alpha * (1.0 - ratio)
		draw_polygon(PackedVector2Array([Vector2.ZERO, tip + perp * width, tip - perp * width]),
				PackedColorArray([Color(color, alpha), Color(color, end_alpha), Color(color, end_alpha)]))


## 錐內的雨絲（往下飄、越遠越淡）與緩慢漂浮的塵埃。
func _draw_particles(perp: Vector2, strength: float) -> void:
	var reach := _reach()
	var spread := half_width * reach / length
	for i in maxi(1, int(MOTES * LightQuality.shaft_detail())):
		var u := _seeds[i * 2] - 0.5
		var phase := _seeds[i * 2 + 1]
		if rain_streaks:
			var v := fposmod(phase + _time * RAIN_SPEED * 0.25, 1.0)
			var p := direction * (reach * v) + perp * (u * 2.0 * spread * v)
			draw_line(p, p + Vector2(-0.6, 4.5), Color(color.lightened(0.5), (1.0 - v) * 0.55 * strength), 1.0)
		var m := fposmod(phase * 3.0 + _time * MOTE_SPEED, 1.0)
		var mote := direction * (reach * m) + perp * (u * 2.0 * spread * m + sin(_time * 0.8 + phase * 6.0) * 4.0)
		draw_circle(mote, 0.9, Color(color.lightened(0.3), sin(m * PI) * 0.35 * strength))


## 光打在地面上的反光：寬度跟著光錐落地的寬度，地面比光錐遠就變窄變淡，輕微左右晃動。
func _draw_sheen(strength: float) -> void:
	if floor_y == INF:
		return
	var local_floor := floor_y - global_position.y
	if local_floor < 0.0 or local_floor > length * (1.0 + SHEEN_REACH):
		return
	var falloff := 1.0 if local_floor <= length else 1.0 - (local_floor - length) / (length * SHEEN_REACH)
	var half := maxf(8.0, half_width * minf(1.0, local_floor / length) * 1.15)
	var wobble := sin(_time * 2.6) * 1.5
	LightShaft.draw_floor_sheen(self, wobble - half, wobble + half, local_floor, color, 0.34 * strength * falloff)


## 地面反光：落在地形頂面的一條亮帶，中間最亮、往兩側與往下淡出。場景燈與霓虹招牌共用。
static func draw_floor_sheen(canvas: CanvasItem, left: float, right: float, floor_local_y: float, tint: Color, alpha: float) -> void:
	if alpha <= 0.003 or right - left < 1.0:
		return
	var middle := (left + right) * 0.5
	var clear := Color(tint, 0.0)
	canvas.draw_polygon(PackedVector2Array([Vector2(left, floor_local_y), Vector2(middle, floor_local_y),
			Vector2(right, floor_local_y), Vector2(middle, floor_local_y + SHEEN_DEPTH)]),
			PackedColorArray([clear, Color(tint, alpha), clear, clear]))
