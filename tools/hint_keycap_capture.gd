extends Node
## BG-22／ST-16：教學看板的按鍵帽截圖。每個看板各拍兩張：先用鍵盤（按一下真的按鍵），再拿起手把（按一下真的手把按鍵），
## 看板上的按鍵要跟著換；靠地圖邊的看板文字要整段留在畫面內。只移動主角到看板旁，不改劇情與進度。
## 用法：godot --path . res://tools/hint_keycap_capture.tscn -- --out=<絕對路徑資料夾>

## 關卡 → 要拍的看板欄（格）。
const SHOTS := {
	"res://data/levels/ch1_pawnshop.tres": [28, 46],
	"res://data/levels/ch1_rooftop.tres": [24],
	"res://data/levels/ch1_street.tres": [86, 123],
	# 地圖左邊緣的看板：文字要整段留在畫面內。
	"res://data/levels/ch1_booth_alley.tres": [22],
}

var _out := ""
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _out.is_empty():
		push_error("[HintKeycapCapture] 需要 --out=<資料夾>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _device(gamepad: bool) -> void:
	var event: InputEvent
	if gamepad:
		var button := InputEventJoypadButton.new()
		button.device = 0
		button.button_index = JOY_BUTTON_GUIDE
		button.pressed = true
		event = button
	else:
		var key := InputEventKey.new()
		key.keycode = KEY_SHIFT
		key.physical_keycode = KEY_SHIFT
		key.pressed = true
		event = key
	Input.parse_input_event(event)
	await _frames(3)
	if InputBindings.using_gamepad != gamepad:
		_failures += 1
		print("FAIL the %s press did not switch the prompts" % ("gamepad" if gamepad else "keyboard"))


func _run() -> void:
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	for path: String in SHOTS:
		var level := Level.new()
		level.configure(load(path) as LevelData)
		add_child(level)
		await _frames(60)
		print("entered %s" % path.get_file())
		for i in 600:
			if not Story.is_cinematic_active() and not GameplayLock.is_locked():
				break
			Story.skip_cinematic()
			await _frames(4)
		for column: int in SHOTS[path]:
			var signs := level.find_children("*", "HintSign", true, false).filter(func(node: Node) -> bool:
				return absf((node as Node2D).global_position.x - (column + 0.5) * 16.0) <= 12.0)
			if signs.is_empty():
				_failures += 1
				print("FAIL no hint sign at column %d in %s" % [column, path.get_file()])
				continue
			var sign := signs[0] as HintSign
			level.player.global_position = sign.global_position + Vector2(-20, 0)
			level.player.velocity = Vector2.ZERO
			await _frames(45)
			for gamepad in [false, true]:
				await _device(gamepad)
				await _frames(30)
				var name := "BG-22-%s-%d-%s" % [path.get_file().get_basename().trim_prefix("ch1_"), column, "pad" if gamepad else "keys"]
				if DisplayServer.get_name() == "headless":
					print("reached %s text=%s" % [name, sign.text])
					continue
				var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
				print("saved %s (%s) text=%s" % [name, error_string(image.save_png(_out.path_join(name + ".png"))), sign.text])
		level.queue_free()
		await _frames(10)
	print("HINT_KEYCAP_CAPTURE failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
