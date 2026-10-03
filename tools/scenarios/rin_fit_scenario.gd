extends ScenarioBase
## NE-71 情境：凜在遊戲裡各種動作的「身體大小」檢查，旁邊站一個小兵當大小對照。
## 每張圖畫上：綠框＝碰撞框、橘框＝受擊框、白點＝瞄準起點（肩膀）、紅點＝槍口（子彈生成點）、黃線＝瞄準方向。
## 動作：站、仰射（約 45 度與正上方）、俯射、蹲、跑、跳、格擋。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=rin_fit

const SHOTS: Array = [
	["stand", Vector2(1, 0), [], 0.6],
	["aim_up45", Vector2(1, -1), [], 0.6],
	["aim_up90", Vector2(0.15, -1), [], 0.6],
	["aim_down", Vector2(1, 1), [], 0.6],
	["crouch", Vector2(1, 0), ["move_down"], 0.6],
	["run", Vector2(1, 0), ["move_right"], 0.55],
	["jump", Vector2(1, -0.3), ["jump"], 0.28],
	["block", Vector2(1, -0.2), ["block"], 0.6],
]


func run() -> void:
	await open_arena("res://data/lighting/transfer.tres", 18.0)
	player.health.setup(999, 0.0)
	var trooper := spawn_enemy("res://data/enemies/grunt.tres", 21.5)
	trooper.process_mode = Node.PROCESS_MODE_DISABLED
	var lamp := LightKit.create_point_light(Color(1.0, 0.88, 0.7), 520.0, 0.9, false)
	lamp.global_position = Vector2(12.0 * 16.0, FLOOR_Y - 120.0)
	level.add_child(lamp)
	var overlay := _Overlay.new()
	overlay.player = player
	level.add_child(overlay)
	for shot: Array in SHOTS:
		place_player(18.0)
		await wait(0.9)
		for action: String in shot[2]:
			Input.action_press(action)
		_aim(shot[1])
		await wait(float(shot[3]))
		_aim(shot[1])
		await settle(2)
		capture("rin_fit_%s" % str(shot[0]))
		for action: String in shot[2]:
			Input.action_release(action)
		await wait(0.4)
	await finish()
	await _tunnel()


## 第一關地下最矮的通道（淨高 4 格＝64 像素）：站姿與蹲姿各一張，畫著碰撞框，確認頭不會卡進天花板。
func _tunnel() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load("res://data/levels/level_01.tres"))
	add_child(level)
	await settle(25)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var overlay := _Overlay.new()
	overlay.player = player
	level.add_child(overlay)
	await wait(TITLE_CARD_TIME)
	player.global_position = Vector2(35 * 16.0, 20 * 16.0 - 1.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	var lamp := LightKit.create_point_light(Color(1.0, 0.88, 0.7), 200.0, 1.0, false)
	lamp.global_position = Vector2(33 * 16.0, 17.5 * 16.0)
	level.add_child(lamp)
	await wait(1.0)
	_aim(Vector2(1, 0))
	await wait(0.4)
	capture("rin_fit_tunnel_stand")
	Input.action_press(&"move_down")
	await wait(0.6)
	capture("rin_fit_tunnel_crouch")
	Input.action_release(&"move_down")
	await finish()


## 滑鼠指向「從瞄準起點出發、往 direction 方向」的世界座標。
func _aim(direction: Vector2) -> void:
	var target := player.aim_origin() + direction.normalized() * 90.0
	var screen := get_viewport().get_canvas_transform() * target
	Input.warp_mouse(screen * (Vector2(get_window().size) / get_viewport().get_visible_rect().size))


class _Overlay:
	extends Node2D
	var player: Player

	func _ready() -> void:
		z_index = 100

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if player == null:
			return
		var feet := player.global_position
		var crouch := player.is_crouching
		draw_rect(Rect2(feet + Vector2(-Player.BODY_SIZE.x * 0.5, -Player.BODY_SIZE.y), Player.BODY_SIZE), Color(0.2, 1.0, 0.4, 0.9), false, 1.0)
		var h := Player.CROUCH_HEIGHT if crouch else Player.BODY_SIZE.y
		var box := Vector2(Player.BODY_SIZE.x * 0.8, h * 0.9)
		draw_rect(Rect2(feet + Vector2(-box.x * 0.5, -h * 0.5 - box.y * 0.5), box), Color(1.0, 0.55, 0.1, 0.9), false, 1.0)
		var origin := player.aim_origin()
		draw_circle(origin, 1.6, Color.WHITE)
		draw_circle(player.muzzle_position(), 1.6, Color(1.0, 0.15, 0.15))
		draw_line(origin, origin + player.aim_dir * 70.0, Color(1.0, 0.95, 0.2, 0.7), 1.0)
