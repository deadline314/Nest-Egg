class_name MeleeComboScenario
extends ScenarioBase
## 截圖情境（NE-142、NE-143）：玩家對面前的敵人連按三下近戰（輕、輕、重），每 0.05 秒拍一張，看前搖、出招、收招與軌跡。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=melee_combo

const LIGHTING := "res://data/lighting/neutral.tres"
const FRAMES := 16
const STEP := 0.05


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	place_player(12.0)
	var enemy := spawn_enemy("res://data/enemies/grunt.tres", 10.9)
	enemy.health.setup(999, 0.0)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	await wait(0.4)
	player.facing = -1
	for i in FRAMES:
		if i % 4 == 0:
			player._try_melee()
		capture("melee_%02d" % i)
		await wait(STEP)
	await finish()
