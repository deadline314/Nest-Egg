class_name UiScreensSuite
extends TestSuite
## 介面畫面（NE-36）：主選單與難度卡片、圖鑑卡片牆、暫停資訊、死亡畫面、結算逐項顯示。


# GUI input, layout and focus are processed on idle frames, independent of physics.
func frames(count: int) -> void:
	for i in count:
		await runner.get_tree().process_frame


func run() -> void:
	await _test_game_boots_to_menu()
	await _test_main_menu()
	await _test_codex()
	await _test_pause_info()
	await _test_pause_settings_overlay()
	await _test_main_menu_overlays()
	await _test_difficulty_cards_never_overlap()
	await _test_chapter_card_under_pause()
	await _test_fullscreen_setting()
	await _test_death_screen()
	await _test_victory_screen()
	await _test_hd_portrait()


## 進入點啟動後一定要出現主選單（預載或資料出錯曾讓 F5 只剩黑畫面）。
func _test_game_boots_to_menu() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	runner.add_child(main)
	var menu: MainMenu = null
	for i in 240:
		await frames(1)
		for child in main.get_children():
			if child is MainMenu:
				menu = child
		if menu != null:
			break
	check(menu != null, "the entry scene shows the main menu instead of a black screen")
	runner.remove_child(main)
	main.queue_free()
	await frames(2)


func _test_main_menu() -> void:
	var menu := MainMenu.new()
	var started: Array[DifficultyData] = []
	menu.start_requested.connect(func(d: DifficultyData) -> void: started.append(d))
	runner.add_child(menu)
	await frames(4)
	check(menu._main_page.visible and not menu._difficulty_page.visible, "主選單先顯示選單頁")
	check(menu._cards.size() == GameState.difficulties.size(), "每個難度一張卡片")
	check(menu._dev_button != null and menu._dev_button.is_visible_in_tree() and not menu._dev_button.tooltip_text.is_empty(), "除錯版主選單有開發工具按鈕，並有說明")
	menu._dev_button.pressed.emit()
	check(DevMenu.is_open, "按開發工具按鈕開出開發工具選單")
	DevMenu.close()
	menu._open_difficulty()
	await frames(2)
	check(menu._difficulty_page.visible, "開始任務會進入難度選擇")
	var hardcore := GameState.difficulties[GameState.difficulties.size() - 1]
	menu._cards[GameState.difficulties.size() - 1].pressed.emit()
	menu._on_start()
	check(started.size() == 1 and started[0] == hardcore, "選了哪張卡片就以那個難度開始")
	var back_event := InputEventAction.new()
	back_event.action = &"ui_cancel"
	back_event.pressed = true
	menu._unhandled_input(back_event)
	check(menu._main_page.visible, "取消鍵回到選單頁")
	menu.queue_free()
	await frames(2)
	GameState.difficulty = GameState.difficulties[1]


func _test_codex() -> void:
	var codex := CodexScreen.new()
	runner.add_child(codex)
	await frames(3)
	check(codex._first_card != null, "圖鑑有卡片可以聚焦")
	check(codex._detail_title.text != "", "圖鑑一開始就顯示第一張卡片的詳情")
	var cards := DefeatCodex.get_all_cards()
	var locked: Dictionary = {}
	for card in cards:
		if not bool(card["unlocked"]):
			locked = card
			break
	if not locked.is_empty():
		codex._show_detail(locked)
		check(codex._detail_title.text == "？？？", "未解鎖的卡片顯示剪影，不洩漏內容")
	var closed := [false]
	codex.closed.connect(func() -> void: closed[0] = true)
	codex._close()
	check(closed[0], "圖鑑可以關閉")
	await frames(2)


