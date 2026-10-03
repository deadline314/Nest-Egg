class_name MachineHitScenario
extends ScenarioBase
## 截圖情境（NE-105）：機械類敵人（沒有骨架）的受擊反應與損傷狀態。
## 一排：偵察機（失速）、電擊犬（踉蹌）、自爆蟲（踉蹌）、哨戒砲台（震動）、迫擊砲（震動）。
## 時間點：完好 → 受擊瞬間 → 生命剩 2/3（冒煙）→ 剩 1/3（漏電）。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=machine_hit

const LIGHTING := "res://data/lighting/neutral.tres"
const CAMERA_TILE := 31.0
const ROW := [
	["drone", 22.0, 52.0], ["shock_hound", 26.0, 0.0], ["bomber", 30.0, 0.0], ["turret", 34.0, 24.0], ["mortar", 38.0, 0.0],
]


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	player.visible = false
	await clear_enemies()
	var row: Array[Enemy] = []
	for entry: Array in ROW:
		var enemy := spawn_enemy("res://data/enemies/%s.tres" % entry[0], entry[1], FLOOR_Y - float(entry[2]))
		enemy.data = enemy.data.duplicate()
		enemy.data.detect_range = 0.0
		enemy.data.attack_range = 0.0
		enemy.data.move_speed = 0.0
		enemy.health.setup(30, 0.0)
		enemy.facing = -1
		row.append(enemy)
	await wait(0.6)
	capture("NE-105-0-intact")
	for enemy in row:
		enemy.hurtbox.receive(_hit(1, 40.0))
		enemy.hurtbox.receive(_hit(1, 40.0))
		enemy.hurtbox.receive(_hit(1, 40.0))
	await wait(0.05)
	capture("NE-105-1-hit")
	await wait(0.5)
	for enemy in row:
		enemy.health.setup(enemy.data.max_health, 0.0)
		enemy.health.current = ceili(enemy.data.max_health * 0.6)
		enemy._update_damage_stage()
	await wait(1.6)
	capture("NE-105-2-stage1")
	for enemy in row:
		enemy.health.current = maxi(1, ceili(enemy.data.max_health * 0.3))
		enemy._update_damage_stage()
	await wait(1.0)
	capture("NE-105-3-stage2")
	await finish()


func _hit(amount: int, push: float) -> DamageInfo:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"scenario", Vector2(push, 0.0))
	info.ignore_invulnerability = true
	return info
