class_name InventoryBackdrop
extends Control
## 靜態深色底隔開場景；細節集中在頁首與頁尾，不在文字背後滾動。


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.04, 0.065))
	draw_rect(Rect2(0, 0, size.x, 45), Color(0.055, 0.085, 0.12))
	draw_rect(Rect2(0, size.y - 31, size.x, 31), Color(0.04, 0.065, 0.09))
	draw_line(Vector2(24, 45), Vector2(size.x - 24, 45), UiTheme.PANEL_EDGE, 1)
	draw_line(Vector2(24, size.y - 31), Vector2(size.x - 24, size.y - 31), UiTheme.PANEL_EDGE, 1)
