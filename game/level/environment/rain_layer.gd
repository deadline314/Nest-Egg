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

## 每一欄地表的高度（像素）。由關卡設定；INF 代表沒有地面。
var surface_heights := PackedFloat32Array()
var tile_size := 16

var _time := 0.0
## 風的累積飄移量（風速隨時間變化，所以位置要累加而不是用時間乘風速）。
var _drift := 0.0
var _splash_budget := 0.0


func _ready() -> void:
	LightKit.mark_emissive(self)


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
	for layer_index in LAYERS.size():
		var layer: Dictionary = LAYERS[layer_index]
		var speed: float = layer["speed"]
		var length: float = layer["length"]
		var color := Color(Palette.RAIN, layer["alpha"])
		var width: float = layer["width"]
		for i in int(layer["count"]):
			var seed_x := _hash01(i * 7 + layer_index * 1013)
			var seed_y := _hash01(i * 13 + layer_index * 7919 + 5)
			var raw := Vector2(seed_x * TILE_W + _drift * speed, seed_y * TILE_H + _time * speed)
			var p := Vector2(
				view.position.x + fposmod(raw.x - view.position.x, TILE_W),
				view.position.y + fposmod(raw.y - view.position.y, TILE_H))
			var surface := _surface_at(p.x)
			if p.y > surface:
				if layer_index == LAYERS.size() - 1 and surface != INF:
					_draw_ripple(p.x, surface, (p.y - surface) / speed)
				continue
			draw_line(p - direction * length, p, color, width)
			if layer_index == LAYERS.size() - 1:
				draw_circle(p, 0.9, Color(Palette.RAIN.lightened(0.5), minf(1.0, layer["alpha"] * 1.2)))  # 近景雨滴的亮頭


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
