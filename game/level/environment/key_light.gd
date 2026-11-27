class_name KeyLight
extends Node2D
## 區段的主光（BG-67）：一盞實際照亮表面的大光、畫在角色後面的大片光暈與斜射光柱、畫在角色前面很淡的一層漫射。
## 被遮住的程度隨時間緩慢起伏：遮得少時光暈大、光柱淡；遮得多時光暈收小、光柱明顯。
## 光暈大部分在角色後面，靠近光源的角色變成光裡的剪影；前面那層是一般混合（只往主光的顏色靠，不會加亮），主角的白髮不會因此過曝。
## 資料在 KeyLightData（地圖 JSON 的 key_light）。低畫質只留照亮表面的光；「減少動態」時固定在中間值。

## 測試與截圖用：0~1 時固定被遮住的程度（負值 = 照資料變化）。
static var forced_occlusion := -1.0

## 光暈遮得最多時縮到原本的多少、亮度剩多少。
const HALO_SHRINK := 0.45
const HALO_DIM := 0.55
## 照亮表面的光在遮得最多時剩多少。
const LIGHT_DIM := 0.45
## 光柱中心的亮度；遮得少時光柱只剩這個比例。
const SHAFT_ALPHA := 0.3
const SHAFT_FLOOR := 0.25
## 光柱各自緩慢明暗（枝葉、雲影），幅度與週期（秒）。
const SHAFT_SHIMMER := 0.18
const SHAFT_SHIMMER_PERIOD := Vector2(8.0, 14.0)
## 有變化時每秒最多重畫幾次；遮住程度的變化小於這個量就不重畫。
const REDRAW_FPS := 12.0
const REDRAW_STEP := 0.004
## 前面那層漫射比光暈大多少。
const WASH_SCALE := 1.5
## 光心：主光色往白靠的比例、整體亮度（< 1，調色之後才不會到頂）。
const CORE_WHITEN := 0.6
const CORE_LEVEL := 1.0

var data: KeyLightData
## 目前被遮住的程度（0~1）。
var occlusion := 0.0

var _time := 0.0
var _since_redraw := 0.0
var _drawn_occlusion := -1.0
var _drawn_time := 0.0
var _light: PointLight2D
var _back: _Glow
var _sheen: _Sheen
var _front: _Wash
var _reach := 0.0
## 每道光柱固定的樣子（相對光源）：起點、寬度、實際長度（照到地面為止）、亮度比例、閃動的相位。
var shaft_starts := PackedVector2Array()
var shaft_widths := PackedFloat32Array()
var shaft_lengths := PackedFloat32Array()
var shaft_levels := PackedFloat32Array()
var shaft_phases := PackedFloat32Array()
## 1 = 這道光柱照到地面（落點畫反光）。
var shaft_landed := PackedByteArray()
var shaft_direction := Vector2.DOWN
## 光源正下方的地面（相對光源的 y；INF = 沒有地面）：前面那層漫射只到地面為止，走道邊緣不被蓋淡。
var wash_floor := INF


## floor_at(x) 回傳世界座標 x 處地面的 y（光柱照到地面為止，並在落點畫反光）；空的 Callable 代表沒有地面。
func setup(p_data: KeyLightData, tile_size: float, floor_at := Callable()) -> void:
	data = p_data
	position = data.tile * tile_size
	_reach = maxf(data.halo_radius * WASH_SCALE, data.shaft_length + data.shaft_spread)
	if floor_at.is_valid():
		wash_floor = float(floor_at.call(position.x)) - position.y
	_build_shafts(floor_at)


func _build_shafts(floor_at: Callable) -> void:
	shaft_direction = Vector2.DOWN.rotated(-deg_to_rad(data.shaft_angle))
	var across := shaft_direction.orthogonal()
	for i in data.shaft_count:
		var h := _hash(i)
		var t := 0.5 if data.shaft_count == 1 else float(i) / float(data.shaft_count - 1)
		var offset := (t - 0.5) * data.shaft_spread + (h - 0.5) * data.shaft_spread / maxf(1.0, data.shaft_count) * 0.6
		var start := across * offset + shaft_direction * (data.halo_radius * 0.12)
		var length := data.shaft_length * (0.7 + 0.3 * _hash(i + 31))
		var landed := 0
		if floor_at.is_valid() and shaft_direction.y > 0.05:
			# 沿光柱往下找第一個落在地面以下的點（每 4 像素一步，只在建立時算一次）。
			var step := 0.0
			while step < length:
				var point := position + start + shaft_direction * step
				if point.y >= float(floor_at.call(point.x)):
					length = step
					landed = 1
					break
				step += 4.0
		shaft_starts.append(start)
		shaft_widths.append(data.shaft_width * (0.6 + 0.8 * _hash(i + 17)))
		shaft_lengths.append(length)
		shaft_levels.append(0.7 + 0.6 * _hash(i + 47))
		shaft_phases.append(h)
		shaft_landed.append(landed)