func _test_pause_info() -> void:
	var menu := PauseMenu.new()
	menu.chapter = &"chapter_02"
	runner.add_child(menu)
	GameState.deaths = 4
	menu.open()
	await frames(2)
	check(menu._status_label.text.contains("第二章"), "暫停畫面顯示目前章節")
	check(menu._status_label.text.contains("4"), "暫停畫面顯示回溯次數")
	check(menu._controls_label.text != "", "暫停畫面顯示操作說明")
	menu.close()
	menu.queue_free()
	GameState.deaths = 0
	await frames(2)


## 暫停選單開設定（NE-173）：設定蓋滿畫面、底下的選單隱藏且不能聚焦，關閉後焦點回到「設定」按鈕。
func _test_pause_settings_overlay() -> void:
	var menu := PauseMenu.new()
	runner.add_child(menu)
	menu.open()
	await frames(3)
	var settings_button := menu._menu_panel.body.get_children().filter(
		func(child: Node) -> bool: return child is Button and (child as Button).text == "設定")[0] as Button
	settings_button.grab_focus()
	check(menu.get_viewport().gui_get_focus_owner() == settings_button, "開設定前焦點在原本的設定按鈕")
	menu._open_settings()
	await frames(4)
	var settings := menu._settings
	check(settings.size.is_equal_approx(menu._root.size) and settings.size.x > 0.0, "暫停選單開的設定畫面佔滿整個畫面")
	check(not menu._menu_panel.visible and not menu._info_panel.visible, "設定開著時暫停選單的面板隱藏，不會疊在一起")
	var owner := menu.get_viewport().gui_get_focus_owner()
	check(owner != null and settings.is_ancestor_of(owner), "設定開著時焦點在設定裡")
	for key in [&"ui_down", &"ui_up", &"ui_down"]:
		var event := InputEventAction.new()
		event.action = key
		event.pressed = true
		Input.parse_input_event(event)
		await frames(2)
		var release := event.duplicate() as InputEventAction
		release.pressed = false
		Input.parse_input_event(release)
		await frames(1)
		owner = menu.get_viewport().gui_get_focus_owner()
		check(owner == null or settings.is_ancestor_of(owner), "設定開著時按上下只動設定裡的控制項")
	settings.close()
	# Overlay restoration and deferred focus run on idle frames, not physics ticks.
	await settings.tree_exited
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	check(menu._menu_panel.visible and menu._info_panel.visible, "設定關閉後暫停選單還原")
	check(menu.get_viewport().gui_get_focus_owner() == settings_button, "設定關閉後焦點回到原本的「設定」按鈕")
	menu.close()
	menu.queue_free()
	await frames(2)


## 主選單開設定與圖鑑：同樣佔滿畫面，底下的主選單隱藏，關閉後還原。
func _test_main_menu_overlays() -> void:
	var menu := MainMenu.new()
	runner.add_child(menu)
	await frames(4)
	for opener in [menu._open_settings, menu._open_codex]:
		opener.call()
		await frames(3)
		var screen: Control = menu._ui.get_child(menu._ui.get_child_count() - 1)
		check(screen.size.is_equal_approx(menu._ui.size) and screen.size.x > 0.0, "主選單開的%s佔滿整個畫面" % screen.get_class())
		check(not menu._main_page.visible, "覆蓋畫面開著時主選單頁隱藏")
		screen.queue_free()
		await frames(3)
		check(menu._main_page.visible, "覆蓋畫面關閉後主選單頁還原")
	menu.queue_free()
	await frames(2)


## 難度卡片每次都並排：反覆進出，且從「影格剛開始」的時機進入（容器還沒排版）也不疊在一起。
func _test_difficulty_cards_never_overlap() -> void:
	var menu := MainMenu.new()
	runner.add_child(menu)
	await frames(4)
	for round in 10:
		await runner.get_tree().process_frame
		menu._open_difficulty()
		await runner.get_tree().create_timer(0.8).timeout
		var overlapping := false
		for i in menu._cards.size():
			for j in range(i + 1, menu._cards.size()):
				if menu._cards[i].get_global_rect().intersects(menu._cards[j].get_global_rect()):
					overlapping = true
		check(not overlapping, "第 %d 次進難度頁，三張卡片並排不重疊" % (round + 1))
		menu._on_back()
		await frames(2)
	menu.queue_free()
	await frames(2)


