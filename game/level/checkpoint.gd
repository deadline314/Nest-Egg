class_name Checkpoint
extends Area2D
## 檢查點：觸碰後記錄位置與武器配置（依難度可能回滿血），死亡時從這裡重來。

var activated := false

var _time := 0.0
var _light: PointLight2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 40)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -20)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	_light = LightKit.create_point_light(Palette.CYAN, 80.0, 0.0, true)
	_light.position = Vector2(0, -30)
	add_child(_light)
	var prompt := WorldPrompt.new()
	prompt.text = "檢查點：死亡後從這裡重來"
	prompt.radius = 60.0
	prompt.offset = Vector2(0, -46)
	add_child(prompt)
	# 從這個檢查點重生時直接顯示為已啟動。
	if GameState.has_checkpoint and GameState.checkpoint_position.distance_to(global_position) < 1.0:
		_set_active(false)


func _on_body_entered(body: Node2D) -> void:
	var player := Pickup.resolve_player(body)
	if player == null or activated or player.is_dead():
		return
	_set_active(true)
	GameState.set_checkpoint(global_position, player.checkpoint_snapshot())
	if GameState.difficulty.checkpoint_heals:
		player.health.heal(player.health.max_health)
	EventBus.toast_requested.emit("檢查點已記錄")


func _set_active(with_effects: bool) -> void:
	activated = true
	_light.energy = 0.9
	if with_effects:
		Fx.burst(global_position + Vector2(0, -30), Palette.CYAN, 16, 140.0)
		Fx.flash_light(global_position + Vector2(0, -30), Palette.CYAN, 140.0, 2.0, 0.5)
		Sfx.play(&"ui_confirm", -4.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2(0, 0), Vector2(0, -40), Palette.TERRAIN_TOP, 2.0)
	var color := LightKit.glow(Palette.CYAN, 2.0 + 0.5 * sin(_time * 4.0)) if activated else Palette.CYAN_DIM.darkened(0.3)
	var wave := sin(_time * 5.0) * 1.5
	draw_colored_polygon(PackedVector2Array([Vector2(1, -40), Vector2(13, -36 + wave), Vector2(1, -31)]), color)
	draw_circle(Vector2(0, -41), 2.0, color)
