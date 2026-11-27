class_name SteamPushScenario
extends ScenarioBase
## 蒸汽擋住敵人的視線（NE-409）：第一章街道的蒸汽閥。主角站在閥門左邊，最近的一名槍手放在蒸汽牆右邊。
## 打開閥門後，槍手隔著蒸汽看不到主角、不開槍，改成穿過蒸汽往主角推進。拍「蒸汽中」與「穿出蒸汽」兩張，
## 並印出槍手還在蒸汽外的時候有沒有瞄準、往主角推進了多遠。隔著蒸汽瞄準或原地不動就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=steam_push

const LEVEL := "res://data/levels/ch1_street.tres"


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
	var valve: SteamValve
	for node in get_tree().get_nodes_in_group(SteamValve.GROUP):
		valve = node as SteamValve
		break
	if valve == null:
		failures += 1
		push_error("[SteamPushScenario] %s 裡沒有蒸汽閥" % LEVEL)
		await finish()
		return
	var screen := valve.screen_rect()
	var gunner: Enemy
	var best := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		var distance := absf(enemy.global_position.x - screen.end.x)
		if distance < best:
			best = distance
			gunner = enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node != gunner:
			node.queue_free()  # 只看這一名槍手
	await wait(TITLE_CARD_TIME)
	player.global_position = valve.global_position + Vector2(-30.0, 0.0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	gunner.global_position = Vector2(screen.end.x + 110.0, valve.global_position.y)
	gunner.fsm.transition(&"patrol")
	snap_camera()
	# 先讓蒸汽升起來，再叫醒槍手（關卡把畫面外的敵人停住，搬過來之後要叫醒），量的是「蒸汽已經在」時的反應。
	valve.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"steam_push_scenario"))
	for i in 3:
		await get_tree().physics_frame
	gunner.process_mode = Node.PROCESS_MODE_INHERIT
	var start_x := gunner.global_position.x
	# 蒸汽擋著的時候，槍手有沒有進入瞄準或出招（隔著蒸汽開槍）；穿出蒸汽之後才出招是正常的。
	var aimed_blind := 0
	var elapsed := 0.0
	var captured := false
	while elapsed < valve.data.screen_seconds - 1.0 and is_instance_valid(gunner):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		for node in get_tree().get_nodes_in_group(&"enemies"):
			if node != gunner:
				node.queue_free()  # 鎖場的增援也拿掉，畫面裡只看這一名槍手
		var inside_or_beyond := gunner.global_position.x <= screen.end.x + 4.0
		if not inside_or_beyond and gunner.is_telegraphing():
			aimed_blind += 1
		if not captured and elapsed >= 1.4:
			captured = true
			capture("NE-409-steam-push-0-inside")
	var pushed := start_x - gunner.global_position.x if is_instance_valid(gunner) else 0.0
	capture("NE-409-steam-push-1-through")
	print("STEAM_PUSH aimed_through_steam_frames=%d pushed=%.0f gunner=%s" % [aimed_blind, pushed, gunner.data.id if is_instance_valid(gunner) else "gone"])
	if pushed < 20.0 or aimed_blind > 0:
		failures += 1
		push_error("[SteamPushScenario] 槍手沒有往主角推進")
	await finish()
