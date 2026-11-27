class_name CrateCoverScenario
extends ScenarioBase
## 遠程敵人躲到落地的貨箱後面（NE-415）：第一章倉庫，打下吊著的貨箱，基礎遠程槍手在貨箱一側、主角在另一側。
## 拍兩張：蹲在貨箱後面、站起來越過箱頂瞄準。印出槍手的 id、狀態、離貨箱多遠、蹲下時判定高度。
## 沒躲到貨箱後面、或一直沒探頭瞄準就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=crate_cover

const LEVEL := "res://data/levels/ch1_warehouse.tres"
const GUNNER_GAP := 110.0
const PLAYER_GAP := 190.0


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
	var crate := get_tree().get_first_node_in_group(SuspendedLoad.GROUP) as SuspendedLoad
	var gunner: Enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.behavior == preload("res://game/enemies/grunt.gd"):
			gunner = enemy
	if crate == null or gunner == null:
		failures += 1
		push_error("[CrateCoverScenario] %s 找不到吊掛貨箱或清掃兵" % LEVEL)
		await finish()
		return
	# 其他敵人停下並隱藏（貨箱也不會砸到他們），畫面與攻擊令牌只留給這名清掃兵。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node != gunner:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
			(node as CanvasItem).visible = false
	gunner.process_mode = Node.PROCESS_MODE_DISABLED
	await wait(TITLE_CARD_TIME + 0.3)
	var floor_y := crate.global_position.y
	player.global_position = Vector2(crate.global_position.x - PLAYER_GAP, floor_y)
	player.velocity = Vector2.ZERO
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right", 1.0)
	snap_camera()
	crate.hurtbox.receive(DamageInfo.create(99, Combat.Team.PLAYER, &"crate_cover_scenario"))
	while crate.state != SuspendedLoad.State.LANDED:
		await get_tree().physics_frame
	await wait(0.4)
	gunner.process_mode = Node.PROCESS_MODE_INHERIT
	gunner.visible = true
	gunner.global_position = Vector2(crate.global_position.x + GUNNER_GAP, floor_y)
	gunner.velocity = Vector2.ZERO
	gunner.raise_alert(player.global_position, 6.0)
	var ducked_shot := false
	var peeked := false
	var elapsed := 0.0
	var report := ""
	while elapsed < 6.0 and not peeked:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var behind := gunner.global_position.x - (crate.global_position.x + crate.size_px.x * 0.5)
		if not ducked_shot and gunner.fsm.is_in(&"cover") and gunner.get("_ducked") == true:
			await wait(0.3)
			ducked_shot = true
			report += "ducked at %.0f px behind, hurt height %.0f; " % [behind, gunner.hurtbox.contact_bounds().size.y]
			capture("NE-415-cover-0-ducked")
		if ducked_shot and gunner.fsm.is_in(&"aim") and gunner.fsm.time_in_state > gunner.data.telegraph_time * 0.75:
			peeked = true
			report += "peeked after %.1f s" % elapsed
			capture("NE-415-cover-1-peek")
	print("CRATE_COVER %s %s state=%s" % [gunner.data.id, report, gunner.fsm.current])
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	if not ducked_shot or not peeked:
		failures += 1
		push_error("[CrateCoverScenario] 清掃兵沒有躲到貨箱後面或沒有探頭：%s（狀態 %s）" % [report, gunner.fsm.current])
	await finish()
