class_name ShopStation
extends Area2D
## 補給點：玩家站在旁邊按互動鍵開啟貨架。貨架內容是 ShopData。原點在底邊中點。

const REACH := Vector2(36, 40)
const PROMPT_RADIUS := 70.0

var data: ShopData
var cell := Vector2i.ZERO

var _player_in_range := false
var _time := 0.0
var _screen: ShopScreen


func configure(p_data: ShopData, p_cell: Vector2i) -> void:
	data = p_data
	cell = p_cell


func _ready() -> void:
	if data == null:
		push_error("[ShopStation] 未指定 ShopData，已移除。")
		queue_free()
		return
	LightKit.mark_emissive(self)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = REACH
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -REACH.y * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var prompt := WorldPrompt.new()
	prompt.text = "{interact} %s：用信用點購買醫療針與護盾電池" % data.display_name
	prompt.radius = PROMPT_RADIUS
	prompt.reach_check = func() -> bool: return _player_in_range
	prompt.offset = Vector2(0, -REACH.y - 12.0)
	add_child(prompt)
	var light := LightKit.create_point_light(Palette.CYAN, 90.0, 0.8, false)
	light.position = Vector2(0, -20)
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	if _player_in_range and Input.is_action_just_pressed(&"interact") and not get_tree().paused:
		_open()
	queue_redraw()


func _open() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.is_dead() or player.state == Player.State.MOUNTED:
		return
	if not is_instance_valid(_screen):
		_screen = ShopScreen.new()
		_screen.configure_shop(player, data)
		get_tree().root.add_child(_screen)
	_screen.open()


func _exit_tree() -> void:
	# 畫面掛在場景根節點下，補給點離開時一起移除，避免殘留。
	if is_instance_valid(_screen):
		_screen.queue_free()


func _on_body_entered(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_player_in_range = false


func _draw() -> void:
	# 補給櫃：金屬櫃身、發光的螢幕與十字標誌。
	draw_rect(Rect2(-12, -30, 24, 30), Palette.TERRAIN_FILL)
	draw_rect(Rect2(-12, -30, 24, 30), Palette.TERRAIN_TOP, false, 1.0)
	var glow := LightKit.glow(Palette.CYAN, 1.6 + 0.4 * sin(_time * 3.0))
	draw_rect(Rect2(-8, -26, 16, 12), Color(0.03, 0.08, 0.1))
	draw_rect(Rect2(-8, -26, 16, 12), glow, false, 1.0)
	draw_line(Vector2(-3, -20), Vector2(3, -20), glow, 2.0)
	draw_line(Vector2(0, -23), Vector2(0, -17), glow, 2.0)
	draw_rect(Rect2(-8, -10, 16, 3), Color(Palette.CYAN_DIM, 0.8))
