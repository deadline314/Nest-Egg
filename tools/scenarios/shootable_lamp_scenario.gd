class_name ShootableLampScenario
extends ScenarioBase
## 可以射暗的燈（NE-399）：第二章裝卸區，主角站在燈下、離沒察覺的護衛一段距離。拍三張：燈亮著（看得到提示）、
## 射暗那一刻、射暗之後；並印出射暗前後護衛看不看得到主角。射暗後護衛仍看得到就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=shootable_lamp

const LEVEL := "res://data/levels/ch2_loading.tres"


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
	# 找一盞底下附近有敵人的燈。
	var lamp: Lamp
	var watcher: Enemy
	for node in level.find_children("*", "Node2D", true, false):
		var candidate := node as Lamp
		if candidate == null or not candidate.shootable or candidate.dead:
			continue
		for enemy_node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := enemy_node as Enemy
			var dx := absf(enemy.global_position.x - candidate.global_position.x)
			if enemy != null and dx > 60.0 and dx < enemy.data.detect_range * 0.9 and absf(enemy.global_position.y - candidate.floor_y) < 24.0:
				lamp = candidate
				watcher = enemy
				break
		if lamp != null:
			break
	if lamp == null:
		failures += 1
		push_error("[ShootableLampScenario] %s 找不到底下有敵人的可射暗燈" % LEVEL)
		await finish()
		return
	_freeze()
	player.global_position = Vector2(lamp.global_position.x, lamp.floor_y - 1.0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	snap_camera()
	await wait(TITLE_CARD_TIME)
	var reach := watcher.data.detect_range
	var seen_before := watcher._can_see_target(reach)
	capture("NE-399-lamp-0-lit")
	await settle(2)
	lamp._hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"shootable_lamp_scenario"))
	await settle(3)
	_freeze()
	capture("NE-399-lamp-1-shot")
	await wait(0.6)
	_freeze()
	var seen_after := watcher._can_see_target(reach)
	capture("NE-399-lamp-2-dark")
	print("SHOOTABLE_LAMP distance=%.0f detect=%.0f seen_before=%s seen_after=%s" % [absf(watcher.global_position.x - player.global_position.x), reach, seen_before, seen_after])
	if not lamp.shot_out or seen_after:
		failures += 1
		push_error("[ShootableLampScenario] 燈沒有熄掉，或射暗後沒察覺的敵人仍看得到主角")
	await finish()


## 拍照期間讓敵人停住（重新生成或被關卡重新啟用的也一起），畫面裡只看燈與主角。
func _freeze() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.process_mode = Node.PROCESS_MODE_DISABLED
