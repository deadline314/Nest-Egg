class_name LightShaft
extends Node2D
## 體積光：光錐、光暈與地面的反光。光錐照到地面為止，不穿過地板。
## 光沒有明確的邊界：光錐往兩側與末端漸淡到看不見，光暈從中心淡到邊緣（BG-36，使用者：「燈光不應該有明確邊界線」）。
## 錐內不畫模仿光線的塵粒與雨絲（使用者覺得很假；場景本來就有真的雨）。
## 加法混合、自發光；由光源（場景燈、砲台…）當子節點使用。關閉體積光（品質低）、
## 或對應的光源被預算停用／熄滅時不繪製。設計見 design/08-lighting/DESIGN.md 的「架構」第 4 節。

## 地面反光的深度：只落在地形頂面那一條（預設 6 像素厚），不畫進地面的剖面。
const SHEEN_DEPTH := 5.0
## 地面比光錐遠多少（光錐長度的倍數）以內還看得到反光。
const SHEEN_REACH := 0.6
## 光錐橫切面的取樣位置（-1 左緣、0 中心、1 右緣）與各位置的亮度比例：中心最亮，往兩側平滑降到 0，所以邊緣沒有線。
## 柔邊給照明用的燈；清楚的邊給和玩法有關的光錐（探照燈的光錐就是它的視野、砲台的光錐是瞄準線）：
## 一樣沒有硬邊線，但亮的範圍幾乎佔滿整個寬度，玩家看得出邊界在哪裡。
const SOFT_AT: Array[float] = [-1.0, -0.62, -0.28, 0.0, 0.28, 0.62, 1.0]
const SOFT_LEVEL: Array[float] = [0.0, 0.38, 0.85, 1.0, 0.85, 0.38, 0.0]
const CRISP_AT: Array[float] = [-1.0, -0.86, -0.5, 0.0, 0.5, 0.86, 1.0]
const CRISP_LEVEL: Array[float] = [0.0, 0.8, 1.0, 1.0, 1.0, 0.8, 0.0]
## 光錐中心、起點的亮度。
const CONE_ALPHA := 0.2
## 點狀光源的光錐起點也留一點寬度，光才不會從一個尖點冒出來。
const MIN_SOURCE_HALF_WIDTH := 1.5
const HALO_SEGMENTS := 12
const HALO_ALPHA := 0.16
## 地面反光輕微晃動，每秒重畫幾次；其餘的部分只在有變化時重畫。
const SHEEN_FPS := 20.0

var color := Color.WHITE
## 光錐長度與末端的半寬（像素）。
var length := 130.0
var half_width := 40.0
var direction := Vector2.DOWN
## 0~1.x：光源當下的亮度比例（閃爍、脈動、供電都反映在這裡）。
var intensity := 1.0
## 光暈的半徑；0＝不畫（有燈具圖的場景燈靠燈具的發光部位與泛光，不需要再疊一圈）。
var halo_radius := 24.0
## 光錐的邊界要不要清楚（見 CRISP_AT）。預設清楚，照明用的場景燈改成柔邊。
var crisp := true
## 要不要畫光錐。往四周發光的燈（燈籠、霓虹管、警示燈）關掉，只留地面的反光。
var cone := true
## 光錐起點的半寬：長條形的發光面（日光燈、燈板）從整條往下照，不是從一個點。
var source_half_width := 0.0
## 地面的世界 y 座標（光錐到此為止，並在上面畫反光）；INF 代表沒有地面。
var floor_y := INF
## 跟隨這盞光源：它不可見（被預算停用）或熄滅時不繪製。
var source: PointLight2D

var _time := 0.0
var _since_redraw := 0.0
## 上次重畫時的樣子（亮度、方向、長度、位置）；沒變就不重畫。
var _drawn_intensity := -1.0
var _drawn_direction := Vector2.ZERO
var _drawn_length := -1.0
var _drawn_origin := Vector2.INF
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _quad_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _wedge := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _wedge_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])


