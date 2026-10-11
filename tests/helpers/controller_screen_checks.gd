extends RefCounted
## NE-229：只用手把按鍵走暫停、死亡、結算與人物交談，並確認聚焦說明不依賴滑鼠 Hover。
## 送的是合成的手把事件（走引擎的焦點與動作對應），不代替實體手把驗收。


static func run(suite: TestSuite) -> void:
	await _check_pause(suite)
	await _check_death(suite)
	await _check_victory(suite)
	await _check_dialogue(suite)
	await _check_shop(suite)
	await _check_codex(suite)


static func _check_pause(suite: TestSuite) -> void:
	var level := await suite.start_level(PropsSuite.level_data())
	var pause: PauseMenu = level._pause_menu
	pause.open()
	await suite.frames(3)
	var bar := pause._root.get_node("FocusHintBar") as FocusHintBar
	suite.check(bar != null and bar.text() == pause._resume_button.tooltip_text, "暫停頁聚焦「繼續」時底部顯示同一句說明")
	await _joy(suite, JOY_BUTTON_DPAD_DOWN)
	suite.check(pause._quest_button.has_focus(), "手把方向鍵往下移到「任務」")
	suite.check(bar.text() == pause._quest_button.tooltip_text and not bar.text().is_empty(), "說明跟著焦點換成「任務」的說明")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(4, 4)
	suite.runner.get_viewport().push_input(motion, true)
	await suite.frames(1)
	suite.check(bar.text().is_empty(), "改用滑鼠時收起底部說明（滑鼠有原生說明）")
	await _joy(suite, JOY_BUTTON_DPAD_UP)
	suite.check(bar.text() == pause._resume_button.tooltip_text, "再用手把移動焦點時說明重新出現")
	pause._open_settings()
	await suite.frames(4)
	var in_settings := suite.runner.get_viewport().gui_get_focus_owner()
	suite.check(in_settings != null and pause._settings.is_ancestor_of(in_settings) and bar.text().is_empty(), "從暫停頁開設定時不重複顯示說明（設定頁有自己的說明列）")
	pause._settings.close()
	await suite.frames(3)
	pause._quest_button.grab_focus()
	await suite.frames(1)
	pause._open_navigation("quests")
	await suite.frames(4)
	var in_journal := suite.runner.get_viewport().gui_get_focus_owner()
	suite.check(is_instance_valid(pause._navigation) and in_journal != null and pause._navigation.is_ancestor_of(in_journal) and bar.text().is_empty(), "從暫停頁開任務頁時不重複顯示說明（任務頁有自己的說明列）")
	await _joy(suite, JOY_BUTTON_B)
	await suite.frames(2)
	suite.check(not is_instance_valid(pause._navigation) and pause._quest_button.has_focus(), "手把 B 從任務頁回到暫停頁並恢復「任務」的焦點")
	pause.close()
	await suite.frames(2)
	suite.check(not bar.is_visible_in_tree(), "關閉暫停頁後說明跟著收起")
	await suite.end_level(level)


static func _check_death(suite: TestSuite) -> void:
	var screen := DeathScreen.new()
	screen.setup({"number": 1, "title": "手把測試", "text": "文字", "hint": "提示", "is_new": false}, true)
	suite.runner.add_child(screen)
	await suite.frames(6)
	var bar := screen.find_child("FocusHintBar", true, false) as FocusHintBar
	var focused := suite.runner.get_viewport().gui_get_focus_owner()
	suite.check(focused is Button and screen.is_ancestor_of(focused), "死亡畫面打開時焦點在按鈕上")
	suite.check(bar != null and not bar.text().is_empty(), "死亡畫面聚焦按鈕時底部顯示說明")
	_check_hint_clear_of_buttons(suite, screen, bar, "100%")
	var retried := [false]
	screen.retry_requested.connect(func() -> void: retried[0] = true)
	await _joy(suite, JOY_BUTTON_A)
	suite.check(retried[0], "手把 A 從死亡畫面重來")
	screen.queue_free()
	await suite.frames(2)
	# 文字放大時卡片變高，說明仍在按鈕下方自己的一列，不蓋到「回主選單」。
	var old_scale := Settings.get_ui_text_scale()
	Settings.set_ui_text_scale(1.2)
	var large := DeathScreen.new()
	# 用真實的敗北圖鑑卡（有說明與攻略兩段），卡片高度和玩家看到的一樣。
	var card := DefeatCodex.unlock(&"grunt_shot")
	card["is_new"] = true
	large.setup(card, true)
	suite.runner.add_child(large)
	await suite.frames(6)
	_check_hint_clear_of_buttons(suite, large, large.find_child("FocusHintBar", true, false) as FocusHintBar, "120%")
	large.queue_free()
	Settings.set_ui_text_scale(old_scale)
	await suite.frames(2)


static func _check_hint_clear_of_buttons(suite: TestSuite, screen: Node, bar: FocusHintBar, label: String) -> void:
	if bar == null or not bar.is_visible_in_tree():
		suite.check(false, "死亡畫面（%s）有顯示按鈕說明" % label)
		return
	var hint := bar.get_global_rect()
	var clear := true
	for button: Button in screen.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.get_global_rect().grow(-1).intersects(hint):
			clear = false
	suite.check(clear, "死亡畫面（%s）的按鈕說明不蓋到任何按鈕" % label)


