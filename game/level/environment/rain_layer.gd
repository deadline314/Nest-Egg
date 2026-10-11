class_name RainLayer
extends Node2D
## 雨：每滴雨的位置由雜湊函式與時間決定（不保存任何狀態、不配置記憶體），在鏡頭範圍內循環。
## 三層景深（遠層慢而淡、近層快而亮）；雨滴落到地表會停下並濺起水花；有屋頂的區域不下雨。

const TILE_W := 600.0
const TILE_H := 360.0
const LAYERS := [
	{"count": 80, "speed": 520.0, "length": 6.0, "alpha": 0.16, "width": 1.0},
	{"count": 70, "speed": 700.0, "length": 10.0, "alpha": 0.26, "width": 1.0},
	{"count": 45, "speed": 900.0, "length": 15.0, "alpha": 0.4, "width": 1.5},
]
## 風造成的水平飄移（相對下落速度的比例）：基準值，再疊上緩慢的陣風。
const WIND := 0.16
const GUST_AMOUNT := 0.55
## 雨滴落地後的漣漪：持續秒數、最大半徑與亮度（只有最近的一層畫，落地前後各一道橢圓，克制不搶眼）。
const RIPPLE_TIME := 0.12
const RIPPLE_RADIUS := 5.0
const RIPPLE_ALPHA := 0.22
const SPLASHES_PER_SECOND := 40.0
## 近景雨滴亮頭的半邊長（像素）。
const HEAD_SIZE := 0.8

## 每一欄地表的高度（像素）。由關卡設定；INF 代表沒有地面。
var surface_heights := PackedFloat32Array()
var tile_size := 16

var _time := 0.0
## 風的累積飄移量（風速隨時間變化，所以位置要累加而不是用時間乘風速）。
var _drift := 0.0
var _splash_budget := 0.0
var _seeds: Array[PackedVector2Array] = []
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	LightKit.mark_emissive(self)
	_build_mesh()


## 每滴雨的起點（由雜湊決定，固定不變）與整片雨的頂點、顏色、索引；每影格只改頂點位置，不配置記憶體。
func _build_mesh() -> void:
	_seeds.clear()
	_points.clear()
	_colors.clear()
	_indices.clear()
	for layer_index in LAYERS.size():
		var layer: Dictionary = LAYERS[layer_index]
		var color := Color(Palette.RAIN, layer["alpha"])
		var seeds := PackedVector2Array()
		for i in int(layer["count"]):
			seeds.append(Vector2(_hash01(i * 7 + layer_index * 1013) * TILE_W, _hash01(i * 13 + layer_index * 7919 + 5) * TILE_H))
			_add_quad(color)
			if layer_index == LAYERS.size() - 1:
				_add_quad(Color(Palette.RAIN.lightened(0.5), minf(1.0, float(layer["alpha"]) * 1.2)))
		_seeds.append(seeds)


func _add_quad(color: Color) -> void:
	var base := _points.size()
	for corner in 4:
		_points.append(Vector2.ZERO)
		_colors.append(color)
	for offset: int in [0, 1, 2, 0, 2, 3]:
		_indices.append(base + offset)


## 目前的風（含陣風）：兩個不同週期的正弦疊起來，沒有明顯的規律。
func _wind() -> float:
	return WIND * (1.0 + GUST_AMOUNT * (0.6 * sin(_time * 0.37) + 0.4 * sin(_time * 1.13 + 1.7)))


func _process(delta: float) -> void:
	_time += delta
	_drift += _wind() * delta
	_splash_budget += SPLASHES_PER_SECOND * delta
	var view := _visible_rect()
	while _splash_budget >= 1.0:
		_splash_budget -= 1.0
		var x := randf_range(view.position.x, view.end.x)
		var surface := _surface_at(x)
		if surface > view.position.y and surface < view.end.y:
			Fx.splash(Vector2(x, surface))
	queue_redraw()


func _draw() -> void:
	var view := _visible_rect()
	var direction := Vector2(_wind(), 1.0).normalized()
	var side := Vector2(direction.y, -direction.x)
	var vertex := 0
	for layer_index in LAYERS.size():
		var layer: Dictionary = LAYERS[layer_index]
		var speed: float = layer["speed"]
		var tail := direction * float(layer["length"])
		var half := side * float(layer["width"]) * 0.5
		var nearest := layer_index == LAYERS.size() - 1
		var seeds := _seeds[layer_index]
		var shift := Vector2(_drift * speed - view.position.x, _time * speed - view.position.y)
		for i in seeds.size():
			var p := Vector2(view.position.x + fposmod(seeds[i].x + shift.x, TILE_W), view.position.y + fposmod(seeds[i].y + shift.y, TILE_H))
			var surface := _surface_at(p.x)
			if p.y > surface:
				# 已經落地的雨滴不畫（四個頂點收在同一點），最近的一層改畫漣漪。
				for corner in (8 if nearest else 4):
					_points[vertex + corner] = p
				vertex += 8 if nearest else 4
				if nearest and surface != INF:
					_draw_ripple(p.x, surface, (p.y - surface) / speed)
				continue
			_points[vertex] = p - tail - half
			_points[vertex + 1] = p - tail + half
			_points[vertex + 2] = p + half
			_points[vertex + 3] = p - half
			vertex += 4
			if nearest:  # 近景雨滴的亮頭
				var head := direction * HEAD_SIZE
				var head_side := side * HEAD_SIZE
				_points[vertex] = p - head - head_side
				_points[vertex + 1] = p - head + head_side
				_points[vertex + 2] = p + head + head_side
				_points[vertex + 3] = p + head - head_side
				vertex += 4
	# 所有雨絲與亮頭合成一次繪製（每個頂點帶自己的顏色）。
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _points, _colors)


## 落地漣漪：雨滴落地後 age 秒內，在落點畫一道向外擴散、漸淡的扁橢圓（沒有狀態，位置與時間全由雨滴本身推算）。
func _draw_ripple(x: float, surface: float, age: float) -> void:
	if age > RIPPLE_TIME:
		return
	var t := age / RIPPLE_TIME
	var radius := 1.5 + RIPPLE_RADIUS * t
	var color := Color(Palette.RAIN, RIPPLE_ALPHA * (1.0 - t))
	draw_set_transform(Vector2(x, surface), 0.0, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 12, color, 1.0)
	draw_set_transform(Vector2.ZERO)


func _surface_at(x: float) -> float:
	if surface_heights.is_empty():
		return INF
	var column := clampi(int(x / tile_size), 0, surface_heights.size() - 1)
	return surface_heights[column]


func _visible_rect() -> Rect2:
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var size := get_viewport().get_visible_rect().size
	var top_left := inverse * Vector2.ZERO
	var bottom_right := inverse * size
	return Rect2(top_left, bottom_right - top_left)


static func _hash01(n: int) -> float:
	var h := (n * 374761393 + 668265263) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h % 10007) / 10007.0
