class_name QuestMapScreen
extends Control
## 任務與地圖共用單一覆蓋畫面；返回路徑保存頁面與焦點。
## 版面（design/18-quest-map-ux/VISUAL_RESEARCH.md 範本 A＋B）：模糊壓暗的遊戲畫面當底，
## 頁首一條分頁列（兩側標切換鍵）、頁尾一條按鍵提示列；任務頁左清單右細節，地圖頁左資訊右地圖。

signal closed
const LIST_WIDTH := 200.0
const INFO_WIDTH := 116.0
const FILTERS := [["進行中", "active"], ["已完成", "completed"], ["全部", "all"], ["主線", "main"], ["支線", "side"]]
const PAGES := ["quests", "region", "world"]
const PAGE_NAMES := {"quests": "任務", "region": "區域地圖", "world": "世界地圖"}
const PAGE_TIPS := {"quests": "查看任務步驟與釘選目標。", "region": "查看目前區域及已探索的地點。", "world": "查看區域之間的真實出入口連接。"}
const LEGEND := [["player", "你的位置", "主角目前在這裡。"], ["goal", "追蹤目標", "前往這裡完成追蹤中的步驟。"], ["exit", "出入口", "從出入口前往其他區域。"], ["checkpoint", "復原點", "啟用後可從這裡重新開始。"], ["shop", "商店", "在商店查看補給與服務。"], ["pickup", "拾取點", "探索附近後可查看拾取地點。"], ["gate", "閘門", "選擇閘門圖示查看通行條件。"]]

var catalog: QuestCatalog
var maps: QuestMapIndex
var state: QuestMapState
var chapter := ""
var player_path := ""
var player_position := Vector2.ZERO
var world: Dictionary = {}
var start_page := "quests"
var _page := ""
var _kind := "all"
var _completed := false
var _selected := ""
var _display_language := ""
var _map_path := ""
var _history: Array[Dictionary] = []
var _body: Control
var _status: Label
var _canvas: QuestMapCanvas
var _list: VBoxContainer
var _details: VBoxContainer
## 任務細節的操作（釘選、前往地圖）固定在細節下方，不跟著內文捲走或被裁掉一半。
var _actions: HFlowContainer
## 獎勵接在目標清單後面；內文比畫面長時，捲動提示會告訴玩家下面還有內容。
var _reward: Label
var _detail_scroll: ScrollContainer
## 細節較長時，操作列尾端說明怎麼往下讀（手把聚焦在按鈕上，內文本身沒有焦點）。
var _scroll_note: Label
var _details_overflow := false
var _detail_head: VBoxContainer
var _title: Label
var _area_caption: Label
var _tabs: HBoxContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	_display_language = Story.language
	# 本頁底部已有聚焦說明，疊在暫停頁裡時不讓暫停頁的說明列重複顯示。
	add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.fill_parent(self)
	theme = UiKit.theme()
	# 模糊壓暗的遊戲畫面：背景 HUD 讀不出字，不會在分頁列後面透出。
	add_child(SceneBackdrop.new())
	var layout := VBoxContainer.new()
	UiKit.fill_parent(layout)
	layout.offset_left = 16
	layout.offset_top = 6
	layout.offset_right = -16
	layout.offset_bottom = -5
	layout.add_theme_constant_override(&"separation", 5)
	add_child(layout)
	layout.add_child(_build_header())
	layout.add_child(FlatStyle.rule(Color(Palette.CYAN_DIM, 0.6)))
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_body)
	layout.add_child(FlatStyle.rule())
	layout.add_child(_build_footer())
	_map_path = player_path
	InputBindings.device_changed.connect(_on_device_changed)
	InputBindings.bindings_changed.connect(_refresh_prompts)
	show_page(start_page, false)


func _process(_delta: float) -> void:
	if _display_language == Story.language:
		return
	_display_language = Story.language
	var owner := get_viewport().gui_get_focus_owner()
	var owned_focus := owner != null and is_ancestor_of(owner)
	var focus_key := _focus_text() if owned_focus else ""
	var scroll := _detail_scroll.scroll_vertical if is_instance_valid(_detail_scroll) else 0
	_build(owned_focus)
	if owned_focus:
		_restore_focus.call_deferred(focus_key)
	if is_instance_valid(_detail_scroll):
		_detail_scroll.set_deferred(&"scroll_vertical", scroll)


