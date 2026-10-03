class_name HitReactionScenario
extends ScenarioBase
## 截圖情境（NE-102）：同一排五隻敵人，由左到右：沒被打、一發輕擊、累積畏縮、重擊硬直、頭目吃重擊。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=hit_reaction

const GRUNT := "res://data/enemies/grunt.tres"
const WARDEN := "res://data/enemies/warden.tres"
const LIGHTING := "res://data/lighting/neutral.tres"
const TILES := [22.0, 26.0, 30.0, 34.0, 39.0]
## 玩家（隱形）站在中間，讓鏡頭看得到整排；敵人不偵測，保持待機。
const CAMERA_TILE := 31.0


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	player.visible = false
	await clear_enemies()
	var row: Array[Enemy] = []
	for i in TILES.size():
		var path := WARDEN if i == TILES.size() - 1 else GRUNT
		var enemy := spawn_enemy(path, TILES[i])
		enemy.data = enemy.data.duplicate()
		enemy.data.detect_range = 0.0
		enemy.data.attack_range = 0.0
		enemy.data.move_speed = 0.0
		enemy.health.setup(9999, 0.0)
		enemy.facing = -1
		row.append(enemy)
	await wait(0.6)
	capture("NE-102-0-before")
	row[1].hurtbox.receive(_light())
	for i in 3:
		row[2].hurtbox.receive(_light())
	row[3].hurtbox.receive(_heavy(6.0))
	row[4].hurtbox.receive(_heavy(6.0))
	await wait(0.04)
	capture("NE-102-1-hit")
	await wait(0.08)
	capture("NE-102-2-mid")
	await wait(0.4)
	capture("NE-102-3-after")
	await finish()


func _light() -> DamageInfo:
	var info := DamageInfo.create(1, Combat.Team.PLAYER, &"scenario", Vector2(40, 0))
	info.ignore_invulnerability = true
	return info


func _heavy(impact: float) -> DamageInfo:
	var info := DamageInfo.create(1, Combat.Team.PLAYER, &"scenario", Vector2(180, -60))
	info.impact = impact
	info.ignore_invulnerability = true
	return info
