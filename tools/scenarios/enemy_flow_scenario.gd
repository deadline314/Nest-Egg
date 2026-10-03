class_name EnemyFlowScenario
extends ScenarioBase
## 截圖情境（NE-107）：人形敵人在遊戲裡完整走一遍流程——巡邏（放鬆）、發現玩家、瞄準或蓄力、出招、恢復、被打、倒下——
## 每 0.2 秒擷取一格，放在 <out>/flow_<敵人>_<序號>.png，之後拼成連續畫面檢查動作是否合理。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=enemy_flow [--enemies=a,b] [--enemy_tile=格數]

const LIGHTING := "res://data/lighting/neutral.tres"
const ENEMIES := ["grunt", "elite_grunt", "sniper", "slasher", "heavy_gunner", "shield_rusher", "flamer", "stalker"]
const FRAMES := 20
const STEP := 0.2
const PLAYER_TILE := 33.0
const ENEMY_TILE := 44.0


func run() -> void:
	var ids: Array = ENEMIES
	var enemy_tile := ENEMY_TILE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			ids = arg.trim_prefix("--enemies=").split(",", false)
		elif arg.begins_with("--enemy_tile="):
			enemy_tile = float(arg.trim_prefix("--enemy_tile="))
	await open_arena(LIGHTING, PLAYER_TILE)
	for id: String in ids:
		await clear_enemies()
		place_player(PLAYER_TILE)
		var enemy := spawn_enemy("res://data/enemies/%s.tres" % id, enemy_tile)
		enemy.health.setup(30, 0.0)
		await wait(0.1)
		for i in FRAMES:
			capture("flow_%s_%02d" % [id, i])
			if i == FRAMES - 6 and is_instance_valid(enemy):
				enemy.hurtbox.receive(_hit(2, 40.0))      # 被打
			if i == FRAMES - 3 and is_instance_valid(enemy):
				enemy.hurtbox.receive(_hit(999, 180.0))   # 擊殺
			await wait(STEP)
	await finish()


func _hit(amount: int, push: float) -> DamageInfo:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"scenario", Vector2(-push, 0.0))
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info
