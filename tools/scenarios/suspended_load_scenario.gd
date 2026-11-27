class_name SuspendedLoadScenario
extends ScenarioBase
## 吊掛貨箱（NE-397）：在第一章倉庫實際開一槍把貨箱打下來。拍三張：吊著（看得到提示）、掉到一半、落地之後，
## 並印出底下那個敵人的血量變化。貨箱沒掉下來或沒傷到敵人就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=suspended_load

const LEVEL := "res://data/levels/ch1_warehouse.tres"
## 主角站在貨箱左邊幾像素。
const STAND_OFF := 78.0


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	var crate: SuspendedLoad
	for node in get_tree().get_nodes_in_group(SuspendedLoad.GROUP):
		crate = node as SuspendedLoad
		break
	if crate == null:
		failures += 1
		push_error("[SuspendedLoadScenario] %s 裡沒有吊掛貨箱" % LEVEL)
		await finish()
		return
	# 只留貨箱旁邊的那個敵人，並讓它站著不動（看得到它被砸）。
	var target: Enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and absf(enemy.global_position.x - crate.global_position.x) < 40.0 and absf(enemy.global_position.y - crate.global_position.y) < 24.0 and target == null:
			target = enemy
			enemy.set_physics_process(false)
		else:
			node.queue_free()
	var before := target.health.current if target != null else -1
	player.global_position = crate.global_position + Vector2(-STAND_OFF, 0.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	capture("NE-397-suspended-0-hanging")
	await settle(2)
	crate.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"suspended_load_scenario"))
	for i in 240:
		await get_tree().physics_frame
		if crate.drop_height() < crate.size_px.y * 1.2:
			break
	capture("NE-397-suspended-1-falling")
	for i in 240:
		if crate.state == SuspendedLoad.State.LANDED:
			break
		await get_tree().physics_frame
	await wait(0.5)
	capture("NE-397-suspended-2-landed")
	var after := target.health.current if is_instance_valid(target) else 0
	print("SUSPENDED_LOAD landed=%s enemy_health=%d->%d" % [crate.state == SuspendedLoad.State.LANDED, before, after])
	if crate.state != SuspendedLoad.State.LANDED or (before > 0 and after >= before):
		failures += 1
		push_error("[SuspendedLoadScenario] 貨箱沒有落地或沒有傷到底下的敵人")
	await finish()
