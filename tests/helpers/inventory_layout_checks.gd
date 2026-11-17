extends RefCounted
## Real counter data at the supported large text size; no transaction is executed.

static func run(suite: TestSuite) -> void:
	var old_scale := Settings.get_ui_text_scale()
	var old_font := Settings.get_ui_font()
	var old_motion := Settings.get_reduce_ui_motion()
	Settings.set_ui_font("smooth")
	Settings.set_ui_text_scale(1.2)
	# This gate measures settled layout; normal opening/slide motion is verified separately.
	Settings.set_reduce_ui_motion(true)
	var level := await suite.start_level(PropsSuite.level_data())
	level.player.consumables.add(ConsumableBag.find(&"med_injector"))
	Progression.add_credits(500)
	var shop := ShopScreen.new()
	shop.configure_shop(level.player, load("res://data/shops/ch1_pawn.tres") as ShopData)
	suite.runner.add_child(shop)
	shop.open()
	shop.select_tab(shop.page_index(PawnPage))
	await suite.frames(8)
	var title: Label
	for child in shop._frame.get_children():
		if child is Label and child.text == shop._screen_title(): title = child
	suite.check(title != null and not title.get_global_rect().intersects(shop._tabs.get_global_rect()), "large real counter title does not overlap its tab row")
	var page := shop._pages[shop._current] as PawnPage
	var detail := page._detail
	var bounds := shop._page_host.get_global_rect()
	suite.check(bounds.encloses(detail.get_global_rect().grow(-0.5)) and not detail._action.get_global_rect().intersects(shop._legend_label.get_global_rect()), "large real pawn detail and action stay above the inventory footer")
	suite.check(detail._body.text == page._entries[page._selected].detail_body and detail._action.text == page._entries[page._selected].action_label, "bounded pawn details retain original full text, price and action")
	var scrolls := detail.find_children("*", "ScrollContainer", true, false)
	suite.check(scrolls.size() == 1, "long pawn details expose one bounded reading region")
	if scrolls.size() == 1:
		var scroll := scrolls[0] as ScrollContainer
		var before := var_to_bytes([Progression.snapshot(), level.player.consumables.snapshot(), page._selected])
		await _key(suite, KEY_PAGEDOWN)
		suite.check(scroll.scroll_vertical > 0, "PageDown scrolls real long pawn details without changing selection")
		await _key(suite, KEY_PAGEUP)
		suite.check(scroll.scroll_vertical == 0, "PageUp returns real pawn details to the beginning")
		var axis := InputEventJoypadMotion.new()
		axis.device = 999
		axis.axis = JOY_AXIS_RIGHT_Y
		axis.axis_value = 0.9
		Input.parse_input_event(axis)
		await suite.frames(2)
		suite.check(scroll.scroll_vertical > 0, "right stick scrolls the same details through public synthetic input")
		axis = axis.duplicate()
		axis.axis_value = 0.0
		Input.parse_input_event(axis)
		suite.check(before == var_to_bytes([Progression.snapshot(), level.player.consumables.snapshot(), page._selected]), "reading details does not pawn, redeem, spend or change the selected item")
		page.refresh()
		await suite.frames(4)
		var hint := detail.get("_scroll_hint") as Label
		suite.check(hint != null and hint.is_visible_in_tree(), "refreshing an overflowing entry retains its current reading guidance")
		var reader := preload("res://ui/inventory/document_reader.gd").new()
		page.add_child(reader)
		var document := StoryItems.find(&"ch3_report_p17")
		reader.show_document(document.title_text(), document.body_text(), document.color)
		await suite.frames(3)
		var behind := scroll.scroll_vertical
		await _key(suite, KEY_PAGEDOWN)
		suite.check(reader._back.has_focus() and scroll.scroll_vertical == behind, "a focused full-document reader prevents detail scrolling behind it")
		reader.queue_free()
		await suite.frames(1)
	shop.close()
	shop.queue_free()
	await suite.frames(2)
	await suite.end_level(level)
	Settings.set_ui_text_scale(old_scale)
	Settings.set_ui_font(old_font)
	Settings.set_reduce_ui_motion(old_motion)
	InputBindings.clear_held_inputs()


static func _key(suite: TestSuite, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await suite.frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await suite.frames(1)
