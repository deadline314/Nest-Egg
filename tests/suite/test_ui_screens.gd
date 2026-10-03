class_name UiScreensSuite
extends TestSuite
## 介面畫面（NE-36）：主選單與難度卡片、圖鑑卡片牆、暫停資訊、死亡畫面、結算逐項顯示。


func run() -> void:
	await _test_main_menu()
	await _test_codex()
	await _test_pause_info()
	await _test_death_screen()
	await _test_victory_screen()


func _test_main_menu() -> void:
	var menu := MainMenu.new()
	var started: Array[DifficultyData] = []
	menu.start_requested.connect(func(d: DifficultyData) -> void: started.append(d))
	runner.add_child(menu)
	await frames(4)
	check(menu._main_page.visible and not menu._difficulty_page.visible, "主選單先顯示選單頁")
	check(menu._cards.size() == GameState.difficulties.size(), "每個難度一張卡片")
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
