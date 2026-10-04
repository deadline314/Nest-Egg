class_name SoundLabSlotsTab
extends HSplitContainer
## 實驗室分頁一：位置與備選。左邊是遊戲裡所有會響的位置（可依域篩選、搜尋）；右邊是選中位置的資訊、
## 目前用的素材、預計使用（和位置清單文件連動）、備選素材與跨類別搜尋整個素材目錄。
## 所有挑選都立刻寫回位置清單文件（只改那一格）；勾「手動放入」代表你自己已經把檔案放進遊戲，套用工具會略過。

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
var _manual_check: CheckBox
var _auto_play: CheckBox
var _result_tabs: TabContainer
var _candidate_list: ItemList
var _category: OptionButton
var _search_edit: LineEdit
var _search_list: ItemList
var _shown_slots: Array[String] = []
var _selected_slot := ""


func _init(p_lab: SoundLab) -> void:
	lab = p_lab


func _ready() -> void:
	_build_left()
	_build_right()
	refresh()


func _build_left() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	add_child(left)
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
	var actions := HBoxContainer.new()
	right.add_child(actions)
	actions.add_child(_button("▶ 遊戲內實際聲音", _play_in_game, "播放這個位置目前在遊戲裡真的會響的聲音"))
	actions.add_child(_button("■ 全部停止", _stop_all, "停止所有試聽與遊戲內的聲音、音樂"))
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
	right.add_child(_heading("目前用的素材（雙擊試聽）"))
	_current_list = ItemList.new()
	_current_list.custom_minimum_size = Vector2(0, 70)
	_current_list.tooltip_text = "這個位置現在在遊戲裡用的素材；點選即試聽"
	_current_list.item_selected.connect(func(i: int) -> void: _maybe_audition(_current_list, i))
	right.add_child(_current_list)
	var planned_row := HBoxContainer.new()
	right.add_child(planned_row)
	planned_row.add_child(_heading("預計使用："))
	_planned_edit = LineEdit.new()
	_planned_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_planned_edit.placeholder_text = "素材編號，用逗號或頓號分開（任何類別都可以），按 Enter 寫入"
	_planned_edit.tooltip_text = "你想在這個位置用的素材編號；按 Enter 寫進位置清單文件"
	_planned_edit.text_submitted.connect(_on_planned_submitted)
	planned_row.add_child(_planned_edit)
	planned_row.add_child(_button("清除", func() -> void: _write_planned(PackedStringArray()), "清掉這個位置的預計使用"))
	_manual_check = CheckBox.new()
	_manual_check.text = "手動放入"
	_manual_check.tooltip_text = "打勾 = 你自己已經把檔案放進遊戲了，套用工具會略過這個位置"
	_manual_check.toggled.connect(_on_manual_toggled)
	planned_row.add_child(_manual_check)
	_result_tabs = TabContainer.new()
	_result_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_result_tabs)
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
	var picks := HBoxContainer.new()
	right.add_child(picks)
	picks.add_child(_button("▶ 試聽選中的", _audition_selected, "播放選中素材的預聽檔"))
	picks.add_child(_button("設為預計使用", func() -> void: _pick(false), "用選中的素材取代這個位置的預計使用（可以多選）"))
	picks.add_child(_button("加入預計使用", func() -> void: _pick(true), "把選中的素材加到這個位置的預計使用後面"))
	_fill_search()


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
		_slot_list.add_item("%s %s  %s" % [mark, sid, slot["name"]])
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
	_current_list.clear()
	for aid: String in slot["current"]:
		_current_list.add_item(_asset_line(aid))
		_current_list.set_item_metadata(_current_list.item_count - 1, aid)
	if _current_list.item_count == 0:
		_current_list.add_item("（目前是程式合成音，沒有素材檔）")
		_current_list.set_item_disabled(0, true)
	_planned_edit.text = "、".join(lab.doc.planned(slot_id))
	_manual_check.set_pressed_no_signal(lab.doc.is_manual(slot_id))
	_fill_list(_candidate_list, slot["candidates"], lab.doc.planned(slot_id))


func _fill_list(list: ItemList, ids: Array, planned: PackedStringArray) -> void:
	list.clear()
	for aid: String in ids:
		list.add_item(("★ " if planned.has(aid) else "") + _asset_line(aid))
		list.set_item_metadata(list.item_count - 1, aid)
		var a := lab.catalog.asset(aid)
		list.set_item_tooltip(list.item_count - 1, "%s／%s\n%s" % [a.get("pack", ""), a.get("file", ""), a.get("desc", "")])


func _asset_line(aid: String) -> String:
	var a := lab.catalog.asset(aid)
	var file := str(a.get("file", "")).get_file()
	return "%s  %5.1fs  %s／%s" % [aid, float(a.get("dur", 0.0)), str(a.get("pack", "")).trim_prefix("oga_").trim_prefix("kenney_"), file]


func _fill_search() -> void:
	var code := ""
	if _category != null and _category.selected > 0:
		code = str(_category.get_item_metadata(_category.selected))
	_fill_list(_search_list, lab.catalog.search(_search_edit.text, code, 300) if _search_edit != null else [], lab.doc.planned(_selected_slot))


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
