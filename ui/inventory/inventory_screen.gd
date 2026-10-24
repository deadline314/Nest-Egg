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
const PORTRAIT_WIDTH := 104.0
const PORTRAIT_GAP := 8.0
const CREDITS_HEIGHT := 16.0
const LEGEND_TEMPLATE := "{inventory} 關閉　{inventory_prev_tab}/{inventory_next_tab} 分頁　↑↓ 選擇　{ui_accept} 確認"

## 死亡或過關時由關卡關閉，避免和結算畫面同時出現。
var allowed := true
var player: Player

var _context: InventoryContext
var _pages: Array[InventoryPage] = []
var _current := 0
var _root: Control
var _frame: Control
var _scan: ColorRect
var _tabs: HBoxContainer
var _tab_buttons: Array[Button] = []
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

	var title := UiKit.label(_screen_title(), 18, Palette.CYAN)
	title.position = Vector2(MARGIN.x, MARGIN.y + 2)
	_frame.add_child(title)

	_tabs = HBoxContainer.new()
	_tabs.position = Vector2(TABS_LEFT, MARGIN.y)
	_tabs.add_theme_constant_override(&"separation", TAB_GAP)
	_frame.add_child(_tabs)

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
	_credits.tooltip_text = "目前持有的信用點；商店、改裝、義體與典當都用它。"
	_frame.add_child(_credits)
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


func _make_tab_button(index: int, width: float) -> Button:
	var button := Button.new()
	button.toggle_mode = false
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 26)
	button.pressed.connect(func() -> void: select_tab(index))
	button.mouse_entered.connect(func() -> void: _show_hint(_pages[index].tab_tooltip()))
	return button


## 畫面標題（子類別可覆寫，例如補給點）。
func _screen_title() -> String:
	return "背包"


## 底部右側的操作提示（可用 {動作} 佔位符）。
func _legend_template() -> String:
	if InputBindings.using_gamepad:
		return "{ui_cancel} 返回　{inventory_prev_tab}/{inventory_next_tab} 分頁　{ui_accept} 確認"
	return LEGEND_TEMPLATE


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
		_tab_buttons[i].tooltip_text = page.tab_tooltip()
	# 只有一個分頁（補給點）時不需要分頁標籤。
	_tabs.visible = pages.size() > 1
	_refresh_tab_labels()


func _refresh_tab_labels() -> void:
	for i in _pages.size():
		var button := _tab_buttons[i]
		var selected := i == _current
		button.text = _pages[i].tab_title() + (" ●" if _pages[i].tab_has_alert() and not selected else "")
		button.add_theme_stylebox_override(&"normal", UiKit.tab_style(selected))
		button.add_theme_stylebox_override(&"hover", UiKit.tab_style(true))
		button.add_theme_stylebox_override(&"pressed", UiKit.tab_style(true))
		var alert := _pages[i].tab_has_alert() and not selected
		button.add_theme_color_override(&"font_color", Palette.CYAN if selected else (Palette.MAGENTA if alert else Palette.UI_MUTED))
		button.add_theme_color_override(&"font_hover_color", Palette.CYAN)


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


func _on_credits_changed(_credits_now: int, _delta: int) -> void:
	_refresh_credits()


func _refresh_credits() -> void:
	if _is_open:
		_credits.text = "信用點　¥%d" % Progression.credits


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
