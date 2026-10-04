class_name MainMenu
extends Control
## 主選單：雨夜沉港的緩慢搖鏡 + 左側選單依序滑入；「開始任務」進入三張難度卡片。
## 每個選項都有一句重點說明（游標或焦點移上去時顯示在選單下方，同時是 tooltip）。

signal start_requested(difficulty: DifficultyData)
signal quit_requested

const VERSION_TEXT := "DEMO 0.1"
const CAMERA_SWAY := 56.0
const CAMERA_PERIOD := 48.0
const MENU_WIDTH := 168.0
const CARD_SIZE := Vector2(184, 172)

var _selected: DifficultyData
var _camera: Camera2D
var _ui: Control
var _main_page: Control
var _difficulty_page: Control
var _hint: Label
var _start_button: Button
var _confirm_button: Button
var _cards: Array[UiCard] = []
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_show_page(_main_page)
	_start_button.grab_focus.call_deferred()


func _process(delta: float) -> void:
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
	_start_button = _menu_button("開始任務", _open_difficulty, "選擇難度，從第一章開始")
	entries.append(_start_button)
	entries.append(_menu_button("敗北圖鑑", _open_codex, "看已解鎖的失敗紀錄與對應的攻略"))
	entries.append(_menu_button("設定", _open_settings, "音量、按鍵、顯示"))
	entries.append(_menu_button("離開", quit_requested.emit, "關閉遊戲"))
	for b in entries:
		list.add_child(b)

	_hint = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_hint.position = Vector2(38, 262)
	_hint.size = Vector2(260, 16)
	_main_page.add_child(_hint)

	var legend := UiKit.label(InputBindings.format("↑↓ 選擇　Enter 確認　Esc 返回"), UiKit.FS_BODY, Palette.UI_MUTED)
	legend.position = Vector2(38, 334)
	_main_page.add_child(legend)
	var version := UiKit.label(VERSION_TEXT, UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.position = Vector2(640 - 120 - 12, 334)
	version.size = Vector2(120, 16)
	_main_page.add_child(version)

	UiMotion.stagger_in([title, subtitle, rule] + entries, 0.06, 24.0)


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
	card.add_text("生命　%d" % difficulty.player_max_health)
	card.add_text("殘機　%s" % lives)
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
	start_requested.emit(_selected)


func _open_settings() -> void:
	var settings := SettingsScreen.new()
	settings.closed.connect(_start_button.grab_focus)
	_ui.add_child(settings)


func _open_codex() -> void:
	var codex := CodexScreen.new()
	codex.closed.connect(_start_button.grab_focus)
	_ui.add_child(codex)
