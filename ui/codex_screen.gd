class_name CodexScreen
extends Control
## 敗北圖鑑：卡片牆。已解鎖顯示標題，未解鎖是剪影；選取（焦點或游標）時右側展開詳情與攻略。
## 滑鼠、鍵盤、手把都用焦點導覽。

signal closed

const COLUMNS := 3
const CARD_SIZE := Vector2(116, 44)
const DETAIL_WIDTH := 214.0

var _detail_title: Label
var _detail_number: Label
var _detail_text: Label
var _detail_hint: Label
var _first_card: Button


func _ready() -> void:
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
	header.add_child(UiKit.label("敗北圖鑑", UiKit.FS_TITLE, Palette.CYAN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var progress := UiKit.label("%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()], UiKit.FS_TITLE, Palette.WARNING)
	header.add_child(progress)
	layout.add_child(UiDivider.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 10)
	layout.add_child(body)
	body.add_child(_build_wall())
	body.add_child(_build_detail())

	var back := UiKit.button("返回", _close, "回到上一頁")
	back.custom_minimum_size = Vector2(120, 0)
	layout.add_child(back)
	var all_cards := DefeatCodex.get_all_cards()
	if not all_cards.is_empty():
		_show_detail(all_cards[0])
	var focus_target := _first_card if _first_card != null else back
	focus_target.grab_focus.call_deferred()


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
	if event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
