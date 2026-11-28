class_name HidingSpotScenario
extends ScenarioBase
## 可躲藏的門簾凹室：第二章裝卸間入口段。連拍：走近時的提示 → 蹲進簾子裡 → 巡邏的敵人從面前走過 → 轉身回來又經過、背對著走遠 → 站起來跟在後面。
## 印出敵人經過時的距離與有沒有進入戰鬥、「不被發現」挑戰有沒有失敗；被發現或挑戰失敗就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=hiding_spot

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
	var spot: HidingSpot
	for node in get_tree().get_nodes_in_group(HidingSpot.GROUP):
		spot = node as HidingSpot
		break
	if spot == null:
		failures += 1
		push_error("[HidingSpotScenario] %s 裡沒有可躲藏的位置" % LEVEL)
		await finish()
		return
	var floor_y := spot.global_position.y
	var inside_x := spot.global_position.x + spot.width * 0.5
	# 找出離簾子最近、在右邊巡邏的敵人：拍攝時讓他往簾子走過來。
	var guard: Enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.global_position.x > inside_x and (guard == null or enemy.global_position.x < guard.global_position.x):
			guard = enemy
	if guard == null:
		failures += 1
		push_error("[HidingSpotScenario] 簾子右邊沒有巡邏的敵人")
		await finish()
		return
	var camera := get_viewport().get_camera_2d() as LevelCamera
	await wait(TITLE_CARD_TIME + 0.3)
	# 守衛放在看不到主角的遠處往左巡邏；主角走近、蹲進去之後他才走到簾子前。
	guard.global_position = Vector2(inside_x + 330.0, floor_y)
	guard.facing = -1

	# 走近：提示展開。
	player.global_position = Vector2(spot.global_position.x - 30.0, floor_y)
	player.velocity = Vector2.ZERO
	var framed := camera != null and camera.acquire_presentation_focus(self, Vector2(inside_x + 40.0, floor_y - 40.0))
	await settle(2)
	snap_camera()
	await wait(1.0)
	capture("hiding-0-approach")

	# 蹲進簾子裡。
	player.global_position = Vector2(inside_x, floor_y)
	Input.action_press(&"move_down")
	await wait(0.5)
	capture("hiding-1-hidden")

	# 巡邏的敵人往簾子走過來、從面前走過去，走到牆邊轉身再走回來、又從面前經過。
	var closest := INF
	var engaged := false
	var passes := 0
	var shot_pass := false
	var was_left := false
	var elapsed := 0.0
	var back_reach := guard.data.detect_range * guard.data.back_sight_scale
	while elapsed < 45.0:
		Input.action_press(&"move_down")  # 原生視窗失去焦點時引擎會放開按鍵；每格重按，拍攝才不受別的視窗影響
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if not is_instance_valid(guard):
			break
		var dx := guard.global_position.x - inside_x
		closest = minf(closest, absf(dx))
		engaged = engaged or guard.is_engaged()
		var left := dx < 0.0
		if left != was_left:
			passes += 1
			was_left = left
		if passes == 1 and not shot_pass and dx < -46.0:
			shot_pass = true
			capture("hiding-2-passing")
		# 第二次經過、背對著走遠到背後看不到的距離：站起來跟上去。
		if passes >= 2 and guard.facing == 1 and dx > back_reach + 24.0:
			break
	capture("hiding-3-passed")
	Input.action_release(&"move_down")
	await wait(0.3)
	capture("hiding-4-out")
	Input.action_press(&"move_right")
	var followed := 0.0
	while followed < 0.9:
		await get_tree().physics_frame
		followed += get_physics_process_delta_time()
		if is_instance_valid(guard):
			engaged = engaged or guard.is_engaged()
			if guard.global_position.x - player.global_position.x < back_reach + 12.0:
				break  # 跟太近就停，不要撞上去
	Input.action_release(&"move_right")
	await wait(0.2)
	capture("hiding-5-follow")
	if is_instance_valid(guard):
		engaged = engaged or guard.is_engaged()
	var challenge_failed := false
	for node in level.get_children():
		if node is AreaChallenge:
			challenge_failed = challenge_failed or (node as AreaChallenge).failed
	print("HIDING closest=%.1f passes=%d engaged=%s challenge_failed=%s" % [closest, passes, engaged, challenge_failed])
	if engaged or challenge_failed or closest > 16.0 or passes < 2:
		failures += 1
		push_error("[HidingSpotScenario] 敵人應該從面前走過去、沒有發現蹲在簾子後的主角")
	if framed:
		camera.release_presentation_focus(self)
	await finish()
