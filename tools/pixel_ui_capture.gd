extends Node
## 真實介面驗證。任務樣本僅作視覺驗證，與正式主線畫面分別保存。

var _out := ""
var _width := 1280
var _height := 720
var _text_scale := 1.0
var _brightness := 0.5
var _reduce := false
var _issues: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--width="): _width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="): _height = int(arg.trim_prefix("--height="))
		elif arg.begins_with("--text-scale="): _text_scale = float(arg.trim_prefix("--text-scale="))
		elif arg.begins_with("--brightness="): _brightness = float(arg.trim_prefix("--brightness="))
		elif arg == "--reduce-motion": _reduce = true
	if _out.is_empty():
		push_error("pixel_ui_capture: --out=<absolute directory> is required")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.use_storage("user://ne227-probe.cfg")
	Settings.erase_section(Settings.DISPLAY_SECTION)
	Settings.set_ui_font("smooth")
	Settings.set_ui_text_scale(_text_scale)
	Settings.set_reduce_ui_motion(_reduce)
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Settings.set_brightness(_brightness)
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	await _settle(3)
	var menu := MainMenu.new()
	add_child(menu)
	await _capture("menu", menu._main_page)
	menu._open_difficulty()
	await _capture("difficulty", menu._difficulty_page)
	menu.queue_free()
	await _settle(3)
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load("res://data/levels/ch1_pawnshop.tres") as LevelData)
	add_child(level)
	await _settle(30)
	level.player.consumables.add(ConsumableBag.find(&"med_injector"))
	StoryItems.acquire(&"ch1_data_disk", false)
	var inventory := level._inventory
	inventory.open()
	inventory.select_tab(inventory.page_index(ConsumablesPage))
	await _capture("inventory", inventory._frame)
	inventory.close()
	await _settle(16)
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.layer = UiLayers.PAUSE
	add_child(layer)
	var root := UiKit.full_rect_root(layer)
	var screen := QuestMapScreen.new()
	var guidance := level.hud.quest_guidance
	screen.catalog = guidance.catalog
	screen.maps = guidance.maps
	screen.state = guidance.state
	screen.chapter = String(level.data.chapter)
	screen.player_path = level.data.resource_path
	screen.player_position = level.player.global_position
	screen.world = WorldState.capture(get_tree())
	root.add_child(screen)
	await _capture("quests-source", screen)
	screen.catalog = QuestMapSuite.fixture_catalog()
	screen._build()
	screen._title.text = "任務目錄（介面驗證樣本）"
	await _capture("quests-fixture", screen)
	screen.queue_free()
	await _settle(3)
	var settings := SettingsScreen.new()
	root.add_child(settings)
	await _settle(3)
	settings._tabs.current_tab = 2
	await _capture("settings", settings)
	var report := {
		"resolution": [_width, _height], "text_scale": Settings.get_ui_text_scale(),
		"brightness": Settings.get_brightness(),
		"reduced_motion": _reduce, "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "layout_issues": _issues,
		"formal_story_quest_count": guidance.catalog.quests.size(), "fixture_is_formal_story": false,
	}
	var file := FileAccess.open(_out.path_join("NE-227-layout-%d.json" % _width), FileAccess.WRITE)
	if file == null:
		push_error("pixel_ui_capture: cannot save layout report")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	print("NE-227 PROBE: ", report)
	get_tree().paused = false
	get_tree().quit(0 if _issues.is_empty() else 1)


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _capture(name: String, screen: Control) -> void:
	await _settle(12)
	await get_tree().create_timer(0.9, true, false, true).timeout
	await _settle(4)
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-227-%s-%d.png" % [name, _width])
	var err := preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(path)
	if err != OK: _issues.append("Cannot save " + path)
	_check_layout(screen, name)
	print("CAPTURE: ", path)


func _check_layout(screen: Control, name: String) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(1)
	for child: Control in screen.find_children("*", "Control", true, false):
		if not child.is_visible_in_tree() or child.size.x == 0 or child.size.y == 0: continue
		if child is UiCard:
			for label: Label in child.find_children("*", "Label", true, false):
				if label.is_visible_in_tree() and not child.get_global_rect().grow(-3).encloses(label.get_global_rect()):
					_issues.append("%s: card clips %s" % [name, label.text])
		var parent := child.get_parent()
		var clipped := false
		while parent is Control and parent != screen:
			if parent is ScrollContainer or parent.clip_contents:
				clipped = true
				break
			parent = parent.get_parent()
		if not clipped and not viewport_rect.encloses(child.get_global_rect()):
			_issues.append("%s: %s outside viewport %s" % [name, child.get_class(), child.get_global_rect()])
