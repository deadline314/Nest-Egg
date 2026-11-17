class_name Ch2MarketEnemiesScenario
extends ScenarioBase
## 第二章市集的兩種新敵人（NE-266）：正式市集入口的兩個戰鬥區，拍押運手的突進預兆與突進、票據投手的扇形預兆與紙頁，
## 以及站在上層公眾攤道時地面敵人看不到（可以繞過）。敵人的行為都是正式程式，只移動主角。
## 用法：godot --fixed-fps 60 res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=ch2_market_enemies

const LEVEL := "res://data/levels/ch2_market_gate.tres"
var _migration: Dictionary


func run() -> void:
	Enemy.activation_culling_enabled = false
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	_migration = MapLayoutMigration.read(level.data)
	if _migration.has("error"):
		failures += 1
		push_error("[Ch2MarketEnemiesScenario] %s" % _migration["error"])
		await finish()
		return
	await settle(30)
	player = level.player
	level.hud.visible = false
	player.health.setup(9999, 0.0)
	# Hurt freeze would restore the old position after the next arranged placement.
	player.health.grant_invulnerability(100000.0)
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
	if escorts.size() != 3 or throwers.size() != 1:
		failures += 1
		push_error("[Ch2MarketEnemiesScenario] 市集預期3名押運手、1名票據投手")
		await finish()
		return
	_place(8.0, 20)  # 先站在入口外，戰區的敵人看不到
	await _frames(int(TITLE_CARD_TIME * 60))
	# 上層攤道（第 14 列平台上）走過第一個戰區：地面的押運手看不到。
	_place(40.0, 14)
	await _frames(90)
	_frame(player.global_position, escorts[0].global_position if not escorts.is_empty() else player.global_position)
	await _frames(2)
	await RenderingServer.frame_post_draw
	capture("NE-266-bypass-walkway")
	if escorts.any(func(enemy: Enemy) -> bool: return enemy.is_engaged()):
		failures += 1
		push_error("[Ch2MarketEnemiesScenario] 上層繞道被地面押運手發現")
	print("MARKET bypass escort states: %s" % [escorts.map(func(e: Enemy) -> String: return str(e.fsm.current))])
	_place(28.0, 20)
	var escort := await _wait_for(escorts, &"windup", 400)
	if escort == null:
		await finish()
		return
	await _frames(20)
	_frame(player.global_position, escort.global_position if escort != null else player.global_position)
	await _frames(2)
	await _capture_phase(escort, &"windup", "NE-266-escort-windup")
	if await _wait_for([escort], &"strike", 120) == null:
		await finish()
		return
	await _capture_phase(escort, &"strike", "NE-266-escort-dash")
	_place(64.0, 20)
	var thrower := await _wait_for(throwers, &"windup", 600)
	if thrower == null:
		await finish()
		return
	await _frames(38)
	_frame(player.global_position, thrower.global_position if thrower != null else player.global_position)
	await _frames(2)
	await _capture_phase(thrower, &"windup", "NE-266-thrower-windup")
	if await _wait_for([thrower], &"recover", 120) == null:
		await finish()
		return
	await _capture_phase(thrower, &"recover", "NE-266-thrower-sheets")
	await finish()


func _place(x_tile: float, row: int) -> void:
	# These authored sample cells predate the map's declared revision shift.
	player.global_position = MapLayoutMigration.position(Vector2(x_tile, row) * level._layout.tile_size, _migration)
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
	failures += 1
	var positions := enemies.map(func(enemy: Enemy) -> String:
		if not is_instance_valid(enemy):
			return "released"
		return "%s %s at %s, distance %.1f, sight %s" % [enemy.data.id, enemy.fsm.current, enemy.global_position, enemy._distance_to_target(), enemy._has_line_of_sight()])
	push_error("[Ch2MarketEnemiesScenario] 等待%s逾時：主角%s，暫停%s，敵人%s" % [state, player.global_position, get_tree().paused, positions])
	return null


func _capture_phase(enemy: Enemy, state: StringName, shot: String) -> void:
	await RenderingServer.frame_post_draw
	var actual := enemy.fsm.current if is_instance_valid(enemy) else &"released"
	if actual != state:
		failures += 1
		push_error("[Ch2MarketEnemiesScenario] %s預期%s，實際%s" % [shot, state, actual])
	print("MARKET_CAPTURE ", JSON.stringify({"shot": shot, "state": actual,
		"physics_frame": Engine.get_physics_frames(), "player": str(player.global_position),
		"enemy": str(enemy.global_position) if is_instance_valid(enemy) else "released"}))
	capture(shot)


## 鏡頭固定在兩點中間（平常的鏡頭會往前看，敵人容易被切到畫面邊緣）；之後的 snap_camera 會恢復跟隨。
func _frame(a: Vector2, b: Vector2) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	camera.set_physics_process(false)
	camera.global_position = (a + b) * 0.5 + Vector2(0, -24.0)
	camera.reset_smoothing()
