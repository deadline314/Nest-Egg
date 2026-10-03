class_name UiHint
extends Control
## 靠近物件的提示框：切角底、底部一個指向物件的小箭頭、出現時彈出。
## 位置由呼叫端決定（箭頭尖端 = 控制項底邊中央）。

const ARROW := 4.0

var _text: String = ""
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_label)
	pivot_offset_ratio = Vector2(0.5, 1.0)


func set_text(text: String) -> void:
	if text == _text:
		return
	_text = text
	_label.text = text
	var text_size := UiKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY)
	size = Vector2(ceilf(text_size.x) + 16.0, text_size.y + 8.0 + ARROW)
	custom_minimum_size = size
	_label.position = Vector2(8, 3)
	_label.size = Vector2(size.x - 16.0, text_size.y)
	queue_redraw()


## 出現動畫：從 0.6 倍彈到 1。
func pop() -> void:
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.1)


func _draw() -> void:
	var body := Rect2(0, 0, size.x, size.y - ARROW)
	var box := ChamferBox.make(Color(0.03, 0.06, 0.09, 0.92), Palette.CYAN_DIM, 3)
	box.draw(get_canvas_item(), body)
	var cx := roundf(size.x * 0.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - ARROW, body.size.y - 1.0), Vector2(cx + ARROW, body.size.y - 1.0), Vector2(cx, size.y)]), Palette.CYAN_DIM)