static func _check_victory(suite: TestSuite) -> void:
	var screen := VictoryScreen.new()
	screen.chapter = &"chapter_01"
	suite.runner.add_child(screen)
	await suite.frames(3)
	await _joy(suite, JOY_BUTTON_A)
	for i in 120:
		await suite.runner.get_tree().physics_frame
		if not screen._buttons[0].disabled:
			break
	await suite.frames(2)
	suite.check(screen._buttons[0].has_focus(), "手把 A 略過結算逐項顯示，焦點落在「再玩一次」")
	var bar := screen.find_child("FocusHintBar", true, false) as FocusHintBar
	suite.check(bar != null and bar.text() == screen._buttons[0].tooltip_text, "結算畫面聚焦按鈕時在按鈕旁顯示說明")
	await _joy(suite, JOY_BUTTON_DPAD_RIGHT)
	suite.check(screen._buttons[1].has_focus() and bar.text() == screen._buttons[1].tooltip_text, "方向鍵移到「回主選單」並換說明")
	var to_menu := [false]
	screen.menu_requested.connect(func() -> void: to_menu[0] = true)
	await _joy(suite, JOY_BUTTON_A)
	suite.check(to_menu[0], "手把 A 從結算回主選單")
	screen.queue_free()
	await suite.frames(2)


static func _check_dialogue(suite: TestSuite) -> void:
	var level := await suite.start_level(PropsSuite.level_data())
	var auto_skip := Story.auto_skip
	Story.auto_skip = false
	Story._scenes["ne229_pad_dialogue"] = {"mode": "dialogue", "lines": [
		{"speaker": "mei", "text": "第一句要先完整顯示，再換下一句。"},
		{"speaker": "mei", "text": "第二句。"},
		{"speaker": "mei", "text": "第三句不用看完，可以跳過。"}]}
	suite.check(Story.play(&"ne229_pad_dialogue", false), "可以播放人物交談")
	await suite.frames(2)
	var layer: DialogueLayer = Story._layer
	suite.check(layer.is_cinematic_active(), "人物交談開始")
	await _joy(suite, JOY_BUTTON_A)
	suite.check(layer._cinematic_index == 0 and layer._text.visible_ratio >= 1.0, "第一次按 A 先顯示整句，不跳句")
	await _joy(suite, JOY_BUTTON_A)
	suite.check(layer._cinematic_index == 1, "再按 A 換下一句")
	await _joy(suite, JOY_BUTTON_B)
	suite.check(not layer.is_cinematic_active(), "手把 B 跳過交談")
	Story._scenes.erase("ne229_pad_dialogue")
	Story.auto_skip = auto_skip
	await suite.end_level(level)


## 補給商店：手把 A 購買（扣款、背包數量增加），B 關閉。
static func _check_shop(suite: TestSuite) -> void:
	var level := await suite.start_level(PropsSuite.level_data())
	Progression.add_credits(500)
	var station := ShopStation.new()
	station.configure(load("res://data/shops/supply.tres"), Vector2i(14, 19))
	station.position = level.player.global_position + Vector2(24, 0)
	level._entities.add_child(station)
	await suite.frames(3)
	station._open()
	await suite.frames(6)
	var screen := station._screen
	suite.check(is_instance_valid(screen) and screen.is_open(), "補給商店打開")
	var shop: ShopData = load("res://data/shops/supply.tres")
	var item: ConsumableData = shop.stock[0]
	var before_credits := Progression.credits
	var before_count := level.player.consumables.count(item.id)
	await _joy(suite, JOY_BUTTON_A)
	suite.check(Progression.credits == before_credits - item.price and level.player.consumables.count(item.id) == before_count + 1, "手把 A 在補給商店買下選中的商品")
	await _joy(suite, JOY_BUTTON_B)
	await suite.frames(6)
	suite.check(not screen.is_open(), "手把 B 關閉補給商店")
	await suite.end_level(level)


## 圖鑑：手把方向鍵移動焦點，B 關閉。
static func _check_codex(suite: TestSuite) -> void:
	var codex := CodexScreen.new()
	var closed := [false]
	codex.closed.connect(func() -> void: closed[0] = true)
	suite.runner.add_child(codex)
	await suite.frames(4)
	var first := suite.runner.get_viewport().gui_get_focus_owner()
	suite.check(first != null and codex.is_ancestor_of(first), "圖鑑打開時焦點在圖鑑裡")
	await _joy(suite, JOY_BUTTON_DPAD_DOWN)
	var moved := suite.runner.get_viewport().gui_get_focus_owner()
	suite.check(moved != null and codex.is_ancestor_of(moved), "手把方向鍵在圖鑑裡移動焦點")
	await _joy(suite, JOY_BUTTON_B)
	await suite.frames(2)
	suite.check(closed[0], "手把 B 關閉圖鑑")
	if is_instance_valid(codex):
		codex.queue_free()
	await suite.frames(2)


static func _joy(suite: TestSuite, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	suite.runner.get_viewport().push_input(event)
	await suite.frames(2)
	event = event.duplicate()
	event.pressed = false
	suite.runner.get_viewport().push_input(event)
	await suite.frames(1)
