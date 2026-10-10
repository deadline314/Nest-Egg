class_name QuestMapScreen
extends Control
## 任務與地圖共用單一覆蓋畫面；返回路徑保存頁面與焦點。

signal closed
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
var _map_path := ""
var _history: Array[Dictionary] = []
var _body: VBoxContainer
var _status: Label
var _canvas: QuestMapCanvas
var _list: VBoxContainer
var _details: VBoxContainer
## 任務細節的操作（釘選、前往地圖）固定在細節下方，不跟著內文捲走或被裁掉一半。
var _actions: HFlowContainer
var _title: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.fill_parent(self)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.98)
	UiKit.fill_parent(shade)
	add_child(shade)
	var layout := VBoxContainer.new()
	UiKit.fill_parent(layout)
	layout.offset_left = 20
	layout.offset_top = 12
	layout.offset_right = -20
	layout.offset_bottom = -12
	layout.add_theme_constant_override(&"separation", 6)
	add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	_title = UiKit.label("任務與地圖", UiKit.FS_TITLE, Palette.CYAN)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	heading.add_child(_button("返回", go_back, "返回上一層畫面。"))
	var nav := HBoxContainer.new()
	layout.add_child(nav)
	nav.add_child(_button("任務", show_page.bind("quests"), "查看任務步驟與釘選目標。"))
	nav.add_child(_button("區域地圖", show_page.bind("region"), "查看目前區域及已探索的地點。"))
	nav.add_child(_button("世界地圖", show_page.bind("world"), "查看區域之間的真實出入口連接。"))
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_body)
	_status = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 28
	layout.add_child(_status)
	_map_path = player_path
	show_page(start_page, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"inventory_next_tab") or event.is_action_pressed(&"inventory_prev_tab"):
		var pages := ["quests", "region", "world"]
		var offset := 1 if event.is_action_pressed(&"inventory_next_tab") else -1
		show_page(pages[posmod(pages.find(_page) + offset, 3)])
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


func _build() -> void:
	for child in _body.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	_buttons.clear()
	_canvas = null
	_details = null
	_actions = null
	_title.text = "任務目錄" if _page == "quests" else "世界地圖" if _page == "world" else "區域地圖"
	if _page == "quests":
		_build_quests()
	else:
		_build_map()
	_bind_hints(self)
	if not _buttons.is_empty():
		_focus_first.call_deferred()


