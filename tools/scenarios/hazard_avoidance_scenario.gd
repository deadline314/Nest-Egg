class_name HazardAvoidanceScenario
extends ScenarioBase
## 敵人避開通電的積水（NE-408）：第二章市集入口第二段，押運手與票據投手在積水兩側巡邏。
## 主角站在積水右邊射斷電纜，拍「通電中」：剪斷時站在水外的押運手朝主角衝過來，到水邊就停下，沒有踩進去（剪斷時已經在水裡的照樣觸電）。
## 印出每個人剪斷時在不在水裡、血量與離水邊的距離。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=hazard_avoidance

const LEVEL := "res://data/levels/ch2_market_gate.tres"
const CABLE_CELL_X := 65


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
	var cable: LiveCable
	for node in get_tree().get_nodes_in_group(LiveCable.GROUP):
		if (node as LiveCable).cell.x == CABLE_CELL_X:
			cable = node
	if cable == null:
		failures += 1
		push_error("[HazardAvoidanceScenario] 找不到格 x=%d 的電纜" % CABLE_CELL_X)
		await finish()
		return
	await wait(TITLE_CARD_TIME + 0.3)
	# 主角站在積水右邊的地上，水外的押運手會朝她衝過來。
	player.global_position = cable.global_position + Vector2(cable.data.water_width * 0.5 + 60.0, 0.0)
	player.velocity = Vector2.ZERO
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_left", 1.0)
	snap_camera()
	var rect := cable.shock_rect()
	var near: Array[Enemy] = []
	var health := {}
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and absf(enemy.global_position.x - cable.global_position.x) < 220.0 and absf(enemy.global_position.y - cable.global_position.y) < 32.0:
			near.append(enemy)
			health[enemy] = enemy.health.current
	# 押運手放到積水左邊、被警報叫向主角（中間隔著水）。
	var charger: Enemy
	for enemy in near:
		if enemy.data.id == &"ch2_escort":
			charger = enemy
	if charger != null:
		charger.global_position = Vector2(rect.position.x - 50.0, cable.global_position.y)
		charger.raise_alert(player.global_position, 6.0)
	await wait(0.3)
	var inside_at_cut := {}
	for enemy in near:
		inside_at_cut[enemy] = rect.has_point(enemy.global_position + Vector2(0.0, -1.0))
	cable.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"hazard_avoidance_scenario"))
	var entered := 0
	var elapsed := 0.0
	var shot := false
	while elapsed < cable.data.warning_seconds + cable.data.live_seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		for enemy in near:
			if is_instance_valid(enemy) and not inside_at_cut[enemy] and rect.has_point(enemy.global_position + Vector2(0.0, -1.0)):
				entered += 1
		if not shot and elapsed > cable.data.warning_seconds + 1.6:
			shot = true
			capture("NE-408-hazard-live")
	var report := PackedStringArray()
	var outside := 0
	for enemy in near:
		outside += int(not inside_at_cut[enemy])
		if is_instance_valid(enemy):
			var edge := minf(absf(enemy.global_position.x - rect.position.x), absf(enemy.global_position.x - rect.end.x))
			report.append("%s in_at_cut=%s %d->%d edge=%.0f" % [enemy.data.id, inside_at_cut[enemy], health[enemy], enemy.health.current, edge])
		else:
			report.append("in_at_cut=%s %d->dead" % [inside_at_cut[enemy], health[enemy]])
	print("HAZARD near=%s outside_walked_in_frames=%d" % [report, entered])
	Input.action_release(&"aim_left")
	AimInput.set_virtual_gamepad(player, false)
	if outside == 0 or entered > 0:
		failures += 1
		push_error("[HazardAvoidanceScenario] 沒有巡邏的敵人，或有敵人踩進通電的積水")
	await finish()
