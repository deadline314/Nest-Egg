class_name UiDivider
extends Control
## 分隔線：一條細線，中央有一個小菱形。

@export var color: Color = Palette.CYAN_DIM


func _init() -> void:
	custom_minimum_size = Vector2(0, 7)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var cy := roundf(size.y * 0.5)
	var cx := roundf(size.x * 0.5)
	draw_line(Vector2(0, cy), Vector2(cx - 6.0, cy), color, 1.0)
	draw_line(Vector2(cx + 6.0, cy), Vector2(size.x, cy), color, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 3, cy), Vector2(cx, cy - 3), Vector2(cx + 3, cy), Vector2(cx, cy + 3)]), Palette.CYAN)
