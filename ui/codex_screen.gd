class_name CodexScreen
extends Control
## 敗北圖鑑：列出所有卡片，已解鎖顯示內容與攻略，未解鎖顯示 ???。

signal closed


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.color = Color(Palette.BG_FAR, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 24
	layout.offset_right = -24
	layout.offset_top = 16
	layout.offset_bottom = -16
	layout.add_theme_constant_override(&"separation", 8)
	add_child(layout)

	var title := "敗北圖鑑　%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()]
	layout.add_child(UiKit.label(title, 16, Palette.CYAN))
	layout.add_child(UiKit.label("每種失敗方式解鎖一張卡片，附上對應的攻略。", 10, Palette.UI_MUTED))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(grid)
	for card in DefeatCodex.get_all_cards():
		grid.add_child(_make_card(card))

	var back := UiKit.button("返回", _close, "回到主選單")
	layout.add_child(back)
	back.grab_focus.call_deferred()


func _make_card(card: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 64)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var unlocked := bool(card.get("unlocked", false))
	var number := "No.%02d　" % int(card.get("number", 0))
	if unlocked:
		box.add_child(UiKit.label(number + str(card.get("title", "")), 11, Palette.WARNING))
		var text := UiKit.label(str(card.get("text", "")), 10, Palette.UI_MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(text)
		panel.tooltip_text = "攻略：" + str(card.get("hint", ""))
	else:
		box.add_child(UiKit.label(number + "？？？", 11, Palette.UI_MUTED))
		box.add_child(UiKit.label("尚未解鎖", 10, Palette.TERRAIN_TOP))
		panel.tooltip_text = "以這種方式失敗一次即可解鎖"
	return panel


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
