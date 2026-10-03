class_name HurtPartsScenario
extends ScenarioBase
## 截圖情境（NE-104）：一排人形敵人，畫出部位受擊框（黃＝弱點）；再各種姿勢（站、蹲、倒下）看判定跟著動，最後打頭與打身體的回饋。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=hurt_parts

const LIGHTING := "res://data/lighting/neutral.tres"
const CAMERA_TILE := 31.0
const IDS := ["grunt", "elite_grunt", "sniper", "stalker", "slasher", "flamer", "shield_rusher", "heavy_gunner"]


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	player.visible = false
	await clear_enemies()
	var row: Array[Enemy] = []
	for i in IDS.size():
		var enemy := spawn_enemy("res://data/enemies/%s.tres" % IDS[i], 16.0 + i * 4.0)
		enemy.data = enemy.data.duplicate()
		enemy.data.detect_range = 0.0
		enemy.data.attack_range = 0.0
		enemy.data.move_speed = 0.0
		enemy.health.setup(100, 0.0)
		enemy.facing = -1
		row.append(enemy)
	await wait(0.6)
	Enemy.debug_hurtboxes = true
	await wait(0.2)
	capture("NE-104-parts-debug")
	Enemy.debug_hurtboxes = false
	await wait(0.2)
	capture("NE-104-markers")
	# 同一種槍：打第一隻的頭（弱點）、第二隻的身體。
	var spec := load("res://data/projectiles/rifle_shot.tres") as ProjectileSpec
	var head := row[0].global_position + (row[0]._parts[0]["box"] as Hurtbox).shape_offset()
	ProjectilePool.spawn(spec, head + Vector2(-60.0, 0.0), Vector2.RIGHT, Combat.Team.PLAYER)
	ProjectilePool.spawn(spec, row[1].global_position + Vector2(-60.0, -18.0), Vector2.RIGHT, Combat.Team.PLAYER)
	await wait(0.13)
	capture("NE-104-shot-1")
	await wait(0.1)
	capture("NE-104-shot-2")
	print("HP after: head-shot %d/%d, body-shot %d/%d" % [row[0].health.current, row[0].health.max_health, row[1].health.current, row[1].health.max_health])
	await finish()