## 章節標題卡低於暫停選單，暫停時藏起來並凍結計時。
func _test_chapter_card_under_pause() -> void:
	check(UiLayers.CHAPTER_CARD < UiLayers.PAUSE and UiLayers.DIALOGUE < UiLayers.PAUSE and UiLayers.INVENTORY < UiLayers.PAUSE,
			"暫停選單疊在章節標題卡、對話、背包之上")
	var card := ChapterCard.new()
	card.title = "測試"
	runner.add_child(card)
	await frames(3)
	check(card._root.visible, "沒暫停時標題卡顯示")
	runner.get_tree().paused = true
	await frames(3)
	check(not card._root.visible, "暫停時開場標題卡不蓋在暫停選單上")
	runner.get_tree().paused = false
	await frames(3)
	check(card._root.visible, "取消暫停後標題卡還原")
	card.queue_free()
	await frames(2)


## 全螢幕（NE-172）：設定存檔與損毀退回、F11 切換、設定畫面勾選框跟著更新、恢復預設回視窗、顯示分頁可捲動。
func _test_fullscreen_setting() -> void:
	var original_path := Settings.storage_path()
	var test_path := "user://test_fullscreen.cfg"
	Settings.use_storage(test_path)
	check(not Settings.get_fullscreen(), "預設是視窗模式")
	Settings.set_value(Settings.DISPLAY_SECTION, "fullscreen", "yes")
	check(not Settings.get_fullscreen(), "設定檔內容損毀時退回視窗模式")

	var screen := SettingsScreen.new()
	runner.add_child(screen)
	await frames(3)
	check(screen._fullscreen != null and not screen._fullscreen.tooltip_text.is_empty(), "顯示分頁有全螢幕選項與說明")
	check(screen._tabs.get_tab_control(2) is ScrollContainer, "顯示分頁項目多時可以捲動")
	var back_bottom := screen.get_global_rect().end.y
	check(screen._tabs.get_global_rect().end.y <= back_bottom, "顯示分頁沒有把底下的按鈕擠出畫面")

	screen._fullscreen.button_pressed = true
	check(Settings.get_fullscreen(), "勾選全螢幕後設定生效")
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	f11.pressed = true
	Settings._input(f11)
	check(not Settings.get_fullscreen() and not screen._fullscreen.button_pressed, "F11 切回視窗，設定畫面的勾選框跟著更新")
	Settings._input(f11)
	check(Settings.get_fullscreen() and screen._fullscreen.button_pressed, "F11 進全螢幕，勾選框跟著更新")
	Settings.save_now()
	Settings.use_storage(test_path)
	check(Settings.get_fullscreen(), "全螢幕設定存檔後重新讀取仍然保留")
	screen._tabs.current_tab = 2
	screen._reset_current_tab()
	check(not Settings.get_fullscreen() and not screen._fullscreen.button_pressed, "恢復預設回到視窗模式")

	var window := runner.get_window()
	DisplayMode.ensure_scaling(window)
	check(window.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and window.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP
			and window.content_scale_size == DisplayMode.DESIGN_SIZE, "畫面以設計解析度等比放大填滿視窗")

	screen.close()
	Settings.use_storage(original_path)
	DirAccess.remove_absolute(test_path)
	await frames(2)


