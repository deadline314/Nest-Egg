extends RefCounted
## NE-228：確認、返回、分頁與取消在各主要畫面一致。
## - 主選單與暫停頁的每個子頁：用手把 A 打開、B 返回，焦點回到打開它的那顆按鈕。
## - 有分頁的畫面（設定、背包、補給商店、任務與地圖）都能用 LB／RB 換頁。
## - 模態頁面開著時，跳躍與射擊不會穿透到主角。
## 送的是合成的手把事件，不代替實體手把驗收（NE-229）。


static func run(suite: TestSuite) -> void:
	# 合成的手把事件會把輸入裝置切成手把；結束時還原，後面的套件才不會沿用手把的按鍵圖示與版面。
	var was_gamepad := InputBindings.using_gamepad
	var device := InputBindings.active_device
	await _check_main_menu(suite)
	await _check_pause_pages(suite)
	await _check_modal_passthrough(suite)
	await _check_entry_hint(suite)
	InputBindings._set_device(was_gamepad, device)
	await suite.frames(1)


static func _check_main_menu(suite: TestSuite) -> void:
	var menu := MainMenu.new()
	suite.runner.add_child(menu)
	await suite.frames(4)
	for label: String in ["設定", "敗北圖鑑"]:
		var button := _button_with_text(menu, label)
		if button == null:
			suite.check(false, "主選單有「%s」按鈕" % label)
			continue
		button.grab_focus()
		await suite.frames(1)
		await _joy(suite, JOY_BUTTON_A)
		await suite.frames(3)
		suite.check(not menu._main_page.visible, "主選單按 A 打開「%s」" % label)
		if label == "設定":
			await _check_tabs(suite, menu, "主選單的設定頁")
		await _joy(suite, JOY_BUTTON_B)
		await suite.frames(4)
		var focus := suite.runner.get_viewport().gui_get_focus_owner()
		suite.check(menu._main_page.visible and focus == button, "主選單從「%s」按 B 返回，焦點回到原按鈕" % label)
	menu.queue_free()
	await suite.frames(2)


static func _check_pause_pages(suite: TestSuite) -> void:
	var level := await suite.start_level(PropsSuite.level_data())
	var pause: PauseMenu = level._pause_menu
	pause.open()
	await suite.frames(3)
	for button: Button in [pause._quest_button, pause._map_button, _button_with_text(pause._root, "設定")]:
		if button == null:
			suite.check(false, "暫停頁有設定按鈕")
			continue
		var label := button.text
		button.grab_focus()
		await suite.frames(1)
		await _joy(suite, JOY_BUTTON_A)
		await suite.frames(4)
		var focus := suite.runner.get_viewport().gui_get_focus_owner()
		suite.check(focus != null and not pause._root.get_children().any(func(child: Node) -> bool: return child is Control and child.visible and child.is_ancestor_of(button)), "暫停頁按 A 打開「%s」，焦點移到新頁面" % label)
		if label != "設定":
			await _check_tabs(suite, pause, "暫停頁的「%s」" % label)
		else:
			await _check_tabs(suite, pause, "暫停頁的設定頁")
		# 地圖頁換過分頁後要按兩次 B 才回到暫停頁（返回會先回上一層）；最多按四次。
		for i in 4:
			await _joy(suite, JOY_BUTTON_B)
			await suite.frames(4)
			if button.is_visible_in_tree():
				break
		focus = suite.runner.get_viewport().gui_get_focus_owner()
		suite.check(button.is_visible_in_tree() and focus == button, "從「%s」按 B 一層層返回暫停頁，焦點回到原按鈕" % label)
	await _joy(suite, JOY_BUTTON_B)
	await suite.frames(3)
	suite.check(not pause._root.visible and not suite.runner.get_tree().paused, "暫停頁按 B 回到遊戲")
	await suite.end_level(level)


## 畫面有分頁時，LB／RB 都會換頁（看焦點或可見內容有沒有改變）。
static func _check_tabs(suite: TestSuite, root: Node, what: String) -> void:
	var before := _visible_signature(root)
	await _joy(suite, JOY_BUTTON_RIGHT_SHOULDER)
	await suite.frames(4)
	var after := _visible_signature(root)
	suite.check(before != after, "%s：RB 換到下一頁" % what)
	await _joy(suite, JOY_BUTTON_LEFT_SHOULDER)
	await suite.frames(4)
	suite.check(_visible_signature(root) == before, "%s：LB 回到原本的頁" % what)


static func _check_modal_passthrough(suite: TestSuite) -> void:
	var level := await suite.start_level(PropsSuite.level_data())
	var player := level.player
	await suite.frames(20)
	for opener: Array in [["暫停頁", func() -> void: level._pause_menu.open()], ["背包", func() -> void: level._inventory.open()], ["任務與地圖", func() -> void:
			level._pause_menu.open()
			level._pause_menu._open_navigation("quests")]]:
		opener[1].call()
		await suite.frames(4)
		var y := player.global_position.y
		var ammo := player.loadout.mag_in(player.loadout.active_slot)
		for action: StringName in [&"jump", &"shoot"]:
			Input.action_press(action)
			await suite.frames(6)
			Input.action_release(action)
		await suite.frames(4)
		var now_ammo := player.loadout.mag_in(player.loadout.active_slot)
		suite.check(is_equal_approx(player.global_position.y, y) and now_ammo == ammo, "%s開著時跳躍與射擊不會穿透到主角" % opener[0])
		# 一層層按 B 關掉，回到遊戲。
		for i in 4:
			if not suite.runner.get_tree().paused and not level._inventory.is_open():
				break
			await _joy(suite, JOY_BUTTON_B)
			await suite.frames(4)
		suite.check(not suite.runner.get_tree().paused and not level._inventory.is_open(), "%s用 B 一路返回遊戲" % opener[0])
	await suite.end_level(level)


## 入區不重播整份按鍵表：新遊戲第一次進關卡時才有開場操作提示，從出入口進到下一區時不再出現。
static func _check_entry_hint(suite: TestSuite) -> void:
	var data := (load("res://data/levels/ch1_street.tres") as LevelData).duplicate(true) as LevelData
	data.intro_scene = &""
	var fresh := await suite.start_level(data)
	await suite.frames(6)
	suite.check(not fresh.hud._hint_expired, "新遊戲第一次進關卡時保留開場操作提示")
	await suite.end_level(fresh)
	GameState.pending_portal = &"street_home"
	var entered := await suite.spawn_level(data)
	await suite.frames(6)
	suite.check(entered.hud._hint_expired and not entered.hud._controls_card.visible, "從出入口進到區域時不重播開場操作提示")
	await suite.end_level(entered)


static func _visible_signature(root: Node) -> String:
	var parts := PackedStringArray()
	for control: Control in root.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and (control is Label or control is Button) and control.get_global_rect().size.x > 0:
			parts.append((control as Variant).text if (control is Label or control is Button) else "")
	return "|".join(parts)


static func _button_with_text(root: Node, text: String) -> Button:
	for button: Button in root.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


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
