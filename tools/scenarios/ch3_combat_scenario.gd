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
	if variant in ["janus", "all"]:
		await _janus()
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


## 守門人：每招的預兆各拍一張（直接指定招式，預兆與判定都是遊戲裡的實際行為）、重播的問號、
## 盾裂、停機等拔插銷，以及一段沒有干預的連續戰鬥畫面。
func _janus() -> void:
	for shot: Array in [["shield_bash", 0.6, "NE-271-shield-bash"], ["scan_low", 0.5, "NE-271-scan-low"],
			["scan_high", 0.5, "NE-271-scan-high"], ["call_backup", 0.4, "NE-271-call-backup"]]:
		var janus := await _open_janus(30.0)
		if janus == null:
			return
		janus.set("_move_id", StringName(shot[0]))
		janus.set("_last_move", StringName(shot[0]))
		janus.fsm.transition(&"windup")
		await _wait_seconds(float(shot[1]))
		_freeze()
		capture(str(shot[2]))
		await _close()
	# 遺忘迴圈：上一招被打中後重播，頭上問號、通訊器旁顯示「程式重播」，同一招照樣完整蓄力。
	var replay := await _open_janus(30.0)
	if replay != null:
		replay.set("_last_move", &"scan_high")
		replay.set("_replay_pending", true)
		replay.set("_move_id", replay.choose_move())
		replay.fsm.transition(&"windup")
		await _wait_seconds(0.4)
		_freeze()
		capture("NE-271-replay")
		await _close()
	# 盾架裂開（撲空三次）、玩家繞到背後：通訊器亮橙色可以打。
	GameState.set_flag(&"ch3_janus_shield_misses", 3, false)
	var cracked := await _open_janus(30.0, 20, false)
	if cracked != null:
		# 繞到他背後的那一刻（轉身要 0.8 秒）：盾架的裂痕和背上亮起的通訊器同時看得到。
		player.global_position = cracked.global_position + Vector2(-cracked.facing * 40.0, 0)
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * (0.15 if cracked.facing < 0 else 0.85), get_viewport().get_visible_rect().size.y * 0.5))
		await _wait_seconds(0.05)
		snap_camera()
		await _wait_seconds(0.25)
		_freeze()
		capture("NE-271-cracked-behind")
		await _close()
	# 穩定度歸零：工作架停住，背後的維修插銷提示。
	var halted := await _open_janus(30.0)
	if halted != null:
		halted.health.take_damage(_lethal())
		await _wait_seconds(0.5)
		# 走到他背後的插銷旁：互動提示出現。
		player.global_position = halted.global_position + Vector2(-halted.facing * 14.0, 0)
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * (0.15 if halted.facing < 0 else 0.85), get_viewport().get_visible_rect().size.y * 0.5))
		await _wait_seconds(0.05)
		snap_camera()
		await _wait_seconds(0.75)
		_freeze()
		capture("NE-271-halted-pin")
		await _close()
	# 連續戰鬥畫面：不干預，玩家站在大廳裡，每 0.5 秒拍一張。
	var live := await _open_janus(30.0)
	if live != null:
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.85, get_viewport().get_visible_rect().size.y * 0.5))
		await _wait_seconds(0.05)
		snap_camera()
		for i in 8:
			await _wait_seconds(0.5)
			capture("NE-271-sequence-%02d" % i)
		await _close()


## 開門禁大廳（登場劇情已看過），回傳守門人；flags_reset 為 false 時保留已設定的戰鬥旗標。
func _open_janus(x_tile: float, row := 20, flags_reset := true, face_left := false) -> JanusBoss:
	var keep: Dictionary = {}
	if not flags_reset:
		for key: String in GameState.world_flags:
			if key.begins_with("ch3_janus_"):
				keep[key] = GameState.world_flags[key]
	await _open("ch3_gate_hall", x_tile, row)
	for key: String in keep:
		GameState.set_flag(StringName(key), keep[key], false)
	GameState.set_flag(&"ch3_janus_intro_seen", true, false)
	var janus: JanusBoss = null
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is JanusBoss:
			janus = node
	if janus == null:
		push_error("[ch3_combat] 門禁大廳沒有守門人")
		return null
	if not flags_reset:
		janus.call(&"_restore_from_flags")
	if face_left:
		# 滑鼠移到畫面左邊：主角轉向守門人，鏡頭的前瞻也跟著往左，兩個人都在畫面裡。
		get_viewport().warp_mouse(Vector2(get_viewport().get_visible_rect().size.x * 0.15, get_viewport().get_visible_rect().size.y * 0.5))
	janus.call(&"_wake")
	await _wait_seconds(1.2)
	return janus


func _wait_seconds(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _lethal() -> DamageInfo:
	var info := DamageInfo.create(999, Combat.Team.PLAYER, &"capture")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info


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
