class_name AreaChallengeScenario
extends ScenarioBase
## 區域可選小挑戰（NE-410）：第二章市集入口「用環境機關擊倒 3 名敵人」。保留 HUD，拍兩張：
## 進區域後的挑戰提示、兩條電纜電倒三名敵人之後的完成提示（含信用點）。印出挑戰進度與信用點變化。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=area_challenge

const LEVEL := "res://data/levels/ch2_market_gate.tres"


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	var challenge: AreaChallenge
	for node in get_tree().get_nodes_in_group(AreaChallenge.GROUP):
		challenge = node as AreaChallenge
	var cables: Array[LiveCable] = []
	for node in get_tree().get_nodes_in_group(LiveCable.GROUP):
		cables.append(node as LiveCable)
	if challenge == null or cables.size() < 2:
		failures += 1
		push_error("[AreaChallengeScenario] %s 沒有區域挑戰或少於兩條電纜" % LEVEL)
		await finish()
		return
	# 敵人站在原地（受傷判定照常），主角站在第一灘水左邊、敵人看不到的高度。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Enemy).set_physics_process(false)
	cables.sort_custom(func(a: LiveCable, b: LiveCable) -> bool: return a.global_position.x < b.global_position.x)
	player.global_position = cables[0].global_position + Vector2(-140.0, 0.0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	snap_camera()
	await wait(AreaChallenge.INTRO_DELAY + 0.6)
	capture("NE-410-challenge-0-intro")
	var credits_before := Progression.credits
	# 第二灘水旁邊的票據投手放進水裡，兩條電纜一起剪。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.id == &"ch2_bill_thrower" and absf(enemy.global_position.x - cables[1].global_position.x) < 160.0:
			enemy.global_position = cables[1].global_position + Vector2(30.0, 0.0)
	# 畫面外的敵人被關卡停住時受傷判定也不在物理世界裡；叫醒但不讓它們走動。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.process_mode = Node.PROCESS_MODE_INHERIT
		(node as Enemy).set_physics_process(false)
	for cable in cables:
		cable.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"area_challenge_scenario"))
	var waited := 0.0
	while not challenge.done and waited < cables[0].data.warning_seconds + cables[0].data.live_seconds + 0.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await wait(0.4)
	capture("NE-410-challenge-1-done")
	print("AREA_CHALLENGE progress=%d/%d done=%s credits=%d->%d" % [challenge.progress, challenge.data.target, challenge.done, credits_before, Progression.credits])
	if not challenge.done or Progression.credits != credits_before + challenge.data.reward_credits:
		failures += 1
		push_error("[AreaChallengeScenario] 挑戰沒有完成或獎勵不對")
	await finish()
