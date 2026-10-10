extends Node
## NE-228：背景 HUD 說明與暫停頁、人物交談、通訊的重疊截圖（Forward+）。
## 用真的滑鼠移動事件讓引擎排程並顯示 HUD 說明，再打開真的暫停頁／交談／通訊後截圖。
## `--legacy` 先移除守門，重現修正前的畫面；只供取景，不改任何遊戲資料。
## 用法：godot --path . res://tools/hud_hover_modal_capture.tscn -- --out=<絕對路徑資料夾> [--legacy] [--width=1280 --height=720]
const Capture := preload("res://tools/viewport_capture.gd")

var _out := ""
var _legacy := false
var _size := Vector2i(1280, 720)
var _level: Level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--legacy":
			_legacy = true
		elif arg.begins_with("--width="):
			_size.x = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_size.y = int(arg.trim_prefix("--height="))
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("[hud_hover_modal_capture] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(1)
		return
	get_window().size = _size
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()


func _run() -> void:
	print("HUD_HOVER_CAPTURE ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name(), " | legacy=", _legacy)
	GameState.story_autosave = false
	Story.auto_skip = false
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	var data := (load("res://data/levels/ch1_street.tres") as LevelData).duplicate(true) as LevelData
	data.intro_scene = &""
	_level = Level.new()
	_level.configure(data)
	add_child(_level)
	await _frames(20)
	_level.camera.snap_to_target()
	var hud := _level.hud
	if _legacy and hud.hover_guard != null:
		hud.hover_guard.free()
		hud.hover_guard = null
	var target: Control = hud.quest_guidance._row if hud.quest_guidance._row.is_visible_in_tree() else hud.credits_tag
	var spot := target.get_global_rect().get_center()
	var tag := "legacy" if _legacy else "fixed"
	var res := "%dx%d" % [_size.x, _size.y]

	await _hover(spot)
	await _capture("%s-%s-0-gameplay-tooltip" % [res, tag])
	_level._pause_menu.open()
	await _frames(6)
	await _capture("%s-%s-1-pause" % [res, tag])
	_level._pause_menu.close()
	await _frames(4)

	await _hover(spot)
	Story._scenes["ne228_capture_radio"] = {"mode": "radio", "lines": [{"speaker": "mei", "text": "背景說明不能蓋住通訊的講者與正文。"}]}
	Story.play(&"ne228_capture_radio", false)
	await _wait_ms(700)
	await _capture("%s-%s-2-radio" % [res, tag])
	Story._layer.cancel_radio()
	await _frames(4)

	await _hover(spot, false)
	Story._scenes["ne228_capture_dialogue"] = {"mode": "dialogue", "lines": [{"speaker": "mei", "text": "交談開始前排程中的說明，不能在交談時冒出來。"}]}
	Story.play(&"ne228_capture_dialogue", false)
	await _wait_ms(1200)
	await _capture("%s-%s-3-dialogue-pending" % [res, tag])
	Story._layer.finish_cinematic()
	await _frames(4)
	get_tree().quit(0)


## shown=true 等說明真的出現；false 只移入就返回（說明還在排程中）。
func _hover(pos: Vector2, shown := true) -> void:
	_move(Vector2(-40, -40))
	await _frames(2)
	_move(pos)
	if shown:
		await _wait_ms(1000)


func _move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)


func _wait_ms(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-228-hover-%s.png" % name)
	var err := Capture.image(get_viewport()).save_png(path)
	print("HUD_HOVER_CAPTURE saved ", path, " err=", err)
