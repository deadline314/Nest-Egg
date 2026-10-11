class_name MeleeContactScenario
extends ScenarioBase
## 命中回饋的位置（NE-268）：真正的按鍵近戰砍一個保全，放慢時間拍命中當下與下一格。
## 火花、閃光要在武器碰到的地方，不在敵人腳底。開 --hurtboxes 可對照受擊範圍。子彈選中深處部位的回饋位置由 HeavyEnemiesSuite 檢查。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=melee_contact [--hurtboxes]

const LIGHTING := "res://data/lighting/neutral.tres"


func run() -> void:
	await open_arena(LIGHTING, 30.0)
	await clear_enemies()
	AimInput.set_virtual_gamepad(player, true)
	var grunt := spawn_enemy("res://data/enemies/grunt.tres", 32.0)
	grunt.data = grunt.data.duplicate()
	grunt.data.detect_range = 0.0
	grunt.data.attack_range = 0.0
	Input.action_press(&"aim_right")
	await wait(0.5)
	Engine.time_scale = 0.1
	var hit := [false]
	var on_hit := func(_at: Vector2, _killed: bool) -> void: hit[0] = true
	EventBus.hit_confirmed.connect(on_hit)
	Input.action_press(&"melee")
	for i in 60:
		await get_tree().physics_frame
		if hit[0]:
			break
	Input.action_release(&"melee")
	await settle(2)
	capture("melee-contact-hit")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await settle(1)
	capture("melee-contact-after")
	Engine.time_scale = 1.0
	EventBus.hit_confirmed.disconnect(on_hit)
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	await finish()
