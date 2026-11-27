class_name InventoryScreen
extends CanvasLayer
## 背包畫面：Tab／I 開關，開啟時遊戲暫停。分頁（武器與彈藥、改裝、消耗品、義體、劇情道具、角色狀態）
## Q／E 或滑鼠切換，方向鍵或滑鼠選擇，Enter／左鍵確認；每個操作都有一句提示顯示在底部。
## 版面（NE-244）：左側清單與詳情，右側一欄是信用點與凜的立繪（陪伴閱讀，不放操作）；自帶角色圖的分頁不顯示這一欄。
## 版面與輸入在這裡，分頁內容各自獨立（見 InventoryPage）；新增分頁只要在 _create_pages() 加一行。

signal opened
signal closed

const OPEN_TIME := 0.24
const CLOSE_TIME := 0.1
const PAGE_SLIDE := 22.0
const PAGE_SLIDE_TIME := 0.15
const MESSAGE_TIME := 2.4
const MARGIN := Vector2(24, 10)
const HEADER_HEIGHT := 34.0
const FOOTER_HEIGHT := 24.0
const TABS_LEFT := 96.0
const TAB_GAP := 4
const TAB_MAX_WIDTH := 104.0
const LEGEND_WIDTH := 292.0
## 右側立繪欄：寬度依立繪比例（約 1:3.2）與可用高度決定；欄與內容之間的間距。
## 拼貼版面（NE-403）：標題字級、標題底板比標題多出來的留白、分頁吊牌的傾斜（度，交錯）、信用點滾動的時間。
## NE-412：標題底板約是 NE-403 的兩倍；分頁吊牌從一條橫桿垂下來，繩長不同（往下多垂幾像素），開啟時輕輕晃一下再停。
const TITLE_SIZE := 34
const TITLE_PLATE_PAD := Vector2(34, 10)
const TAB_TILTS: Array[float] = [-2.5, 2.0, -1.5, 2.5, -2.0, 1.5]
const TAB_DROPS: Array[float] = [0.0, 3.0, 1.0, 4.0, 0.0, 2.0]
const TAB_HEIGHT := 26.0
## 橫桿在分頁上方幾像素。
const ROD_RISE := 7.0
const CREDITS_ROLL := 0.28
## 開啟時分頁吊牌依序彈入：第一張的延遲與間隔（最後一張也在 300 毫秒內停好）。
const TAB_INTRO_DELAY := 0.02
const TAB_INTRO_STEP := 0.015
const PORTRAIT_WIDTH := 104.0
const PORTRAIT_GAP := 8.0
const CREDITS_HEIGHT := 16.0
const Labels := preload("res://ui/inventory/inventory_labels.gd")

## 死亡或過關時由關卡關閉，避免和結算畫面同時出現。
var allowed := true
var player: Player

var _context: InventoryContext
var _pages: Array[InventoryPage] = []
var _current := 0
var _root: Control
var _frame: Control
var _title: Label
var _title_plate: CollagePlate
var _scan: ColorRect
var _tabs: HBoxContainer
var _rod: Control
var _tab_buttons: Array[TagButton] = []
var _page_host: Control
var _portrait: SidePortrait
var _credits: Label
var _hint_label: Label
var _legend_label: Label
var _message_left := 0.0
var _open_tween: Tween
var _page_tween: Tween
var _is_open := false


## 加入場景樹前呼叫。
func configure(p_player: Player) -> void:
	player = p_player


func _ready() -> void:
	# 高於劇情對話框，打開背包時蓋住通訊框而不是和它重疊（順序見 UiLayers）。
	layer = UiLayers.INVENTORY
	process_mode = Node.PROCESS_MODE_ALWAYS
	_context = InventoryContext.new(player)
	_context.message.connect(_show_message)
	_build_layout()
	_create_pages()
	InputBindings.bindings_changed.connect(_refresh_legend)
	Progression.credits_changed.connect(_on_credits_changed)
	_set_open_state(false)


func is_open() -> bool:
	return _is_open