func _exit_tree() -> void:
	if InputBindings.device_changed.is_connected(_on_device_changed):
		InputBindings.device_changed.disconnect(_on_device_changed)
	if InputBindings.bindings_changed.is_connected(_refresh_prompts):
		InputBindings.bindings_changed.disconnect(_refresh_prompts)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 20
	_title = UiKit.caption("導覽終端", Palette.CYAN)
	_title.custom_minimum_size.x = 150
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override(&"separation", 8)
	header.add_child(_tabs)
	_area_caption = UiKit.caption(_area_name(player_path), Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_area_caption.custom_minimum_size.x = 150
	_area_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_area_caption)
	return header


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 14
	footer.add_theme_constant_override(&"separation", 10)
	_status = UiKit.caption("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(_status)
	footer.add_child(FlatStyle.prompt(&"ui_accept", "選擇", Callable(), "確認目前選取的項目。"))
	footer.add_child(FlatStyle.prompt(&"ui_cancel", "返回", go_back, "返回上一層畫面。"))
	return footer


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"inventory_next_tab") or event.is_action_pressed(&"inventory_prev_tab"):
		var offset := 1 if event.is_action_pressed(&"inventory_next_tab") else -1
		show_page(PAGES[posmod(PAGES.find(_page) + offset, PAGES.size())])
		get_viewport().set_input_as_handled()
	elif _page == "quests" and is_instance_valid(_detail_scroll):
		# 任務細節沒有可聚焦的內文；右搖桿與 PageUp／PageDown 直接捲動它，焦點留在原本的按鈕上。
		var direction := 1 if event.is_action_pressed(&"aim_down") or event.is_action_pressed(&"ui_page_down") else -1 if event.is_action_pressed(&"aim_up") or event.is_action_pressed(&"ui_page_up") else 0
		if direction != 0 and ScrollCue.step(_detail_scroll, direction):
			get_viewport().set_input_as_handled()


func show_page(page: String, remember := true) -> void:
	if _page == page:
		return
	if remember and not _page.is_empty():
		_history.append({"page": _page, "map_path": _map_path, "selected": _selected, "focus_text": _focus_text()})
	_page = page
	_build()


func go_back() -> void:
	if not _history.is_empty():
		var previous: Dictionary = _history.pop_back()
		_page = previous["page"]
		_map_path = previous["map_path"]
		_selected = previous["selected"]
		_build()
		_restore_focus.call_deferred(str(previous.get("focus_text", "")))
	else:
		closed.emit()
		queue_free()


func _build(focus_first := true) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_canvas = null
	_details = null
	_actions = null
	_reward = null
	_detail_scroll = null
	_scroll_note = null
	_detail_head = null
	_title.text = "導覽終端　%s" % PAGE_NAMES.get(_page, "")
	_build_tabs()
	if _page == "quests":
		_build_quests()
	else:
		_build_map()
	_bind_hints(self)
	if focus_first and not _buttons.is_empty():
		_focus_first.call_deferred()


func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var prev := FlatStyle.keycap(InputBindings.primary_label(&"inventory_prev_tab"))
	prev.set_meta(&"prompt_action", &"inventory_prev_tab")
	_tabs.add_child(prev)
	for page: String in PAGES:
		var tab := UiKit.button(PAGE_NAMES[page], show_page.bind(page), PAGE_TIPS[page])
		FlatStyle.tab(tab, page == _page)
		_tabs.add_child(tab)
	var next := FlatStyle.keycap(InputBindings.primary_label(&"inventory_next_tab"))
	next.set_meta(&"prompt_action", &"inventory_next_tab")
	_tabs.add_child(next)


# ---------------------------------------------------------------------------
# 任務頁
# ---------------------------------------------------------------------------

