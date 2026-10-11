extends Node
## NE-244：背包新版面（左側清單與詳情、右側立繪）的 Forward+ 截圖與版面檢查。
## 在真實關卡裡打開背包，逐頁拍照，再開補給商店拍一張；每一張都檢查：文字不超出畫面、不被裁切、
## 立繪不壓到任何文字或按鈕。最後開關背包幾次，確認立繪只有一份、關閉後放掉貼圖。只取景與量測，不改遊戲資料。
## 用法：godot --path . res://tools/inventory_layout_capture.tscn -- --out=<絕對路徑資料夾>
##        [--level=pawnshop|warehouse] [--width=1280] [--height=720] [--text-scale=1.0]
## 結束時印出 INVENTORY_LAYOUT issues=N；有問題以非零狀態結束。
const Capture := preload("res://tools/viewport_capture.gd")
const Sweep := preload("res://tools/ui_textscale_sweep.gd")

var _out := ""
var _level_id := "pawnshop"
var _width := 1280
var _height := 720
var _scale := 1.0
var _issues := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--level="):
			_level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
		elif arg.begins_with("--text-scale="):
			_scale = float(arg.trim_prefix("--text-scale="))
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("[inventory_layout_capture] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(2)
		return
	# 先換成獨立設定檔再設視窗：載入設定會套用設定裡的視窗大小，順序反過來會被改回去。
	Settings.use_storage("user://inventory-layout-capture-settings.cfg")
	Settings.set_ui_text_scale(_scale)
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()


func _run() -> void:
	await _frames(2)
	if get_window().size != Vector2i(_width, _height):
		get_window().size = Vector2i(_width, _height)
		await _frames(2)
	print("INVENTORY_LAYOUT window=%s" % get_window().size)
	GameState.story_autosave = false
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	var source := load("res://data/levels/ch1_%s.tres" % _level_id) as LevelData
	if source == null:
		printerr("[inventory_layout_capture] 找不到關卡 ch1_%s" % _level_id)
		get_tree().quit(2)
		return
	var data := source.duplicate(true) as LevelData
	data.intro_scene = &""
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _frames(30)
	Progression.add_credits(1280)
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	await _wait(InventoryScreen.OPEN_TIME + 0.4)
	for tab in inventory._pages.size():
		inventory.select_tab(tab)
		await _wait(InventoryScreen.PAGE_SLIDE_TIME + 0.3)
		await _capture("tab%d" % tab, inventory)
	inventory.close()
	await _wait(0.5)
	# 開關幾次：立繪只能有一份，關閉後不留貼圖。
	for i in 3:
		inventory.open()
		await _frames(3)
		inventory.close()
		await _wait(0.3)
	var portraits := inventory.find_children("*", "SidePortrait", true, false).size()
	if portraits != 1 or inventory._portrait.has_texture():
		_issues.append("開關背包後有 %d 份立繪，關閉後%s貼圖" % [portraits, "仍持有" if inventory._portrait.has_texture() else "沒有"])
	var station := ShopStation.new()
	station.configure(load("res://data/shops/supply.tres"), Vector2i(14, 19))
	station.position = level.player.global_position + Vector2(24, 0)
	level._entities.add_child(station)
	await _frames(4)
	station._open()
	await _wait(InventoryScreen.OPEN_TIME + 0.4)
	await _capture("shop", station._screen)
	print("INVENTORY_LAYOUT issues=%d" % _issues.size())
	for issue in _issues:
		print("INVENTORY_LAYOUT ", issue)
	get_tree().quit(0 if _issues.is_empty() else 1)


func _capture(name: String, screen: InventoryScreen) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-244-%s-%s-%d-%d.png" % [_level_id, name, _width, roundi(_scale * 100.0)])
	var error := Capture.image(get_viewport()).save_png(path)
	print("INVENTORY_LAYOUT saved %s err=%d" % [path, error])
	_audit(name, screen)


func _audit(page: String, screen: InventoryScreen) -> void:
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var portrait: SidePortrait = screen._portrait
	var area := Rect2()
	if portrait.is_visible_in_tree():
		var drawn := portrait.drawn_rect()
		if not drawn.has_area():
			_issues.append("%s：右側欄開著但沒有立繪" % page)
		area = Rect2(portrait.get_global_rect().position + drawn.position, drawn.size).grow(-1)
	for node: Control in screen.find_children("*", "Control", true, false):
		if node == portrait or not node.is_visible_in_tree():
			continue
		var rect := node.get_global_rect()
		if node is Label:
			var label := node as Label
			if label.text.strip_edges().is_empty():
				continue
			var scroll := Sweep._scroll_owner(label)
			if scroll == null and not view.encloses(rect.grow(-0.5)):
				_issues.append("%s：「%s」超出畫面 %s" % [page, label.text.left(16), rect])
			elif label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and label.clip_text:
				var need := label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
				if need > rect.size.x + 1.0:
					_issues.append("%s：「%s」被裁切（需要 %.0f，只有 %.0f）" % [page, label.text.left(16), need, rect.size.x])
		if area.has_area() and (node is Label or node is Button or node is ItemCard) and area.intersects(rect):
			_issues.append("%s：立繪壓到「%s」" % [page, (node as Label).text.left(16) if node is Label else node.name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await _frames(2)
