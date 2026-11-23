class_name QuestMapScreen
extends Control
## 任務與地圖共用單一覆蓋畫面；返回路徑保存頁面與焦點。
## 版面（design/18-quest-map-ux/VISUAL_RESEARCH.md 範本 A＋B）：模糊壓暗的遊戲畫面當底，
## 頁首一條分頁列（兩側標切換鍵）、頁尾一條按鍵提示列；任務頁左清單右細節，地圖頁左資訊右地圖。

signal closed
const LIST_WIDTH := 200.0
const INFO_WIDTH := 116.0
const FILTERS := {
	"active": [["進行中", "進行中", "Active"], ["顯示進行中的任務。", "進行中のクエストを表示します。", "Show active quests."]],
	"completed": [["已完成", "完了", "Done"], ["顯示已完成的任務。", "完了したクエストを表示します。", "Show completed quests."]],
	"all": [["全部", "すべて", "All"], ["顯示全部任務。", "すべてのクエストを表示します。", "Show all quest types."]],
	"main": [["主線", "メイン", "Main"], ["顯示主線任務。", "メインクエストを表示します。", "Show main quests."]],
	"side": [["支線", "サブ", "Side"], ["顯示支線任務。", "サブクエストを表示します。", "Show side quests."]],
}
const PAGES := ["quests", "region", "world"]
const PAGE_NAMES := {"quests": ["任務", "クエスト", "Quests"], "region": ["區域地圖", "エリア", "Area"], "world": ["世界地圖", "全体", "World"]}
const PAGE_TIPS := {
	"quests": ["查看任務步驟與釘選目標。", "手順を確認して目的を追跡できます。", "Review steps and track a quest."],
	"region": ["查看目前區域及已探索的地點。", "現在地と探索済みの場所を確認します。", "View this area and explored locations."],
	"world": ["查看區域之間的真實出入口連接。", "各エリアを結ぶ出入口を確認します。", "See how areas connect."],
}
const LEGEND := [["player", "你的位置", "主角目前在這裡。"], ["goal", "追蹤目標", "前往這裡完成追蹤中的步驟。"], ["exit", "出入口", "從出入口前往其他區域。"], ["checkpoint", "復原點", "啟用後可從這裡重新開始。"], ["shop", "商店", "在商店查看補給與服務。"], ["pickup", "拾取點", "探索附近後可查看拾取地點。"], ["gate", "閘門", "選擇閘門圖示查看通行條件。"]]
const SOURCE_MAP_COPY := {
	"zh": {"center": "回到來源", "marker": "文件來源", "hint": "取得這份文件的地點。", "zoom": "放大來源周圍的地圖。"},
	"ja": {"center": "入手先に戻る", "marker": "入手先", "hint": "この書類を入手した場所。", "zoom": "入手先の周辺を拡大。"},
	"en": {"center": "Center source", "marker": "Document source", "hint": "Where this document was obtained.", "zoom": "Zoom in around the source."},
}

var catalog: QuestCatalog
var maps: QuestMapIndex
var state: QuestMapState
var chapter := ""
var player_path := ""
var player_position := Vector2.ZERO
var world: Dictionary = {}
var start_page := "quests"
var reference_location: Dictionary = {}
var reference_label := ""
var _page := ""
var _kind := "all"
var _completed := false
var _selected := ""
var _display_language := ""
var _map_path := ""
var _history: Array[Dictionary] = []
var _body: Control
var _footer: HBoxContainer
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