func _input(event: InputEvent) -> void:
	AimInput.observe(event)
	if GameplayLock.is_locked():
		return
	if not _is_open:
		if allowed and _opens_with_key() and event.is_action_pressed(&"inventory") and _can_open():
			open()
			get_viewport().set_input_as_handled()
		return
	# The shared navigator owns stick edges, hold repeat and release.
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		return
	var handled := true
	if event.is_action_pressed(&"ui_cancel"):
		if not _pages[_current].handle_back():
			close()
	elif event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause"):
		close()
	elif event.is_action_pressed(&"inventory_prev_tab"):
		select_tab(posmod(_current - 1, _pages.size()))
	elif event.is_action_pressed(&"inventory_next_tab"):
		select_tab(posmod(_current + 1, _pages.size()))
	elif event.is_action_pressed(&"ui_up", true):
		_pages[_current].navigate(Vector2i(0, -1))
	elif event.is_action_pressed(&"ui_down", true):
		_pages[_current].navigate(Vector2i(0, 1))
	elif event.is_action_pressed(&"ui_left", true):
		_pages[_current].navigate(Vector2i(-1, 0))
	elif event.is_action_pressed(&"ui_right", true):
		_pages[_current].navigate(Vector2i(1, 0))
	elif event.is_action_pressed(&"ui_accept"):
		_pages[_current].activate()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_show_hint(_pages[_current].current_hint())


## 其他選單或過場暫停遊戲時、玩家已倒下時不能開背包。
func _can_open() -> bool:
	return not GameplayLock.is_locked() and not get_tree().paused and _context != null and _context.is_valid() and not Story.is_cinematic_active()


func open() -> void:
	if _is_open or not _can_open():
		return
	_is_open = true
	Fx.reset_time()
	get_tree().paused = true
	UiKit.set_cursor_visible(true)
	_set_open_state(true)
	_title.text = _screen_title()
	for page in _pages:
		page.visible = false
	_portrait.acquire()
	_show_page(_current, false)
	_refresh_tab_labels()
	_refresh_legend()
	_refresh_credits()
	_play_open_animation()
	Sfx.play(&"ui_confirm", -8.0, 0.0)
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	InputBindings.clear_held_inputs()
	_pages[_current].page_hidden()
	# 遊戲立刻繼續，關閉動畫只是視覺上的收合。
	get_tree().paused = false
	UiKit.set_cursor_visible(false)
	Sfx.play(&"ui_cancel", -8.0, 0.0)
	_play_close_animation()
	closed.emit()


## 某種分頁目前在第幾個位置（找不到回傳 -1）；測試與工具用它，不必寫死分頁順序。
func page_index(page_type: Script) -> int:
	for i in _pages.size():
		if _pages[i].get_script() == page_type:
			return i
	return -1


func select_tab(index: int) -> void:
	if index == _current or index < 0 or index >= _pages.size():
		return
	_pages[_current].page_hidden()
	_current = index
	Sfx.play(&"ui_move", -10.0, 0.0)
	_show_page(index, true)
	_refresh_tab_labels()


