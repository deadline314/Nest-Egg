class_name HintSign
extends Node2D
## 教學看板：地圖數字字元（1~9）對應 LevelData.hints 的文字，玩家靠近時顯示重點操作說明。

var text := ""

var _time := 0.0


func _ready() -> void:
	var prompt := WorldPrompt.new()
	prompt.text = text
	prompt.radius = 64.0
	prompt.offset = Vector2(0, -30)
	add_child(prompt)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2(0, 0), Vector2(0, -12), Palette.TERRAIN_TOP, 2.0)
	draw_rect(Rect2(-7, -20, 14, 9), Palette.TERRAIN_EDGE)
	var glow := LightKit.glow(Palette.CYAN, 1.5 + 0.4 * sin(_time * 3.0))
	draw_rect(Rect2(-7, -20, 14, 9), glow, false, 1.0)
	draw_line(Vector2(0, -18), Vector2(0, -15), glow, 1.5)
	draw_circle(Vector2(0, -13), 0.8, glow)
