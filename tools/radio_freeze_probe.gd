extends Node
## NE-246 重要通訊凍結探針：在真的港區街道關卡（有敵人），玩家真的開槍、子彈還在飛時播出重要通訊，
## 檢查同一顆子彈、敵人與遊玩計時在閱讀時不動；中途開關暫停選單仍凍結；確認逐句前進，讀完才解凍。
## 接著拿起手把：連續兩則重要通訊用手把確認鍵逐句讀完（每按一次只前進一句、順序不亂）；通訊中途死亡不留凍結也不算看過。
## 用法：godot --path . res://tools/radio_freeze_probe.tscn -- --out=<絕對路徑資料夾>（無頭也可跑，只是不截圖）
##   --mode=quit --save-dir=<絕對路徑>：從真的 Main 進街道、播重要通訊時正常退出（Main 會存檔）。
##   --mode=resume --save-dir=<同一個路徑>：另一個程序按「繼續遊戲」，不能留著凍結，被打斷的通訊沒有算看過、之後會重播。

const LEVEL := "res://data/levels/ch1_street.tres"
const SCENE := &"ch1_g06_tip_blade"
## 連續兩則（手把）與死亡打斷用的重要通訊。
const PAIR: Array[StringName] = [&"ch1_g06_tip_slide", &"ch1_g06_tip_collector"]
const DEATH_SCENE := &"ch1_g07_dog"
const QUIT_SCENE := &"ch1_g06_lamp"

var _out := ""
var _failures := 0
var _mode := ""
var _save_dir := ""
var _main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	if _mode in ["quit", "resume"]:
		if not _save_dir.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_save_dir) != OK:
			push_error("[RadioFreezeProbe] --mode=%s 需要可寫入的絕對路徑 --save-dir" % _mode)
			get_tree().quit(2)
			return
		_run_main.call_deferred()
		return
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(6)
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	print("saved %s (%s)" % [name, error_string(image.save_png(_out.path_join(name + ".png")))])


## 真的按 Enter（ui_accept 的鍵盤綁定）直到通訊讀完；回傳按了幾次。
func _read_all(layer: DialogueLayer) -> int:
	var presses := 0
	while layer.is_radio_frozen() and presses < 60:
		await _frames(8)
		Input.parse_input_event(_key(true))
		await _frames(2)
		Input.parse_input_event(_key(false))
		presses += 1
	await _frames(4)
	return presses


