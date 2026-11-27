class_name MainMenu
extends Control
## 主選單的城市慢鏡、固定導覽列和難度選擇。
## 每個選項都有一句重點說明（游標或焦點移上去時顯示在選單下方，同時是 tooltip）。
## 拼貼版面（NE-403、NE-412）：遊戲名壓在斜切的霓虹招牌底板上；選單群佔左邊約 45%，每個選項是一樣不同的實物
## （主要動作是很大的米白當票、圖鑑是檔案夾標籤、設定是維修貼紙、離開是洋紅的封條膠帶），左右錯開、正負交替傾斜、互相壓住一角，
## 選到的轉正、放大、浮到最上面（TagButton）。右邊是主角的骨架立繪站在城市前面；版本號是圓形戳章、操作提示是一條膠帶。
## 選項與標題的字跟著斜（6 度以內），說明文字水平。開啟時底板切入、選項依序彈入；「減少動態」時直接到位。

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
const MENU_INK := Color("e9e2ce")
## 主要動作（當票）的位置大小與傾斜；後面錯位的外文字。
const HERO := Rect2(22, 122, 214, 58)
const HERO_TILT := -4.0
const HERO_GHOST := {"start": "DEPLOY", "resume": "RESUME"}
## 其他選項依序放的位置與傾斜（度）：左右錯開、正負交替、互相壓住一角。
const SLOTS: Array[Rect2] = [Rect2(40, 186, 134, 30), Rect2(150, 205, 118, 28), Rect2(54, 231, 110, 26), Rect2(166, 240, 104, 26)]
const SLOT_TILTS: Array[float] = [3.5, -5.0, 4.5, -3.0]
## 右邊的主角立繪佔畫面的範圍（錨點：左、上、右、下）。
const PORTRAIT_ANCHORS := [0.56, 0.1, 0.96, 0.98]
## 標題：字級（遊戲像素）、底板的位置與大小、錯位副標的字級。
const TITLE_SIZE := 50
const TITLE_PLATE := Rect2(14, 22, 312, 92)
const GHOST_SIZE := 30
## 開場吊牌依序彈入：第一張的延遲與每張之間的間隔（最後一張也要在 300 毫秒內停好）。
const INTRO_DELAY := 0.03
const INTRO_STEP := 0.02
const CARD_SIZE := Vector2(184, 194)
const COPY := {
	"subtitle": ["巢中之卵", "巣の卵", ""],
	"resume": ["繼續遊戲", "続きから", "Continue"],
	"resume_hint": ["恢復上次保存的整輪進度", "最後に保存した進行状況を再開", "Restore your last campaign save."],
	"start": ["開始任務", "任務を開始", "New game"],
	"start_hint": ["選擇難度，從序章開始", "難易度を選び、序章から始めます。", "Choose a difficulty and start the prologue."],
	"codex": ["圖鑑", "図鑑", "Codex"],
	"codex_hint": ["查看敗北紀錄，重看本輪看過的故事", "敗北記録を読み、見た場面を再生します。", "View defeat records and replay unlocked scenes."],
	"settings": ["設定", "設定", "Settings"],
	"settings_hint": ["音量、按鍵、顯示", "音量・操作・表示を調整します。", "Adjust audio, controls and display."],
	"quit": ["離開", "終了", "Quit"],
	"quit_hint": ["關閉遊戲", "ゲームを終了します。", "Close the game."],
	"developer": ["開發工具（F5）", "開発ツール（F5）", "Developer tools (F5)"],
	"developer_hint": ["音效與打擊感等開發工具", "音響や打撃感の調整ツール。", "Open sound, combat and other development tools."],
	"difficulty": ["選擇難度", "難易度を選択", "Choose a difficulty"],
	"difficulty_hint": ["開始後不能中途更換；通關後可以用別的難度重玩。", "開始後は難易度を変更できません。クリア後は別の難易度を選べます。", "Difficulty stays fixed for this run."],
	"confirm": ["出發", "出発", "Start"],
	"confirm_hint": ["以選擇的難度開始序章", "選んだ難易度で序章を始めます。", "Start the prologue on this difficulty."],
	"back": ["返回", "戻る", "Back"],
	"back_hint": ["回到主選單", "メインメニューに戻ります。", "Return to the main menu."],
	"menu_controls": ["{ui_up}/{ui_down} 選擇　{ui_accept} 確認", "{ui_up}/{ui_down} 選択　{ui_accept} 決定", "{ui_up}/{ui_down} Move   {ui_accept} Select"],
	"difficulty_controls": ["{ui_left}/{ui_right} 選難度　{ui_accept} 確認　{ui_cancel} 返回",
		"{ui_left}/{ui_right} 難易度を選択　{ui_accept} 決定　{ui_cancel} 戻る",
		"{ui_left}/{ui_right} Difficulty   {ui_accept} Select   {ui_cancel} Back"],
	"unlimited": ["無限", "無制限", "Unlimited"],
	"health_lives": ["生命 %d　殘機 %s", "体力 %d　残機 %s", "HP %d   Lives %s"],
	"pace": ["敵人節奏　%s", "敵の攻撃間隔　%s", "Enemy attacks: %s"],
	"pace_slow": ["慢", "長め", "Slow"],
	"pace_fast": ["快", "短め", "Fast"],
	"pace_standard": ["標準", "標準", "Standard"],
	"heals": ["檢查點回血　有", "チェックポイント回復あり", "Checkpoint healing: On"],
	"no_heal": ["檢查點回血　沒有", "チェックポイント回復なし", "Checkpoint healing: Off"],
}
## 開發工具按鈕離右上角的距離（右、上）。
const DEV_BUTTON_MARGIN := Vector2(12, 10)

