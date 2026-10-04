class_name SoundLabSlotsTab
extends SoundLabRatioSplit
## 實驗室分頁一：位置與備選。左欄上半是遊戲裡所有會響的位置（可依域篩選、搜尋），下半是備選素材與跨類別搜尋整個素材目錄
## （兩者上下各約一半，中間可拖動）；右欄是選中位置的資訊、畫面情境、音量、目前用的素材、預計使用（和位置清單文件連動）。
## 所有挑選都立刻寫回位置清單文件（只改那一格）；勾「手動放入」代表你自己已經把檔案放進遊戲，套用工具會略過。

const SEARCH_MATCH_LIMIT := 100000  ## 搜尋先取全部符合的，才能算出被隱藏的個數
const SEARCH_SHOW_LIMIT := 300  ## 搜尋結果最多列出幾個

var lab: SoundLab
var _domain: OptionButton
var _search: LineEdit
var _slot_list: ItemList
var _title: Label
var _where: Label
var _source: Label
var _volume_slider: HSlider
var _volume_label: Label
var _current_list: ItemList
var _planned_edit: LineEdit
var _planned_list: ItemList
var _manual_check: CheckBox
var _scene_option: OptionButton
var _scene_note: Label
var _auto_play: CheckBox
var _result_tabs: TabContainer
var _candidate_list: ItemList
var _category: OptionButton
var _search_edit: LineEdit
var _search_list: ItemList
var _rows: SoundLabRatioSplit
var _shown_slots: Array[String] = []
var _selected_slot := ""
## 「先聽現在、再聽預計」兩段聲音之間的間隔（秒）；測試時縮短。
var compare_gap := 1.2


func _init(p_lab: SoundLab) -> void:
	lab = p_lab


func _ready() -> void:
	setup(lab.layout, "slots_columns", 0.5, "拖動調整左欄（位置與備選素材）和右欄（位置資訊）的寬度")
	_rows = SoundLabRatioSplit.new()
	_rows.vertical = true
	_rows.setup(lab.layout, "slots_left_rows", 0.5, "拖動調整位置清單和備選素材的高度")
	_rows.custom_minimum_size = Vector2(300, 0)
	add_child(_rows)
	_build_slot_pane(_rows)
	_build_candidate_pane(_rows)
	_build_right()
	refresh()


## 左欄上半：位置清單與篩選。
func _build_slot_pane(parent: Control) -> void:
	var left := VBoxContainer.new()
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(left)
	_domain = OptionButton.new()
	_domain.tooltip_text = "只看某一類位置：武器、命中、角色、移動、機關、介面、環境音、背景音樂"
	_domain.add_item("全部位置")
	for domain: String in lab.catalog.domains.keys():
		_domain.add_item("%s %s" % [domain, lab.catalog.domains[domain]])
		_domain.set_item_metadata(_domain.item_count - 1, domain)
	_domain.item_selected.connect(func(_i: int) -> void: _fill_slots())
	left.add_child(_domain)
	_search = LineEdit.new()
	_search.placeholder_text = "搜尋位置（編號、名稱、用在哪裡）"
	_search.tooltip_text = "輸入位置編號、名稱或用途的一部分"
	_search.text_changed.connect(func(_t: String) -> void: _fill_slots())
	left.add_child(_search)
	_slot_list = ItemList.new()
	_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot_list.tooltip_text = "★ 已填預計使用　✓ 已勾手動放入"
	_slot_list.item_selected.connect(_on_slot_selected)
	left.add_child(_slot_list)


