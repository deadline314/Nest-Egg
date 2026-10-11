extends Node
## NE-228：放大文字的版面巡檢（Forward+）。依序拍設定的四個分頁與補給商店，並列出超出畫面或被裁切的文字。
## 文字大小寫到獨立設定檔，不影響玩家設定。只取景與量測，不改遊戲資料。
## 用法：godot --path . res://tools/ui_textscale_sweep.tscn -- --out=<絕對路徑資料夾> [--text-scale=1.2]
const Capture := preload("res://tools/viewport_capture.gd")

var _out := ""
var _scale := 1.2
var _issues := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--text-scale="):
			_scale = float(arg.trim_prefix("--text-scale="))
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("[ui_textscale_sweep] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	DisplayMode.ensure_scaling(get_window())
	Settings.use_storage("user://ui-textscale-sweep-settings.cfg")
	Settings.set_ui_text_scale(_scale)
	_run.call_deferred()


func _run() -> void:
	GameState.story_autosave = false
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	var settings := SettingsScreen.new()
	add_child(settings)
	await _frames(10)
	for i in settings._tabs.get_tab_count():
		settings._tabs.current_tab = i
		await _frames(8)
		await _capture("settings-%d" % i, settings)
	settings.queue_free()
	await _frames(2)

	GameState.start_new_run(GameState.difficulties[1])
	var data := (load("res://data/levels/ch1_pawnshop.tres") as LevelData).duplicate(true) as LevelData
	data.intro_scene = &""
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _frames(20)
	Progression.add_credits(420)
	var station := ShopStation.new()
	station.configure(load("res://data/shops/supply.tres"), Vector2i(14, 19))
	station.position = level.player.global_position + Vector2(24, 0)
	level._entities.add_child(station)
	await _frames(4)
	station._open()
	# 用實際時間等開啟動畫（淡入與掃描線）跑完：GPU 很快時 30 影格不到動畫長度，會拍到半透明的過渡畫面。
	await get_tree().create_timer(InventoryScreen.OPEN_TIME + 0.4, true, false, true).timeout
	await _frames(2)
	await _capture("shop", station._screen)
	print("UI_TEXTSCALE_SWEEP issues=", _issues.size())
	for issue in _issues:
		print("UI_TEXTSCALE_SWEEP ", issue)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _capture(name: String, root: Node) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-228-sweep-%s-%d.png" % [name, roundi(_scale * 100.0)])
	print("UI_TEXTSCALE_SWEEP saved ", path, " err=", Capture.image(get_viewport()).save_png(path))
	_audit(name, root)


## 可見的 Label 超出畫面，或文字比自己的框寬（沒有自動換行也沒有省略）就記一筆。
## 可捲動清單裡還沒捲到的列不算問題（捲動區本身在畫面內就讀得到）；但清單有更多內容卻沒有捲動提示，記一筆。
func _audit(page: String, root: Node) -> void:
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var scrolled_out := 0
	for label: Label in root.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():
			continue
		var rect := label.get_global_rect()
		var scroll := _scroll_owner(label)
		var bounds := view.intersection(scroll.get_global_rect()) if scroll != null else view
		if scroll != null and view.encloses(scroll.get_global_rect().grow(-0.5)) and not bounds.encloses(rect.grow(-0.5)):
			scrolled_out += 1
		elif not view.encloses(rect.grow(-0.5)):
			_issues.append("%s：「%s」超出畫面 %s" % [page, label.text.left(16), rect])
		elif label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and label.clip_text:
			var need := label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
			if need > rect.size.x + 1.0:
				_issues.append("%s：「%s」被裁切（需要 %.0f，只有 %.0f）" % [page, label.text.left(16), need, rect.size.x])
	for scroll: ScrollContainer in root.find_children("*", "ScrollContainer", true, false):
		var bar := scroll.get_v_scroll_bar()
		if scroll.is_visible_in_tree() and bar.max_value - bar.page > 1.0 and ScrollCue.of(scroll) == null:
			_issues.append("%s：捲動區「%s」還有內容但沒有捲動提示" % [page, scroll.name])
	print("UI_TEXTSCALE_SWEEP %s 捲動區內尚未捲到的文字 %d 筆（不算問題）" % [page, scrolled_out])


static func _scroll_owner(node: Node) -> ScrollContainer:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return parent
		parent = parent.get_parent()
	return null
