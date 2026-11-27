class_name ConveyorScenario
extends ScenarioBase
## 輸送帶（NE-401）：第四章工廠中繼區。主角站在輸送帶上靠近馬達的地方。拍兩張：原方向（有提示、箭頭往左）、
## 射中馬達反轉後（燈變橘、箭頭往右）；並印出兩段時間裡主角被帶走的距離。方向不對就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=conveyor

const LEVEL := "res://data/levels/ch4_factory_relay.tres"
const FROM_MOTOR := 70.0


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	var belt: Conveyor
	for node in get_tree().get_nodes_in_group(Conveyor.GROUP):
		belt = node as Conveyor
		break
	if belt == null:
		failures += 1
		push_error("[ConveyorScenario] %s 裡沒有輸送帶" % LEVEL)
		await finish()
		return
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()  # 只看輸送帶本身；掃描者的雷射會把主角打退、干擾量測
	var rect := belt.belt_rect()
	# 用虛擬手把往右瞄：面向馬達，鏡頭往前看才拍得到馬達。
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right", 1.0)
	await wait(TITLE_CARD_TIME + 0.5)
	player.global_position = Vector2(rect.end.x - FROM_MOTOR, rect.end.y)
	player.velocity = Vector2.ZERO
	# 拍照那一刻先停住推力：被帶著走時鏡頭會往前看，馬達會跑出畫面。
	belt.set_physics_process(false)
	await settle(2)
	snap_camera()
	await wait(0.4)
	capture("NE-401-conveyor-0-forward")
	belt.set_physics_process(true)
	var x0 := player.global_position.x
	await wait(1.0)
	var carried_forward := player.global_position.x - x0
	player.global_position = Vector2(rect.end.x - FROM_MOTOR, rect.end.y)
	belt.set_physics_process(false)
	await settle(2)
	snap_camera()
	belt.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"conveyor_scenario"))
	await wait(0.4)
	capture("NE-401-conveyor-1-reversed")
	belt.set_physics_process(true)
	var x1 := player.global_position.x
	await wait(1.0)
	var carried_back := player.global_position.x - x1
	print("CONVEYOR forward_dx=%.1f reversed_dx=%.1f reversed=%s" % [carried_forward, carried_back, belt.is_reversed()])
	if carried_forward >= -10.0 or carried_back <= 10.0 or not belt.is_reversed():
		failures += 1
		push_error("[ConveyorScenario] 輸送帶沒有把主角往正確的方向帶走")
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	await finish()