func _build_right() -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(240, 0)
	add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	right.add_child(_title)
	_where = Label.new()
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_where.tooltip_text = "這個位置在遊戲裡的哪裡用到"
	right.add_child(_where)
	_source = Label.new()
	_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source.tooltip_text = "這個位置現在的聲音來源：音效檔（含授權包與時長）或程式合成音；缺檔會在這裡標示"
	right.add_child(_source)
	var scene_row := HFlowContainer.new()
	right.add_child(scene_row)
	scene_row.add_child(_heading("畫面情境："))
	_scene_option = OptionButton.new()
	_scene_option.custom_minimum_size = Vector2(170, 0)
	_scene_option.tooltip_text = "這個聲音在遊戲裡會在什麼情境下響；選一個，按右邊的按鈕在右側畫面舞台裡看實際的動畫和聲音"
	scene_row.add_child(_scene_option)
	scene_row.add_child(_button("▶ 用遊戲現在的音效", func() -> void: play_in_stage(""), "在右側畫面舞台執行這個情境（例如連續射擊），用遊戲現在的聲音（下面「遊戲現在用」那組）"))
	scene_row.add_child(_button("▶ 用預計換成的音效", func() -> void: play_in_stage_with_planned(), "同一個情境，這個位置的聲音暫時換成下面「預計換成」那一整組素材（每次輪流用，只在記憶體，不寫入任何資料），聽射擊時預計的聲音實際的感覺"))
	scene_row.add_child(_button("▶ 用備選素材在畫面中試", func() -> void: play_in_stage_with_candidate(), "同一個情境，但這個位置的聲音暫時換成下面選中的素材（只在記憶體，不寫入任何資料），看動畫配上候選聲音的感覺"))
	_scene_note = Label.new()
	_scene_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scene_note.tooltip_text = "這個位置有沒有對應的畫面情境；沒有的話說明原因"
	right.add_child(_scene_note)
	var actions := HFlowContainer.new()
	right.add_child(actions)
	actions.add_child(_button("▶ 遊戲內實際聲音", _play_in_game, "播放這個位置目前在遊戲裡真的會響的聲音"))
	actions.add_child(_button("■ 全部停止", _stop_all, "停止所有試聽與遊戲內的聲音、音樂"))
	actions.add_child(_button("▶ 先聽現在、再聽預計", func() -> void: compare_current_and_planned(), "先播遊戲現在的聲音，隔一下再播預計換成的第一個素材（預聽檔的響度是套用後的響度），比較兩者"))
	_volume_label = Label.new()
	_volume_label.text = "音量微調"
	actions.add_child(_volume_label)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = -24.0
	_volume_slider.max_value = 12.0
	_volume_slider.step = 0.5
	_volume_slider.custom_minimum_size = Vector2(160, 0)
	_volume_slider.tooltip_text = "這個位置的音量微調（dB），拖動立刻生效；要保存請按「預覽差異／儲存音量」"
	_volume_slider.value_changed.connect(_on_volume_changed)
	actions.add_child(_volume_slider)
	actions.add_child(_button("預覽差異", func() -> void: save_volume(true), "列出和資料檔不同的音量，不寫入"))
	actions.add_child(_button("儲存音量", func() -> void: save_volume(false), "驗證後寫回音效庫（先備份成 .bak）"))
	_auto_play = CheckBox.new()
	_auto_play.text = "選取即試聽"
	_auto_play.button_pressed = true
	_auto_play.tooltip_text = "點選素材就自動播放預聽檔"
	actions.add_child(_auto_play)
	right.add_child(_heading("遊戲現在用（已經在遊戲裡；點選試聽）"))
	_current_list = _compare_list("這個位置現在在遊戲裡用的素材（每個素材一行：編號、時長、說明、檔名與素材包）；點選即試聽")
	_current_list.item_selected.connect(func(i: int) -> void: _maybe_audition(_current_list, i))
	right.add_child(_current_list)
	right.add_child(_heading("預計換成（你挑的，還沒套用到遊戲；點選試聽）"))
	_planned_list = _compare_list("位置清單文件裡這個位置的預計使用，列出你挑的每一個素材；擷取出來的片段標明來源；沒有預聽檔的也列出但無法試聽")
	_planned_list.item_selected.connect(func(i: int) -> void: _maybe_audition(_planned_list, i))
	_planned_list.item_activated.connect(_audition_planned_item)
	right.add_child(_planned_list)
	var planned_row := HBoxContainer.new()
	right.add_child(planned_row)
	planned_row.add_child(_heading("編輯："))
	_planned_edit = LineEdit.new()
	_planned_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_planned_edit.placeholder_text = "素材編號，用逗號或頓號分開，按 Enter 寫入"
	_planned_edit.tooltip_text = "直接輸入預計使用的素材編號（任何類別都可以）；按 Enter 寫進位置清單文件"
	_planned_edit.text_submitted.connect(_on_planned_submitted)
	planned_row.add_child(_planned_edit)
	planned_row.add_child(_button("清除", func() -> void: _write_planned(PackedStringArray()), "清掉這個位置的預計使用"))
	_manual_check = CheckBox.new()
	_manual_check.text = "手動放入"
	_manual_check.tooltip_text = "打勾 = 你自己已經把檔案放進遊戲了，套用工具會略過這個位置"
	_manual_check.toggled.connect(_on_manual_toggled)
	planned_row.add_child(_manual_check)