var _selected: DifficultyData
var _camera: Camera2D
var _ui: Control
var _main_page: Control
var _difficulty_page: Control
var _hint: Label
var _start_button: Button
var _menu_list: Control
var _portrait: SidePortrait
var _menu_focus: Button
var _menu_hover: Button
var _title_plate: CollagePlate
var _tags: Array[TagButton] = []
var _confirm_button: Button
var _dev_button: Button
var _cards: Array[UiCard] = []
var _time := 0.0
var _menu_legend: Label
var _difficulty_legend: Label


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
	_build_portrait()
	_build_main_page()
	_build_difficulty_page()
	InputBindings.bindings_changed.connect(_refresh_legends)
	Settings.display_changed.connect(_sync_menu_motion)
	_refresh_legends()
	_show_page(_main_page)
	(_continue_button if _continue_button != null else _start_button).grab_focus.call_deferred()


func _process(delta: float) -> void:
	if Settings.get_reduce_ui_motion():
		return
	# 緩慢左右搖鏡：視差層錯開移動，城市看起來有深度。
	_time += delta
	_camera.position.x = 320.0 + sin(_time * TAU / CAMERA_PERIOD) * CAMERA_SWAY


func _input(event: InputEvent) -> void:
	if _main_page == null or not _main_page.is_visible_in_tree() or _menu_hover == null:
		return
	if event is InputEventMouse:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down") \
			or event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right") \
			or event.is_action_pressed(&"ui_focus_next") or event.is_action_pressed(&"ui_focus_prev"):
		_menu_hover = null
		_update_hint()


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
	gradient.colors = PackedColorArray([Color("0b1016fa"), Color("121b24df"), Color("10162400")])
	gradient.offsets = PackedFloat32Array([0.0, 0.44, 1.0])
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

	# 招牌底板 → 錯位的大副標（很淡）→ 遊戲名 → 小副標。文字一律水平，只有底板傾斜。
	_title_plate = CollagePlate.new()
	_title_plate.position = TITLE_PLATE.position
	_title_plate.size = TITLE_PLATE.size
	_main_page.add_child(_title_plate)
	var ghost := UiKit.label(_text("subtitle") if not _text("subtitle").is_empty() else "NEST EGG", GHOST_SIZE, Color(Palette.CYAN, 0.16))
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = Vector2(186, 62)
	_main_page.add_child(ghost)
	var title := UiKit.label("NEST EGG", TITLE_SIZE, MENU_INK)
	title.add_theme_font_override(&"font", UiKit.special_font(&"display"))
	title.position = Vector2(30, 26)
	_main_page.add_child(title)
	var subtitle := UiKit.label(_text("subtitle"), UiKit.FS_BODY, Palette.CYAN)
	subtitle.position = Vector2(36, 92)
	_main_page.add_child(subtitle)
	# 標題的字跟著招牌底板一起斜（繞底板中心轉）。
	for label: Control in [ghost, title, subtitle]:
		label.pivot_offset = TITLE_PLATE.get_center() - label.position
		label.rotation = deg_to_rad(_title_plate.tilt_degrees)

	# 選項自己擺位置（會轉動，不能放在容器裡）；焦點順序照清單順序明確指定。
	_menu_list = Control.new()
	_menu_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_page.add_child(_menu_list)
	var entries: Array[TagButton] = []
	if continue_available:
		_continue_button = _menu_button(_text("resume"), continue_requested.emit, _text("resume_hint"), &"ticket", "resume")
		entries.append(_continue_button)
	_start_button = _menu_button(_text("start"), _open_difficulty, _text("start_hint"), &"tag" if continue_available else &"ticket", "start")
	entries.append(_start_button)
	entries.append(_menu_button(_text("codex"), _open_codex, _text("codex_hint"), &"folder"))
	entries.append(_menu_button(_text("settings"), _open_settings, _text("settings_hint"), &"sticker"))
	entries.append(_menu_button(_text("quit"), quit_requested.emit, _text("quit_hint"), &"seal"))
	for i in entries.size():
		var tag := entries[i]
		var slot: Rect2 = HERO if i == 0 else SLOTS[mini(i - 1, SLOTS.size() - 1)]
		tag.tilt_degrees = HERO_TILT if i == 0 else SLOT_TILTS[mini(i - 1, SLOT_TILTS.size() - 1)]
		tag.custom_minimum_size = slot.size
		_menu_list.add_child(tag)
		tag.reset_size()
		tag.place(slot.position)
	_link_focus(entries)

	_hint = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_hint.position = Vector2(38, 288)
	_hint.size = Vector2(260, 16)
	_main_page.add_child(_hint)
	_layout_menu_list.call_deferred()
	if not save_notice.is_empty():
		var notice_panel := PanelContainer.new()
		notice_panel.theme_type_variation = &"TooltipPanel"
		notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		notice_panel.position = Vector2(310, 225)
		notice_panel.custom_minimum_size.x = 300.0
		_main_page.add_child(notice_panel)
		var notice := UiKit.label(save_notice)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice_panel.add_child(notice)

	_menu_legend = _add_legend(_main_page)
	_menu_legend.position = Vector2(38, 334)
	CollageDecal.attach(_menu_legend, &"tape")
	# 發行版標出收錄範圍，玩家一眼知道這份程式玩到哪一章；存檔也依此分開保存。
	var edition := CampaignEdition.current()
	var version_text := VERSION_TEXT if edition.development else "%s　%s" % [edition.version if not edition.version.is_empty() else VERSION_TEXT, edition.title(Story.language)]
	# 版本號是右下角斜蓋的圓形戳章。
	var version := UiKit.label(version_text, UiKit.FS_BODY, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_page.add_child(version)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_left = -76
	version.offset_top = -60
	version.offset_right = -18
	version.offset_bottom = -14
	version.pivot_offset = Vector2(29, 23)
	version.rotation = deg_to_rad(-8.0)
	CollageDecal.attach(version, &"stamp")
	_build_dev_entry()

	# 開場：底板斜切進來，標題與副標滑入，吊牌依序彈入（全部 300 毫秒內）。
	UiMotion.stagger_in([title, ghost, subtitle], 0.03, 10.0)
	_play_intro()


## 開場動畫：先把底板與吊牌藏起來，等兩個影格（第一個影格常因為載入背景而很長，tween 會被那一格一次吃掉）再開始。
func _play_intro() -> void:
	if Settings.get_reduce_ui_motion():
		_title_plate.intro()
		for tag in _tags:
			tag.intro(0.0)
		return
	_title_plate._set_intro(0.0)
	for tag in _tags:
		tag._set_intro(0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_title_plate.intro()
	for i in _tags.size():
		_tags[i].intro(INTRO_DELAY + INTRO_STEP * i)


## 編輯器與除錯版才有的開發工具入口：不依賴 F5 能不能送到遊戲視窗（編輯器可能先攔走 F5）。
func _build_dev_entry() -> void:
	if not DevMenu.is_available():
		return
	_dev_button = UiKit.button(_text("developer"), DevMenu.open, _text("developer_hint"))
	# 貼著右上角、向左下長（右下角是版本戳章）：按鈕的最小尺寸由主題決定，不用自己算寬度才不會被切掉。
	_dev_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dev_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_button.offset_right = -DEV_BUTTON_MARGIN.x
	_dev_button.offset_top = DEV_BUTTON_MARGIN.y
	_bind_menu_highlight(_dev_button)
	_main_page.add_child(_dev_button)


## 一個選項：style 決定它是哪一樣實物；當票是主要動作（字比較大、讓出票根、後面錯位的外文字）。
func _menu_button(text: String, on_pressed: Callable, tooltip: String, style: StringName, ghost := "") -> TagButton:
	var b := TagButton.new()
	b.text = text
	b.tooltip_text = tooltip
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	b.theme_type_variation = &"MenuAction"
	b.tilt_text = true
	b.add_theme_color_override(&"font_color", Palette.UI_TEXT)
	b.add_theme_color_override(&"font_hover_color", MENU_INK)
	b.add_theme_color_override(&"font_focus_color", MENU_INK)
	b.style = style
	match style:
		&"ticket":
			b.ghost_text = HERO_GHOST.get(ghost, "")
			b.text_margin = TagButton.STUB + 12.0
			b.add_theme_font_size_override(&"font_size", UiKit.scaled_size(UiKit.FS_TITLE))
		&"sticker":
			b.text_margin = 24.0
		&"seal":
			b.text_margin = 12.0
	_tags.append(b)
	_bind_menu_highlight(b)
	return b


func _bind_menu_highlight(button: Button) -> void:
	button.focus_entered.connect(_focus_action.bind(button))
	button.mouse_entered.connect(_hover_action.bind(button))
	button.mouse_exited.connect(_leave_action.bind(button))
	button.gui_input.connect(_restore_pointer_highlight.bind(button))


func _restore_pointer_highlight(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseMotion and _menu_hover != button:
		_hover_action(button)


func _focus_action(button: Button) -> void:
	_menu_focus = button
	_menu_hover = null
	_update_hint()


func _hover_action(button: Button) -> void:
	_menu_hover = button
	_update_hint()


func _leave_action(button: Button) -> void:
	if _menu_hover == button:
		_menu_hover = null
		_update_hint()


## 焦點順序照清單：上下鍵與 Tab 依序移動，左右不跳到別的選項。
func _link_focus(entries: Array[TagButton]) -> void:
	for i in entries.size():
		var tag := entries[i]
		var previous := entries[maxi(i - 1, 0)]
		var next := entries[mini(i + 1, entries.size() - 1)]
		tag.focus_neighbor_top = tag.get_path_to(previous)
		tag.focus_neighbor_bottom = tag.get_path_to(next)
		tag.focus_neighbor_left = NodePath(".")
		tag.focus_neighbor_right = NodePath(".")
		tag.focus_previous = tag.get_path_to(previous)
		tag.focus_next = tag.get_path_to(next)


## 選單排好後，說明放在最下面那一項的下面（水平，不跟著斜）。
func _layout_menu_list() -> void:
	if _hint != null:
		var bottom := 0.0
		for tag in _tags:
			bottom = maxf(bottom, tag.position.y + tag.size.y)
		_hint.position.y = bottom + 10.0
	_update_hint()


## 右邊的主角立繪（和背包同一個元件）：站在城市前面、朝左看著選單。
func _build_portrait() -> void:
	_portrait = SidePortrait.new()
	_portrait.facing = -1
	_portrait.anchor_left = PORTRAIT_ANCHORS[0]
	_portrait.anchor_top = PORTRAIT_ANCHORS[1]
	_portrait.anchor_right = PORTRAIT_ANCHORS[2]
	_portrait.anchor_bottom = PORTRAIT_ANCHORS[3]
	_ui.add_child(_portrait)
	_portrait.acquire()


## 「減少動態」切換時，吊牌直接回到該有的樣子。
func _sync_menu_motion() -> void:
	for tag in _tags:
		tag._refresh_active()


## 選單下方的說明：滑鼠指著的那一項優先，否則是焦點所在的那一項（吊牌自己處理轉正與往前）。
func _update_hint() -> void:
	var button := _menu_hover if is_instance_valid(_menu_hover) else _menu_focus
	if not is_instance_valid(button) or _hint == null:
		return
	_hint.text = button.tooltip_text


func _build_difficulty_page() -> void:
	_difficulty_page = Control.new()
	_difficulty_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_difficulty_page)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_difficulty_page.add_child(shade)

	var heading := UiKit.label(_text("difficulty"), UiKit.FS_TITLE, Palette.CYAN)
	heading.position = Vector2(36, 28)
	_difficulty_page.add_child(heading)
	var sub := UiKit.label(_text("difficulty_hint"), UiKit.FS_BODY, Palette.UI_MUTED)
	sub.position = Vector2(38, 60)
	_difficulty_page.add_child(sub)

	var body := VBoxContainer.new()
	body.position = Vector2(36, 86)
	body.add_theme_constant_override(&"separation", 6)
	_difficulty_page.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	body.add_child(row)
	var group := ButtonGroup.new()
	for difficulty in GameState.difficulties:
		var card := _make_difficulty_card(difficulty, group)
		row.add_child(card)
		_cards.append(card)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	body.add_child(buttons)
	_confirm_button = UiKit.button(_text("confirm"), _on_start, _text("confirm_hint"))
	_confirm_button.custom_minimum_size = Vector2(150, 26)
	buttons.add_child(_confirm_button)
	var back := UiKit.button(_text("back"), _on_back, _text("back_hint"))
	back.custom_minimum_size = Vector2(110, 26)
	buttons.add_child(back)
	_difficulty_legend = _add_legend(body)


static func _text(key: String) -> String:
	var index := maxi(0, StoryLocale.LANGUAGES.find(Story.language))
	return COPY[key][index]


func _add_legend(page: Control) -> Label:
	var legend := UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	page.add_child(legend)
	return legend


func _refresh_legends() -> void:
	_menu_legend.text = InputBindings.format(_text("menu_controls"))
	_difficulty_legend.text = InputBindings.format(_text("difficulty_controls"))


func _make_difficulty_card(difficulty: DifficultyData, group: ButtonGroup) -> UiCard:
	var card := UiCard.new(CARD_SIZE)
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = difficulty == _selected
	var description := difficulty.description_for(Story.language)
	card.tooltip_text = description
	card.add_text(difficulty.display_name_for(Story.language), UiKit.FS_TITLE, Palette.CYAN if difficulty == _selected else Palette.UI_TEXT)
	card.add_text(description, UiKit.FS_BODY, Palette.UI_MUTED, true)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.content.add_child(spacer)
	card.content.add_child(UiDivider.new())
	var lives := "%d" % difficulty.lives if difficulty.has_limited_lives() else _text("unlimited")
	card.add_text(_text("health_lives") % [difficulty.player_max_health, lives])
	card.add_text(_text("pace") % _pace_text(difficulty.enemy_cooldown_multiplier))
	card.add_text(_text("heals" if difficulty.checkpoint_heals else "no_heal"))
	card.pressed.connect(_select_difficulty.bind(difficulty))
	return card


## 敵人冷卻倍率轉成一個字：倍率越大敵人越慢。
static func _pace_text(cooldown_multiplier: float) -> String:
	if cooldown_multiplier >= 1.2:
		return _text("pace_slow")
	if cooldown_multiplier <= 0.9:
		return _text("pace_fast")
	return _text("pace_standard")


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