func _joy(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


## 手把確認鍵（A）逐句讀完：每句等字打完才按，記下每按一次後畫面上的句子；回傳按了幾次。
func _read_all_pad(layer: DialogueLayer, shown: Array[String]) -> int:
	var presses := 0
	while layer.is_radio_frozen() and presses < 60:
		await _frames(70)
		var before := layer._radio_text.text
		if shown.is_empty() or shown.back() != before:
			shown.append(before)
		_joy(JOY_BUTTON_A, true)
		await _frames(2)
		_joy(JOY_BUTTON_A, false)
		presses += 1
	await _frames(4)
	return presses


func _key(pressed: bool) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = pressed
	return key


func _enemy_positions(level: Level) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for enemy in level.get_tree().get_nodes_in_group(&"enemies"):
		result.append((enemy as Node2D).global_position)
	return result


func _run() -> void:
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL))
	get_tree().root.add_child(level)
	await _frames(90)
	var layer: DialogueLayer = Story._layer
	# 走到第一群敵人附近，面向右開一槍，子彈還在飛時播通訊。
	level.player.global_position.x = 96.0 * 16.0
	await _frames(30)
	AimInput.using_gamepad = true
	Input.action_press(&"aim_right")
	# 走過來時觸發的通訊（燈的提示）先像玩家一樣讀完。
	for i in 600:
		if not Story.is_cinematic_active() and not GameplayLock.is_locked():
			break
		Story.skip_cinematic()
		await _read_all(layer)
		await _frames(2)
	_check(not Story.was_seen(SCENE), "the test radio has not played yet")
	Input.action_press(&"shoot")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release(&"shoot")
	await get_tree().physics_frame
	var bullets := ProjectilePool.container().get_children().filter(func(node: Node) -> bool: return node is Projectile and (node as Projectile).visible)
	_check(not bullets.is_empty(), "a real player bullet is in flight")
	Story.play(SCENE)
	await _frames(20)
	_check(layer.is_radio_frozen() and get_tree().paused, "the important radio froze the world")
	var bullet: Projectile = bullets[0] if not bullets.is_empty() else null
	var bullet_at := bullet.global_position if bullet != null else Vector2.ZERO
	var enemies := _enemy_positions(level)
	var clock := GameState.run_time
	await _shot("NE-246-reading")
	await _frames(120)
	_check(bullet == null or bullet.global_position == bullet_at, "the same bullet stays still while reading")
	_check(_enemy_positions(level) == enemies and GameState.run_time == clock, "enemies and the play clock stay still while reading")
	level._pause_menu.open()
	await _shot("NE-246-pause-over-radio")
	level._pause_menu.close()
	await _frames(10)
	_check(layer.is_radio_frozen() and get_tree().paused and (bullet == null or bullet.global_position == bullet_at), "closing the pause menu keeps the world frozen")
	var presses := await _read_all(layer)
	_check(presses >= Story.resolved_lines(SCENE).size(), "each line needed its own confirm (%d presses)" % presses)
	await _frames(10)
	_check(not layer.is_radio_frozen() and not get_tree().paused and Story.was_seen(SCENE), "confirming each line ends the radio and thaws the world")
	await _frames(30)
	_check(bullet == null or not bullet.visible or bullet.global_position != bullet_at, "the bullet continues after reading")
	Input.action_release(&"aim_right")
	await _pad_pair(level, layer)
	await _death_interrupts(level, layer)
	print("RADIO_FREEZE_PROBE failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## 拿起手把（世界沒凍結時按一下），連續播兩則重要通訊：提示改顯示手把確認鍵；每按一次只前進一句，兩則依序讀完。
func _pad_pair(level: Level, layer: DialogueLayer) -> void:
	# 這段量的是通訊，不是戰鬥：讀到一半時旁邊的敵人照樣會打過來（算圖慢時尤其多），先讓主角撐得住，免得被打倒而量錯。
	level.player.health.setup(9999, 0.0)
	_joy(JOY_BUTTON_GUIDE, true)
	await _frames(2)
	_joy(JOY_BUTTON_GUIDE, false)
	await _frames(4)
	_check(InputBindings.using_gamepad, "picking up the gamepad switches the prompts to the gamepad")
	var finished: Array[StringName] = []
	var on_finished := func(id: StringName) -> void: finished.append(id)
	Story.scene_finished.connect(on_finished)
	# 走過來時可能已經聽過其中一則：這裡要的是「連續兩則」的行為，所以不受「只播一次」限制。
	for id in PAIR:
		Story.play(id, false)
	await _frames(70)
	var expected_prompt := InputBindings.format("{ui_accept} 繼續")
	_check(layer.is_radio_frozen() and get_tree().paused, "back-to-back important radios freeze the world")
	# 提示會閃爍，所以只看文字：確認鍵要是手把的按鍵名稱。
	_check(layer._radio_continue.text == expected_prompt and expected_prompt.begins_with(InputBindings.joy_label(&"ui_accept")),
			"the radio shows the gamepad confirm button (%s)" % layer._radio_continue.text)
	await _shot("NE-246-pad-reading")
	var expected_lines: Array[String] = []
	for id in PAIR:
		for line in Story.resolved_lines(id):
			expected_lines.append(str(line.get("text", "")))
	var shown: Array[String] = []
	var presses := await _read_all_pad(layer, shown)
	await _frames(10)
	_check(presses == expected_lines.size(), "one press per fully shown line (%d presses for %d lines)" % [presses, expected_lines.size()])
	_check(shown == expected_lines, "the lines appear once each, in script order: %s" % [shown])
	_check(finished.filter(func(id: StringName) -> bool: return id in PAIR) == PAIR, "the two radios finish in the order they were played: %s" % [finished])
	# 讀完之後，關卡自己觸發的其他通訊（例如敵人走近時的提示）照樣讀完；這裡要確認的是沒有凍結卡住。
	var extra := 0
	while layer.is_radio_frozen() and extra < 10:
		extra += await _read_all_pad(layer, [] as Array[String])
	_check(not layer.is_radio_frozen() and not get_tree().paused and not GameplayLock.is_locked(), "the world thaws after the last line (%d extra lines read)" % extra)
	Story.scene_finished.disconnect(on_finished)


## 重要通訊讀到一半時死亡：不能留下凍結，通訊不算看過（之後會重播），死亡照常結算。
func _death_interrupts(level: Level, layer: DialogueLayer) -> void:
	var deaths := GameState.deaths
	var seen_before := Story.was_seen(DEATH_SCENE)
	Story.play(DEATH_SCENE, false)
	await _frames(20)
	_check(layer.is_radio_frozen(), "the radio freezes before the death")
	level.player.health.kill(DamageInfo.create(9999, Combat.Team.ENEMY, &"probe"))
	await _frames(30)
	_check(level.died and GameState.deaths == deaths + 1, "the death still counts once")
	_check(not layer.is_radio_frozen() and Story.was_seen(DEATH_SCENE) == seen_before, "the death cancels the radio without marking it read")
	_check(layer._radio_lock == 0, "the reading lock is released after the death")


## 跨程序：quit 在播重要通訊時正常退出；resume 在新程序繼續，不留凍結、通訊沒算看過，之後還能完整讀。
func _run_main() -> void:
	Story.auto_skip = false
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("_run_store", RunSaveStore.new(_save_dir.path_join("slot.json")))
	add_child(_main)
	await _frames(30)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and bool(_main.call("_route_pending")):
		await _frames(10)
	if _mode == "quit":
		_main.call("_on_start_requested", GameState.difficulties[1])
		await _frames(5)
		_main.call("_on_area_requested", LEVEL)
	else:
		_main.call("_on_continue_requested")
	var level: Level = null
	while Time.get_ticks_msec() < deadline:
		level = _main.get("_screen") as Level
		if level != null and level.data.resource_path == LEVEL and level.player != null:
			break
		await _frames(1)
	_check(level != null and level.data.resource_path == LEVEL, "Main lands in the street (%s)" % _mode)
	await _frames(60)
	var layer: DialogueLayer = Story._layer
	# 進場時的其他通訊照常讀完。
	for i in 30:
		if not Story.is_cinematic_active() and not layer.is_radio_frozen():
			break
		Story.skip_cinematic()
		await _read_all(layer)
	if _mode == "quit":
		Story.play(QUIT_SCENE)
		await _frames(20)
		_check(layer.is_radio_frozen(), "the important radio is up when the player quits")
		print("RADIO_FREEZE_PROBE mode=quit failures=%d" % _failures)
		_main.call("_quit", 1 if _failures > 0 else 0)
		return
	_check(not layer.is_radio_frozen() and not get_tree().paused and not GameplayLock.is_locked(), "continuing leaves no reading freeze behind")
	_check(not Story.was_seen(QUIT_SCENE), "the radio cut off by quitting is not marked as read")
	Story.play(QUIT_SCENE)
	await _frames(20)
	_check(layer.is_radio_frozen(), "the interrupted radio can play again")
	var presses := await _read_all(layer)
	_check(Story.was_seen(QUIT_SCENE) and presses >= Story.resolved_lines(QUIT_SCENE).size() and not get_tree().paused, "the replayed radio reads to the end and thaws")
	print("RADIO_FREEZE_PROBE mode=resume failures=%d" % _failures)
	_main.call("_quit", 1 if _failures > 0 else 0)