## 左欄下半：備選素材、跨類別搜尋，以及對選中素材的試聽與設定按鈕。
func _build_candidate_pane(parent: Control) -> void:
	var pane := VBoxContainer.new()
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(pane)
	_result_tabs = TabContainer.new()
	_result_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(_result_tabs)
	var candidates_box := VBoxContainer.new()
	candidates_box.name = "備選素材"
	_result_tabs.add_child(candidates_box)
	_candidate_list = _multi_list()
	candidates_box.add_child(_candidate_list)
	var search_box := VBoxContainer.new()
	search_box.name = "搜尋全部素材（跨類別）"
	_result_tabs.add_child(search_box)
	var search_row := HBoxContainer.new()
	search_box.add_child(search_row)
	_category = OptionButton.new()
	_category.tooltip_text = "只看某一類素材；選「全部類別」可以跨類別挑"
	_category.add_item("全部類別")
	for code: String in lab.catalog.categories.keys():
		_category.add_item("%s %s" % [code, lab.catalog.categories[code]])
		_category.set_item_metadata(_category.item_count - 1, code)
	_category.item_selected.connect(func(_i: int) -> void: _fill_search())
	search_row.add_child(_category)
	_search_edit = LineEdit.new()
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.placeholder_text = "搜尋素材（編號、素材包、檔名、說明；空白分隔多個詞）"
	_search_edit.tooltip_text = "例如 shotgun 或 rain loop 或 GUN-0031；槍聲素材的說明（槍種、距離）也能搜"
	_search_edit.text_changed.connect(func(_t: String) -> void: _fill_search())
	search_row.add_child(_search_edit)
	_search_list = _multi_list()
	search_box.add_child(_search_list)
	var picks := HFlowContainer.new()
	pane.add_child(picks)
	picks.add_child(_button("▶ 試聽選中的", _audition_selected, "播放選中素材的預聽檔"))
	picks.add_child(_button("設為預計使用", func() -> void: _pick(false), "用選中的素材取代這個位置的預計使用（可以多選）"))
	picks.add_child(_button("加入預計使用", func() -> void: _pick(true), "把選中的素材加到這個位置的預計使用後面"))
	picks.add_child(_button("✂ 擷取片段…", _open_clip_editor, "一個素材裡有多段聲音時：看完整波形、挑一段、試聽，確認後輸出成新素材"))
	_fill_search()


## 並排比較用的清單：每個素材一行完整說明，兩份清單平分高度。
func _audition_planned_item(index: int) -> void:
	if _planned_list.get_item_metadata(index) != null:
		lab.audition_asset(str(_planned_list.get_item_metadata(index)))


func _compare_list(tip: String) -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 80)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.tooltip_text = tip
	return list


func _multi_list() -> ItemList:
	var list := ItemList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.tooltip_text = "點一下試聽；Ctrl 或 Shift 多選；雙擊設為預計使用"
	list.item_selected.connect(func(i: int) -> void: _maybe_audition(list, i))
	list.item_activated.connect(func(i: int) -> void:
		list.select(i, false)
		_pick(false))
	return list


func _button(text: String, action: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Palette.CYAN)
	return label


# ---------------------------------------------------------------------------
# 位置清單
# ---------------------------------------------------------------------------

## 文件被外部改過、或我們寫入後重新整理畫面（保留選中的位置）。
func refresh() -> void:
	_fill_slots()
	if _selected_slot != "":
		_show_slot(_selected_slot)


func _fill_slots() -> void:
	var domain := ""
	if _domain.selected > 0:
		domain = str(_domain.get_item_metadata(_domain.selected))
	var query := _search.text.to_lower().strip_edges()
	_slot_list.clear()
	_shown_slots.clear()
	for slot: Dictionary in lab.catalog.slots_in(domain):
		var sid := str(slot["id"])
		if not query.is_empty() and not ("%s %s %s %s" % [sid, slot["name"], slot["where"], slot["target"]]).to_lower().contains(query):
			continue
		var mark := ("★" if not lab.doc.planned(sid).is_empty() else "　") + ("✓" if lab.doc.is_manual(sid) else "　")
		var planned := lab.doc.planned(sid)
		var planned_text := "" if planned.is_empty() else "  → %s%s" % [planned[0], "" if planned.size() == 1 else "（共 %d）" % planned.size()]
		_slot_list.add_item("%s %s  %s%s" % [mark, sid, slot["name"], planned_text])
		_shown_slots.append(sid)
		if sid == _selected_slot:
			_slot_list.select(_slot_list.item_count - 1)


