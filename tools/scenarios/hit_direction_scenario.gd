class_name HitDirectionScenario
extends ScenarioBase
## 截圖情境（NE-103）：先看正面與背面中彈的退縮方向，再看四種擊殺（正面輕擊、背面輕擊、正面重擊、背面重擊）的倒法。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=hit_direction

const GRUNT := "res://data/enemies/grunt.tres"
const LIGHTING := "res://data/lighting/neutral.tres"
const CAMERA_TILE := 31.0
const HURT_TILES := [23.0, 28.0]
const DEATH_TILES := [20.0, 26.0, 32.0, 38.0]


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	player.visible = false
	await clear_enemies()
	await _hurt_pair()
	await clear_enemies()
	await _deaths()
	await finish()


func _spawn_still(tile: float) -> Enemy:
	var enemy := spawn_enemy(GRUNT, tile)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.health.setup(9999, 0.0)
	enemy.facing = -1
	return enemy


func _info(amount: int, to_right: bool, impact: float) -> DamageInfo:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"scenario", Vector2(180.0 if to_right else -180.0, -60.0))
	info.impact = impact
	info.ignore_invulnerability = true
	return info


func _hurt_pair() -> void:
	var front := _spawn_still(HURT_TILES[0])
	var back := _spawn_still(HURT_TILES[1])
	await wait(0.5)
	capture("NE-103-hurt-0")
	front.hurtbox.receive(_info(1, true, 3.0))
	back.hurtbox.receive(_info(1, false, 3.0))
	await wait(0.07)
	capture("NE-103-hurt-1")
	await wait(0.4)
	capture("NE-103-hurt-2")


func _deaths() -> void:
	var group: Array[Enemy] = []
	for tile: float in DEATH_TILES:
		group.append(_spawn_still(tile))
	await wait(0.5)
	capture("NE-103-death-0")
	group[0].hurtbox.receive(_info(9999, true, 1.0))
	group[1].hurtbox.receive(_info(9999, false, 1.0))
	group[2].hurtbox.receive(_info(9999, true, 7.0))
	group[3].hurtbox.receive(_info(9999, false, 7.0))
	await wait(0.12)
	capture("NE-103-death-1")
	await wait(0.2)
	capture("NE-103-death-2")
	await wait(0.4)
	capture("NE-103-death-3")