func _build_quests() -> void:
	var columns := HBoxContainer.new()
	UiKit.fill_parent(columns)
	columns.add_theme_constant_override(&"separation", 14)
	_body.add_child(columns)
	columns.add_child(_build_list_column())
	var divider := ColorRect.new()
	divider.color = FlatStyle.LINE
	divider.custom_minimum_size.x = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(divider)
	columns.add_child(_build_detail_column())
	var quests := catalog.list_for(chapter, _kind, _completed, GameState.world_flags)
	if quests.is_empty():
		_wrapped(_list, "目前沒有已完成的任務。" if _completed else "目前尚無可追蹤的任務。", Palette.UI_MUTED)
		_wrapped(_details, "開啟區域地圖，查看你走過的路與出入口。")
		_status.text = "使用方向鍵或搖桿選擇，按確認鍵開啟，按返回鍵回上一層。"
		return
	if not quests.any(func(q: Dictionary) -> bool: return q["id"] == _selected):
		_selected = quests[0]["id"]
	var group := ""
	for quest in quests:
		if _kind == "all" and quest["kind"] != group:
			group = quest["kind"]
			_list.add_child(FlatStyle.section("主線" if group == "main" else "支線"))
		_list.add_child(_quest_row(quest))
	_select(_selected)


func _build_list_column() -> Control:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = LIST_WIDTH
	left.add_theme_constant_override(&"separation", 6)
	# 狀態（進行中／已完成）與種類（全部／主線／支線）各是一組；放不下時整組換行，不把一顆按鈕單獨擠到下一行。
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override(&"h_separation", 8)
	filters.add_theme_constant_override(&"v_separation", 2)
	left.add_child(filters)
	var counts := _counts()
	var group: HBoxContainer = null
	for entry: Array in FILTERS:
		var key: String = entry[1]
		if group == null or key == "all":
			group = HBoxContainer.new()
			group.add_theme_constant_override(&"separation", 2)
			filters.add_child(group)
		var on := (_completed if key == "completed" else not _completed if key == "active" else _kind == key)
		var text: String = entry[0]
		if key in ["active", "completed"]:
			text = "%s %d" % [text, counts[key]]
		var button := UiKit.button(text, _filter.bind(key), "顯示%s任務。" % entry[0])
		button.toggle_mode = true
		button.button_pressed = on
		FlatStyle.chip(button, on)
		button.set_meta(&"nav_key", "filter:" + key)
		group.add_child(button)
		_buttons.append(button)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	list_scroll.add_child(_list)
	ScrollCue.attach(list_scroll)
	return left


func _build_detail_column() -> Control:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 4)
	_detail_head = VBoxContainer.new()
	_detail_head.add_theme_constant_override(&"separation", 1)
	right.add_child(_detail_head)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_scroll)
	_detail_scroll = detail_scroll
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override(&"separation", 3)
	detail_scroll.add_child(_details)
	ScrollCue.attach(detail_scroll).overflow_changed.connect(_on_details_overflow)
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override(&"h_separation", 4)
	_actions.add_theme_constant_override(&"v_separation", 3)
	right.add_child(_actions)
	return right


## 清單列：一行標題、下方小字寫地點與進度；追蹤中的任務另標洋紅小字。
func _quest_row(quest: Dictionary) -> Button:
	var status := QuestCatalog.status(quest, GameState.world_flags)
	var symbol := "✓" if status == "completed" else "▣" if status == "blocked" else "◆" if quest["kind"] == "main" else "◇"
	var localized_title := QuestCatalog.display_text(quest, "title")
	var button := UiKit.button("%s %s" % [symbol, localized_title], _select.bind(quest["id"], true), "查看%s的步驟與地點。" % localized_title)
	FlatStyle.row(button, quest["id"] == _selected)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.y = UiKit.scaled_size(UiKit.FS_BODY) + FlatStyle.row_caption_space() + 6
	button.set_meta(&"quest_id", quest["id"])
	button.set_meta(&"nav_key", "quest:" + str(quest["id"]))
	var meta := UiKit.caption(_progress_text(quest))
	button.add_child(meta)
	# 小字貼在列的下緣，文字放大時跟著列高往下移，不壓到標題。
	var place_meta := func() -> void: meta.position = Vector2(14, button.size.y - meta.get_minimum_size().y - 2)
	button.resized.connect(place_meta)
	meta.resized.connect(place_meta)
	var labels: Array[Label] = [meta]
	var colors: Array[Color] = [Palette.UI_MUTED]
	if state.pinned_id == quest["id"]:
		var pinned := UiKit.caption("追蹤中", Palette.MAGENTA, HORIZONTAL_ALIGNMENT_RIGHT)
		button.add_child(pinned)
		pinned.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
		pinned.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		pinned.grow_vertical = Control.GROW_DIRECTION_BEGIN
		pinned.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		pinned.offset_left -= 6
		pinned.offset_right -= 6
		pinned.offset_top -= 2
		pinned.offset_bottom -= 2
		labels.append(pinned)
		colors.append(Palette.MAGENTA)
	FlatStyle.follow_row_focus(button, labels, colors)
	_buttons.append(button)
	return button


