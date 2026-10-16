extends RefCounted
## NE-279：走真實 UI 輸入／回看播放器，驗證返回、暫停與唯讀進度。

const OPENING := &"ch1_p01_door"


static func run(s: TestSuite) -> void:
	var progress := GameState.story_progress_snapshot()
	var economy := Progression.snapshot()
	var language := Story.language
	var gamepad := InputBindings.using_gamepad
	var device := InputBindings.active_device
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	var empty := CodexScreen.new()
	s.runner.add_child(empty)
	await s.frames(4)
	empty.select_tab(1)
	await s.frames(2)
	s.check(empty._replay_page.entries.is_empty() and empty._replay_page._play.disabled, "回顧空清單不洩漏未看過故事，也沒有可啟動的按鈕")
	empty.queue_free()
	await s.frames(2)
	Story._completed[OPENING] = true
	Story._completed[&"ch1_c14_home"] = true
	Story._completed[&"ch1_c09_wake"] = true
	for code in ["zh", "ja", "en"]:
		Story.set_language(code)
		var codex := CodexScreen.new()
		s.runner.add_child(codex)
		await s.frames(4)
		codex.select_tab(1)
		await s.frames(2)
		var ids: Array = codex._replay_page.entries.map(func(entry: Dictionary) -> StringName: return entry["id"])
		s.check(ids == [OPENING, &"ch1_c09_wake", &"ch1_c14_home"], "%s 回顧只列已完成過場，依故事順序排列" % code)
		var title := str(Story._scenes[String(OPENING)]["title"])
		s.check(codex._replay_page.buttons[0].text == title and not codex._replay_page.description(codex._replay_page.entries[0]).is_empty(), "%s 回顧名稱沿用劇本，項目附有說明" % code)
		codex.queue_free()
		await s.frames(2)
	Story.set_language(language)
	await _check_menu_and_pause(s)
	await _check_pointer_and_controller(s)
	await _check_natural_end_and_exit(s)
	GameState.restore_story_progress(progress)
	Progression.restore(economy, false)
	InputBindings._set_device(gamepad, device)
	await s.frames(2)


static func _check_menu_and_pause(s: TestSuite) -> void:
	for paused in [false, true]:
		var level: Level = await s.spawn_level(PropsSuite.level_data()) if paused else null
		var menu: Node = level._pause_menu if paused else MainMenu.new()
		if not paused:
			s.runner.add_child(menu)
		await s.frames(4)
		if paused:
			menu.open()
		menu._open_codex()
		await s.frames(4)
		var host: Control = menu._root if paused else menu._ui
		var codex := host.get_child(host.get_child_count() - 1) as CodexScreen
		s.check(codex != null, "主選單／暫停入口都開啟同一份圖鑑（暫停=%s）" % paused)
		await _action(s, &"inventory_next_tab")
		s.check(codex._current_tab == 1 and codex._replay_page.buttons[0].has_focus(), "分頁鍵切入回顧並聚焦第一項")
		await _action(s, &"ui_down")
		var selected: Button = codex._replay_page.buttons[1]
		s.check(selected.has_focus(), "方向鍵可選第二個回顧項目")
		s.check(codex._replay_page.buttons.filter(func(button: Button) -> bool: return button.button_pressed).size() == 1, "回顧同時只有一個選中項目，不留下前一列的高亮")
		var before := GameState.story_progress_snapshot()
		var credits := Progression.snapshot()
		var reading := GameplayLock.acquire(menu, -1, true)
		codex._start_replay(OPENING)
		s.check(not Story.is_replaying() and codex.visible, "重要通訊允許開暫停圖鑑，但閱讀鎖仍在時不啟動另一套演出")
		GameplayLock.release(reading)
		var position := level.player.position if paused else Vector2.ZERO
		var clock := GameState.run_time
		var saves := [0]
		var on_save := func() -> void: saves[0] += 1
		GameState.run_save_requested.connect(on_save)
		await _action(s, &"ui_accept")
		s.check(Story.is_replaying() and not codex.visible and s.runner.get_tree().paused, "確認鍵開始真正回看、藏起圖鑑並凍結世界")
		if paused:
			s.check((menu._root.get_node("FocusHintBar") as FocusHintBar).text().is_empty(), "暫停頁聚焦說明不跨越圖鑑蓋住回看")
		# 真實播放器的取消輸入；不得讓同一事件關掉暫停選單。
		await _action(s, &"ui_cancel")
		await _wait_replay(s)
		await s.frames(3)
		s.check(not Story.is_replaying() and codex.visible and selected.has_focus() and codex._replay_page.selected == 1, "略過後回到原項目、分頁與焦點")
		s.check(s.runner.get_tree().paused == paused, "回看釋放自己的暫停責任，保留原暫停=%s" % paused)
		if paused:
			s.check(level.player.process_mode != Node.PROCESS_MODE_ALWAYS and level.player.position == position and GameState.run_time == clock, "真實關卡回看與返回後玩家位置和遊戲時間保持凍結")
		s.check(GameState.story_progress_snapshot() == before and Progression.snapshot() == credits and saves[0] == 0, "回看不改旗標、觀看紀錄、物品或成長，不請求保存")
		GameState.run_save_requested.disconnect(on_save)
		await _action(s, &"ui_cancel")
		await s.frames(3)
		s.check(not is_instance_valid(codex), "返回鍵離開圖鑑")
		if paused:
			s.check(menu._root.visible and s.runner.get_tree().paused, "離開圖鑑後仍在暫停頁")
			menu.close()
			await s.end_level(level)
		else:
			menu.queue_free()
		await s.frames(3)


