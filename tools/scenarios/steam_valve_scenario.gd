class_name SteamValveScenario
extends ScenarioBase
## 蒸汽閥（NE-398）：在第一章街道的槍手火線前實際打開閥門。拍三張：還沒打開（看得到提示）、蒸汽牆擋子彈、散去之後，
## 並印出蒸汽在的時候被吃掉幾發敵方子彈。閥門沒打開或沒擋到子彈就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=steam_valve

const LEVEL := "res://data/levels/ch1_street.tres"
const STAND_OFF := 30.0


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
		push_error("[SteamValveScenario] %s 裡沒有蒸汽閥" % LEVEL)
		await finish()
		return
	player.global_position = valve.global_position + Vector2(-STAND_OFF, 0.0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	_freeze_enemies()
	snap_camera()
	await wait(TITLE_CARD_TIME)
	_freeze_enemies()
	capture("NE-398-valve-0-ready")
	await settle(2)
	valve.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"steam_valve_scenario"))
	# 從蒸汽牆右邊朝主角發射六發敵方子彈，追蹤每一發有沒有穿過蒸汽。
	var screen := valve.screen_rect()
	var spec := load("res://data/projectiles/collector_shot.tres") as ProjectileSpec
	var bullets: Array[Projectile] = []
	var crossed := 0
	for i in 6:
		_freeze_enemies()
		bullets.append(ProjectilePool.spawn(spec, Vector2(screen.end.x + 60.0, player.global_position.y - 22.0), Vector2.LEFT, Combat.Team.ENEMY))
		for f in 11:
			await get_tree().physics_frame
			for bullet in bullets:
				if bullet != null and bullet.active and bullet.global_position.x < screen.position.x - 2.0:
					crossed += 1
					bullet.deactivate()
		if i == 2:
			capture("NE-398-valve-1-venting")
	await wait(valve.data.screen_seconds)
	_freeze_enemies()
	capture("NE-398-valve-2-cleared")
	print("STEAM_VALVE shots=%d crossed=%d state_after=%d" % [bullets.size(), crossed, valve.state])
	if crossed > 0 or valve.state != SteamValve.State.COOLING:
		failures += 1
		push_error("[SteamValveScenario] 有 %d 發子彈穿過蒸汽牆，或時間到沒有散去" % crossed)
	await finish()


## 拍照期間讓敵人停住（重新生成的也一起），畫面裡只看閥門與子彈。
func _freeze_enemies() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.process_mode = Node.PROCESS_MODE_DISABLED