# ---------------------------------------------------------------------------
# 版面
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	_root = UiKit.full_rect_root(self)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(InventoryBackdrop.new())

	_frame = Control.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)
	_frame.resized.connect(func() -> void: _frame.pivot_offset = _frame.size * 0.5)

	# 標題放大、壓在斜切的招牌底板上（底板傾斜，字保持水平）。
	_title_plate = CollagePlate.new()
	_title_plate.tilt_degrees = -3.0
	_title_plate.skew = 10.0
	_title_plate.cut = 8.0
	_frame.add_child(_title_plate)
	_title = UiKit.label(_screen_title(), TITLE_SIZE, Palette.CYAN)
	_title.position = Vector2(MARGIN.x + 4.0, MARGIN.y - 1.0)
	_frame.add_child(_title)

	# 標題的字跟著底板一起斜。
	_title.resized.connect(func() -> void:
		_title.pivot_offset = _title.size * 0.5
		_title.rotation = deg_to_rad(_title_plate.tilt_degrees))

	# 分頁吊牌掛在一條橫桿上（橫桿畫在吊牌後面）。
	_rod = Control.new()
	_rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rod.draw.connect(_draw_rod)
	_frame.add_child(_rod)
	_tabs = HBoxContainer.new()
	_tabs.position = Vector2(TABS_LEFT, MARGIN.y)
	_tabs.add_theme_constant_override(&"separation", TAB_GAP)
	_frame.add_child(_tabs)
	_title.minimum_size_changed.connect(_layout_header)

	_page_host = Control.new()
	_page_host.position = Vector2(MARGIN.x, MARGIN.y + HEADER_HEIGHT + 8)
	_page_host.size = Vector2(640 - MARGIN.x * 2, 360 - MARGIN.y * 2 - HEADER_HEIGHT - FOOTER_HEIGHT - 14)
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_page_host)

	# 右側一欄：上面是信用點，下面是立繪；立繪停在說明列上方，不壓到底部的操作提示。
	var column_x := 640 - MARGIN.x - PORTRAIT_WIDTH
	_credits = UiKit.label("", 11, Palette.NEON_YELLOW, HORIZONTAL_ALIGNMENT_RIGHT)
	_credits.position = Vector2(column_x, _page_host.position.y)
	_credits.size = Vector2(PORTRAIT_WIDTH, CREDITS_HEIGHT)
	_credits.clip_text = true
	_credits.mouse_filter = Control.MOUSE_FILTER_PASS
	_frame.add_child(_credits)
	CollageDecal.attach(_credits, &"price", Palette.NEON_YELLOW)
	_portrait = SidePortrait.new()
	_frame.add_child(_portrait)
	_layout_side_column()

	_hint_label = UiKit.label("", 11, Palette.UI_TEXT)
	_hint_label.position = Vector2(MARGIN.x, 360 - MARGIN.y - FOOTER_HEIGHT + 2)
	_hint_label.size = Vector2(320, 18)
	_hint_label.clip_text = true
	# 放大文字時說明比狀態列長：用省略號收尾，不從字的中間切開（完整說明在右側細節）。
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_frame.add_child(_hint_label)
	_legend_label = UiKit.label("", 9, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_legend_label.position = Vector2(640 - MARGIN.x - LEGEND_WIDTH, 360 - MARGIN.y - FOOTER_HEIGHT + 4)
	_legend_label.size = Vector2(LEGEND_WIDTH, 16)
	_frame.add_child(_legend_label)

	# 開啟時掃過畫面中央的亮線（CRT 開機）。
	_scan = ColorRect.new()
	_scan.color = Color(0.8, 1.0, 1.0, 0.9)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.position = Vector2(0, 179)
	_scan.size = Vector2(640, 2)
	_scan.visible = false
	_root.add_child(_scan)


## 分頁是一排吊牌：微微傾斜、目前所在的那一張轉正往前（不取得焦點，和修前一樣只用 Q/E 與滑鼠切換）。
func _make_tab_button(index: int, width: float) -> TagButton:
	var button := TagButton.new()
	button.toggle_mode = false
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.text_margin = 11.0
	button.text_margin_right = 4.0
	button.hang_drop = TAB_DROPS[index % TAB_DROPS.size()]
	button.custom_minimum_size = Vector2(width, TAB_HEIGHT + button.hang_drop)
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.rod_y = -ROD_RISE
	button.tilt_degrees = TAB_TILTS[index % TAB_TILTS.size()]
	button.pressed.connect(func() -> void: select_tab(index))
	button.mouse_entered.connect(func() -> void: _show_hint(_pages[index].tab_tooltip()))
	return button


## 畫面標題（子類別可覆寫，例如補給點）。
func _screen_title() -> String:
	return Labels.get_text(&"pack_title")


## 底部右側的操作提示（可用 {動作} 佔位符）。
func _legend_template() -> String:
	var key := &"bag_pad" if InputBindings.using_gamepad else &"bag_keys"
	return Labels.get_text(key) % Labels.get_text(&"tabs")


func _refresh_legend() -> void:
	if _is_open:
		_legend_label.text = InputBindings.format(_legend_template())


## 這個畫面是否由背包鍵開啟（補給點之類由場景物件開啟的畫面覆寫成 false）。
func _opens_with_key() -> bool:
	return true


## 分頁清單。新增分頁在這裡加一行，標籤與切換會自動處理。子類別可覆寫成自己的分頁。
func _build_pages() -> Array[InventoryPage]:
	return [WeaponsPage.new(), UpgradesPage.new(), ConsumablesPage.new(), CyberPage.new(), StoryItemsPage.new(), StatusPage.new()]


func _create_pages() -> void:
	var pages := _build_pages()
	# 分頁標籤的寬度依分頁數量自動縮放，塞得進畫面。
	var available := 640.0 - TABS_LEFT - MARGIN.x
	var tab_width := minf(TAB_MAX_WIDTH, (available - TAB_GAP * (pages.size() - 1)) / pages.size())
	for i in pages.size():
		var button := _make_tab_button(i, tab_width)
		_tabs.add_child(button)
		_tab_buttons.append(button)
		var page := pages[i]
		page.bind(_context)
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.hint_changed.connect(_on_page_hint.bind(i))
		page.visible = false
		_page_host.add_child(page)
		_pages.append(page)
	# 只有一個分頁（補給點）時不需要分頁標籤。
	_tabs.visible = pages.size() > 1
	_rod.visible = _tabs.visible
	_refresh_tab_labels()


## Counter names can be wider than the bag title, including after text-size changes.
func _layout_header() -> void:
	var title_size := _title.get_combined_minimum_size()
	_title_plate.position = _title.position - TITLE_PLATE_PAD * Vector2(0.5, 0.5) - Vector2(6, 0)
	_title_plate.size = title_size + TITLE_PLATE_PAD
	if _tab_buttons.is_empty():
		return
	_tabs.position.x = maxf(TABS_LEFT, _title.position.x + _title.get_combined_minimum_size().x + 12.0)
	var available := maxf(0.0, 640.0 - _tabs.position.x - MARGIN.x - TAB_GAP * (_tab_buttons.size() - 1))
	var preferred := minf(TAB_MAX_WIDTH, available / _tab_buttons.size())
	var needed := 0.0
	var padding := 0.0
	for button in _tab_buttons:
		var natural := button.get_minimum_size().x
		needed += natural
		padding += maxf(0.0, preferred - natural)
	# Wide captions use their intrinsic width. Use the remaining space for shorter tabs.
	var share := clampf((available - needed) / padding, 0.0, 1.0) if padding > 0.0 else 0.0
	for button in _tab_buttons:
		var natural := button.get_minimum_size().x
		button.custom_minimum_size.x = natural + maxf(0.0, preferred - natural) * share
	_rod.position = _tabs.position - Vector2(6.0, ROD_RISE + 2.0)
	_rod.size = Vector2(640.0 - MARGIN.x - _rod.position.x + 4.0, 6.0)
	_rod.queue_redraw()


## 分頁上方的橫桿：一條金屬桿，兩端有固定座。
func _draw_rod() -> void:
	var y := 2.0
	_rod.draw_line(Vector2(0, y), Vector2(_rod.size.x, y), Color(Palette.UI_MUTED, 0.75), 2.0)
	_rod.draw_line(Vector2(0, y - 1.0), Vector2(_rod.size.x, y - 1.0), Color(1, 1, 1, 0.12), 1.0)
	for x in [2.0, _rod.size.x - 2.0]:
		_rod.draw_circle(Vector2(x, y), 2.5, Color(Palette.UI_MUTED, 0.9))


func _refresh_tab_labels() -> void:
	for i in _pages.size():
		var button := _tab_buttons[i]
		var selected := i == _current
		button.text = _pages[i].tab_title() + (" ●" if _pages[i].tab_has_alert() and not selected else "")
		button.tooltip_text = _pages[i].tab_tooltip()
		button.pinned = selected
		var alert := _pages[i].tab_has_alert() and not selected
		button.accent = Palette.MAGENTA if alert else Palette.CYAN
		button.add_theme_color_override(&"font_color", Palette.CYAN if selected else (Palette.MAGENTA if alert else Palette.UI_MUTED))
		button.add_theme_color_override(&"font_hover_color", Palette.CYAN)
	_layout_header()


func _show_page(index: int, animate: bool) -> void:
	var page := _pages[index]
	for other in _pages:
		other.visible = other == page
	# 自帶角色圖的分頁（角色狀態）用整個寬度，右側欄收起，避免同時出現兩個凜。
	var side := page.shows_side_portrait()
	_portrait.visible = side
	_credits.visible = side
	_page_host.size.x = 640 - MARGIN.x * 2 - (PORTRAIT_WIDTH + PORTRAIT_GAP if side else 0.0)
	if side:
		_layout_side_column()
	page.page_shown(animate)
	if _page_tween != null and _page_tween.is_valid():
		_page_tween.kill()
	page.position = Vector2.ZERO
	page.modulate.a = 1.0
	if animate and not Settings.get_reduce_ui_motion():
		page.position.x = PAGE_SLIDE
		page.modulate.a = 0.0
		_page_tween = create_tween().set_parallel(true)
		_page_tween.tween_property(page, "position:x", 0.0, PAGE_SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_page_tween.tween_property(page, "modulate:a", 1.0, PAGE_SLIDE_TIME)
	_show_hint(page.current_hint())


# ---------------------------------------------------------------------------
# 說明列與訊息
# ---------------------------------------------------------------------------

func _on_page_hint(text: String, page_index: int) -> void:
	if page_index == _current and _message_left <= 0.0:
		_show_hint(text)


func _show_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.add_theme_color_override(&"font_color", Palette.UI_TEXT)


func _show_message(text: String, is_warning: bool) -> void:
	_hint_label.text = text
	_hint_label.add_theme_color_override(&"font_color", Palette.WARNING if is_warning else Palette.CYAN)
	_message_left = MESSAGE_TIME
	_refresh_tab_labels()


# ---------------------------------------------------------------------------
# 開關動畫
# ---------------------------------------------------------------------------

## 立繪從信用點那一行的下面開始（放大文字時那一行會變高），停在說明列上方。
func _layout_side_column() -> void:
	var column_x := 640 - MARGIN.x - PORTRAIT_WIDTH
	var credits_height := maxf(CREDITS_HEIGHT, _credits.get_combined_minimum_size().y)
	_credits.size = Vector2(PORTRAIT_WIDTH, credits_height)
	var top := _page_host.position.y + credits_height + 4.0
	_portrait.position = Vector2(column_x, top)
	_portrait.size = Vector2(PORTRAIT_WIDTH, _page_host.position.y + _page_host.size.y - top)


## 信用點改變時數字滾動到新的值（「減少動態」時直接顯示）。
func _on_credits_changed(credits_now: int, delta: int) -> void:
	if not _is_open:
		return
	_refresh_credits()
	if delta != 0:
		UiMotion.count_up(_credits, credits_now - delta, credits_now, CREDITS_ROLL, Labels.get_text(&"credits"))


func _refresh_credits() -> void:
	if _is_open:
		_credits.text = Labels.get_text(&"credits") % Progression.credits
		_credits.tooltip_text = Labels.get_text(&"credits_help")


## 關閉時停用所有子節點的處理，背包不佔 CPU；立繪貼圖也一併放掉。
func _set_open_state(open_state: bool) -> void:
	if not open_state and _portrait != null:
		_portrait.release()
	_root.visible = open_state
	_root.process_mode = Node.PROCESS_MODE_ALWAYS if open_state else Node.PROCESS_MODE_DISABLED
	set_process(open_state)


func _play_open_animation() -> void:
	_kill_open_tween()
	if Settings.get_reduce_ui_motion():
		_frame.scale = Vector2.ONE
		_frame.modulate = Color.WHITE
		_root.modulate.a = 1.0
		_scan.visible = false
		return
	_frame.scale = Vector2(1.0, 0.03)
	_frame.modulate = Color(1, 1, 1, 0)
	# 標題底板斜切進來、分頁吊牌依序彈入。
	_title_plate.intro(0.04)
	for i in _tab_buttons.size():
		_tab_buttons[i].intro(TAB_INTRO_DELAY + TAB_INTRO_STEP * i)
		_tab_buttons[i].swing(0.0, 1.0 if i % 2 == 0 else -0.8)
	_root.modulate.a = 0.0
	_scan.visible = not Settings.get_reduce_flashes()
	_scan.modulate.a = 1.0
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_root, "modulate:a", 1.0, 0.1)
	_open_tween.tween_property(_frame, "scale:y", 1.0, OPEN_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_frame, "modulate", Color.WHITE, OPEN_TIME + 0.1)
	_open_tween.tween_property(_scan, "modulate:a", 0.0, OPEN_TIME)
	_open_tween.chain().tween_callback(func() -> void: _scan.visible = false)


func _play_close_animation() -> void:
	_kill_open_tween()
	if Settings.get_reduce_ui_motion():
		_set_open_state(false)
		return
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_frame, "scale:y", 0.03, CLOSE_TIME).set_ease(Tween.EASE_IN)
	_open_tween.tween_property(_root, "modulate:a", 0.0, CLOSE_TIME)
	_open_tween.chain().tween_callback(func() -> void:
		if not _is_open:
			_set_open_state(false))


func _kill_open_tween() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