func _on_slot_selected(index: int) -> void:
	_show_slot(_shown_slots[index])


func select_slot(slot_id: String) -> void:
	var index := _shown_slots.find(slot_id)
	if index >= 0:
		_slot_list.select(index)
	_show_slot(slot_id)


func selected_slot() -> String:
	return _selected_slot


func _show_slot(slot_id: String) -> void:
	var slot := lab.catalog.slot(slot_id)
	if slot.is_empty():
		return
	_selected_slot = slot_id
	_title.text = "%s　%s" % [slot_id, slot["name"]]
	_where.text = "%s（%s）" % [slot["where"], slot["target"]]
	_show_source(slot)
	_fill_scenes(slot_id)
	_fill_blocks(_current_list, slot["current"])
	if (slot["current"] as Array).is_empty():
		_current_list.add_item("（目前是程式合成音，沒有素材檔）")
		_current_list.set_item_disabled(0, true)
	_planned_edit.text = "、".join(lab.doc.planned(slot_id))
	_fill_planned_list(lab.doc.planned(slot_id))
	_manual_check.set_pressed_no_signal(lab.doc.is_manual(slot_id))
	_fill_list(_candidate_list, slot["candidates"], lab.doc.planned(slot_id))


func _fill_scenes(slot_id: String) -> void:
	var scenes := StageScenes.shared()
	_scene_option.clear()
	for id in scenes.scenes_for_slot(slot_id):
		_scene_option.add_item(str(scenes.scene(id).get("name", id)))
		_scene_option.set_item_metadata(_scene_option.item_count - 1, id)
	var has_scene := _scene_option.item_count > 0
	_scene_option.disabled = not has_scene
	if has_scene:
		_scene_note.text = str(scenes.scene(str(_scene_option.get_item_metadata(0))).get("tip", ""))
	else:
		var reason := scenes.slot_reason(slot_id)
		_scene_note.text = "沒有畫面情境：%s（只能播聲音）" % (reason if not reason.is_empty() else "尚未登記")


## 在畫面舞台執行這個位置的情境。candidate 是素材編號時，這個位置的聲音暫時換成它的預聽檔。回傳是否完整跑完。
func play_in_stage(candidate: String) -> bool:
	if not _stage_ready():
		return false
	var preview := {}
	if not candidate.is_empty():
		var slot := lab.catalog.slot(_selected_slot)
		if str(slot["kind"]) == "music":
			lab.notify("音樂位置請在「背景音樂與環境音」分頁用 cue 試聽")
			return false
		var stream := lab.catalog.load_preview(candidate)
		if stream == null:
			lab.notify("沒有 %s 的預聽檔：請先執行 python tools/audio/setup_audition.py" % candidate)
			return false
		preview[StringName(str(slot["target"]))] = stream
		lab.notify("在畫面中用 %s 取代 %s 的聲音（只是試聽，沒有寫入）" % [candidate, slot["target"]])
	return await _run_stage(preview)


## 在畫面舞台執行這個位置的情境，聲音換成「預計換成」的整組素材（每次輪流用）；沒有可試聽的素材時只提示。回傳是否完整跑完。
func play_in_stage_with_planned() -> bool:
	if not _stage_ready():
		return false
	var slot := lab.catalog.slot(_selected_slot)
	if str(slot["kind"]) == "music":
		lab.notify("音樂位置請在「背景音樂與環境音」分頁用 cue 試聽")
		return false
	var planned := lab.doc.planned(_selected_slot)
	var streams: Array[AudioStream] = []
	for aid in planned:
		var stream := lab.catalog.load_preview(aid) if lab.catalog.has_preview(aid) else null
		if stream != null:
			streams.append(stream)
	if streams.is_empty():
		lab.notify("這個位置還沒有預計換成的素材，或它們都沒有預聽檔（補齊：python tools/audio/build_candidates.py）" if not planned.is_empty() else "這個位置還沒有預計換成的素材，先在下面的備選或搜尋挑一個")
		return false
	lab.notify("在畫面中用預計換成的 %d 個素材（共挑了 %d 個）輪流取代 %s 的聲音（只是試聽，沒有寫入）" % [streams.size(), planned.size(), slot["target"]])
	return await _run_stage({StringName(str(slot["target"])): streams})