func _progress_text(quest: Dictionary) -> String:
	var steps: Array = quest["steps"]
	var done := 0
	for step: Dictionary in steps:
		if QuestCatalog.flag_set(GameState.world_flags, str(step["complete_flag"])):
			done += 1
	var step := QuestCatalog.current_step(quest, GameState.world_flags)
	if step.is_empty() and not steps.is_empty():
		step = steps.back()
	return "%s　%d／%d" % [_area_name(str(step.get("location", {}).get("level", ""))), done, steps.size()]


func _counts() -> Dictionary:
	return {"active": catalog.list_for(chapter, "all", false, GameState.world_flags).size(), "completed": catalog.list_for(chapter, "all", true, GameState.world_flags).size()}


func _filter(value: String) -> void:
	if value in ["active", "completed"]:
		_completed = value == "completed"
	else:
		_kind = value
	_selected = ""
	_build()
	_restore_focus.call_deferred("filter:" + value)


func _select(id: String, focus_details := false) -> void:
	_selected = id
	for box: Control in [_detail_head, _details, _actions]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for row in _list.get_children():
		if row is Button and row.has_meta(&"quest_id"):
			FlatStyle.row(row, row.get_meta(&"quest_id") == id)
	var quest := catalog.find(id)
	if quest.is_empty():
		return
	var status := QuestCatalog.status(quest, GameState.world_flags)
	var pinned := state.pinned_id == id
	var kind_text := "主線任務" if quest["kind"] == "main" else "支線任務"
	var status_text: String = {"completed": "已完成", "blocked": "暫時卡住"}.get(status, "進行中")
	if pinned:
		status_text += "　·　追蹤中"
	_detail_head.add_child(UiKit.caption("%s　／　%s" % [kind_text, status_text], Palette.MAGENTA if pinned else Palette.CYAN))
	var title := UiKit.heading(QuestCatalog.display_text(quest, "title"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_head.add_child(title)
	var step := QuestCatalog.current_step(quest, GameState.world_flags)
	if step.is_empty():
		step = quest["steps"].back()
	var location: Dictionary = step["location"]
	_detail_head.add_child(UiKit.caption("◎ 目的地：%s" % _area_name(location["level"])))
	if status == "blocked":
		_details.add_child(SlantBanner.new(QuestCatalog.display_text(quest, "blocked_reason"), Palette.WARNING))
		_wrapped(_details, QuestCatalog.display_text(quest, "suggestion"))
	elif status != "completed":
		# 現在要做的那一件事用斜切橫幅（範本 B），一眼看到下一步。
		_details.add_child(SlantBanner.new("▶ " + QuestCatalog.display_text(step, "title"), Palette.MAGENTA if pinned else Palette.CYAN))
	_details.add_child(FlatStyle.section("背景"))
	_wrapped(_details, QuestCatalog.display_text(quest, "background"), Color(Palette.UI_TEXT, 0.85))
	var steps: Array = quest["steps"]
	var done := 0
	for entry: Dictionary in steps:
		if QuestCatalog.flag_set(GameState.world_flags, str(entry["complete_flag"])):
			done += 1
	_details.add_child(FlatStyle.section("目標　%d／%d" % [done, steps.size()]))
	for entry: Dictionary in steps:
		var complete: bool = QuestCatalog.flag_set(GameState.world_flags, str(entry["complete_flag"]))
		var current := not complete and entry == step
		var prefix := "✓ " if complete else "▶ " if current else "○ "
		var color := Color(Palette.UI_MUTED, 0.7) if complete else Palette.CYAN if current else Palette.UI_MUTED
		_wrapped(_details, prefix + QuestCatalog.display_text(entry, "title"), color)
	if not QuestCatalog.display_text(quest, "reward").is_empty():
		_details.add_child(FlatStyle.section("獎勵"))
		_reward = _wrapped(_details, QuestCatalog.display_text(quest, "reward"), Palette.NEON_YELLOW)
	_detail_scroll.scroll_vertical = 0
	if status != "completed":
		var pin := UiKit.button("取消釘選" if pinned else "釘選這項任務", _pin.bind(id), "讓目標列與方向箭頭追蹤這項任務。")
		FlatStyle.chip(pin)
		_actions.add_child(pin)
	var data: LevelData = maps.areas.get(location["level"], {}).get("data")
	if data != null:
		var jump := UiKit.button("前往%s的地圖" % data.display_name, _jump_to_map.bind(location["level"]), "查看選中任務的目的地，返回後回到任務細節。")
		FlatStyle.chip(jump)
		_actions.add_child(jump)
	_scroll_note = UiKit.caption("右搖桿／PageDown 往下讀")
	_scroll_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scroll_note.visible = _details_overflow
	_actions.add_child(_scroll_note)
	_link_actions()
	_bind_hints(_details)
	_bind_hints(_actions)
	if focus_details:
		_focus_details.call_deferred()


func _on_details_overflow(below: bool, above: bool) -> void:
	_details_overflow = below or above
	if is_instance_valid(_scroll_note):
		_scroll_note.visible = _details_overflow


func _pin(id: String) -> void:
	state.pin("" if state.pinned_id == id else id, catalog)
	# 追蹤狀態也顯示在清單列上，重建清單後焦點回到釘選按鈕。
	_build()
	_restore_focus.call_deferred("取消釘選" if state.pinned_id == id else "釘選這項任務")


func _jump_to_map(path: String) -> void:
	_history.append({"page": _page, "map_path": _map_path, "selected": _selected, "focus_text": _focus_text()})
	_map_path = path
	_page = "region"
	_build()


# ---------------------------------------------------------------------------
# 地圖頁
# ---------------------------------------------------------------------------

func _build_map() -> void:
	var data: LevelData = maps.areas.get(_map_path, {}).get("data")
	var columns := HBoxContainer.new()
	UiKit.fill_parent(columns)
	columns.add_theme_constant_override(&"separation", 10)
	_body.add_child(columns)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = INFO_WIDTH
	info.add_theme_constant_override(&"separation", 3)
	columns.add_child(info)
	var world_mode := _page == "world"
	info.add_child(UiKit.caption("第一章的區域" if world_mode else "目前區域" if _map_path == player_path else "查看中的區域", Palette.CYAN))
	var heading := UiKit.heading("世界地圖" if world_mode else data.display_name if data != null else "尚未載入區域")
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(heading)
	var stats := UiKit.caption("")
	info.add_child(stats)
	if not world_mode:
		var tools := HFlowContainer.new()
		tools.add_theme_constant_override(&"h_separation", 2)
		tools.add_theme_constant_override(&"v_separation", 2)
		info.add_child(tools)
		for entry: Array in [["放大", _zoom.bind(2.0), "放大區域地圖，中心對準玩家位置。"], ["縮小", _zoom.bind(0.5), "縮小區域地圖，查看更遠的路。"], ["回到所在區域", _here, "顯示主角目前所在的區域。"]]:
			var tool := UiKit.button(entry[0], entry[1], entry[2])
			FlatStyle.chip(tool)
			tools.add_child(tool)
			_buttons.append(tool)
	info.add_child(FlatStyle.section("圖例"))
	for item: Array in LEGEND:
		var button := UiKit.button("　 " + str(item[1]), Callable(), item[2])
		FlatStyle.chip(button)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var glyph := UiKit.caption(QuestMapCanvas.SYMBOLS[item[0]], QuestMapCanvas.COLORS[item[0]])
		glyph.position = Vector2(5, 1)
		button.add_child(glyph)
		info.add_child(button)
		_buttons.append(button)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame_box := StyleBoxFlat.new()
	frame_box.bg_color = Color(0.01, 0.02, 0.035, 0.96)
	frame_box.set_border_width_all(1)
	frame_box.border_color = Color(Palette.CYAN_DIM, 0.45)
	frame.add_theme_stylebox_override(&"panel", frame_box)
	columns.add_child(frame)
	_canvas = QuestMapCanvas.new()
	_canvas.maps = maps
	_canvas.state = state
	_canvas.path = _map_path
	_canvas.player_path = player_path
	_canvas.player_position = player_position
	_canvas.world_mode = world_mode
	_canvas.flags = GameState.world_flags
	_canvas.world = world
	var quest := catalog.find(_selected) if not _selected.is_empty() else state.target(catalog, chapter, GameState.world_flags)
	var step := QuestCatalog.current_step(quest, GameState.world_flags)
	if step.is_empty() and not quest.is_empty():
		step = quest["steps"].back()
	_canvas.goal = step.get("location", {})
	_canvas.marker_selected.connect(func(text: String) -> void: _status.text = text)
	_canvas.area_selected.connect(_jump_to_map)
	_canvas.refreshed.connect(func() -> void: stats.text = _map_stats(world_mode))
	frame.add_child(_canvas)
	_status.text = "未探索處只顯示外框；選擇圖示可以閱讀說明。"
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.refresh.call_deferred()


func _map_stats(world_mode: bool) -> String:
	if world_mode:
		var visited := 0
		for path: String in maps.areas:
			if state.explored.has(path):
				visited += 1
		return "去過 %d／%d 個區域" % [visited, maps.areas.size()]
	return "已探索 %d%%" % roundi(_canvas.explored_ratio * 100.0) if _canvas != null else ""


func _zoom(factor: float) -> void:
	_canvas.zoom = clampf(_canvas.zoom * factor, 1, 4)
	_canvas.refresh()


func _here() -> void:
	_map_path = player_path
	_build()


# ---------------------------------------------------------------------------
# 共用
# ---------------------------------------------------------------------------

func _area_name(path: String) -> String:
	var data: LevelData = maps.areas.get(path, {}).get("data") if maps != null else null
	return data.display_name if data != null else ""


static func _wrapped(parent: Control, text: String, color := Palette.UI_TEXT) -> Label:
	var label := UiKit.label(text, UiKit.FS_BODY, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _bind_hints(node: Node) -> void:
	if node is Control and not node.tooltip_text.is_empty():
		var control := node as Control
		if not control.has_meta("quest_hint"):
			control.set_meta("quest_hint", true)
			control.focus_entered.connect(func() -> void: _status.text = control.tooltip_text)
			control.mouse_entered.connect(func() -> void: _status.text = control.tooltip_text)
	for child in node.get_children():
		_bind_hints(child)


func _on_device_changed(_gamepad: bool, _device: int) -> void:
	_refresh_prompts()


func _refresh_prompts() -> void:
	FlatStyle.refresh_prompts(self)


func _focus_first() -> void:
	if not _buttons.is_empty() and is_instance_valid(_buttons[0]) and _buttons[0].is_inside_tree():
		_buttons[0].grab_focus()


## 焦點的識別：有 nav_key 的按鈕（文字含數量的分段）用它，其餘用按鈕文字。
func _focus_text() -> String:
	var owner := get_viewport().gui_get_focus_owner() as Button
	if owner == null:
		return ""
	return str(owner.get_meta(&"nav_key")) if owner.has_meta(&"nav_key") else owner.text


func _restore_focus(text: String) -> void:
	for button: Button in find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and (button.text == text or (button.has_meta(&"nav_key") and button.get_meta(&"nav_key") == text)):
			button.grab_focus()
			return


## 操作按鈕並排顯示，但方向鍵上下也能在它們之間移動，和原本直排時的操作習慣一致。
func _link_actions() -> void:
	var buttons := _actions.get_children().filter(func(node: Node) -> bool: return node is Button)
	for i in range(1, buttons.size()):
		var prev := buttons[i - 1] as Control
		var next := buttons[i] as Control
		prev.focus_neighbor_bottom = prev.get_path_to(next)
		next.focus_neighbor_top = next.get_path_to(prev)


func _focus_details() -> void:
	for box: Control in [_actions, _details]:
		if is_instance_valid(box) and box.is_inside_tree():
			for button: Button in box.find_children("*", "Button", true, false):
				button.grab_focus()
				return
