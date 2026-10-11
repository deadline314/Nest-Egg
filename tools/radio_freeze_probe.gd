extends Node
## NE-246 重要通訊凍結探針：在真的港區街道關卡（有敵人），玩家真的開槍、子彈還在飛時播出重要通訊，
## 檢查同一顆子彈、敵人與遊玩計時在閱讀時不動；中途開關暫停選單仍凍結；確認逐句前進，讀完才解凍。
## 用法：godot --path . res://tools/radio_freeze_probe.tscn -- --out=<絕對路徑資料夾>（無頭也可跑，只是不截圖）

const LEVEL := "res://data/levels/ch1_street.tres"
const SCENE := &"ch1_g06_tip_blade"

var _out := ""
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	print("RADIO_FREEZE_PROBE failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