func _stage_ready() -> bool:
	if _selected_slot.is_empty() or _scene_option.item_count == 0:
		lab.notify("這個位置沒有畫面情境")
		return false
	if lab.dock == null:
		lab.notify("畫面舞台沒有開啟")
		return false
	return true


func _run_stage(preview: Dictionary) -> bool:
	return await lab.dock.play_scene(str(_scene_option.get_item_metadata(_scene_option.selected)), preview)


func play_in_stage_with_candidate() -> bool:
	var picked := selected_assets()
	if picked.is_empty():
		lab.notify("先在下面的備選或搜尋結果選一個素材")
		return false
	return await play_in_stage(picked[0])


## 只列出有預聽檔的素材（最多 max_shown 個，0 = 不限）；有被隱藏的在清單最上面用一行說明。
func _fill_list(list: ItemList, ids: Array, planned: PackedStringArray, max_shown := 0) -> void:
	list.clear()
	var split := lab.catalog.split_by_preview(ids)
	if int(split["hidden"]) > 0:
		list.add_item(lab.hidden_assets_note(int(split["hidden"])))
		list.set_item_disabled(0, true)
	for aid: String in split["shown"]:
		if max_shown > 0 and list.item_count >= max_shown:
			break
		list.add_item(("★ " if planned.has(aid) else "") + _asset_line(aid))
		list.set_item_metadata(list.item_count - 1, aid)
		var a := lab.catalog.asset(aid)
		list.set_item_tooltip(list.item_count - 1, "%s／%s
%s" % [a.get("pack", ""), a.get("file", ""), a.get("desc", "")])


## 每個素材一行完整說明的清單（遊戲現在用）；沒有預聽檔的隱藏並說明（NE-174）。
func _fill_blocks(list: ItemList, ids: Array) -> void:
	list.clear()
	var split := lab.catalog.split_by_preview(ids)
	if int(split["hidden"]) > 0:
		list.add_item(lab.hidden_assets_note(int(split["hidden"])))
		list.set_item_disabled(0, true)
	for aid: String in split["shown"]:
		list.add_item(lab.asset_detail(aid))
		list.set_item_metadata(list.item_count - 1, aid)
		var a := lab.catalog.asset(aid)
		list.set_item_tooltip(list.item_count - 1, "%s／%s
%s" % [a.get("pack", ""), a.get("file", ""), a.get("desc", "")])


## 預計換成的清單：位置清單文件裡填的每一個素材都列出；沒有預聽檔或目錄找不到的也列出並標明（不隱藏使用者自己的挑選）。
func _fill_planned_list(ids: PackedStringArray) -> void:
	_planned_list.clear()
	if ids.is_empty():
		_planned_list.add_item("（還沒挑；在下面的備選或搜尋選素材，按「設為預計使用」）")
		_planned_list.set_item_disabled(0, true)
		return
	for aid in ids:
		var note := ""
		if not lab.catalog.assets.has(aid):
			note = "⚠ "
		elif not lab.catalog.has_preview(aid):
			note = "⚠ 沒有預聽檔，無法試聽　"
		_planned_list.add_item(note + lab.asset_detail(aid))
		_planned_list.set_item_metadata(_planned_list.item_count - 1, aid)
		var a := lab.catalog.asset(aid)
		_planned_list.set_item_tooltip(_planned_list.item_count - 1, "%s／%s
%s" % [a.get("pack", ""), a.get("file", ""), a.get("desc", "")])


## 先播遊戲現在的聲音，隔一下再播預計換成的第一個素材，方便比較。回傳預計素材是否播出。
func compare_current_and_planned() -> bool:
	if _selected_slot == "":
		lab.notify("先在左邊選一個位置")
		return false
	var planned := lab.doc.planned(_selected_slot)
	if planned.is_empty():
		lab.notify("這個位置還沒有預計使用，先在下面的備選或搜尋挑一個")
		return false
	_play_in_game()
	await lab.get_tree().create_timer(compare_gap).timeout
	if not is_inside_tree():
		return false
	return lab.audition_asset(planned[0])


func _asset_line(aid: String) -> String:
	return lab.asset_line(aid)


func _fill_search() -> void:
	var code := ""
	if _category != null and _category.selected > 0:
		code = str(_category.get_item_metadata(_category.selected))
	var matches: Array = lab.catalog.search(_search_edit.text, code, SEARCH_MATCH_LIMIT) if _search_edit != null else []
	_fill_list(_search_list, matches, lab.doc.planned(_selected_slot), SEARCH_SHOW_LIMIT)


# ---------------------------------------------------------------------------
# 試聽與挑選
# ---------------------------------------------------------------------------

func _maybe_audition(list: ItemList, index: int) -> void:
	if _auto_play.button_pressed and list.get_item_metadata(index) != null:
		lab.audition_asset(str(list.get_item_metadata(index)))


func _active_list() -> ItemList:
	return _candidate_list if _result_tabs.current_tab == 0 else _search_list


func selected_assets() -> PackedStringArray:
	var result := PackedStringArray()
	for index in _active_list().get_selected_items():
		result.append(str(_active_list().get_item_metadata(index)))
	return result


func _audition_selected() -> void:
	var ids := selected_assets()
	if ids.is_empty():
		lab.notify("先在下面的清單點選一個素材")
		return
	lab.audition_asset(ids[ids.size() - 1])


func _open_clip_editor() -> void:
	var ids := selected_assets()
	if ids.is_empty():
		lab.notify("先在下面的清單點選要擷取的素材")
		return
	lab.open_clip_editor(ids[ids.size() - 1])


## 切到「搜尋全部素材」並搜尋這個編號（新擷取的素材立刻看得到）。
func show_in_search(asset_id: String) -> void:
	_result_tabs.current_tab = 1
	_category.select(0)
	_search_edit.text = asset_id
	_fill_search()


## 把這個素材設成目前選中位置的預計使用（取代原有的）；沒選位置或寫入失敗回傳 false。
func plan_asset(asset_id: String) -> bool:
	if _selected_slot == "":
		return false
	var ok := lab.doc.set_planned(_selected_slot, PackedStringArray([asset_id]))
	refresh()
	return ok


## 把選中的素材設成（或加到）這個位置的預計使用，立刻寫回位置清單文件。
func _pick(append: bool) -> void:
	if _selected_slot == "":
		lab.notify("先在左邊選一個位置")
		return
	var ids := selected_assets()
	if ids.is_empty():
		lab.notify("先在下面的清單點選要用的素材")
		return
	var result := PackedStringArray()
	if append:
		result.append_array(lab.doc.planned(_selected_slot))
	for aid in ids:
		if not result.has(aid):
			result.append(aid)
	_write_planned(result)


func _on_planned_submitted(text: String) -> void:
	var ids := PackedStringArray()
	for match in RegEx.create_from_string(PlacementDoc.ASSET_PATTERN).search_all(text):
		var aid := match.get_string()
		if lab.catalog.assets.has(aid):
			ids.append(aid)
		else:
			lab.notify("素材目錄沒有 %s，已略過" % aid)
	_write_planned(ids)


func _write_planned(ids: PackedStringArray) -> void:
	if _selected_slot == "":
		return
	if lab.doc.set_planned(_selected_slot, ids):
		lab.notify("已寫入 %s：%s = %s" % [lab.doc.path.get_file(), _selected_slot, "、".join(ids) if not ids.is_empty() else "（清空）"])
	else:
		lab.notify("寫入失敗：位置清單文件沒有 %s，或無法寫入（看 log）" % _selected_slot)
	refresh()


func _on_manual_toggled(pressed: bool) -> void:
	if _selected_slot == "":
		return
	if lab.doc.set_manual(_selected_slot, pressed):
		lab.notify("%s 的手動放入：%s" % [_selected_slot, "已勾選（套用工具會略過）" if pressed else "取消勾選"])
	refresh()


## 播放這個位置在遊戲裡實際會響的聲音（音效庫的音效，或對應的音樂 cue）。
func _play_in_game() -> void:
	var slot := lab.catalog.slot(_selected_slot)
	if slot.is_empty():
		lab.notify("先在左邊選一個位置")
		return
	var target := StringName(str(slot["target"]))
	if slot["kind"] == "music":
		for cue: String in Music.cue_ids():
			if str(Music.cue_def(StringName(cue)).get("track", "")) == String(target):
				Music.play_cue(StringName(cue), true)
				lab.notify("播放音樂 cue「%s」" % cue)
				return
		lab.notify("沒有 cue 使用曲目「%s」" % target)
	elif str(slot["target"]).begins_with("amb_"):
		lab.notify("環境音在「背景音樂與環境音」分頁試聽" if not Sfx.has_sound(target) else "播放環境音單次片段")
		Sfx.play(target)
	else:
		Sfx.play(target, 0.0, 0.0)
		lab.notify("播放遊戲內音效「%s」（%s）" % [target, Sfx.source_of(target)])


func _stop_all() -> void:
	lab.audition.stop()
	Sfx.stop_all()
	Music.stop(0.3)
	Ambience.stop_all(0.3)
	lab.notify("已停止")


# ---------------------------------------------------------------------------
# 來源與音量微調
# ---------------------------------------------------------------------------

func _show_source(slot: Dictionary) -> void:
	var target := StringName(str(slot["target"]))
	var licenses := _license_packs()
	if slot["kind"] == "music":
		var track := Music.track_def(target)
		_source.text = "來源：音樂檔 %s（授權包 %s，%s）" % [track.get("file", "（無）"), track.get("pack", "（未登記）"), licenses.get(str(track.get("pack", "")), "授權未登記")]
		_volume_slider.editable = false
		_volume_label.text = "音量微調（音樂請到「背景音樂」分頁）"
		return
	var source := Sfx.source_of(target)
	var failed: PackedStringArray = Sfx.bank().failed_files().get(target, PackedStringArray())
	var packs := PackedStringArray()
	for pack in Sfx.bank().packs_of(target):
		packs.append("%s（%s）" % [pack, licenses.get(pack, "授權未登記")])
	var seconds := 0.0
	for stream: AudioStream in Sfx.bank().variants(target):
		seconds = maxf(seconds, stream.get_length())
	match source:
		&"file":
			_source.text = "來源：音效檔 %d 個變體（最長 %.2f 秒），授權包 %s" % [Sfx.bank().variants(target).size(), seconds, "、".join(packs)]
		&"synth":
			_source.text = "來源：程式合成音（沒有音效檔）"
		_:
			_source.text = "來源：未定義"
	if not failed.is_empty():
		_source.text += "　⚠ 缺檔或無法載入：" + "、".join(failed)
	_volume_slider.editable = Sfx.bank().has_files(target)
	_volume_label.text = "音量微調"
	_volume_slider.set_value_no_signal(Sfx.bank().volume_db(target))


## 授權包 id → 授權名稱（從授權登記讀；開發機才有）。
func _license_packs() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets_src/audio/LICENSES.json")) if FileAccess.file_exists("res://assets_src/audio/LICENSES.json") else {}
	var result := {}
	if typeof(parsed) == TYPE_DICTIONARY:
		for pack: String in (parsed as Dictionary).keys():
			result[pack] = str((parsed[pack] as Dictionary).get("license", ""))
	return result


func _on_volume_changed(value: float) -> void:
	var slot := lab.catalog.slot(_selected_slot)
	if slot.is_empty() or slot["kind"] == "music":
		return
	var def: Variant = Sfx.bank().all_defs().get(str(slot["target"]))
	if typeof(def) == TYPE_DICTIONARY:
		(def as Dictionary)["volume_db"] = value
		lab.notify("%s 音量微調 %+.1f dB（尚未儲存）" % [slot["target"], value])


## 預覽或儲存這個位置的音量微調到 data/audio/sound_bank.json（先備份成 .bak）。
func save_volume(dry_run: bool) -> Dictionary:
	var slot := lab.catalog.slot(_selected_slot)
	if slot.is_empty() or slot["kind"] == "music":
		lab.notify("先選一個音效位置")
		return {}
	var value := _volume_slider.value
	var result := AudioDataWriter.apply(SoundBank.PATH, [{"path": ["sounds", str(slot["target"]), "volume_db"], "value": value}], dry_run)
	if not (result["errors"] as PackedStringArray).is_empty():
		lab.notify("沒有寫入：" + "；".join(result["errors"]))
	elif (result["diff"] as PackedStringArray).is_empty():
		lab.notify("和資料檔一樣，沒有差異")
	else:
		lab.notify(("（預覽）" if dry_run else "已儲存，備份在 %s：" % result["backup"]) + "；".join(result["diff"]))
	return result