func _test_death_screen() -> void:
	GameState.deaths = 2
	var screen := DeathScreen.new()
	screen.setup({"number": 3, "title": "測試", "text": "文字", "hint": "提示", "is_new": true}, true)
	runner.add_child(screen)
	await frames(6)
	check(is_instance_valid(screen), "死亡畫面建立成功")
	var retried := [false]
	screen.retry_requested.connect(func() -> void: retried[0] = true)
	screen.retry_requested.emit()
	check(retried[0], "死亡畫面可以重來")
	# 缺欄位的卡片不應該出錯。
	var broken := DeathScreen.new()
	broken.setup({}, false)
	runner.add_child(broken)
	await frames(3)
	check(is_instance_valid(broken), "卡片資料缺欄位時仍能顯示")
	screen.queue_free()
	broken.queue_free()
	GameState.deaths = 0
	await frames(2)


func _test_victory_screen() -> void:
	var screen := VictoryScreen.new()
	screen.chapter = &"chapter_01"
	runner.add_child(screen)
	await frames(3)
	check(screen._rows.size() >= 6, "結算畫面有評價項目")
	check(screen._buttons[0].disabled, "逐項顯示期間按鈕先停用")
	var skip := InputEventAction.new()
	skip.action = &"ui_accept"
	skip.pressed = true
	screen._unhandled_input(skip)
	for i in 120:
		await runner.get_tree().physics_frame
		if not screen._buttons[0].disabled:
			break
	check(not screen._buttons[0].disabled, "按確認鍵可略過逐項顯示並啟用按鈕")
	for row in screen._rows:
		check(row.modulate.a > 0.99, "略過後所有項目都已顯示")
		break
	screen.queue_free()
	await frames(2)


## 角色高解析立繪（NE-215）：用骨架在子視窗以 2 倍解析度繪製、平滑濾鏡、只在可見時更新；找不到角色時不崩潰。
func _test_hd_portrait() -> void:
	var portrait := HdPortrait.new()
	portrait.size = Vector2(192, 256)
	runner.get_tree().root.add_child(portrait)
	await frames(4)
	var viewport: SubViewport = null
	for node in portrait.find_children("*", "SubViewport", true, false):
		viewport = node
	check(viewport != null and viewport.size == Vector2i(384, 512), "the portrait renders at twice its display size (%s)" % [viewport.size if viewport != null else "none"])
	check(viewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "the portrait only updates while visible")
	check(viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "the portrait is drawn with smooth filtering, not pixel-scaled")
	var rigs := portrait.find_children("*", "CharacterRig", true, false)
	check(rigs.size() == 1 and (rigs[0] as CharacterRig).is_valid(), "the portrait is the real character rig (the same textures as in the game)")
	portrait.size = Vector2(96, 128)
	await frames(2)
	check(viewport.size == Vector2i(192, 256), "resizing the portrait resizes the render target")
	portrait.scale = Vector2(4, 3)
	await frames(2)
	var screen_scale := (portrait.get_viewport().get_stretch_transform() * portrait.get_global_transform_with_canvas()).get_scale().abs()
	var physical := Vector2i((portrait.size * screen_scale).ceil())
	check(viewport.size.x >= physical.x and viewport.size.y >= physical.y, "the portrait covers actual screen pixels after parent/stretch scaling, without resizing the Control")
	portrait.scale = Vector2.ONE
	await frames(2)
	check(viewport.size == Vector2i(192, 256), "returning to a small display releases the oversized render target")
	var window := runner.get_tree().root
	var old_factor := window.content_scale_factor
	window.content_scale_factor = 3.0
	await frames(2)
	var stretch_scale := window.get_stretch_transform().get_scale().abs()
	var stretched := Vector2i((portrait.size * stretch_scale).ceil())
	check(viewport.size.x >= stretched.x and viewport.size.y >= stretched.y, "window content scaling also preserves native portrait pixels")
	window.content_scale_factor = old_factor
	portrait.queue_free()
	var missing := HdPortrait.new()
	missing.character = "test_no_such_character"
	missing.size = Vector2(96, 128)
	runner.get_tree().root.add_child(missing)
	await frames(3)
	check(is_instance_valid(missing), "a missing character does not crash the page")
	missing.queue_free()