static func _hash(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + 4.1414) * 43758.5453, 1.0)


func _ready() -> void:
	name = "KeyLight"
	occlusion = _target_occlusion()
	_light = LightKit.create_point_light(data.color, data.light_radius, _light_energy(), false, false)
	_light.name = "KeyLightSurface"
	add_child(_light)
	_back = _Glow.new()
	_back.key = self
	# 一般混合（往主光色靠）而不是加法：亮度永遠不超過主光色本身、不會超過泛光門檻，
	# 光心不會變成一塊純白，也不會泛光泛到上層的提示牌與對話氣泡（BG-70）。
	_back.material = LightKit.emissive_material()
	_back.z_as_relative = false
	_back.z_index = WorldLayers.KEY_LIGHT_BACK
	add_child(_back)
	_sheen = _Sheen.new()
	_sheen.key = self
	_sheen.material = LightKit.additive_emissive_material()
	_sheen.z_as_relative = false
	_sheen.z_index = WorldLayers.KEY_LIGHT_SHEEN
	add_child(_sheen)
	_front = _Wash.new()
	_front.key = self
	_front.material = LightKit.emissive_material()
	_front.z_as_relative = false
	_front.z_index = WorldLayers.KEY_LIGHT_FRONT
	add_child(_front)
	Settings.display_changed.connect(_on_display_changed)
	_on_display_changed()


func _process(delta: float) -> void:
	_time += delta
	occlusion = _target_occlusion()
	_light.energy = _light_energy()
	var show := LightQuality.volumetrics() and _on_screen()
	_back.visible = show
	_sheen.visible = show and data.shaft_count > 0
	_front.visible = show and data.front_wash > 0.0
	if not show:
		return
	_since_redraw += delta
	var shimmer := not Settings.get_reduce_ui_motion() and data.shaft_count > 0
	var changed := absf(occlusion - _drawn_occlusion) >= REDRAW_STEP or (shimmer and _time - _drawn_time >= 1.0 / REDRAW_FPS)
	if changed and _since_redraw >= 1.0 / REDRAW_FPS:
		_since_redraw = 0.0
		_drawn_occlusion = occlusion
		_drawn_time = _time
		_back.queue_redraw()
		_sheen.queue_redraw()
		_front.queue_redraw()


## 光暈的半徑與中心亮度（給繪製與檢查用）。
func halo_radius() -> float:
	return data.halo_radius * lerpf(1.0, HALO_SHRINK, occlusion)


func halo_alpha() -> float:
	return data.halo_alpha * lerpf(1.0, HALO_DIM, occlusion)


## 光心的顏色：主光色往白靠一點再壓暗一階，經過區段的亮部色調後每個色版仍不到頂（不是純白）。
func core_color() -> Color:
	return data.color.lerp(Color.WHITE, CORE_WHITEN) * CORE_LEVEL


## 第 i 道光柱目前的亮度（含遮住程度與緩慢的明暗）。
func shaft_alpha(i: int) -> float:
	var alpha := shaft_strength() * SHAFT_ALPHA * shaft_levels[i]
	if not Settings.get_reduce_ui_motion():
		var h := shaft_phases[i]
		var period := lerpf(SHAFT_SHIMMER_PERIOD.x, SHAFT_SHIMMER_PERIOD.y, h)
		alpha *= 1.0 + SHAFT_SHIMMER * sin(TAU * _drawn_time / period + h * 9.0)
	return clampf(alpha, 0.0, 1.0)


## 光柱的明顯程度（0~1）：遮得越多越明顯。
func shaft_strength() -> float:
	return lerpf(SHAFT_FLOOR, 1.0, smoothstep(0.3, 0.85, occlusion))


func _target_occlusion() -> float:
	if forced_occlusion >= 0.0:
		return clampf(forced_occlusion, 0.0, 1.0)
	if Settings.get_reduce_ui_motion():
		return data.middle_occlusion()
	# 「減少閃光」時變化再慢一倍。
	return data.occlusion_at(_time * (0.5 if Settings.get_reduce_flashes() else 1.0))


