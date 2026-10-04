class_name DevMenuSuite
extends TestSuite
## F5 開發工具選單（NE-168）：F5 開關、暫停與滑鼠還原、工具清單資料與容錯、切換場景（測試用記錄函式取代）、tooltip。

const FIXTURES := "res://tests/fixtures/dev_menu/"


func run() -> void:
	_test_shipped_tools()
	_test_tool_list_validation()
	await _test_open_close()
	await _test_choose()


func _press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	DevMenu._input(event)


func _test_shipped_tools() -> void:
	var entries := DevMenu.load_entries(DevMenu.TOOLS_PATH)
	check(entries.size() >= 2, "the shipped tool list has the labs (%d)" % entries.size())
	var ids := {}
	for entry in entries:
		check(not ids.has(entry["id"]), "tool id %s is unique" % entry["id"])
		ids[entry["id"]] = true
		check(ResourceLoader.exists(str(entry["scene"])), "tool %s points to a scene that exists: %s" % [entry["id"], entry["scene"]])
		check(not str(entry.get("tip", "")).is_empty(), "tool %s has a tooltip" % entry["id"])
	check(ids.has("sound_lab") and ids.has("feel_lab"), "the sound lab and the feel lab are listed")
	check(ResourceLoader.exists(str(ProjectSettings.get_setting("application/run/main_scene", ""))), "the main scene used by 'back to menu' exists")


func _test_tool_list_validation() -> void:
	check(DevMenu.load_entries("res://tests/fixtures/dev_menu/no_such.json").is_empty(), "a missing tool list gives no entries and no crash (release builds)")
	check(DevMenu.load_entries(FIXTURES + "bad_format.json").is_empty(), "a tool list of the wrong shape is rejected")
	var mixed := DevMenu.load_entries(FIXTURES + "mixed.json")
	check(mixed.size() == 1 and mixed[0]["id"] == "ok_tool", "incomplete and duplicate tools are skipped, the good one is kept (%d)" % mixed.size())


func _test_open_close() -> void:
	var menu := DevMenu
	check(menu.is_available(), "the menu is available in a debug run")
	var paused_before := runner.get_tree().paused
	_press(KEY_F5)
	check(menu.is_open and runner.get_tree().paused, "F5 opens the menu and pauses the game")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse is visible while the menu is open")
	var gaps := PackedStringArray()
	_collect_tooltip_gaps(menu, gaps)
	check(gaps.is_empty(), "every button has a tooltip: %s" % ", ".join(gaps))
	_press(KEY_F5)
	check(not menu.is_open and runner.get_tree().paused == paused_before, "F5 again closes it and restores the pause state")
	_press(KEY_F5)
	_press(KEY_ESCAPE)
	check(not menu.is_open, "Esc closes the menu")
	_press(KEY_ESCAPE)
	check(not menu.is_open, "Esc with the menu closed does nothing")
	runner.get_tree().paused = true
	_press(KEY_F5)
	_press(KEY_F5)
	check(runner.get_tree().paused, "a game that was already paused stays paused after closing")
	runner.get_tree().paused = paused_before
	await frames(1)


func _test_choose() -> void:
	var menu := DevMenu
	var changed: Array[String] = []
	var original: Callable = menu.scene_changer
	menu.scene_changer = func(path: String) -> void: changed.append(path)
	_press(KEY_F5)
	check(menu.choose(menu.entries[0]) and changed == [str(menu.entries[0]["scene"])], "choosing a tool switches to its scene")
	check(not menu.is_open and not runner.get_tree().paused, "choosing a tool closes the menu and unpauses")
	changed.clear()
	_press(KEY_F5)
	check(menu.choose(menu.BACK_TO_MENU_ENTRY) and changed == [str(ProjectSettings.get_setting("application/run/main_scene"))], "back to menu goes to the main scene")
	changed.clear()
	_press(KEY_F5)
	check(not menu.choose({"id": "test_dev_menu_missing", "name": "test_dev_menu_missing", "scene": "res://tools/test_dev_menu_missing.tscn"}) and changed.is_empty(), "a tool whose scene is missing is reported and nothing changes")
	check(menu.is_open, "the menu stays open after a failed choice")
	_press(KEY_F5)
	menu.scene_changer = original
	await frames(1)


func _collect_tooltip_gaps(node: Node, into: PackedStringArray) -> void:
	if node is Button and (node as Button).tooltip_text.is_empty():
		into.append((node as Button).text)
	for child in node.get_children():
		_collect_tooltip_gaps(child, into)
