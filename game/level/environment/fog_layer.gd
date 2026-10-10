class_name FogLayer
extends Node2D
## 地面霧氣：貼地的半透明色帶與緩慢飄移的霧團，只畫在鏡頭範圍內。
## 霧貼著每一欄實際的地面（鏡頭中央往下第一個可站的面），不畫進地面的剖面；霧團是邊緣淡出的柔光，不是實心圓。

const BAND_HEIGHT := 70.0
const BLOBS := 7
## 光源染色的影響距離與染色程度、光源清單的更新間隔（秒）。
const TINT_RANGE := 240.0
const TINT_STRENGTH := 0.7
const TINT_REFRESH := 0.25
## 找地面時從鏡頭中央往上多少像素開始找（讓站在中央平台上的角色腳下也有霧）。
const FLOOR_SEARCH_ABOVE := 40.0
## 霧團：柔光貼圖的不透明度（中心）與壓扁比例。
const BLOB_ALPHA := 0.09
const BLOB_FLATTEN := 0.55

var ground_y := 320.0
## 關卡的格子資料，由關卡設定：有它就逐欄找地面；沒有（測試、預覽）就用 ground_y 一條線。
var layout: LevelLayout
var color := Color(0.55, 0.45, 0.85, 1.0)
## 濃度倍率（1 = 標準），由光影設定調整。
var density := 1.0

var _time := 0.0
## 附近光源（染色用），定期更新，不在每影格配置陣列。
var _tint_sources: Array[PointLight2D] = []
var _tint_refresh := 0.0


func _ready() -> void:
	LightKit.mark_emissive(self)


func _process(delta: float) -> void:
	_time += delta
	_tint_refresh -= delta
	if _tint_refresh <= 0.0:
		_tint_refresh = TINT_REFRESH
		_tint_sources.clear()
		if LightQuality.volumetrics():
			for node in get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
				var light := node as PointLight2D
				if light != null and light.visible and light.enabled and light.energy > 0.3:
					_tint_sources.append(light)
	queue_redraw()


func _draw() -> void:
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var view_size := get_viewport().get_visible_rect().size
	var top_left := inverse * Vector2.ZERO
	var bottom_right := inverse * view_size
	var left := top_left.x
	var right := bottom_right.x
	var from_y := (top_left.y + bottom_right.y) * 0.5 - FLOOR_SEARCH_ABOVE
	var band_alpha := clampf(0.16 * density, 0.0, 1.0)
	var clear := Color(color, 0.0)
	var solid := Color(color, band_alpha)
	# 色帶：同一個地面高度的相鄰欄合成一塊。
	var step := float(layout.tile_size) if layout != null else right - left
	var run_start := left
	var run_floor := _floor_at(left, from_y)
	var x := left + step
	while x <= right + step:
		var floor_here := _floor_at(minf(x, right), from_y) if x < right else INF
		if x >= right or not is_equal_approx(floor_here, run_floor):
			var run_end := minf(x, right)
			if run_floor != INF and run_end > run_start:
				draw_polygon(PackedVector2Array([Vector2(run_start, run_floor - BAND_HEIGHT), Vector2(run_end, run_floor - BAND_HEIGHT),
						Vector2(run_end, run_floor), Vector2(run_start, run_floor)]), PackedColorArray([clear, clear, solid, solid]))
			run_start = run_end
			run_floor = floor_here
		x += step
	var soft := LightKit.soft_texture()
	for i in BLOBS:
		var span := right - left + 200.0
		var blob_x := left - 100.0 + fposmod(i * 173.0 + _time * (8.0 + i * 2.0), span)
		var floor_y := _floor_at(blob_x, from_y)
		if floor_y == INF:
			continue
		var blob := Vector2(blob_x, floor_y - 18.0 - (i % 3) * 10.0)
		var radius := 40.0 + (i % 4) * 12.0
		draw_texture_rect(soft, Rect2(blob - Vector2(radius, radius * BLOB_FLATTEN), Vector2(radius * 2.0, radius * 2.0 * BLOB_FLATTEN)), false,
				Color(_tinted(blob), clampf(BLOB_ALPHA * density, 0.0, 1.0)))


## world_x 這一欄的地面高度（世界 y）：從 from_y 往下第一個可站的面；沒有就回傳 INF。
func _floor_at(world_x: float, from_y: float) -> float:
	if layout == null:
		return ground_y
	var column := int(floor(world_x / layout.tile_size))
	if column < 0 or column >= layout.width:
		return INF
	return layout.floor_below(column, maxi(0, int(from_y / layout.tile_size)))


## 霧團被附近光源染色：越靠近光源越接近光源的顏色，光池之外維持霧本來的冷色。
func _tinted(position: Vector2) -> Color:
	var result := color
	for light in _tint_sources:
		# 清單每 0.25 秒才更新，期間燈可能已被移除（壞掉、關卡中途生成的臨時燈）。
		if not is_instance_valid(light):
			continue
		var distance := light.global_position.distance_to(to_global(position))
		if distance < TINT_RANGE:
			var weight := (1.0 - distance / TINT_RANGE) * TINT_STRENGTH
			result = result.lerp(light.color, weight)
	return result
