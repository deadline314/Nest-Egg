class_name ExoticEnemiesScenario
extends ScenarioBase
## 截圖情境（NE-99）：飛行、攀附、軌道、懸浮與群體的新敵人在遊戲裡交戰——井道蝙蝠機（盤旋、張翼預兆、俯衝）、攀牆者（倒掛、蹲伏、撲出）、
## 吊軌砲（軌道、鎖定、換位）、雲母（脈動、充電、放電）、蜂群（隊形、蓄力衝刺）。玩家站著不動、生命很多。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=exotic_enemies

const LIGHTING := "res://data/lighting/neutral.tres"
const CAMERA_TILE := 20.0
const WAIT_LIMIT := 8.0


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	await clear_enemies()
	await _bat()
	await _gecko()
	await _rail_cannon()
	await _jelly()
	await _swarm()
	await finish()


func _until(enemy: Enemy, state: StringName, extra := 0.0) -> bool:
	var waited := 0.0
	while not enemy.fsm.is_in(state) and waited < WAIT_LIMIT and is_instance_valid(enemy):
		await wait(0.05)
		waited += 0.05
	await wait(extra)
	return enemy.fsm.is_in(state)


func _reset_player(x_tile: float) -> void:
	place_player(x_tile)
	player.health.setup(999, 0.0)


func _bat() -> void:
	_reset_player(CAMERA_TILE)
	var bat := spawn_enemy("res://data/enemies/shaft_bat.tres", CAMERA_TILE + 6.0, FLOOR_Y - 110.0)
	await _until(bat, &"hover", 0.6)
	capture("NE-99-bat-hover")
	await _until(bat, &"lock", 0.3)
	capture("NE-99-bat-lock")
	await _until(bat, &"dive", 0.15)
	capture("NE-99-bat-dive")
	bat.queue_free()
	await settle(3)


func _gecko() -> void:
	_reset_player(CAMERA_TILE)
	var gecko := spawn_enemy("res://data/enemies/wall_gecko.tres", CAMERA_TILE + 6.0, FLOOR_Y - 5.0)
	await _until(gecko, &"patrol", 0.8)
	capture("NE-99-gecko-crawl")
	await _until(gecko, &"windup", 0.35)
	capture("NE-99-gecko-windup")
	await _until(gecko, &"leap", 0.12)
	capture("NE-99-gecko-leap")
	await _until(gecko, &"land", 0.1)
	capture("NE-99-gecko-land")
	gecko.queue_free()
	await settle(3)


func _rail_cannon() -> void:
	_reset_player(CAMERA_TILE - 4.0)
	var cannon := spawn_enemy("res://data/enemies/rail_cannon.tres", CAMERA_TILE + 4.0, FLOOR_Y - 50.0)
	await _until(cannon, &"track", 0.3)
	capture("NE-99-rail-track")
	await _until(cannon, &"lock", 0.15)
	capture("NE-99-rail-lock")
	await _until(cannon, &"slide", 0.35)
	capture("NE-99-rail-slide")
	cannon.queue_free()
	await settle(3)


func _jelly() -> void:
	_reset_player(CAMERA_TILE)
	var jelly := spawn_enemy("res://data/enemies/cloud_jelly.tres", CAMERA_TILE + 3.0, FLOOR_Y - 70.0)
	await _until(jelly, &"drift", 0.8)
	capture("NE-99-jelly-drift")
	await _until(jelly, &"charge", 0.5)
	capture("NE-99-jelly-charge")
	await _until(jelly, &"discharge", 0.25)
	capture("NE-99-jelly-discharge")
	jelly.queue_free()
	await settle(3)


func _swarm() -> void:
	_reset_player(CAMERA_TILE)
	var data := load("res://data/enemies/swarm_bee.tres") as EnemyData
	var bees := SwarmBee.spawn_swarm(level._entities, data, Vector2((CAMERA_TILE + 5.0) * 16.0, FLOOR_Y - 60.0), 24)
	await wait(1.4)
	capture("NE-99-swarm-orbit")
	await wait(1.6)
	capture("NE-99-swarm-sting")
	for bee in bees:
		if is_instance_valid(bee):
			bee.queue_free()
	await settle(3)
