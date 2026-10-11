class_name MainMenu
extends Control
## 主選單：雨夜沉港的緩慢搖鏡 + 左側選單依序滑入；「開始任務」進入三張難度卡片。
## 每個選項都有一句重點說明（游標或焦點移上去時顯示在選單下方，同時是 tooltip）。

signal start_requested(difficulty: DifficultyData)
signal quit_requested
signal continue_requested
var continue_available := false
var overwrite_required := false
var save_notice := ""
var _overwrite_dialog: RunOverwritePrompt
var _continue_button: Button

const VERSION_TEXT := "DEMO 0.1"
const CAMERA_SWAY := 56.0
const CAMERA_PERIOD := 48.0
const MENU_WIDTH := 168.0
const CARD_SIZE := Vector2(184, 194)
## 開發工具按鈕離右下角的距離（右、下）；下方留給版本字樣。
const DEV_BUTTON_MARGIN := Vector2(12, 30)

var _selected: DifficultyData
var _camera: Camera2D
var _ui: Control
var _main_page: Control
var _difficulty_page: Control
var _hint: Label
var _start_button: Button
var _confirm_button: Button
var _dev_button: Button
var _cards: Array[UiCard] = []
var _time := 0.0
var _legends: Array[Label] = []


func _ready() -> void:
	UiKit.fill_parent(self)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	_selected = GameState.difficulty
	UiKit.set_cursor_visible(true)
	Music.show_menu()
	add_child(LevelBackground.new())
	_camera = Camera2D.new()
	_camera.position = Vector2(320, 180)
	add_child(_camera)

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiKit.theme()
	layer.add_child(_ui)
	_ui.add_child(_make_shade())
	_build_main_page()
	_build_difficulty_page()
	InputBindings.bindings_changed.connect(_refresh_legends)
	_refresh_legends()
	_show_page(_main_page)
	(_continue_button if _continue_button != null else _start_button).grab_focus.call_deferred()


func _process(delta: float) -> void:
	if Settings.get_reduce_ui_motion():
		return
	# 緩慢左右搖鏡：視差層錯開移動，城市看起來有深度。
	_time += delta
	_camera.position.x = 320.0 + sin(_time * TAU / CAMERA_PERIOD) * CAMERA_SWAY


func _unhandled_input(event: InputEvent) -> void:
	if _difficulty_page.visible and event.is_action_pressed(&"ui_cancel"):
		_show_page(_main_page)
		_start_button.grab_focus()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 版面
# ---------------------------------------------------------------------------

