extends Node
## 序章真輸入探針（ST-16）：從真正的 Main 新遊戲入口開始，用移動、跳躍、射擊、近戰、格擋、衝刺與互動鍵玩完序章，
## 走出店門進當舖，沿途截圖並檢查每一項練習是否靠真的動作完成。瞄準用手把右搖桿的輸入（AimInput 的手把路徑）。
## 用法：godot --path . res://tools/prologue_play_probe.tscn -- --out=<絕對路徑資料夾>

const LIMIT := 1800

var _out := ""
var _main: Node
var _failures := 0
var _played: Array[StringName] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(4)
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	print("saved %s (%s)" % [name, error_string(image.save_png(_out.path_join(name + ".png")))])


func _level() -> Level:
	var screen: Variant = _main.get("_screen")
	return screen as Level if screen is Level else null


func _player() -> Player:
	var level := _level()
	return level.player if level != null else null


## 玩家讀完演出就按略過（等同 Esc）；選擇題選預設。
func _finish_story(shot := "") -> void:
	var shown := false
	for i in LIMIT:
		if not Story.is_cinematic_active():
			return
		if not shot.is_empty() and not shown:
			await _frames(60)
			await _shot(shot)
			shown = true
		Story.skip_cinematic()
		await _frames(6)


func _walk_to(x: float, tolerance := 6.0) -> void:
	for i in LIMIT:
		var player := _player()
		if player == null:
			return
		await _finish_story()
		var dx := x - player.global_position.x
		if absf(dx) <= tolerance:
			break
		var action := &"move_right" if dx > 0.0 else &"move_left"
		Input.action_press(action)
		await _frames(1)
		Input.action_release(action)
	Input.action_release(&"move_right")
	Input.action_release(&"move_left")
	await _frames(4)


func _press(action: StringName, hold := 2) -> void:
	Input.action_press(action)
	await _frames(hold)
	Input.action_release(action)
	await _frames(2)


func _aim(direction: Vector2) -> void:
	AimInput.using_gamepad = true
	for name in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		Input.action_release(name)
	if direction.x > 0.0:
		Input.action_press(&"aim_right", direction.x)
	elif direction.x < 0.0:
		Input.action_press(&"aim_left", -direction.x)
	if direction.y < 0.0:
		Input.action_press(&"aim_up", -direction.y)
	elif direction.y > 0.0:
		Input.action_press(&"aim_down", direction.y)


func _station(id: StringName) -> TrainingStation:
	for node in _level().find_children("*", "TrainingStation", true, false):
		if (node as TrainingStation).data.id == id:
			return node
	return null


func _npc(id: StringName) -> NpcActor:
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if (node as NpcActor).data.id == id:
			return node
	return null


func _wait_flag(flag: StringName, frames := 600) -> bool:
	for i in frames:
		if GameState.has_flag(flag):
			return true
		await _frames(1)
	return GameState.has_flag(flag)


