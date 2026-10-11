extends Node
## NE-264：主角站在畫面左右邊緣附近、面向左右時，彈帶與生命護盾標籤的位置（Forward+）。只取景，不改遊戲資料。
## 用法：godot --path . res://tools/hud_edge_capture.tscn -- --out=<絕對路徑資料夾> [--size=1280x720] [--legacy-note=標籤]
## 每張圖輸出時也印出彈帶與標籤在畫面上的範圍，超出畫面會標出來；最後在街道中段往右跑，記錄一般跑動時的站位。
const Capture := preload("res://tools/viewport_capture.gd")

var _out := ""
var _size := Vector2i(1280, 720)
var _tag := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			var dims := arg.trim_prefix("--size=").split("x")
			if dims.size() == 2:
				_size = Vector2i(int(dims[0]), int(dims[1]))
		elif arg.begins_with("--legacy-note="):
			_tag = arg.trim_prefix("--legacy-note=")
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("[hud_edge_capture] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(1)
		return
	get_window().size = _size
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()


func _run() -> void:
	GameState.story_autosave = false
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	var data := (load("res://data/levels/ch1_street.tres") as LevelData).duplicate(true) as LevelData
	data.intro_scene = &""
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _frames(30)
	AimInput.using_gamepad = true
	var width := float(level._layout.width * data.tile_size)
	# 左緣面向右（背後沒空間）→ 左緣面向左 → 右緣面向左（背後沒空間）→ 右緣面向右。
	for shot: Array in [["left-facing-right", 24.0, &"aim_right"], ["left-facing-left", 24.0, &"aim_left"], ["right-facing-left", width - 24.0, &"aim_left"], ["right-facing-right", width - 24.0, &"aim_right"]]:
		level.player.global_position.x = shot[1]
		level.player.velocity = Vector2.ZERO
		Input.action_press(shot[2])
		await _frames(50)
		level.camera.snap_to_target()
		await _frames(20)
		await _capture(str(shot[0]), level)
		Input.action_release(shot[2])
	# 跑步中的實際站位：在街道中段持續往右跑，記錄主角錨點與彈帶、標籤在畫面上的位置。
	level.player.global_position.x = width * 0.4
	Input.action_press(&"aim_right")
	Input.action_press(&"move_right")
	for i in 6:
		await _frames(30)
		var tray := level.hud.ammo_tray
		var anchor: Vector2 = level.get_viewport().get_canvas_transform() * (level.player.global_position + Vector2(0, -34))
		print("HUD_RUN t=%d anchor_x=%.0f above=%.2f tray_pos=%.0f tag_x=%.0f tag_w=%.0f" % [i, anchor.x, tray._above, tray._pos.x, level.hud.vitals_tag._pos.x, level.hud.vitals_tag._content_width() + VitalsTag.PAD * 2.0])
	await _capture("running-right", level)
	Input.action_release(&"move_right")
	Input.action_release(&"aim_right")
	get_tree().quit(0)


func _capture(name: String, level: Level) -> void:
	await RenderingServer.frame_post_draw
	var label := "%dx%d" % [_size.x, _size.y]
	var path := _out.path_join("NE-264-%s-%s%s.png" % [name, label, ("-" + _tag) if not _tag.is_empty() else ""])
	var tray := level.hud.ammo_tray
	var view := tray.get_viewport_rect().size.x
	var left := INF
	var right := -INF
	for i in tray.icon_count():
		var rect := tray._icon_draw_rect(i, tray.icon_count(), 1.0)
		left = minf(left, rect.position.x)
		right = maxf(right, rect.end.x)
	var tag := level.hud.vitals_tag
	print("HUD_EDGE %s tray=[%.0f, %.0f] tag_x=%.0f view=%.0f inside=%s saved=%s err=%s" % [name, left, right, tag._pos.x, view, left >= 0.0 and right <= view, path, Capture.image(get_viewport()).save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