func _ready() -> void:
	material = LightKit.additive_emissive_material()
	_time = randf() * 10.0
	Settings.display_changed.connect(_refresh_visibility)
	_refresh_visibility()


func _process(delta: float) -> void:
	if not _should_draw():
		visible = false
		return
	visible = true
	_time += delta
	_since_redraw += delta
	var origin := global_position
	var changed := not is_equal_approx(intensity, _drawn_intensity) or not direction.is_equal_approx(_drawn_direction) \
			or not is_equal_approx(length, _drawn_length) or not origin.is_equal_approx(_drawn_origin)
	# 品質「中」每秒最多重畫 30 次；「高」有變化的那一格就重畫。
	var ready := LightQuality.shaft_detail() >= 1.0 or _since_redraw >= 1.0 / 30.0
	if (changed and ready) or (floor_y != INF and _since_redraw >= 1.0 / SHEEN_FPS):
		_since_redraw = 0.0
		_drawn_intensity = intensity
		_drawn_direction = direction
		_drawn_length = length
		_drawn_origin = origin
		queue_redraw()


func _refresh_visibility() -> void:
	visible = _should_draw()
	_drawn_intensity = -1.0


func _should_draw() -> bool:
	if not LightQuality.volumetrics() or intensity <= 0.01:
		return false
	return source == null or (source.visible and source.enabled)


func _draw() -> void:
	var perp := direction.orthogonal()
	var strength := clampf(intensity, 0.0, 1.5)
	if cone:
		_draw_cone(perp, strength)
	if halo_radius > 0.0:
		_draw_halo(strength)
	_draw_sheen(strength)


## 光實際照得到的長度：往下照時到地面為止。
func _reach() -> float:
	if floor_y == INF or direction.y <= 0.01:
		return length
	return clampf((floor_y - global_position.y) / direction.y, 0.0, length)


## 光錐：沿橫切面分成幾條，每條兩側的亮度照 PROFILE_LEVEL 內插，所以從中心往兩側平滑淡到 0；
## 沿長度從起點淡到末端（被地面截斷時末端保留當下的亮度）。
func _draw_cone(perp: Vector2, strength: float) -> void:
	var reach := _reach()
	if reach <= 0.0:
		return
	var ratio := reach / length
	var tip := direction * reach
	var start := maxf(source_half_width, MIN_SOURCE_HALF_WIDTH)
	var width := start + (half_width - start) * ratio
	var near := CONE_ALPHA * strength
	var far := near * (1.0 - ratio)
	var at := CRISP_AT if crisp else SOFT_AT
	var level := CRISP_LEVEL if crisp else SOFT_LEVEL
	for index in at.size() - 1:
		var left := at[index]
		var right := at[index + 1]
		_quad[0] = perp * (start * left)
		_quad[1] = perp * (start * right)
		_quad[2] = tip + perp * (width * right)
		_quad[3] = tip + perp * (width * left)
		_quad_colors[0] = Color(color, near * level[index])
		_quad_colors[1] = Color(color, near * level[index + 1])
		_quad_colors[2] = Color(color, far * level[index + 1])
		_quad_colors[3] = Color(color, far * level[index])
		draw_polygon(_quad, _quad_colors)


## 光暈：中心最亮、往外淡到 0 的圓，沒有邊線。
func _draw_halo(strength: float) -> void:
	_wedge[0] = Vector2.ZERO
	_wedge_colors[0] = Color(color, HALO_ALPHA * strength)
	_wedge_colors[1] = Color(color, 0.0)
	_wedge_colors[2] = _wedge_colors[1]
	for index in HALO_SEGMENTS:
		_wedge[1] = Vector2.from_angle(TAU * float(index) / float(HALO_SEGMENTS)) * halo_radius
		_wedge[2] = Vector2.from_angle(TAU * float(index + 1) / float(HALO_SEGMENTS)) * halo_radius
		draw_polygon(_wedge, _wedge_colors)


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
