class_name PropPaperVisual
extends Node2D
## One physical receipt strip, shared by its outlet and temporary hand carrier.
## Presentation only: neither drawing nor reparenting grants an inventory item.

const PAPER_COLOR := Color(0.744, 0.72, 0.64)
const PAPER_INK := Color(0.36, 0.38, 0.44, 0.8)

var width := 4.0
var length := 8.0
var progress := 0.0


func _draw() -> void:
	var visible_length := length * progress
	if visible_length < 0.5:
		return
	var left := -width * 0.5
	draw_rect(Rect2(left, 0.0, width, visible_length), PAPER_COLOR)
	var line := 1.5
	while line < visible_length - 1.2:
		draw_line(Vector2(left + 0.7, line), Vector2(left + width - 0.7, line), PAPER_INK, 0.5)
		line += 1.6
	var tooth := width / 3.0
	for i in 3:
		var x := left + tooth * i
		draw_colored_polygon(PackedVector2Array([Vector2(x, visible_length), Vector2(x + tooth, visible_length),
			Vector2(x + tooth * 0.5, visible_length + 0.9)]), PAPER_COLOR)
