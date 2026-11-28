class_name StalkerWalkScenario
extends ScenarioBase
## 迷彩獵手走路的實機連續圖（NE-480）：牠唯一出現的區域（level_02 升降井與夾層區），遊戲倍率。
## 主角站在牠左邊、面向牠；迷彩獵手以平常的速度走過來（拍照時不讓牠開火、強制現形，才看得到走路的樣子）。
## 走到畫面裡之後每 0.1 秒拍一張，共 8 張（約一個步伐週期）。其他敵人停下並隱藏，操作提示關掉。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=stalker_walk

const LEVEL := "res://data/levels/level_02.tres"
const START_GAP := 300.0
const SHOW_FROM := 215.0
const FRAMES := 8


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
	var stalker: Enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.id == &"stalker" and stalker == null:
			stalker = enemy
		else:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
			(node as CanvasItem).visible = false
	if stalker == null:
		failures += 1
		push_error("[StalkerWalkScenario] %s 找不到迷彩獵手" % LEVEL)
		await finish()
		return
	stalker.process_mode = Node.PROCESS_MODE_DISABLED
	await wait(TITLE_CARD_TIME + 0.3)
	for prompt in level.find_children("*", "WorldPrompt", true, false):
		prompt.set(&"enabled", false)
	var spot := stalker.global_position
	var stand := spot - Vector2(START_GAP, 0.0)
	player.global_position = stand
	AimInput.set_virtual_gamepad(player, true)
	AimInput.restore_direction(Vector2.RIGHT)
	snap_camera()
	await wait(0.4)
	stalker.process_mode = Node.PROCESS_MODE_INHERIT
	var shots := 0
	var next_shot := 0.0
	var elapsed := 0.0
	while elapsed < 10.0 and shots < FRAMES:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		player.global_position = stand
		player.velocity = Vector2.ZERO
		stalker.set("_cooldown", 99.0)
		stalker.set("_reveal_left", 99.0)
		var gap := stalker.global_position.x - stand.x
		if gap <= SHOW_FROM and absf(stalker.velocity.x) > 1.0 and elapsed >= next_shot:
			capture("NE-480-walk-%d" % shots)
			shots += 1
			next_shot = elapsed + 0.1
	print("STALKER_WALK frames %d, speed %.0f px/s" % [shots, absf(stalker.velocity.x)])
	if shots < FRAMES:
		failures += 1
		push_error("[StalkerWalkScenario] 只拍到 %d 張（狀態 %s）" % [shots, stalker.fsm.current])
	AimInput.set_virtual_gamepad(player, false)
	await finish()
