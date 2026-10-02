class_name Lamp
extends Node2D
## 場景燈：投射陰影的動態光源，偶爾閃爍營造廢墟氛圍。

const FLICKER_CHANCE := 0.008

var color := Palette.CYAN
var radius := 190.0

var _light: PointLight2D
var _flicker_left := 0.0
var _base_energy := 1.5


func _ready() -> void:
	LightKit.mark_emissive(self)
	_light = LightKit.create_point_light(color, radius, _base_energy, true)
	add_child(_light)


func _process(delta: float) -> void:
	if _flicker_left > 0.0:
		_flicker_left -= delta
		_light.energy = _base_energy * (0.2 if int(_flicker_left * 30.0) % 2 == 0 else 1.0)
	elif randf() < FLICKER_CHANCE:
		_flicker_left = randf_range(0.1, 0.35)
	else:
		_light.energy = _base_energy


func _draw() -> void:
	draw_rect(Rect2(-6, -2, 12, 3), Palette.TERRAIN_TOP)
	draw_rect(Rect2(-4, 1, 8, 2), LightKit.glow(color, 2.5))
	# 光錐（純裝飾，非常淡）
	draw_colored_polygon(PackedVector2Array([Vector2(-4, 3), Vector2(4, 3), Vector2(40, 120), Vector2(-40, 120)]),
			Color(color, 0.035))
