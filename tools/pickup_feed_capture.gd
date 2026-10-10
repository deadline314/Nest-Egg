extends Node
## NE-228：拾取紀錄與舊的中央「取得」橫幅對照（Forward+）。用真實關卡與道具資料的提示文字，只取景。
## 用法：godot --path . res://tools/pickup_feed_capture.tscn -- --out=<絕對路徑資料夾>
const Capture := preload("res://tools/viewport_capture.gd")

var _out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("[pickup_feed_capture] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
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
	level.camera.snap_to_target()
	var medkit := load("res://data/consumables/med_injector.tres") as ConsumableData
	var name := medkit.display_name if medkit != null else "醫療針"
	var texts := ["取得 %s（1/3）" % name, "取得 %s（2/3）" % name, "取得 P-9 手槍"]
	# 修前：中央橫幅一次只顯示一句，後一句蓋掉前一句。
	level.hud.toast_banner.show_text(texts[-1], UiBanner.Kind.ITEM, Hud.TOAST_TIME)
	await _frames(3)
	await _capture("before-banner")
	level.hud.toast_banner.hide()
	for text in texts:
		EventBus.toast_requested.emit(text)
		await _frames(1)
	await _frames(2)
	await _capture("after-feed")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-228-pickup-%s.png" % name)
	print("PICKUP_FEED_CAPTURE ", path, " err=", Capture.image(get_viewport()).save_png(path))
