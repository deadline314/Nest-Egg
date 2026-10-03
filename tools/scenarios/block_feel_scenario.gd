class_name BlockFeelScenario
extends ScenarioBase
## 截圖情境（NE-144）：舉盾瞬間（完美格擋窗口環）、完美格擋反彈（子彈拖尾）、普通格擋。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=block_feel

const LIGHTING := "res://data/lighting/neutral.tres"


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	place_player(12.0)
	player.global_position.x = 12.0 * 16.0
	await wait(0.4)
	Input.action_press(&"block")
	await wait(0.06)
	capture("block_window")
	# 窗口內被打中：完美格擋，子彈彈回。
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	ProjectilePool.spawn(spec, player.global_position + Vector2(60, -26), Vector2.LEFT, Combat.Team.ENEMY, 4.0)
	for i in 4:
		await wait(0.04)
		capture("block_parry_%d" % i)
	await wait(0.5)
	# 窗口過了再被打中：普通格擋。
	ProjectilePool.spawn(spec, player.global_position + Vector2(60, -26), Vector2.LEFT, Combat.Team.ENEMY, 4.0)
	await wait(0.12)
	capture("block_normal")
	Input.action_release(&"block")
	await finish()
