class_name WatchdogMovesScenario
extends ScenarioBase
## 看門狗招式定格（NE-253）：正式第一章碼頭倉庫，依序拍地盤（鍊子與黃黑線）、撲咬預兆、被扯回背部發橙光、
## 吠叫預兆（頭部打開）、點射鎖定紅線、飛彈紅圈、第三階段鍊斷。招式由狀態機觸發，牠的動作與判定都是正式程式。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=watchdog_moves

const LEVEL := "res://data/levels/ch1_warehouse.tres"

var _dog: PatternBoss


func run() -> void:
	Enemy.activation_culling_enabled = false
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(9999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is PatternBoss:
			_dog = node
		else:
			node.queue_free()
	if _dog == null:
		push_error("[WatchdogMoves] 倉庫裡找不到看門狗")
		await finish()
		return
	var line := _dog.anchor().x - _dog.pattern.leash_length
	player.global_position.x = line - 8.0
	snap_camera()
	await wait(TITLE_CARD_TIME)
	_dog.call(&"_wake")
	await _until(&"idle", 3.0)
	Engine.time_scale = 0.2
	capture("NE-253-moves-territory")
	await _move(&"lunge", line + 10.0)
	await _until(&"windup", 1.0)
	await settle(3)
	capture("NE-253-moves-lunge-windup")
	player.global_position.x = line - 30.0
	await _until(&"yanked", 3.0)
	await settle(3)
	capture("NE-253-moves-yanked-back-open")
	await _until(&"idle", 4.0)
	await _move(&"burst", line - 30.0)
	await _until_locked(2.0)
	await settle(2)
	capture("NE-253-moves-burst-locked")
	await _until(&"idle", 4.0)
	player.global_position.x = _dog.global_position.x - 40.0
	await _move(&"bark", player.global_position.x)
	await settle(3)
	capture("NE-253-moves-bark-head-open")
	await _until(&"idle", 4.0)
	_dog.call(&"_apply_phase", 1, false)
	player.global_position.x = line - 30.0
	await _move(&"missiles", line - 30.0)
	await settle(4)
	capture("NE-253-moves-missile-marks")
	await _until(&"idle", 4.0)
	_dog.health.current = int(_dog.health.max_health * 0.25)
	_dog.call(&"_apply_phase", 2, true)
	await settle(4)
	capture("NE-253-moves-chain-snapped")
	Engine.time_scale = 1.0
	await finish()


func _move(id: StringName, player_x: float) -> void:
	player.global_position.x = player_x
	player.velocity = Vector2.ZERO
	_dog.set("_move_id", id)
	_dog.fsm.transition(&"windup")
	await settle(2)


func _until(state: StringName, seconds: float) -> void:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0 / maxf(0.05, Engine.time_scale)) * 4
	while not _dog.fsm.is_in(state) and Time.get_ticks_msec() < limit:
		await get_tree().physics_frame


func _until_locked(seconds: float) -> void:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0 / maxf(0.05, Engine.time_scale)) * 4
	while not _dog.is_aim_locked() and Time.get_ticks_msec() < limit:
		await get_tree().physics_frame