static func _check_pointer_and_controller(s: TestSuite) -> void:
	for pointer in [false, true]:
		var codex := CodexScreen.new()
		s.runner.add_child(codex)
		await s.frames(3)
		codex.select_tab(1)
		await s.frames(3)
		if pointer:
			var position := codex._replay_page.buttons[0].get_global_rect().get_center()
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = position
			event.global_position = position
			event.pressed = true
			s.runner.get_viewport().push_input(event, true)
			await s.frames(2)
			event = event.duplicate() as InputEventMouseButton
			event.pressed = false
			s.runner.get_viewport().push_input(event, true)
			await s.frames(2)
		else:
			await _joy(s, JOY_BUTTON_A)
		s.check(Story.is_replaying(), "滑鼠點擊／合成手把 A 可從回顧項目啟動播放（滑鼠=%s）" % pointer)
		await _joy(s, JOY_BUTTON_B)
		await _wait_replay(s)
		await s.frames(3)
		s.check(codex.visible and codex._replay_page.buttons[0].has_focus(), "合成手把 B 略過後回到原回顧項目")
		codex.queue_free()
		await s.frames(3)


static func _joy(s: TestSuite, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	s.runner.get_viewport().push_input(event, true)
	await s.frames(2)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	s.runner.get_viewport().push_input(event, true)
	await s.frames(2)


static func _check_natural_end_and_exit(s: TestSuite) -> void:
	# 最小正式舞台 fixture，驗「自然播完」與非正常移除的回收，不取代正式故事內容驗收。
	var id := &"test_codex_replay_end"
	Story._scenes[String(id)] = {"mode": "animated", "title": "Replay fixture", "gallery_order": 20, "steps": [{"do": "scene", "id": "rainy_harbor", "fade": 0.0}, {"do": "wait", "time": 0.04}]}
	Story._completed[id] = true
	var fixtures: Array[StringName] = [id]
	for i in 12:
		var extra := StringName("test_codex_scroll_%d" % i)
		Story._scenes[String(extra)] = Story._scenes[String(id)].duplicate(true)
		Story._scenes[String(extra)]["gallery_order"] = i
		Story._completed[extra] = true
		fixtures.append(extra)
	var codex := CodexScreen.new()
	s.runner.add_child(codex)
	await s.frames(3)
	codex.select_tab(1)
	await s.frames(2)
	var index: int = codex._replay_page.entries.find_custom(func(entry: Dictionary) -> bool: return entry["id"] == id)
	var button: Button = codex._replay_page.buttons[index]
	button.grab_focus()
	await s.frames(3)
	var scroll: int = codex._replay_page._scroll.scroll_vertical
	s.check(scroll > 0, "長回顧清單聚焦下方項目時會跟著捲動")
	codex._start_replay(id)
	await _wait_replay(s)
	await s.frames(3)
	s.check(codex.visible and not Story.is_replaying() and not GameplayLock.is_locked(), "自然播完回圖鑑並釋放播放鎖")
	s.check(button.has_focus() and codex._replay_page._scroll.scroll_vertical == scroll, "自然播完保留長清單原捲動位置與原項目焦點")
	codex._start_replay(OPENING)
	codex.queue_free()
	await _wait_replay(s)
	s.check(not Story.is_replaying() and not GameplayLock.is_locked(), "圖鑑被外部移除也會停止自己啟動的回看")
	for fixture in fixtures:
		Story._scenes.erase(String(fixture))
		Story._completed.erase(fixture)


static func _wait_replay(s: TestSuite) -> void:
	for i in 360:
		if not Story.is_replaying():
			break
		await s.frames(1)
	# 若過場沒有結束，保留失敗但回收狀態，避免其餘測試掛住。
	if Story.is_replaying():
		s.check(false, "回看必須結束而非無限等待")
		Story.stop_replay()
		await s.frames(4)


static func _action(s: TestSuite, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	s.runner.get_viewport().push_input(event, true)
	await s.frames(2)
	event = event.duplicate() as InputEventAction
	event.pressed = false
	s.runner.get_viewport().push_input(event, true)
	await s.frames(2)