func _make_shade() -> Control:
	# 左側暗色漸層：讓文字在亮的背景上也讀得清楚。
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.02, 0.03, 0.06, 0.92), Color(0.02, 0.03, 0.06, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 256
	tex.height = 4
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.anchor_right = 0.62
	rect.offset_right = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _build_main_page() -> void:
	_main_page = Control.new()
	_main_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_main_page)

	var title := UiKit.label("NEST EGG", UiKit.FS_DISPLAY, LightKit.glow(Palette.CYAN, 1.6))
	title.position = Vector2(36, 40)
	_main_page.add_child(title)
	var subtitle := UiKit.label("巢中之卵", UiKit.FS_BODY, Palette.UI_MUTED)
	subtitle.position = Vector2(38, 84)
	_main_page.add_child(subtitle)
	var rule := UiDivider.new()
	rule.position = Vector2(36, 104)
	rule.custom_minimum_size = Vector2(MENU_WIDTH, 7)
	rule.size = Vector2(MENU_WIDTH, 7)
	_main_page.add_child(rule)

	var list := VBoxContainer.new()
	list.position = Vector2(36, 124)
	list.add_theme_constant_override(&"separation", 6)
	_main_page.add_child(list)
	var entries: Array[Button] = []
	if continue_available:
		_continue_button = _menu_button("繼續遊戲", continue_requested.emit, "恢復上次保存的整輪進度")
		entries.append(_continue_button)
	_start_button = _menu_button("開始任務", _open_difficulty, "選擇難度，從第一章開始")
	entries.append(_start_button)
	entries.append(_menu_button("敗北圖鑑", _open_codex, "看已解鎖的失敗紀錄與對應的攻略"))
	entries.append(_menu_button("設定", _open_settings, "音量、按鍵、顯示"))
	entries.append(_menu_button("離開", quit_requested.emit, "關閉遊戲"))
	for b in entries:
		list.add_child(b)

	_hint = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_hint.position = Vector2(38, 288)
	_hint.size = Vector2(260, 16)
	_main_page.add_child(_hint)
	list.resized.connect(func() -> void: _hint.position.y = list.position.y + list.size.y + 8)
	_hint.position.y = list.position.y + list.size.y + 8
	if not save_notice.is_empty():
		var notice := UiKit.label(save_notice, UiKit.FS_BODY, Palette.UI_MUTED)
		# 先開自動換行再定尺寸；反過來的話 Label 會先撐到整行文字寬，長說明超出畫面。
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.position = Vector2(310, 250)
		notice.size = Vector2(300, 64)
		_main_page.add_child(notice)

	_add_legend(_main_page)
	# 發行版標出收錄範圍，玩家一眼知道這份程式玩到哪一章；存檔也依此分開保存。
	var edition := CampaignEdition.current()
	var version_text := VERSION_TEXT if edition.development else "%s　%s" % [edition.version if not edition.version.is_empty() else VERSION_TEXT, edition.title()]
	var version := UiKit.label(version_text, UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_main_page.add_child(version)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.custom_minimum_size.x = 120
	version.offset_left = -132
	version.offset_top = -30
	version.offset_right = -12
	version.offset_bottom = -8
	_build_dev_entry()

	UiMotion.stagger_in([title, subtitle, rule] + entries, 0.06, 24.0)


## 編輯器與除錯版才有的開發工具入口：不依賴 F5 能不能送到遊戲視窗（編輯器可能先攔走 F5）。
func _build_dev_entry() -> void:
	if not DevMenu.is_available():
		return
	_dev_button = UiKit.button("開發工具（F5）", DevMenu.open, "音效實驗室、打擊感實驗室等開發用工具；只有編輯器與除錯版有")
	# 貼著右下角、向左上長：按鈕的最小尺寸由主題決定，不用自己算寬度才不會被切掉。
	_dev_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dev_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dev_button.offset_right = -DEV_BUTTON_MARGIN.x
	_dev_button.offset_bottom = -DEV_BUTTON_MARGIN.y
	_dev_button.focus_entered.connect(_set_hint.bind(_dev_button.tooltip_text))
	_dev_button.mouse_entered.connect(_set_hint.bind(_dev_button.tooltip_text))
	_main_page.add_child(_dev_button)


func _menu_button(text: String, on_pressed: Callable, tooltip: String) -> Button:
	var b := UiKit.button(text, on_pressed, tooltip)
	b.custom_minimum_size = Vector2(MENU_WIDTH, 26)
	b.focus_entered.connect(_set_hint.bind(tooltip))
	b.mouse_entered.connect(_set_hint.bind(tooltip))
	return b


func _set_hint(text: String) -> void:
	_hint.text = text


func _build_difficulty_page() -> void:
	_difficulty_page = Control.new()
	_difficulty_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_difficulty_page)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_difficulty_page.add_child(shade)

	var heading := UiKit.label("選擇難度", UiKit.FS_TITLE, Palette.CYAN)
	heading.position = Vector2(36, 28)
	_difficulty_page.add_child(heading)
	var sub := UiKit.label("開始後不能中途更換；通關後可以用別的難度重玩。", UiKit.FS_BODY, Palette.UI_MUTED)
	sub.position = Vector2(38, 60)
	_difficulty_page.add_child(sub)

	var row := HBoxContainer.new()
	row.position = Vector2(36, 92)
	row.add_theme_constant_override(&"separation", 10)
	_difficulty_page.add_child(row)
	var group := ButtonGroup.new()
	for difficulty in GameState.difficulties:
		var card := _make_difficulty_card(difficulty, group)
		row.add_child(card)
		_cards.append(card)

	var buttons := HBoxContainer.new()
	buttons.position = Vector2(36, 292)
	buttons.add_theme_constant_override(&"separation", 10)
	_difficulty_page.add_child(buttons)
	_confirm_button = UiKit.button("出發", _on_start, "以選擇的難度開始第一章")
	_confirm_button.custom_minimum_size = Vector2(150, 26)
	buttons.add_child(_confirm_button)
	var back := UiKit.button("返回", _on_back, "回到主選單")
	back.custom_minimum_size = Vector2(110, 26)
	buttons.add_child(back)
	_add_legend(_difficulty_page)


