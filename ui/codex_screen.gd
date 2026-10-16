class_name CodexScreen
extends Control
## 圖鑑：敗北卡片與本輪已看過的故事。回看使用 Story 的唯讀播放接點。
## 滑鼠、鍵盤、手把都用焦點導覽。

signal closed

const COLUMNS := 3
const CARD_SIZE := Vector2(116, 44)
const DETAIL_WIDTH := 214.0
const ReplayPage := preload("res://ui/codex_replay_page.gd")

var _detail_title: Label
var _detail_number: Label
var _detail_text: Label
var _detail_hint: Label
var _first_card: Button
var _defeat_body: HBoxContainer
var _replay_page: ReplayPage
var _tabs: Array[Button] = []
var _progress: Label
var _legend: Label
var _current_tab := 0
var _replay_id: StringName = &""
var _replay_focus: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 本頁已有詳情與操作列，父選單的聚焦說明不得越過圖鑑蓋住回看。
	add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	UiKit.fill_parent(self)
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
	layout.offset_bottom = -14
	layout.add_theme_constant_override(&"separation", 6)
	add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	header.add_child(UiKit.label(ReplayPage.copy("圖鑑", "記録", "Archives"), UiKit.FS_TITLE, Palette.CYAN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var progress := UiKit.label("%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()], UiKit.FS_TITLE, Palette.WARNING)
	header.add_child(progress)
	_progress = progress
	layout.add_child(UiDivider.new())
	var tabs := HBoxContainer.new()
	layout.add_child(tabs)
	var group := ButtonGroup.new()
	for title in [ReplayPage.copy("敗北紀錄", "敗北の記録", "Defeats"), ReplayPage.copy("回顧", "回想", "Memories")]:
		var button := UiKit.button(title, select_tab.bind(_tabs.size()))
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.x = 110
		tabs.add_child(button)
		_tabs.append(button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 10)
	layout.add_child(body)
	_defeat_body = body
	body.add_child(_build_wall())
	body.add_child(_build_detail())
	_replay_page = ReplayPage.new()
	_replay_page.replay_requested.connect(_start_replay)
	layout.add_child(_replay_page)
	_replay_page.hide()

	_legend = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	layout.add_child(_legend)
	InputBindings.bindings_changed.connect(_refresh_legend)
	_refresh_legend()
	Story.replay_finished.connect(_on_replay_finished)
	var back := UiKit.button(ReplayPage.copy("返回", "戻る", "Back"), _close)
	back.custom_minimum_size = Vector2(120, 0)
	layout.add_child(back)
	var all_cards := DefeatCodex.get_all_cards()
	if not all_cards.is_empty():
		_show_detail(all_cards[0])
	var focus_target := _first_card if _first_card != null else back
	focus_target.grab_focus.call_deferred()
	_tabs[0].button_pressed = true


func select_tab(index: int) -> void:
	if _replay_id != &"":
		return
	_current_tab = posmod(index, _tabs.size())
	_defeat_body.visible = _current_tab == 0
	_replay_page.visible = _current_tab == 1
	_progress.text = "%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()] if _current_tab == 0 else ReplayPage.copy("已收錄 %d 段", "%d 件の記録", "%d memories") % _replay_page.entries.size()
	_tabs[_current_tab].button_pressed = true
	if _current_tab == 1 and not _replay_page.buttons.is_empty():
		_replay_page.focus_selected()
	elif _current_tab == 0 and _first_card != null:
		_first_card.grab_focus.call_deferred()
	else:
		_tabs[_current_tab].grab_focus.call_deferred()


func _refresh_legend() -> void:
	_legend.text = InputBindings.format(ReplayPage.copy("{inventory_prev_tab}/{inventory_next_tab} 分頁　{ui_accept} 確認　{ui_cancel} 返回", "{inventory_prev_tab}/{inventory_next_tab} タブ　{ui_accept} 決定　{ui_cancel} 戻る", "{inventory_prev_tab}/{inventory_next_tab} Tabs   {ui_accept} Confirm   {ui_cancel} Back"))


func _start_replay(id: StringName) -> void:
	if _replay_id != &"":
		return
	# 重要通訊允許開暫停頁，但它仍擁有閱讀鎖與對話層；先讀完，避免兩套演出疊在一起。
	if GameplayLock.is_locked():
		_replay_page.show_failure(true)
		return
	_replay_focus = get_viewport().gui_get_focus_owner()
	if not Story.replay(id):
		_replay_page.show_failure()
		return
	_replay_id = id
	# 暫停頁的層高於過場；藏起覆蓋頁，保留原清單、選取和捲動位置。
	hide()


func _on_replay_finished(id: StringName) -> void:
	if id != _replay_id:
		return
	_replay_id = &""
	if not is_inside_tree() or is_queued_for_deletion():
		return
	show()
	if is_instance_valid(_replay_focus) and _replay_focus.is_visible_in_tree():
		_replay_focus.grab_focus.call_deferred()
	else:
		_replay_page.focus_selected()


func _exit_tree() -> void:
	if _replay_id != &"":
		Story.stop_replay()


func _build_wall() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	scroll.add_child(grid)
	for card in DefeatCodex.get_all_cards():
		var node := _make_card(card)
		grid.add_child(node)
		if _first_card == null:
			_first_card = node
	return scroll


func _build_detail() -> Control:
	var panel := UiPanel.new("詳情", Palette.WARNING)
	panel.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail_number = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	panel.body.add_child(_detail_number)
	_detail_title = UiKit.label("", UiKit.FS_TITLE, Palette.UI_TEXT)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_detail_title)
	_detail_text = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_detail_text)
	panel.body.add_child(UiDivider.new())
	_detail_hint = UiKit.label("", UiKit.FS_BODY, Palette.CYAN)
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(_detail_hint)
	return panel


func _make_card(card: Dictionary) -> UiCard:
	var unlocked := bool(card.get("unlocked", false))
	var number := "No.%02d" % int(card.get("number", 0))
	var node := UiCard.new(CARD_SIZE)
	node.content.add_theme_constant_override(&"separation", 1)
	node.add_text(number, UiKit.FS_BODY, Palette.WARNING if unlocked else Palette.UI_MUTED)
	var title := str(card.get("title", "")) if unlocked else "？？？"
	node.add_text(title, UiKit.FS_BODY, Palette.UI_TEXT if unlocked else Palette.TERRAIN_TOP)
	if not unlocked:
		node.modulate = Color(1, 1, 1, 0.55)
	node.focus_entered.connect(_show_detail.bind(card))
	node.mouse_entered.connect(_show_detail.bind(card))
	node.tooltip_text = ("攻略：" + str(card.get("hint", ""))) if unlocked else "以這種方式失敗一次即可解鎖"
	return node


func _show_detail(card: Dictionary) -> void:
	var unlocked := bool(card.get("unlocked", false))
	_detail_number.text = "No.%02d" % int(card.get("number", 0))
	if unlocked:
		_detail_title.text = str(card.get("title", ""))
		_detail_text.text = str(card.get("text", ""))
		_detail_hint.text = "攻略　" + str(card.get("hint", ""))
	else:
		_detail_title.text = "？？？"
		_detail_text.text = "尚未解鎖。"
		_detail_hint.text = "以這種方式失敗一次即可解鎖。"


func _unhandled_input(event: InputEvent) -> void:
	if _replay_id != &"" or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"inventory_prev_tab") or event.is_action_pressed(&"inventory_next_tab"):
		select_tab(_current_tab + (1 if event.is_action_pressed(&"inventory_next_tab") else -1))
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
