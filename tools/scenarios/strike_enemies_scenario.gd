class_name StrikeEnemiesScenario
extends ScenarioBase
## 截圖情境（NE-118）：每種非槍械攻擊各拍預兆、出招、收招；電漿鞭兩種高度、鎖鏈鐵鉤拉扯中的鎖鏈。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=strike_enemies

const LIGHTING := "res://data/lighting/neutral.tres"
const IDS: Array[String] = ["chainsaw_arm", "hydraulic_claw", "plasma_whip", "chain_hook"]
const GAPS := {"chainsaw_arm": 2.6, "hydraulic_claw": 2.4, "plasma_whip": 5.5, "chain_hook": 6.0}


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	player.health.setup(999, 0.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.LEFT
	for id in IDS:
		var enemy := spawn_enemy("res://data/enemies/strike/%s.tres" % id, 12.0 + float(GAPS[id]))
		await wait(0.2)
		enemy.global_position.x = player.global_position.x + float(GAPS[id]) * 16.0
		var shot_states: Array[StringName] = [&"windup", &"strike", &"recover"]
		if id == "chain_hook":
			shot_states = [&"windup", &"throw", &"reel"]
		for state in shot_states:
			var guard := 0
			while not enemy.fsm.is_in(state) and guard < 600:
				await get_tree().physics_frame
				guard += 1
			await wait(0.18 if state != &"windup" else 0.45)
			capture("%s_%s" % [id, state])
		await wait(0.8)
		enemy.queue_free()
		player.end_pull()
		player.global_position.x = 12.0 * 16.0
		await wait(0.3)
	AimInput.using_gamepad = false
	await finish()
