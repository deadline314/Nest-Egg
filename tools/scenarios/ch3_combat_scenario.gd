extends "res://tools/scenarios/scenario_base.gd"
## 第三章戰鬥的實際畫面（NE-272、NE-271）：在真正的第三章地圖上讓敵人照常行動，等到指定的預兆或狀態才定格拍照。
## 用法：tools/screenshot.tscn -- --scenario=ch3_combat --out=<資料夾> [--variant=inspectors|janus|all]
## 定格時停住所有敵人與玩家（子彈照常飛），所以拍到的是預兆正在畫的那一格，不是事後擺出來的姿勢。

const WAIT_FRAMES := 900


func run() -> void:
	var variant := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):
			variant = arg.trim_prefix("--variant=")
	Story.auto_skip = true
	if variant in ["inspectors", "all"]:
		await _inspectors()
	if variant in ["janus", "all"] and has_method(&"_janus"):
		await call(&"_janus")
	await settle(10)


func _inspectors() -> void:
	# 泵室下槽第一場：只有一台抽水巡檢器，地上的衝撞路線亮起。
	await _open("ch3_pump", 35.0)
	if await _wait_enemy(&"pump_inspector", func(e: Enemy) -> bool: return e.fsm.is_in(&"windup") and e.fsm.time_in_state > 0.35):
		_freeze()
		capture("NE-272-pump-telegraph")
	await _close()
	# 泵室下槽第二場：絕緣巡檢器掛在上橋底下，探頭降到胸口高度、水平預兆線鎖定。
	await _open("ch3_pump", 49.0)
	if await _wait_enemy(&"insulation_inspector", func(e: Enemy) -> bool: return (e as InsulationInspector).is_locked()):
		_freeze()
		capture("NE-272-insulation-lock")
	await _close()
	# 夾層維修帶：走下面就是一近戰一遠距的短戰。
	await _open("ch3_mezzanine", 42.0)
	if await _wait_enemy(&"", func(e: Enemy) -> bool: return e.is_telegraphing()):
		_freeze()
		capture("NE-272-mezzanine-fight")
	await _close()


## 開第三章的某張地圖：略過進場劇情與章節卡，玩家站在 x_tile、第 row 列的地面上（列＝腳下那一格的上緣）。
func _open(ident: String, x_tile: float, row := 20) -> void:
	if not ident.begins_with("ch3_"):
		ident = "ch3_" + ident
	GameState.start_new_run(GameState.difficulties[1])
	for id in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var data := (load("res://data/levels/%s.tres" % ident) as LevelData).duplicate()
	data.intro_scene = &""
	data.show_chapter_card = false
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(5)
	player = level.player
	player.health.setup(9999, 0.0)
	player.global_position = Vector2((x_tile + 0.5) * 16.0, row * 16.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await settle(5)


## 等某種敵人（空白＝任一隻）符合條件；回傳是否等到。
func _wait_enemy(id: StringName, condition: Callable) -> bool:
	for i in WAIT_FRAMES:
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy != null and (id == &"" or enemy.data.id == id) and bool(condition.call(enemy)):
				return true
		await get_tree().physics_frame
	push_error("[ch3_combat] 等不到 %s 的指定狀態" % (id if id != &"" else &"任一敵人"))
	return false


func _freeze() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.set_physics_process(false)
		(node as CanvasItem).queue_redraw()
	if player != null:
		player.set_physics_process(false)


func _close() -> void:
	if level != null:
		level.queue_free()
		level = null
	await settle(5)
