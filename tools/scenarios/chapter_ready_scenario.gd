class_name ChapterReadyScenario
extends ScenarioBase
## 舊關卡敵人放進章節（NE-470）：
## 第一章倉庫（收帳人的地盤）打下吊掛貨箱：收帳人·盾手衝向站在貨箱上的主角、撞上貨箱暈眩；收帳人·重槍手對貨箱上的主角掃射
## （貨箱擋住視線時牠不開火，見 ChapterReadyEnemiesSuite）。
## 第三章辦公大廳（天穹的地盤）：鎮暴員蓄力、重裝機槍手轉管、狙擊手鎖定、擲彈兵的落點圈，各拍一張預兆。
## 每張只留一名敵人，其他敵人停下並隱藏，操作提示關掉。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=chapter_ready

const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const OFFICE := "res://data/levels/ch3_office_hall.tres"
const PLAYER_TILE := 8.0
const DOME := [
	["res://data/enemies/shield_rusher.tres", 12.0, &"windup", 0.45, "rusher"],
	["res://data/enemies/heavy_gunner.tres", 15.0, &"spin_up", 0.9, "gunner"],
	["res://data/enemies/sniper.tres", 20.0, &"lock", 0.45, "sniper"],
	["res://data/enemies/mortar.tres", 14.0, &"aim", 0.5, "mortar"],
]

var _report := {}


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	await _warehouse()
	await _office()
	print("CHAPTER_READY %s" % JSON.stringify(_report))
	await finish()


func _open(path: String) -> void:
	if level != null:
		level.queue_free()
		await get_tree().process_frame
	level = Level.new()
	level.configure(load(path) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(node as CanvasItem).visible = false
	await wait(TITLE_CARD_TIME + 0.3)
	for prompt in level.find_children("*", "WorldPrompt", true, false):
		prompt.set(&"enabled", false)
	AimInput.set_virtual_gamepad(player, true)
	AimInput.restore_direction(Vector2.RIGHT)


func _spawn(path: String, at: Vector2) -> Enemy:
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = at
	level._entities.add_child(enemy)
	return enemy


## 等敵人進入某個狀態並待一段時間；逾時回傳 false。
func _await_state(enemy: Enemy, state: StringName, hold: float, timeout: float, keep_player: Vector2) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		player.global_position = keep_player
		player.velocity = Vector2.ZERO
		if enemy.fsm.is_in(state) and enemy.fsm.time_in_state >= hold:
			return true
	return false


func _warehouse() -> void:
	await _open(WAREHOUSE)
	var crate := get_tree().get_first_node_in_group(SuspendedLoad.GROUP) as SuspendedLoad
	if crate == null:
		_fail("%s 找不到吊掛貨箱" % WAREHOUSE)
		return
	crate.hurtbox.receive(DamageInfo.create(99, Combat.Team.PLAYER, &"chapter_ready_scenario"))
	while crate.state != SuspendedLoad.State.LANDED:
		await get_tree().physics_frame
	var floor_y := crate.global_position.y
	# 盾手：主角站在貨箱上，盾手衝過來撞上貨箱。
	var on_crate := Vector2(crate.global_position.x, floor_y - crate.size_px.y)
	player.global_position = on_crate
	snap_camera()
	var shield := _spawn("res://data/enemies/collector_shield.tres", Vector2(crate.global_position.x + 130.0, floor_y))
	if await _await_state(shield, &"windup", 0.4, 8.0, on_crate):
		capture("NE-470-0a-shield-windup")
	if await _await_state(shield, &"dazed", 0.25, 8.0, on_crate):
		_report["shield"] = "dazed against the crate"
		capture("NE-470-0-shield-crate")
	else:
		_fail("收帳人·盾手沒有撞上貨箱暈眩（狀態 %s）" % shield.fsm.current)
	shield.queue_free()
	# 重槍手：對站在貨箱上的主角掃射。
	var behind := on_crate
	player.global_position = behind
	snap_camera()
	var heavy := _spawn("res://data/enemies/collector_heavy.tres", Vector2(crate.global_position.x + 120.0, floor_y))
	heavy.raise_alert(behind, 4.0)
	if await _await_state(heavy, &"fire", 1.0, 10.0, behind):
		_report["heavy"] = "firing, %d shots" % int(heavy.get("shots_fired"))
		capture("NE-470-1-heavy-crate")
	else:
		_fail("收帳人·重槍手沒有開火（狀態 %s）" % heavy.fsm.current)
	heavy.queue_free()


func _office() -> void:
	await _open(OFFICE)
	var floor_y := player.global_position.y
	var stand := Vector2(PLAYER_TILE * 16.0, floor_y)
	for entry: Array in DOME:
		player.global_position = stand
		snap_camera()
		await wait(0.3)
		var enemy := _spawn(entry[0], Vector2((PLAYER_TILE + float(entry[1])) * 16.0, floor_y))
		if await _await_state(enemy, entry[2], entry[3], 10.0, stand):
			_report[entry[4]] = "%s at %.0f px" % [entry[2], enemy.global_position.x - stand.x]
			capture("NE-470-%s-%s" % [str(2 + DOME.find(entry)), entry[4]])
		else:
			_fail("%s 沒有進入 %s（狀態 %s）" % [entry[4], entry[2], enemy.fsm.current])
		enemy.queue_free()
		await get_tree().physics_frame


func _fail(message: String) -> void:
	failures += 1
	push_error("[ChapterReadyScenario] " + message)
