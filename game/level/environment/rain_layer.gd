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
## 風造成的水平飄移（相對下落速度的比例）。
const WIND := 0.16
const SPLASHES_PER_SECOND := 40.0

## 每一欄地表的高度（像素）。由關卡設定；INF 代表沒有地面。
var surface_heights := PackedFloat32Array()
var tile_size := 16

var _time := 0.0
var _splash_budget := 0.0


func _process(delta: float) -> void:
	_time += delta
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
	var direction := Vector2(WIND, 1.0).normalized()
	for layer_index in LAYERS.size():
		var layer: Dictionary = LAYERS[layer_index]
		var speed: float = layer["speed"]
		var length: float = layer["length"]
		var color := Color(Palette.RAIN, layer["alpha"])
		var width: float = layer["width"]
		for i in int(layer["count"]):
			var seed_x := _hash01(i * 7 + layer_index * 1013)
			var seed_y := _hash01(i * 13 + layer_index * 7919 + 5)
			var raw := Vector2(seed_x * TILE_W + _time * speed * WIND, seed_y * TILE_H + _time * speed)
			var p := Vector2(
				view.position.x + fposmod(raw.x - view.position.x, TILE_W),
				view.position.y + fposmod(raw.y - view.position.y, TILE_H))
			if p.y > _surface_at(p.x):
				continue
			draw_line(p - direction * length, p, color, width)


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