func _build_quests() -> void:
	var filters := HBoxContainer.new()
	_body.add_child(filters)
	for entry in [["進行中", "active"], ["已完成", "completed"], ["全部", "all"], ["主線", "main"], ["支線", "side"]]:
		var button := _button(entry[0], _filter.bind(entry[1]), "顯示%s任務。" % entry[0])
		button.toggle_mode = true
		button.button_pressed = (_completed if entry[1] == "completed" else not _completed if entry[1] == "active" else _kind == entry[1])
		filters.add_child(button)
		_buttons.append(button)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(columns)
	var left := UiPanel.new("選擇任務")
	left.custom_minimum_size.x = 222
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.body.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list)
	var right := UiPanel.new("任務細節", Palette.MAGENTA)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.body.add_child(detail_scroll)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_details)
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override(&"h_separation", 6)
	_actions.add_theme_constant_override(&"v_separation", 4)
	right.body.add_child(_actions)
	var quests := catalog.list_for(chapter, _kind, _completed, GameState.world_flags)
	if quests.is_empty():
		_wrapped(_list, "目前沒有已完成的任務。" if _completed else "目前尚無可追蹤的任務。")
		_wrapped(_details, "開啟區域地圖，查看你走過的路與出入口。")
		_status.text = "使用方向鍵或搖桿選擇，按確認鍵開啟，按返回鍵回上一層。"
		return
	if not quests.any(func(q: Dictionary) -> bool: return q["id"] == _selected):
		_selected = quests[0]["id"]
	for quest in quests:
		var status := QuestCatalog.status(quest, GameState.world_flags)
		var symbol := "✓" if status == "completed" else "▣" if status == "blocked" else "◆" if quest["kind"] == "main" else "◇"
		var button := _button("%s %s" % [symbol, quest["title"]], _select.bind(quest["id"], true), "查看%s的步驟與地點。" % quest["title"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		_list.add_child(button)
		_buttons.append(button)
	_select(_selected)


func _filter(value: String) -> void:
	var filter_text := ""
	for entry in [["進行中", "active"], ["已完成", "completed"], ["全部", "all"], ["主線", "main"], ["支線", "side"]]:
		if entry[1] == value:
			filter_text = entry[0]
	if value in ["active", "completed"]:
		_completed = value == "completed"
	else:
		_kind = value
	_selected = ""
	_build()
	_restore_focus.call_deferred(filter_text)


func _select(id: String, focus_details := false) -> void:
	_selected = id
	for child in _details.get_children() + _actions.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	var quest := catalog.find(id)
	if quest.is_empty():
		return
	_wrapped(_details, str(quest["title"]), Palette.CYAN)
	_wrapped(_details, str(quest["background"]))
	var status := QuestCatalog.status(quest, GameState.world_flags)
	if status == "blocked":
		_wrapped(_details, str(quest.get("blocked_reason", "")), Palette.WARNING)
		_wrapped(_details, str(quest.get("suggestion", "")))
	_details.add_child(UiDivider.new())
	for step: Dictionary in quest["steps"]:
		var complete: bool = QuestCatalog.flag_set(GameState.world_flags, str(step["complete_flag"]))
		_wrapped(_details, ("✓ " if complete else "○ ") + str(step["title"]))
	_wrapped(_details, "獎勵：%s" % quest["reward"], Palette.NEON_YELLOW)
	if status != "completed":
		_actions.add_child(_button("取消釘選" if state.pinned_id == id else "釘選這項任務", _pin.bind(id), "讓目標列與方向箭頭追蹤這項任務。"))
	var step := QuestCatalog.current_step(quest, GameState.world_flags)
	if step.is_empty():
		step = quest["steps"].back()
	var location: Dictionary = step["location"]
	var data: LevelData = maps.areas.get(location["level"], {}).get("data")
	if data != null:
		_actions.add_child(_button("前往%s的地圖" % data.display_name, _jump_to_map.bind(location["level"]), "查看選中任務的目的地，返回後回到任務細節。"))
	_link_actions()
	_bind_hints(_details)
	_bind_hints(_actions)
	if focus_details:
		_focus_details.call_deferred()


func _pin(id: String) -> void:
	state.pin("" if state.pinned_id == id else id, catalog)
	_select(id, true)


func _jump_to_map(path: String) -> void:
	_history.append({"page": _page, "map_path": _map_path, "selected": _selected, "focus_text": _focus_text()})
	_map_path = path
	_page = "region"
	_build()


func _build_map() -> void:
	var data: LevelData = maps.areas.get(_map_path, {}).get("data")
	var toolbar := HBoxContainer.new()
	_body.add_child(toolbar)
	toolbar.add_child(UiKit.label("世界連接" if _page == "world" else data.display_name if data != null else "尚未載入區域", UiKit.FS_BODY, Palette.CYAN))
	if _page == "region":
		toolbar.add_child(_button("放大", _zoom.bind(2.0), "放大區域地圖，中心對準玩家位置。"))
		toolbar.add_child(_button("縮小", _zoom.bind(0.5), "縮小區域地圖，查看更遠的路。"))
		toolbar.add_child(_button("回到所在區域", _here, "顯示主角目前所在的區域。"))
	_canvas = QuestMapCanvas.new()
	_canvas.custom_minimum_size.y = 140
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.maps = maps
	_canvas.state = state
	_canvas.path = _map_path
	_canvas.player_path = player_path
	_canvas.player_position = player_position
	_canvas.world_mode = _page == "world"
	_canvas.flags = GameState.world_flags
	_canvas.world = world
	var quest := catalog.find(_selected) if not _selected.is_empty() else state.target(catalog, chapter, GameState.world_flags)
	var step := QuestCatalog.current_step(quest, GameState.world_flags)
	if step.is_empty() and not quest.is_empty():
		step = quest["steps"].back()
	_canvas.goal = step.get("location", {})
	_canvas.marker_selected.connect(func(text: String) -> void: _status.text = text)
	_canvas.area_selected.connect(_jump_to_map)
	_body.add_child(_canvas)
	var legend := HBoxContainer.new()
	_body.add_child(legend)
	for item in [["▲", "玩家", "主角目前在這裡。"], ["↔", "出口", "從出入口前往其他區域。"], ["◆", "復原點", "啟用後可從這裡重新開始。"], ["＄", "商店", "在商店查看補給與服務。"], ["＋", "拾取點", "探索附近後可查看拾取地點。"], ["◎", "目標", "前往這裡完成追蹤中的步驟。"], ["▣", "閘門", "選擇閘門圖示查看通行條件。"]]:
		var button := _button(item[0] + " " + item[1], Callable(), item[2])
		legend.add_child(button)
		_buttons.append(button)
	_status.text = "未探索處只顯示外框；選擇圖示可以閱讀說明。"
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.refresh.call_deferred()


func _zoom(factor: float) -> void:
	_canvas.zoom = clampf(_canvas.zoom * factor, 1, 4)
	_canvas.refresh()


func _here() -> void:
	_map_path = player_path
	_build()


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


static func _button(text: String, action: Callable, tooltip: String) -> Button:
	var button := UiKit.button(text, action, tooltip)
	button.custom_minimum_size.x = 0
	return button


func _focus_first() -> void:
	if not _buttons.is_empty() and is_instance_valid(_buttons[0]) and _buttons[0].is_inside_tree():
		_buttons[0].grab_focus()


func _focus_text() -> String:
	var owner := get_viewport().gui_get_focus_owner() as Button
	return owner.text if owner != null else ""


func _restore_focus(text: String) -> void:
	for button: Button in find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text == text:
			button.grab_focus()
			return


## 操作按鈕並排顯示，但方向鍵上下也能在它們之間移動，和原本直排時的操作習慣一致。
func _link_actions() -> void:
	var buttons := _actions.get_children()
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
