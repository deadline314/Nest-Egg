class_name CreatureCombatScenario
extends ScenarioBase
## 截圖情境（NE-98）：觸手與蠕行生物在遊戲裡實際交戰——打撈臂（步行、掃地、砸地預告、打斷觸手、核心露出）、
## 纏絲（火花預兆、伸出鞭打）、浮標蟲（鼓起、噴酸液、分裂）、雲蛇（地面隆起、躍出）。玩家站著不動、生命很多。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=creature_combat

const LIGHTING := "res://data/lighting/neutral.tres"
const CAMERA_TILE := 20.0
const WAIT_LIMIT := 8.0


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	await clear_enemies()
	await _salvage_arm()
	await _tangle_wire()
	await _buoy_worm()
	await _cloud_serpent()
	await finish()


## 等敵人進入某個狀態（最多 WAIT_LIMIT 秒），再多等 extra 秒，回傳有沒有等到。
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


func _salvage_arm() -> void:
	_reset_player(CAMERA_TILE)
	var arm := spawn_enemy("res://data/enemies/salvage_arm.tres", CAMERA_TILE + 9.0) as ChainEnemy
	await wait(0.4)
	await _until(arm, &"chase", 1.2)
	capture("NE-98-arm-walk")
	await _until(arm, &"sweep_windup", 0.35)
	capture("NE-98-arm-sweep-windup")
	await _until(arm, &"sweep", 0.2)
	capture("NE-98-arm-sweep")
	await _until(arm, &"recover")
	arm._use_slam_next = true
	arm._cooldown = 0.0
	_reset_player(CAMERA_TILE)
	await _until(arm, &"slam_windup", 0.45)
	capture("NE-98-arm-slam-windup")
	await _until(arm, &"slam", 0.12)
	capture("NE-98-arm-slam")
	await _until(arm, &"recover")
	# 打斷觸手：前面兩條先斷，再斷光
	arm.chain.sever(5, Vector2.RIGHT)
	arm.chain.sever(4, Vector2.RIGHT)
	await wait(0.35)
	capture("NE-98-arm-severed-two")
	for i in 4:
		arm.chain.sever(i, Vector2.LEFT)
	await wait(0.5)
	capture("NE-98-arm-core-exposed")
	Enemy.debug_hurtboxes = true
	await wait(0.2)
	capture("NE-98-arm-hurtboxes")
	Enemy.debug_hurtboxes = false
	arm.queue_free()
	await settle(3)


func _tangle_wire() -> void:
	_reset_player(CAMERA_TILE)
	var wire := spawn_enemy("res://data/enemies/tangle_wire.tres", CAMERA_TILE + 4.0, FLOOR_Y - 20.0) as ChainEnemy
	await _until(wire, &"warn", 0.5)
	capture("NE-98-wire-warn")
	await _until(wire, &"lash", 0.28)
	capture("NE-98-wire-lash")
	await wait(0.25)
	Enemy.debug_hurtboxes = true
	await wait(0.1)
	capture("NE-98-wire-hurtboxes")
	Enemy.debug_hurtboxes = false
	wire.queue_free()
	await settle(3)


func _buoy_worm() -> void:
	_reset_player(CAMERA_TILE)
	var worm := spawn_enemy("res://data/enemies/buoy_worm.tres", CAMERA_TILE + 7.0) as ChainEnemy
	await _until(worm, &"swell", 0.4)
	capture("NE-98-buoy-swell")
	await _until(worm, &"spit", 0.2)
	capture("NE-98-buoy-spit")
	worm.hurtbox.receive(_lethal())
	await wait(0.35)
	capture("NE-98-buoy-split")
	await clear_enemies()


func _cloud_serpent() -> void:
	_reset_player(CAMERA_TILE)
	var serpent := spawn_enemy("res://data/enemies/cloud_serpent.tres", CAMERA_TILE + 8.0, FLOOR_Y + 16.0) as Enemy
	await _until(serpent, &"rumble", 0.55)
	capture("NE-98-serpent-rumble")
	await _until(serpent, &"erupt", 0.25)
	capture("NE-98-serpent-erupt")
	await wait(0.2)
	capture("NE-98-serpent-arc")
	await _until(serpent, &"dive", 0.05)
	capture("NE-98-serpent-dive")


func _lethal() -> DamageInfo:
	var info := DamageInfo.create(999, Combat.Team.PLAYER, &"scenario")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info
