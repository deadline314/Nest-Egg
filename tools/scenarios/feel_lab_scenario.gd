class_name FeelLabScenario
extends ScenarioBase
## 截圖情境（NE-133）：開打擊感實驗室，放材質靶、移動靶與幾種敵人，開槍與近戰後拍畫面（含右側面板）。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=feel_lab

func run() -> void:
	var lab := FeelLab.new()
	add_child(lab)
	await wait(1.2)
	level = lab.level
	player = lab.player
	player.facing = 1
	for material in [&"flesh", &"metal", &"glass", &"wood"]:
		lab.spawn_material_target(material)
	lab.spawn_material_target(&"armor", true)
	lab.spawn_enemy("grunt", 16.0)
	lab.spawn_enemy("drone", 18.0)
	await wait(0.6)
	capture("lab_idle")
	for i in 3:
		Input.action_press(&"shoot")
		await wait(0.25)
		Input.action_release(&"shoot")
		await wait(0.05)
	lab.spawn_material_target(&"metal", false, true)
	for i in lab._event_option.item_count:
		if lab._event_option.get_item_text(i) == "player_finisher":
			lab._event_option.select(i)
	lab.rebuild_params()
	Feel.play(&"boss_land")
	Sfx.play_event(&"hit_enemy")
	await wait(0.3)
	capture("lab_shooting")
	await finish()
