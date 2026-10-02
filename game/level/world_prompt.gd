class_name WorldPrompt
extends Node2D
## 世界提示（遊戲內的 Hover 說明）：玩家靠近時在物件上方淡入一行重點說明，離開時淡出。
## 可掛在任何物件下重複使用（道具、載具、檢查點、教學看板）。

const FADE_SPEED := 6.0
const PADDING := Vector2(5, 3)
const FONT_SIZE := 9

@export var text: String = ""
@export var radius: float = 48.0
@export var offset: Vector2 = Vector2(0, -34)

var enabled := true
var _alpha := 0.0
var _font: Font
var _player_ref: WeakRef


func _ready() -> void:
	z_index = 20
	_font = UiKit.font()
	position = offset


func _process(delta: float) -> void:
	var target := 1.0 if enabled and _player_near() else 0.0
	var previous := _alpha
	_alpha = move_toward(_alpha, target, FADE_SPEED * delta)
	if _alpha != previous or _alpha > 0.0:
		queue_redraw()


func _player_near() -> bool:
	var player: Node2D = _player_ref.get_ref() as Node2D if _player_ref != null else null
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node2D
		if player == null:
			return false
		_player_ref = weakref(player)
	return player.global_position.distance_to(global_position - offset) <= radius


func _draw() -> void:
	if _alpha <= 0.0 or text.is_empty() or _font == null:
		return
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y) - PADDING, size + PADDING * 2.0)
	draw_rect(rect, Color(Palette.UI_PANEL, 0.85 * _alpha))
	draw_rect(rect, Color(Palette.CYAN_DIM, _alpha), false, 1.0)
	draw_string(_font, Vector2(-size.x * 0.5, -size.y * 0.25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			Color(Palette.UI_TEXT, _alpha))
