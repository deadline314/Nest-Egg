class_name LiveCableScenario
extends ScenarioBase
## 斷電纜（NE-400）：第二章市集入口，兩名護衛之間的積水。主角站在水外射斷電纜。拍三張：吊著（有提示）、
## 落水預警、通電中；並印出水裡那名護衛的血量變化與主角有沒有受傷。護衛沒觸電或主角在水外受傷就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=live_cable

const LEVEL := "res://data/levels/ch2_market_gate.tres"
const STAND_OFF := 100.0


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
		cable = node as LiveCable
		break
	if cable == null:
		failures += 1
		push_error("[LiveCableScenario] %s 裡沒有斷電纜" % LEVEL)
		await finish()
		return
	# 讓最近的一名護衛站在水裡（不讓它自己走開），其他敵人停住。
	var target: Enemy
	var best := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		var distance := absf(enemy.global_position.x - cable.global_position.x) if enemy != null else INF
		if distance < best:
			best = distance
			target = enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node != target:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	if target != null:
		target.set_physics_process(false)
		target.global_position = cable.global_position + Vector2(24.0, 0.0)
	# 只記電流造成的傷害：主角站在水外，不應該被電到。
	var shocked_player := [0]
	player.health.damaged.connect(func(info: DamageInfo) -> void:
		if info.source_id == cable.data.source_id:
			shocked_player[0] += 1)
	player.global_position = cable.global_position + Vector2(-STAND_OFF, 0.0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	snap_camera()
	await wait(TITLE_CARD_TIME + 1.5)
	print("LIVE_CABLE screen_x=%.0f" % (get_viewport().get_canvas_transform() * cable.global_position).x)
	if target != null:
		target.global_position = cable.global_position + Vector2(24.0, 0.0)
	var before := target.health.current if target != null else -1
	capture("NE-400-cable-0-hanging")
	await settle(2)
	cable.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"live_cable_scenario"))
	await wait(cable.data.warning_seconds * 0.5)
	capture("NE-400-cable-1-warning")
	await wait(cable.data.warning_seconds * 0.5 + 0.6)
	capture("NE-400-cable-2-live")
	await wait(0.6)
	var after := target.health.current if is_instance_valid(target) else 0
	print("LIVE_CABLE live=%s guard_health=%d->%d player_shocked=%d" % [cable.is_live() or cable.state == LiveCable.State.SPENT, before, after, shocked_player[0]])
	if (before > 0 and after >= before) or shocked_player[0] > 0:
		failures += 1
		push_error("[LiveCableScenario] 水裡的護衛沒有觸電，或水外的主角被電到")
	await finish()