static func for_level(level: Level) -> QuestMapScreen:
	if not is_instance_valid(level) or not is_instance_valid(level.player) \
			or not is_instance_valid(level.hud) or level.hud.quest_guidance == null:
		return null
	var guidance := level.hud.quest_guidance
	var screen := QuestMapScreen.new()
	screen.catalog = guidance.catalog
	screen.maps = guidance.maps
	screen.state = guidance.state
	screen.chapter = String(level.data.chapter)
	screen.player_path = level.data.resource_path
	screen.player_position = level.player.global_position
	screen.world = WorldState.capture(level.get_tree())
	return screen


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
	_map_path = str(reference_location.get("level", player_path))
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
	_refresh_footer()
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
	_title = UiKit.caption("", Palette.CYAN)
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
	_footer = HBoxContainer.new()
	_footer.custom_minimum_size.y = 14
	_footer.add_theme_constant_override(&"separation", 10)
	_status = UiKit.caption("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_footer.add_child(_status)
	_refresh_footer()
	return _footer


func _refresh_footer() -> void:
	for index in range(_footer.get_child_count() - 1, 0, -1):
		var prompt := _footer.get_child(index)
		_footer.remove_child(prompt)
		prompt.queue_free()
	_footer.add_child(FlatStyle.prompt(&"ui_accept", _text(["選擇", "選択", "Select"]), Callable(),
		_text(["確認目前選取的項目。", "選んでいる項目を決定します。", "Select the focused item."])))
	_footer.add_child(FlatStyle.prompt(&"ui_cancel", _text(["返回", "戻る", "Back"]), go_back,
		_text(["返回上一層畫面。", "前の画面へ戻ります。", "Return to the previous screen."])))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		go_back()
		get_viewport().set_input_as_handled()
	elif reference_location.is_empty() and (event.is_action_pressed(&"inventory_next_tab") or event.is_action_pressed(&"inventory_prev_tab")):
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
		for index in range(_history.size() - 1, -1, -1):
			if _history[index]["page"] == page:
				_history.resize(index + 1)
				go_back()
				return
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
	_title.text = _text(["導覽終端", "ナビ端末", "Navigation"])
	if PAGE_NAMES.has(_page):
		_title.text += "　" + _text(PAGE_NAMES[_page])
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
	if not reference_location.is_empty():
		var label := UiKit.caption(reference_label, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(label)
		return
	var prev := FlatStyle.keycap(InputBindings.primary_label(&"inventory_prev_tab"))
	prev.set_meta(&"prompt_action", &"inventory_prev_tab")
	_tabs.add_child(prev)
	for page: String in PAGES:
		var tab := UiKit.button(_text(PAGE_NAMES[page]), show_page.bind(page), _text(PAGE_TIPS[page]))
		tab.set_meta(&"nav_key", "page:" + page)
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
		var empty_text := _text(["目前沒有已完成的任務。", "完了したクエストはありません。", "You have no completed quests."]) if _completed \
			else _text(["目前尚無可追蹤的任務。", "追跡できるクエストはありません。", "You have no quests to track."])
		_wrapped(_list, empty_text, Palette.UI_MUTED)
		_wrapped(_details, _text(["開啟區域地圖，查看你走過的路與出入口。", "エリアマップで通った道や出入口を確認できます。", "Open the area map to see explored paths and exits."]))
		_status.text = _text(["使用方向鍵或搖桿選擇，按確認鍵開啟，按返回鍵回上一層。", "方向キーかスティックで項目を選びます。", "Use the arrow keys or stick to move."])
		return
	if not quests.any(func(q: Dictionary) -> bool: return q["id"] == _selected):
		_selected = quests[0]["id"]
	var group := ""
	for quest in quests:
		if _kind == "all" and quest["kind"] != group:
			group = quest["kind"]
			_list.add_child(FlatStyle.section(_text(FILTERS["main" if group == "main" else "side"][0])))
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
	for key: String in FILTERS:
		var entry: Array = FILTERS[key]
		if group == null or key == "all":
			group = HBoxContainer.new()
			group.add_theme_constant_override(&"separation", 2)
			filters.add_child(group)
		var on := (_completed if key == "completed" else not _completed if key == "active" else _kind == key)
		var text := _text(entry[0])
		if key in ["active", "completed"]:
			text = "%s %d" % [text, counts[key]]
		var button := UiKit.button(text, _filter.bind(key), _text(entry[1]))
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
	var tooltip := _text(["查看%s的步驟與地點。", "「%s」の手順と目的地を確認します。", "View steps for “%s”."]) % localized_title
	var button := UiKit.button("%s %s" % [symbol, localized_title], _select.bind(quest["id"], true), tooltip)
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
	if state.pinned_id == quest["id"] and status != "completed":
		var pinned := UiKit.caption(_text(["追蹤中", "追跡中", "Tracking"]), Palette.MAGENTA, HORIZONTAL_ALIGNMENT_RIGHT)
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
	var pinned := state.pinned_id == id and status != "completed"
	var kind_text := _text(["主線任務", "メインクエスト", "Main quest"]) if quest["kind"] == "main" \
		else _text(["支線任務", "サブクエスト", "Side quest"])
	var status_text := _text(FILTERS["completed"][0]) if status == "completed" else _text(FILTERS["active"][0])
	if status == "blocked":
		status_text = _text(["暫時卡住", "進行不可", "Blocked"])
	if pinned:
		status_text += "　·　" + _text(["追蹤中", "追跡中", "Tracking"])
	_detail_head.add_child(UiKit.caption("%s　／　%s" % [kind_text, status_text], Palette.MAGENTA if pinned else Palette.CYAN))
	var title := UiKit.heading(QuestCatalog.display_text(quest, "title"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_head.add_child(title)
	var step := QuestCatalog.current_step(quest, GameState.world_flags)
	if step.is_empty():
		step = quest["steps"].back()
	var location: Dictionary = step["location"]
	_detail_head.add_child(UiKit.caption(_text(["◎ 目的地：%s", "◎ 目的地：%s", "◎ Destination: %s"]) % _area_name(location["level"])))
	if status == "blocked":
		_details.add_child(SlantBanner.new(QuestCatalog.display_text(quest, "blocked_reason"), Palette.WARNING))
		_wrapped(_details, QuestCatalog.display_text(quest, "suggestion"))
	elif status != "completed":
		# 現在要做的那一件事用斜切橫幅（範本 B），一眼看到下一步。
		_details.add_child(SlantBanner.new("▶ " + QuestCatalog.display_text(step, "title"), Palette.MAGENTA if pinned else Palette.CYAN))
	_details.add_child(FlatStyle.section(_text(["背景", "背景", "Background"])))
	_wrapped(_details, QuestCatalog.display_text(quest, "background"), Color(Palette.UI_TEXT, 0.85))
	var steps: Array = quest["steps"]
	var done := 0
	for entry: Dictionary in steps:
		if QuestCatalog.flag_set(GameState.world_flags, str(entry["complete_flag"])):
			done += 1
	_details.add_child(FlatStyle.section(_text(["目標　%d／%d", "目標　%d／%d", "Objectives %d/%d"]) % [done, steps.size()]))
	for entry: Dictionary in steps:
		var complete: bool = QuestCatalog.flag_set(GameState.world_flags, str(entry["complete_flag"]))
		var current := not complete and entry == step
		var prefix := "✓ " if complete else "▶ " if current else "○ "
		var color := Color(Palette.UI_MUTED, 0.7) if complete else Palette.CYAN if current else Palette.UI_MUTED
		_wrapped(_details, prefix + QuestCatalog.display_text(entry, "title"), color)
	if not QuestCatalog.display_text(quest, "reward").is_empty():
		_details.add_child(FlatStyle.section(_text(["獎勵", "報酬", "Reward"])))
		_reward = _wrapped(_details, QuestCatalog.display_text(quest, "reward"), Palette.NEON_YELLOW)
	_detail_scroll.scroll_vertical = 0
	if status != "completed":
		var pin_text := _text(["取消釘選", "追跡を解除", "Stop tracking"]) if pinned else _text(["釘選這項任務", "追跡する", "Track quest"])
		var pin_tip := _text(["恢復自動追蹤任務。", "クエストの自動追跡に戻します。", "Use automatic quest tracking again."]) if pinned \
			else _text(["讓目標列與方向箭頭追蹤這項任務。", "このクエストを目標表示に設定します。", "Show this quest and its direction in the HUD."])
		var pin := UiKit.button(pin_text, _pin.bind(id), pin_tip)
		pin.set_meta(&"nav_key", "action:pin")
		FlatStyle.chip(pin)
		_actions.add_child(pin)
	var data: LevelData = maps.areas.get(location["level"], {}).get("data")
	if data != null:
		var jump_text := _text(["前往%s的地圖" % data.display_name, "地図を開く", "Open map"])
		var jump := UiKit.button(jump_text, _jump_to_map.bind(location["level"]),
			_text(["查看選中任務的目的地。", "選んだクエストの目的地を地図で確認します。", "Open the selected quest’s destination on the map."]))
		jump.set_meta(&"nav_key", "action:destination")
		FlatStyle.chip(jump)
		_actions.add_child(jump)
	_scroll_note = UiKit.caption(_text(["右搖桿／PageDown 往下讀", "右スティック／Page Downでスクロール", "Right stick / Page Down to scroll"]))
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
	_restore_focus.call_deferred("action:pin")


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
	var showing_source := not reference_location.is_empty()
	var source_copy: Dictionary = SOURCE_MAP_COPY.get(Story.language, SOURCE_MAP_COPY["zh"])
	var area_caption := "目前區域" if _map_path == player_path else "查看中的區域"
	if world_mode:
		area_caption = "本章區域"
		if not chapter.is_empty():
			area_caption = str(Story.chapter_info(StringName(chapter)).get("title", area_caption))
	info.add_child(UiKit.caption(area_caption, Palette.CYAN))
	var heading := UiKit.heading("世界地圖" if world_mode else data.display_name if data != null else "尚未載入區域")
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 自動換行的標題先知道欄寬；否則第一次排版以零寬逐字換行，地圖會在同一格多重建一次。
	heading.custom_minimum_size.x = INFO_WIDTH
	info.add_child(heading)
	# 先佔一行高，填入統計時版面不會再變一次（避免地圖在同一格重建兩次）。
	var stats := UiKit.caption(" ")
	info.add_child(stats)
	if not world_mode:
		var tools := HFlowContainer.new()
		tools.add_theme_constant_override(&"h_separation", 2)
		tools.add_theme_constant_override(&"v_separation", 2)
		info.add_child(tools)
		var zoom_hint: String = source_copy["zoom"] if showing_source else "放大區域地圖，中心對準玩家位置。"
		var center := [source_copy["center"], _here, source_copy["hint"]] if showing_source else ["回到所在區域", _here, "顯示主角目前所在的區域。"]
		for entry: Array in [["放大", _zoom.bind(2.0), zoom_hint], ["縮小", _zoom.bind(0.5), "縮小區域地圖，查看更遠的路。"], center]:
			var tool := UiKit.button(entry[0], entry[1], entry[2])
			FlatStyle.chip(tool)
			tools.add_child(tool)
			_buttons.append(tool)
	info.add_child(FlatStyle.section("圖例"))
	for item: Array in LEGEND:
		var source_marker: bool = showing_source and item[0] == "goal"
		var text: String = source_copy["marker"] if source_marker else item[1]
		var tip: String = source_copy["hint"] if source_marker else item[2]
		var button := UiKit.button("　 " + text, Callable(), tip)
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
	_canvas.goal = step.get("location", {}) if reference_location.is_empty() else reference_location
	_canvas.goal_name = reference_label
	_canvas.marker_selected.connect(func(text: String) -> void: _status.text = text)
	_canvas.area_selected.connect(_jump_to_map)
	_canvas.refreshed.connect(func() -> void: stats.text = _map_stats(world_mode))
	frame.add_child(_canvas)
	_status.text = "未探索處只顯示外框；選擇圖示可以閱讀說明。"
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.queue_refresh()


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
	var path := str(reference_location.get("level", player_path))
	if _map_path == path:
		_canvas.zoom = 1.0
		_canvas.refresh()
		return
	var focus_key := _focus_text()
	_map_path = path
	_build()
	_restore_focus.call_deferred(focus_key)


# ---------------------------------------------------------------------------
# 共用
# ---------------------------------------------------------------------------

func _text(choices: Array) -> String:
	return choices[1] if _display_language == "ja" else choices[2] if _display_language == "en" else choices[0]


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