func _add_legend(page: Control) -> void:
	var legend := UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	legend.position = Vector2(38, 334)
	page.add_child(legend)
	_legends.append(legend)


func _refresh_legends() -> void:
	for legend in _legends:
		legend.text = InputBindings.format("{ui_up}/{ui_down} 選擇　{ui_accept} 確認　{ui_cancel} 返回")


func _make_difficulty_card(difficulty: DifficultyData, group: ButtonGroup) -> UiCard:
	var card := UiCard.new(CARD_SIZE)
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = difficulty == _selected
	card.tooltip_text = difficulty.description
	card.add_text(difficulty.display_name, UiKit.FS_TITLE, Palette.CYAN if difficulty == _selected else Palette.UI_TEXT)
	card.add_text(difficulty.description, UiKit.FS_BODY, Palette.UI_MUTED, true)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.content.add_child(spacer)
	card.content.add_child(UiDivider.new())
	var lives := "無限" if not difficulty.has_limited_lives() else "%d" % difficulty.lives
	card.add_text("生命 %d　殘機 %s" % [difficulty.player_max_health, lives])
	card.add_text("敵人節奏　%s" % _pace_text(difficulty.enemy_cooldown_multiplier))
	card.add_text("檢查點回血　%s" % ("有" if difficulty.checkpoint_heals else "沒有"))
	card.pressed.connect(_select_difficulty.bind(difficulty))
	return card


## 敵人冷卻倍率轉成一個字：倍率越大敵人越慢。
static func _pace_text(cooldown_multiplier: float) -> String:
	if cooldown_multiplier >= 1.2:
		return "慢"
	if cooldown_multiplier <= 0.9:
		return "快"
	return "標準"


func _select_difficulty(difficulty: DifficultyData) -> void:
	_selected = difficulty
	for i in _cards.size():
		var title: Label = _cards[i].content.get_child(0)
		title.add_theme_color_override(&"font_color", Palette.CYAN if GameState.difficulties[i] == difficulty else Palette.UI_TEXT)


func _show_page(page: Control) -> void:
	_main_page.visible = page == _main_page
	_difficulty_page.visible = page == _difficulty_page


# ---------------------------------------------------------------------------
# 動作
# ---------------------------------------------------------------------------

func _open_difficulty() -> void:
	_show_page(_difficulty_page)
	for card in _cards:
		if card.button_pressed:
			card.grab_focus()
			break
	UiMotion.stagger_in(_cards, 0.07, 28.0)


func _on_back() -> void:
	_show_page(_main_page)
	_start_button.grab_focus()


func _on_start() -> void:
	if not overwrite_required:
		start_requested.emit(_selected)
		return
	if is_instance_valid(_overwrite_dialog):
		return
	_overwrite_dialog = RunOverwritePrompt.new()
	_overwrite_dialog.confirmed.connect(func() -> void: start_requested.emit(_selected))
	UiOverlay.open(_ui, _overwrite_dialog)


func _open_settings() -> void:
	var settings := SettingsScreen.new()
	UiOverlay.open(_ui, settings)


func _open_codex() -> void:
	var codex := CodexScreen.new()
	UiOverlay.open(_ui, codex)