func _light_energy() -> float:
	return data.energy * lerpf(1.0, LIGHT_DIM, occlusion)


func _on_screen() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var view := viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	return view.intersects(Rect2(global_position - Vector2(_reach, _reach), Vector2(_reach, _reach) * 2.0))


func _on_display_changed() -> void:
	_drawn_occlusion = -1.0
	_process(0.0)


## 角色後面：光暈與光柱（加法混合）。
class _Glow:
	extends Node2D

	const SIDES: Array[float] = [-1.0, 1.0]

	var key: KeyLight
	var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])

	func _draw() -> void:
		var data := key.data
		var radius := key.halo_radius()
		var alpha := key.halo_alpha()
		var soft := LightKit.soft_texture()
		# 外圈大片柔光往主光色靠，內圈小而亮、偏暖白（見 core_color）；兩層都是一般混合，最亮處就是 core_color。
		draw_texture_rect(soft, Rect2(-Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(data.color, alpha * 0.75))
		var core := radius * 0.38
		draw_texture_rect(soft, Rect2(-Vector2(core, core), Vector2(core, core) * 2.0), false, Color(key.core_color(), minf(1.0, alpha * 1.3)))
		if data.shaft_count > 0:
			_draw_shafts(data)

	func _draw_shafts(data: KeyLightData) -> void:
		var across := key.shaft_direction.orthogonal()
		for i in key.shaft_starts.size():
			var length := key.shaft_lengths[i]
			if length < 4.0:
				continue
			var alpha := key.shaft_alpha(i)
			_draw_shaft(key.shaft_starts[i], key.shaft_direction, across, key.shaft_widths[i], length, Color(data.color, clampf(alpha, 0.0, 1.0)))

	## 一道光柱：橫切面從中心往兩側淡到 0；沿長度先亮起來、再淡到 0，沒有任何硬邊。
	func _draw_shaft(start: Vector2, direction: Vector2, across: Vector2, width: float, length: float, color: Color) -> void:
		var clear := Color(color, 0.0)
		var lit_at := 0.22
		for side in SIDES:
			var edge := across * (width * 0.5 * side)
			var mid := direction * (length * lit_at)
			var tip := direction * length
			# 起點到最亮處（起點也有一點寬度，從淡變亮）。
			_quad[0] = start
			_quad[1] = start + edge * 0.6
			_quad[2] = start + mid + edge
			_quad[3] = start + mid
			_colors[0] = Color(color, color.a * 0.35)
			_colors[1] = clear
			_colors[2] = clear
			_colors[3] = color
			draw_polygon(_quad, _colors)
			# 最亮處到末端。
			_quad[0] = start + mid
			_quad[1] = start + mid + edge
			_quad[2] = start + tip + edge * 1.3
			_quad[3] = start + tip
			_colors[0] = color
			_colors[1] = clear
			_colors[2] = clear
			_colors[3] = clear
			draw_polygon(_quad, _colors)



## 地面上：光柱落點的反光（照到地面的光柱才有），畫在地形頂面上，讓走道邊緣更清楚。
class _Sheen:
	extends Node2D

	var key: KeyLight

	func _draw() -> void:
		for i in key.shaft_starts.size():
			if key.shaft_landed[i] != 1:
				continue
			var land := key.shaft_starts[i] + key.shaft_direction * key.shaft_lengths[i]
			var half := key.shaft_widths[i] * 0.9
			LightShaft.draw_floor_sheen(self, land.x - half, land.x + half, land.y, key.data.color, key.shaft_alpha(i) * 1.2)


## 角色前面：很淡的一層主光顏色（一般混合，不加亮）。
class _Wash:
	extends Node2D

	var key: KeyLight

	func _draw() -> void:
		var data := key.data
		var radius := data.halo_radius * KeyLight.WASH_SCALE * lerpf(1.0, 0.7, key.occlusion)
		var alpha := data.front_wash * lerpf(1.0, 0.6, key.occlusion)
		var soft := LightKit.soft_texture()
		var full := Rect2(-Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		# 只畫到地面為止（對應貼圖的同一段），地面以下不加漫射。
		var bottom := minf(full.end.y, key.wash_floor)
		if bottom <= full.position.y:
			return
		var kept := (bottom - full.position.y) / full.size.y
		var size := Vector2(soft.get_width(), soft.get_height())
		draw_texture_rect_region(soft, Rect2(full.position, Vector2(full.size.x, full.size.y * kept)), Rect2(Vector2.ZERO, Vector2(size.x, size.y * kept)), Color(data.color, alpha))
