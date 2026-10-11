extends Node
## 真實關卡的 Forward+ 截圖。--fixtures 僅供 UI 驗證，所有樣本畫面加上標示。

var _out := ""
var _fixtures := false
var _only_page := ""
var _width := 1280
var _height := 720
var _level_id := "pawnshop"
var _text_scale := 1.0
var _watermark: Label
var _layout_issues := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only-page="):
			_only_page = arg.trim_prefix("--only-page=")
		elif arg == "--fixtures":
			_fixtures = true
		elif arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
		elif arg.begins_with("--text-scale="):
			_text_scale = float(arg.trim_prefix("--text-scale="))
		elif arg.begins_with("--level="):
			_level_id = arg.trim_prefix("--level=")
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.use_storage("user://ne223-probe-settings.cfg")
	Settings.set_ui_text_scale(_text_scale)
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[0])
	add_child(LightKit.create_environment())
	var level := Level.new()
	level.configure(load("res://data/levels/ch1_%s.tres" % _level_id) as LevelData)
	add_child(level)
	for i in 20:
		await get_tree().process_frame
	if _level_id == "pawnshop":
		level.player.global_position = Vector2(60.5 * 16, 320)
		level.camera.snap_to_target()
		level._lighting.snap()
		level.camera.force_update_scroll()
		await get_tree().physics_frame
	get_tree().paused = true
	var guidance := level.hud.quest_guidance
	if _fixtures:
		guidance.catalog = QuestMapSuite.fixture_catalog()
		GameState.world_flags["nav_test_done"] = true
		guidance._refresh_target()
		var watermark_layer := CanvasLayer.new()
		watermark_layer.layer = UiLayers.PAUSE + 1
		add_child(watermark_layer)
		var watermark := UiKit.label("介面驗證樣本；非正式主線", UiKit.FS_BODY, Palette.NEON_YELLOW)
		_watermark = watermark
		watermark.position = Vector2(184, 32)
		watermark_layer.add_child(watermark)
	# 探索樣本只用真實幾何的可見格子，不用手繪地圖。
	var layout: LevelLayout = guidance.maps.areas[level.data.resource_path]["layout"]
	for x in range(0, layout.width / 2, 4):
		var y := layout.floor_below(x, 4)
		if is_finite(y):
			guidance.state.reveal(level.data.resource_path, guidance.maps.visible_cells(level.data.resource_path, Vector2((x + 0.5) * 16, y - 8), WorldState.capture(get_tree())))
	guidance._update_arrow()
	guidance._row.visible = _fixtures
	await _capture("hud")
	if not _fixtures:
		level._pause_menu.open()
		await _capture("pause")
		level._pause_menu.close()
		get_tree().paused = true
	if is_instance_valid(_watermark):
		# 導覽頁的頁首與細節都在上方，樣本標示改放右下角提示列上方。
		_watermark.position = Vector2(470, 322)
	var layer := CanvasLayer.new()
	layer.layer = UiLayers.PAUSE
	add_child(layer)
	var root := UiKit.full_rect_root(layer)
	var screen := QuestMapScreen.new()
	screen.catalog = guidance.catalog
	screen.maps = guidance.maps
	screen.state = guidance.state
	screen.chapter = String(level.data.chapter)
	screen.player_path = level.data.resource_path
	screen.player_position = level.player.global_position
	screen.world = WorldState.capture(get_tree())
	root.add_child(screen)
	for page in ["quests", "region", "world"]:
		screen.show_page(page, false)
		if page == "quests" and _fixtures:
			for filter in ["all", "main", "side", "completed"]:
				if filter == "completed":
					screen._kind = "all"
				screen._filter(filter)
				if _fixtures:
					screen._title.text += "（驗證樣本）"
				await _capture("quests_" + filter)
				_check_layout(screen)
				screen._completed = false
		else:
			if _fixtures:
				screen._title.text += "（驗證樣本）"
			await _capture(page)
		_check_layout(screen)
	var report := {"resolution": [_width, _height], "level": _level_id, "fixture_tasks": _fixtures, "layout_issues": Array(_layout_issues), "story_quest_count": guidance.catalog.quests.size(), "renderer": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(_out.path_join("layout-%s-%d-%s.json" % [_level_id, _width, "fixture" if _fixtures else "source"]), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("NE-223 PROBE: ", report)
	get_tree().paused = false
	get_tree().quit(0 if _layout_issues.is_empty() else 1)


func _capture(page: String) -> void:
	if not _only_page.is_empty() and page != _only_page and not (_only_page == "maps" and page in ["region", "world"]):
		return
	for i in 16:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-223-%s-%s-%d%s.png" % [_level_id, page, _width, "-fixture" if _fixtures else "-source"])
	var error := preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(path)
	print("CAPTURE: %s (%s)" % [path, error_string(error)])
	if error != OK:
		_layout_issues.append("無法儲存截圖：" + path)


func _check_layout(screen: QuestMapScreen) -> void:
	var rect := screen.get_global_rect()
	for child: Control in screen.find_children("*", "Control", true, false):
		if not child.is_visible_in_tree() or child.size.x == 0 or child.size.y == 0:
			continue
		# 捲動區的內容可以超出視窗，會由容器裁切。
		var parent := child.get_parent()
		var clipped := false
		while parent is Control and parent != screen:
			if parent is ScrollContainer or parent.clip_contents:
				clipped = true
				break
			parent = parent.get_parent()
		if not clipped and not rect.grow(1).encloses(child.get_global_rect()):
			_layout_issues.append("%s 超出畫面：%s" % [child.get_class(), child.get_global_rect()])
