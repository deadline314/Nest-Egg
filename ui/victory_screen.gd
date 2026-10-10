class_name VictoryScreen
extends Control
## 結算畫面：章節名、評價項目一項一項跳出來，最後是敗北圖鑑進度與下一章預告。

signal replay_requested
signal menu_requested

const REVEAL_INTERVAL := 0.22
const VALUE_X := 210.0
const EDITION_END_TEXT := "本版本收錄到這裡，進度已保存。"

## 剛通關的章節（Main 指定），用來取章節名與下一章預告。
var chapter: StringName = &"chapter_01"

var _rows: Array[Control] = []
var _skip_requested := false
var _buttons: Array[Button] = []


func _ready() -> void:
	UiKit.fill_parent(self)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	UiKit.set_cursor_visible(true)
	Music.show_victory()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.95)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiPanel.new("結算")
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var info := Story.chapter_info(chapter)
	# 標題與難度同一列，留出空間給章末的下一步與收錄說明（720p 也放得下按鈕）。
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override(&"separation", 16)
	heading.add_child(UiKit.label(str(info.get("end_title", "任務完成")), UiKit.FS_TITLE, Palette.CYAN))
	var difficulty := UiKit.label("難度　%s" % GameState.difficulty.display_name, UiKit.FS_BODY, Palette.UI_MUTED)
	difficulty.size_flags_vertical = Control.SIZE_SHRINK_END
	heading.add_child(difficulty)
	panel.body.add_child(heading)
	panel.body.add_child(UiDivider.new())

	for entry in _stat_entries():
		var row := _stat_row(entry["label"], str(entry["value"]), entry.get("color", Palette.UI_TEXT))
		panel.body.add_child(row)
		_rows.append(row)
	var teaser := str(info.get("teaser", ""))
	# 累積版本的最後一章：同一行說清楚內容到此、進度已保存，不讓玩家以為下一章壞掉，也不加高面板。
	if CampaignEdition.current().is_last_chapter(chapter):
		teaser = ("%s　" % teaser if teaser != "" else "") + EDITION_END_TEXT
	if teaser != "":
		panel.body.add_child(UiDivider.new())
		var teaser_label := UiKit.label(teaser, UiKit.FS_BODY, Palette.NEON_YELLOW)
		panel.body.add_child(teaser_label)
		_rows.append(teaser_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	panel.body.add_child(buttons)
	var replay := UiKit.button("再玩一次", replay_requested.emit, "相同難度重新開始")
	replay.custom_minimum_size = Vector2(160, 0)
	var menu := UiKit.button("回主選單", menu_requested.emit, "更換難度或查看圖鑑")
	menu.custom_minimum_size = Vector2(140, 0)
	buttons.add_child(replay)
	buttons.add_child(menu)
	_buttons = [replay, menu]
	for b in _buttons:
		b.disabled = true
	replay.grab_focus.call_deferred()
	# 鍵盤與手把移動焦點時，在底部顯示同一句說明。
	FocusHintBar.attach(self, FocusHintBar.Placement.BOTTOM_RIGHT)
	_run_reveal.call_deferred()


func _stat_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{"label": "通關時間", "value": UiKit.format_time(GameState.run_time)},
		{"label": "回溯次數", "value": GameState.deaths, "color": Palette.DANGER if GameState.deaths > 0 else Palette.UI_TEXT},
		{"label": "擊破數", "value": GameState.kills},
		{"label": "終結技", "value": GameState.finishers},
		{"label": "信用點", "value": "¥ %d" % Progression.credits, "color": Palette.NEON_YELLOW},
		{"label": "敗北圖鑑", "value": "%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()]},
	]
	var collection := StoryItems.overall_collection()
	if collection.y > 0:
		entries.insert(5, {"label": "背景收集", "value": "%d / %d" % [collection.x, collection.y]})
	return entries


func _stat_row(label_text: String, value_text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	var name_label := UiKit.label(label_text, UiKit.FS_BODY, Palette.UI_MUTED)
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)
	row.add_child(UiKit.label(value_text, UiKit.FS_BODY, color))
	return row


## 項目一項一項跳出，結束後才開放按鈕（避免連點直接跳過）。按確認鍵或射擊鍵可以立刻全部顯示。
func _run_reveal() -> void:
	await UiMotion.reveal_sequence(_rows, REVEAL_INTERVAL,
			func(_n: Control) -> void: Sfx.play(&"ui_move", -10.0, 0.0),
			func() -> bool: return _skip_requested)
	for b in _buttons:
		if is_instance_valid(b):
			b.disabled = false
	if is_instance_valid(_buttons[0]):
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _skip_requested and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"shoot")):
		_skip_requested = true
		get_viewport().set_input_as_handled()
