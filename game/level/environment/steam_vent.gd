class_name SteamVent
extends Node2D
## 地面排氣孔：週期性冒出緩慢上升的蒸汽，被燈光照到時特別有氛圍。

const INTERVAL := 0.12

var _timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = INTERVAL * randf_range(0.6, 1.4)
		Fx.steam(global_position + Vector2(randf_range(-6, 6), -2))


func _draw() -> void:
	draw_rect(Rect2(-10, -3, 20, 3), Palette.TERRAIN_EDGE)
	for i in 4:
		draw_line(Vector2(-8 + i * 5, -3), Vector2(-8 + i * 5, 0), Color("05070c"), 1.0)