func _run() -> void:
	Story.scene_started.connect(func(id: StringName, _mode: StringName) -> void: _played.append(id))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(30)
	# 軟體算圖時選單轉場很慢：轉場還沒結束時 Main 會忽略開始，所以每秒重按一次，最多等兩分鐘。
	var deadline := Time.get_ticks_msec() + 120000
	var started := false
	while Time.get_ticks_msec() < deadline and (_level() == null or _player() == null):
		if not started and not bool(_main.call("_route_pending")):
			_main.call("_on_start_requested", GameState.difficulties[1])
			started = _main.get("_active_run")
		await _frames(30)
	var level := _level()
	_check(level != null and level.data.resource_path == "res://data/levels/ch1_prologue.tres", "a new game from Main enters the prologue")
	if level == null:
		print("PROLOGUE_PLAY_PROBE failures=%d" % _failures)
		get_tree().quit(1)
		return
	await _frames(90)
	await _finish_story("ST-16-p01-door")
	var deaths := GameState.deaths
	# 暫停選單的略過：短按先確認（預設焦點「繼續練習」），這裡取消，回到原步、不改進度。
	var menu: PauseMenu = level._pause_menu
	for i in LIMIT:
		if not GameplayLock.is_locked() and not Story.is_cinematic_active():
			break
		await _frames(1)
	await _frames(30)
	menu.open()
	_check(menu._root.visible, "the pause menu opens once the opening hands over control")
	menu._skip_button.button_down.emit()
	menu._skip_button.button_up.emit()
	menu._skip_button.pressed.emit()
	await _frames(40)  # 選單有淡入動畫
	await _shot("ST-16-skip-confirm")
	menu._cancel_skip()
	menu.close()
	_check(not GameState.has_flag(&"ch1_prologue_skipped"), "cancelling the prologue skip keeps the practice")
	# P01→P02：走到工作桌（真的移動才算），再跳上兩格高的搬貨台。
	var bench := _station(&"ch1_training_workbench")
	await _walk_to(bench.global_position.x)
	_check(await _wait_flag(&"ch1_prologue_bench_done", 60), "walking to the workbench completes the movement practice")
	await _finish_story("ST-16-p02-talk")
	var platform := _station(&"ch1_training_platform")
	# 像玩家一樣：沒跳上去就退回助跑再跳（最多四次）。
	for attempt in 4:
		await _walk_to(platform.global_position.x - 46.0, 4.0)
		await _frames(20)
		if attempt == 0:
			await _shot("ST-16-p02-jump-prompt")
		Input.action_press(&"move_right")
		Input.action_press(&"jump")
		# 像玩家一樣在空中收方向：到了搬貨台上方就放開右鍵，落在台上。
		for i in 70:
			if i == 16:
				Input.action_release(&"jump")
			if _player().global_position.x >= platform.global_position.x - 6.0:
				Input.action_release(&"move_right")
			if GameState.has_flag(&"ch1_prologue_jump_done"):
				break
			await _frames(1)
		Input.action_release(&"jump")
		Input.action_release(&"move_right")
		if GameState.has_flag(&"ch1_prologue_jump_done"):
			break
		var p := _player()
		print("jump attempt %d missed: player %s state %s, platform %s, locked %s, story %s" % [attempt, p.global_position, p.state, platform.global_position, GameplayLock.is_locked(), Story.is_cinematic_active()])
	_check(await _wait_flag(&"ch1_prologue_jump_done", 60), "a real jump onto the cargo platform completes the jump practice")
	await _finish_story()
	# P03：射擊線，用手把瞄準右方開槍打低靶。
	var range_mark := _station(&"ch1_training_range")
	await _walk_to(range_mark.global_position.x)
	await _finish_story("ST-16-p03-range")
	_check(_npc(&"ch1_old_k_backyard").is_present() and not _npc(&"ch1_old_k_prologue").is_present(), "Old K moves to the backyard line once the tool is down")
	var target := _station(&"ch1_training_target")
	await _walk_to(target.global_position.x - 120.0)
	_aim(Vector2.RIGHT)
	await _frames(10)
	await _shot("ST-16-p03-aim")
	for i in 6:
		await _press(&"shoot", 3)
		if GameState.has_flag(&"ch1_prologue_shot_done"):
			break
		await _frames(20)
	_check(await _wait_flag(&"ch1_prologue_shot_done", 120), "a real shot hits the low target")
	await _finish_story()
	# P04：橡膠靶近戰、訓練器格擋（先被打停一次，再舉盾擋下）、衝刺穿線。
	var area := _station(&"ch1_training_area")
	await _walk_to(area.global_position.x)
	await _finish_story("ST-16-p04-intro")
	var dummy := _station(&"ch1_training_dummy")
	await _walk_to(dummy.global_position.x - 22.0)
	_aim(Vector2.RIGHT)
	for i in 6:
		await _press(&"melee", 3)
		if GameState.has_flag(&"ch1_prologue_melee_done"):
			break
		await _frames(20)
	_check(await _wait_flag(&"ch1_prologue_melee_done", 120), "a real melee hit on the rubber dummy")
	await _finish_story()
	var trainer := _station(&"ch1_training_trainer")
	await _walk_to(trainer.global_position.x - 34.0)
	var health := _player().health.current
	for i in 300:
		if GameState.has_flag(&"ch1_prologue_fall_shown"):
			break
		if trainer._phase == &"warn" and i % 30 == 0:
			await _shot("ST-16-p04-trainer-warn")
		await _frames(1)
	_check(GameState.has_flag(&"ch1_prologue_fall_shown") and _player().health.current == health and GameState.deaths == deaths, "an unblocked strike stops the trainer without hurting or killing")
	await _finish_story("ST-16-p04-fall")
	_aim(Vector2.RIGHT)
	Input.action_press(&"block")
	_check(await _wait_flag(&"ch1_prologue_guard_done", 600), "holding block toward the trainer blocks its strike")
	Input.action_release(&"block")
	await _finish_story()
	var dash := _station(&"ch1_training_dash")
	await _walk_to(dash.global_position.x - 40.0)
	Input.action_press(&"move_right")
	await _frames(2)
	await _press(&"dash", 3)
	await _frames(20)
	Input.action_release(&"move_right")
	_check(await _wait_flag(&"ch1_prologue_dash_done", 120), "a real dash across the training line")
	await _finish_story()
	# P05→P06：回櫃台和老 K 說話兩次，從旁邊的門回店裡。
	var old_k := _npc(&"ch1_old_k_counter")
	_check(old_k.is_present() and not _npc(&"ch1_old_k_backyard").is_present(), "Old K is back at the counter after the dash")
	await _walk_to(old_k.global_position.x + 14.0)
	await _press(&"interact")
	await _finish_story("ST-16-p05-service")
	_check(GameState.has_flag(&"ch1_prologue_service_heard"), "Old K explains the recovery service")
	await _frames(70)
	await _press(&"interact")
	await _finish_story("ST-16-p06-call")
	_check(GameState.has_flag(&"ch1_prologue_exit"), "the wrap-up call hands over the exit")
	var exit: Portal = _level()._portals.get(&"prologue_exit")
	await _walk_to(exit.global_position.x)
	await _press(&"interact")
	deadline = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not (_level() != null and _level().data.resource_path == "res://data/levels/ch1_pawnshop.tres" and _player() != null):
		await _frames(1)
	await _frames(150)
	await _shot("ST-16-pawnshop-arrival")
	_check(_level() != null and _level().data.resource_path == "res://data/levels/ch1_pawnshop.tres", "the prologue door leads into the pawnshop")
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"), "the prologue never counted a death or the first registration")
	var missing := PacingEstimate.PROLOGUE_PATH.filter(func(id: StringName) -> bool: return not _played.has(id))
	_check(missing.is_empty(), "the pacing path matches the scenes a real run plays (missing %s)" % [missing])
	print("PROLOGUE_PATH_PLAYED %s" % [_played])
	print("PROLOGUE_PLAY_PROBE failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
