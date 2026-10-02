class_name Pickup
extends Area2D
## 道具基底：玩家（或玩家駕駛的載具）碰到即觸發 _apply()；回傳 false 代表不需要（例如滿血），道具保留。
## 子類別覆寫：_apply(player)、_draw_icon()、hint_text()

const BOB_SPEED := 3.0
const BOB_HEIGHT := 2.0
## 玩家停留在道具上時（例如原本滿血後受傷）重新嘗試拾取的間隔。
const RETRY_INTERVAL := 0.3

var _time := 0.0
var _retry_left := RETRY_INTERVAL


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -8)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	var hint := hint_text()
	if not hint.is_empty():
		var prompt := WorldPrompt.new()
		prompt.text = hint
		prompt.radius = 56.0
		prompt.offset = Vector2(0, -26)
		add_child(prompt)


func hint_text() -> String:
	return ""


func _apply(_player: Player) -> bool:
	return false


func _draw_icon() -> void:
	pass


func _process(delta: float) -> void:
	_time += delta
	_retry_left -= delta
	if _retry_left <= 0.0 and monitoring:
		_retry_left = RETRY_INTERVAL
		for body in get_overlapping_bodies():
			_on_body_entered(body)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -8 + sin(_time * BOB_SPEED) * BOB_HEIGHT))
	_draw_icon()
	draw_set_transform(Vector2.ZERO)


func _on_body_entered(body: Node2D) -> void:
	var player := resolve_player(body)
	if player == null or player.is_dead():
		return
	if is_queued_for_deletion():
		return
	if _apply(player):
		Fx.burst(global_position + Vector2(0, -8), Palette.CYAN, 10, 100.0)
		Fx.flash_light(global_position + Vector2(0, -8), Palette.CYAN, 60.0, 1.2, 0.25)
		Sfx.play(&"pickup", -6.0)
		set_deferred(&"monitoring", false)
		queue_free()


## 碰到的可能是玩家本人，或玩家正在駕駛的載具。
static func resolve_player(body: Node) -> Player:
	if body is Player:
		return body as Player
	if body is Vehicle:
		return (body as Vehicle).driver
	return null
