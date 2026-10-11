class_name Ch2MarketEnemiesScenario
extends ScenarioBase
## 第二章市集的兩種新敵人（NE-266）：正式市集入口的兩個戰鬥區，拍押運手的突進預兆與突進、票據投手的扇形預兆與紙頁，
## 以及站在上層公眾攤道時地面敵人看不到（可以繞過）。敵人的行為都是正式程式，只移動主角。
## 用法：godot --fixed-fps 60 res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=ch2_market_enemies

const LEVEL := "res://data/levels/ch2_market_gate.tres"


func run() -> void:
	Enemy.activation_culling_enabled = false
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(9999, 0.0)
	player.set_physics_process(false)
	var escorts: Array[Enemy] = []
	var throwers: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy.data.id == &"ch2_escort":
			escorts.append(enemy)
		elif enemy.data.id == &"ch2_bill_thrower":
			throwers.append(enemy)
	print("MARKET escorts=%d throwers=%d" % [escorts.size(), throwers.size()])
	_place(8.0, 20)  # 先站在入口外，戰區的敵人看不到
	await _frames(int(TITLE_CARD_TIME * 60))
	# 上層攤道（第 14 列平台上）走過第一個戰區：地面的押運手看不到。
	_place(40.0, 14)
	await _frames(90)
	_frame(player.global_position, escorts[0].global_position if not escorts.is_empty() else player.global_position)
	await _frames(2)
	capture("NE-266-bypass-walkway")
	print("MARKET bypass escort states: %s" % [escorts.map(func(e: Enemy) -> String: return str(e.fsm.current))])
	_place(28.0, 20)
	var escort := await _wait_for(escorts, &"windup", 400)
	await _frames(20)
	_frame(player.global_position, escort.global_position if escort != null else player.global_position)
	await _frames(2)
	capture("NE-266-escort-windup")
	await _frames(12)
	capture("NE-266-escort-dash")
	_place(64.0, 20)
	var thrower := await _wait_for(throwers, &"windup", 600)
	await _frames(38)
	_frame(player.global_position, thrower.global_position if thrower != null else player.global_position)
	await _frames(2)
	capture("NE-266-thrower-windup")
	await _frames(40)
	capture("NE-266-thrower-sheets")
	await finish()


func _place(x_tile: float, row: int) -> void:
	player.global_position = Vector2(x_tile * 16.0, row * 16.0)
	player.velocity = Vector2.ZERO
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.set_physics_process(true)
	snap_camera()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _wait_for(enemies: Array[Enemy], state: StringName, frames_max: int) -> Enemy:
	for i in frames_max:
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.fsm.is_in(state):
				return enemy
		await get_tree().physics_frame
	return null


## 鏡頭固定在兩點中間（平常的鏡頭會往前看，敵人容易被切到畫面邊緣）；之後的 snap_camera 會恢復跟隨。
func _frame(a: Vector2, b: Vector2) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	camera.set_physics_process(false)
	camera.global_position = (a + b) * 0.5 + Vector2(0, -24.0)
	camera.reset_smoothing()
