class_name FogLayer
extends Node2D
## 地面霧氣：貼地的半透明色帶與緩慢飄移的霧團，只畫在鏡頭範圍內。

const BAND_HEIGHT := 70.0
const BLOBS := 7

var ground_y := 320.0
var color := Color(0.55, 0.45, 0.85, 1.0)
## 濃度倍率（1 = 標準），由光影設定調整。
var density := 1.0

var _time := 0.0


func _ready() -> void:
	LightKit.mark_emissive(self)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var view_size := get_viewport().get_visible_rect().size
	var left := (inverse * Vector2.ZERO).x
	var right := (inverse * view_size).x
	var top := ground_y - BAND_HEIGHT
	var band := PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, ground_y + 20), Vector2(left, ground_y + 20)])
	var band_alpha := clampf(0.16 * density, 0.0, 1.0)
	draw_polygon(band, PackedColorArray([Color(color, 0.0), Color(color, 0.0), Color(color, band_alpha), Color(color, band_alpha)]))
	for i in BLOBS:
		var span := right - left + 200.0
		var x := left - 100.0 + fposmod(i * 173.0 + _time * (8.0 + i * 2.0), span)
		var y := ground_y - 18.0 - (i % 3) * 10.0
		draw_circle(Vector2(x, y), 40.0 + (i % 4) * 12.0, Color(color, clampf(0.035 * density, 0.0, 1.0)))
