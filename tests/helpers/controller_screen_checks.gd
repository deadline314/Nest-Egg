extends RefCounted
## NE-229：只用手把按鍵走暫停、死亡、結算與人物交談，並確認聚焦說明不依賴滑鼠 Hover。
## 送的是合成的手把事件（走引擎的焦點與動作對應），不代替實體手把驗收。


static func run(suite: TestSuite) -> void:
	await _check_pause(suite)
	await _check_death(suite)
	await _check_victory(suite)
	await _check_dialogue(suite)


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
	var retried := [false]
	screen.retry_requested.connect(func() -> void: retried[0] = true)
	await _joy(suite, JOY_BUTTON_A)
	suite.check(retried[0], "手把 A 從死亡畫面重來")
	screen.queue_free()
	await suite.frames(2)


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
	var bar := screen.get_node("FocusHintBar") as FocusHintBar
	suite.check(bar != null and bar.text() == screen._buttons[0].tooltip_text, "結算畫面聚焦按鈕時底部顯示說明")
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
