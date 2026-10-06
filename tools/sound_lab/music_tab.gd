class_name SoundLabMusicTab
extends ScrollContainer
## 實驗室分頁三：背景音樂與環境音。列出所有 cue 試聽、跳到結尾前幾秒聽迴圈接縫、交叉淡化到另一首；
## 選中 cue 後列出它那首曲子的備選曲目，可試聽、設成預計使用（寫回位置清單文件）；
## 模擬「某個關卡與光影區段、某個狀態」會選到哪個 cue；環境音依光影區段試聽。

const SEAM_LEAD := 5.0

var lab: SoundLab
var _cue_list: ItemList
var _candidate_list: ItemList
var _candidate_note: Label
var _note_base := ""
var _sting_row: HBoxContainer
var _start_spin: SpinBox
var _info: Label
var _zone: OptionButton
var _state: OptionButton
var _resolved: Label
var _ambience_zone: OptionButton
var _ambience_info: Label
var _volume: HSlider
var _cue_volume: HSlider
var _fade_in: HSlider
var _fade_out: HSlider


func _init(p_lab: SoundLab) -> void:
	lab = p_lab
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ready() -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	box.add_child(_heading("背景音樂 cue"))
	_cue_list = ItemList.new()
	_cue_list.custom_minimum_size = Vector2(0, 220)
	_cue_list.tooltip_text = "雙擊播放；曲目、淡入淡出秒數與授權包都列在後面"
	_cue_list.item_activated.connect(func(_i: int) -> void: play_selected())
	box.add_child(_cue_list)
	for cue: Variant in Music.cue_ids():
		var def := Music.cue_def(StringName(str(cue)))
		var track := Music.track_def(StringName(str(def.get("track", ""))))
		_cue_list.add_item("%s　→ %s（淡入 %.1f／淡出 %.1f 秒，%s）" % [cue, def.get("track", ""), float(def.get("fade_in", 1.5)), float(def.get("fade_out", 1.5)), track.get("pack", "")])
		_cue_list.set_item_metadata(_cue_list.item_count - 1, str(cue))
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("▶ 播放", play_selected, "播放選中的 cue（交叉淡化）"))
	row.add_child(_button("▶ 跳到結尾前 5 秒", seek_to_seam, "從結尾前 5 秒開始聽，檢查迴圈接縫是否自然"))
	row.add_child(_button("■ 停止", func() -> void: Music.stop(0.5), "淡出停止"))
	row.add_child(_button("目前 cue", show_now_playing, "顯示現在播放的 cue、狀態與位置"))
	_volume = HSlider.new()
	_volume.min_value = -24.0
	_volume.max_value = 6.0
	_volume.step = 0.5
	_volume.value = 0.0
	_volume.custom_minimum_size = Vector2(200, 0)
	_volume.tooltip_text = "暫時調整正在播放的音樂音量（dB，不寫入資料）"
	_volume.value_changed.connect(func(v: float) -> void: Music.player().set_volume(v, 0.1))
	row.add_child(_volume)
	_info = Label.new()
	_info.tooltip_text = "現在播放的 cue 與位置"
	box.add_child(_info)
	row = HBoxContainer.new()
	box.add_child(row)
	_cue_volume = _slider(row, "cue 音量 dB", -24.0, 12.0, 0.5, "選中 cue 的音量（dB），拖動立刻生效")
	_fade_in = _slider(row, "淡入 秒", 0.0, 10.0, 0.1, "選中 cue 的淡入秒數")
	_fade_out = _slider(row, "淡出 秒", 0.0, 10.0, 0.1, "選中 cue 的淡出秒數")
	row.add_child(_button("預覽差異", func() -> void: save_cue(true), "列出和 music.json 不同的數值，不寫入"))
	row.add_child(_button("儲存", func() -> void: save_cue(false), "驗證後寫回 data/audio/music.json（先備份成 .bak）"))
	_cue_list.item_selected.connect(func(_i: int) -> void: _load_cue_values())

	box.add_child(_heading("備選曲目（選一個 cue 後，列出可以換成它的曲子）"))
	_candidate_list = ItemList.new()
	_candidate_list.custom_minimum_size = Vector2(0, 200)
	_candidate_list.tooltip_text = "★ 已填預計使用　（目前）正在用的曲子；雙擊試聽預聽檔前 60 秒，響度已調成和遊戲內一致"
	_candidate_list.item_activated.connect(func(_i: int) -> void: audition_candidate())
	_candidate_list.item_selected.connect(func(_i: int) -> void: _update_note())
	box.add_child(_candidate_list)
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("▶ 試聽備選", audition_candidate, "播放選中的備選曲目（會先停掉正在播的 cue）"))
	row.add_child(_button("★ 設為預計使用", pick_candidate, "把選中的曲目寫進位置清單文件的「預計使用」，之後用套用工具換進遊戲"))
	row.add_child(_button("■ 停止試聽", func() -> void: lab.audition.stop(), "停止備選曲目的試聽"))
	_sting_row = HBoxContainer.new()
	_sting_row.visible = false
	box.add_child(_sting_row)
	var start_label := Label.new()
	start_label.text = "短曲起點 秒"
	_sting_row.add_child(start_label)
	_start_spin = SpinBox.new()
	_start_spin.min_value = 0.0
	_start_spin.max_value = 600.0
	_start_spin.step = 0.5
	_start_spin.tooltip_text = "通關、死亡短曲從原曲第幾秒開始取 %d 秒（0＝從頭）；「設為預計使用」會一起寫進位置清單。預聽檔只有原曲前 %d 秒" % [int(PlacementDoc.STING_SECONDS), int(SoundLab.MUSIC_PREVIEW_SECONDS)]
	_start_spin.value_changed.connect(func(_v: float) -> void: _update_note())
	_sting_row.add_child(_start_spin)
	_sting_row.add_child(_button("▶ 試聽取用範圍", audition_candidate, "只播選中的備選曲目從這個起點起的 %d 秒，也就是套用後短曲實際會用的段落" % int(PlacementDoc.STING_SECONDS)))
	_candidate_note = Label.new()
	_candidate_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_candidate_note)

	box.add_child(_heading("狀態模擬：這個光影區段、這個狀態會播哪個 cue"))
	row = HBoxContainer.new()
	box.add_child(row)
	_zone = OptionButton.new()
	_zone.tooltip_text = "光影設定 id（遊戲裡的區段）"
	for zone in _zone_ids():
		_zone.add_item(zone)
	row.add_child(_zone)
	_state = OptionButton.new()
	_state.tooltip_text = "平靜、安全區、戰鬥、頭目"
	for state in Music.STATES:
		_state.add_item(state)
	row.add_child(_state)
	row.add_child(_button("查詢", simulate, "查出這個區段與狀態會選到的 cue（戰鬥、頭目的一串 cue 每次查詢會輪流）"))
	row.add_child(_button("▶ 查詢並播放", func() -> void: simulate(true), "查詢後直接播放"))
	_resolved = Label.new()
	box.add_child(_resolved)

	box.add_child(_heading("環境音（依光影區段）"))
	row = HBoxContainer.new()
	box.add_child(row)
	_ambience_zone = OptionButton.new()
	_ambience_zone.tooltip_text = "選一個光影區段，播放它的環境音層"
	for zone in _zone_ids():
		_ambience_zone.add_item(zone)
	row.add_child(_ambience_zone)
	row.add_child(_button("▶ 播放環境音", play_ambience, "播放這個區段的環境音（最多三層）"))
	row.add_child(_button("■ 停止", func() -> void: Ambience.stop_all(0.5), "淡出停止"))
	_ambience_info = Label.new()
	box.add_child(_ambience_info)


func _slider(parent: Control, title: String, low: float, high: float, step: float, tip: String) -> HSlider:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size = Vector2(150, 0)
	slider.tooltip_text = tip
	slider.value_changed.connect(func(_v: float) -> void: _apply_cue_values())
	parent.add_child(slider)
	return slider


func _load_cue_values() -> void:
	_fill_candidates()
	var def := Music.cue_def(StringName(selected_cue()))
	for pair: Array in [[_cue_volume, "volume_db", 0.0], [_fade_in, "fade_in", 1.5], [_fade_out, "fade_out", 1.5]]:
		(pair[0] as HSlider).set_value_no_signal(float(def.get(pair[1], pair[2])))


## 拖動滑桿：立刻改記憶體中的 cue 資料（下一次播放生效；正在播這個 cue 的音量也跟著動）。
func _apply_cue_values() -> void:
	var cue := selected_cue()
	var def: Variant = Music._cues.get(cue)
	if typeof(def) != TYPE_DICTIONARY:
		return
	(def as Dictionary)["volume_db"] = _cue_volume.value
	(def as Dictionary)["fade_in"] = _fade_in.value
	(def as Dictionary)["fade_out"] = _fade_out.value
	if Music.current_cue() == StringName(cue):
		var track := Music.track_def(StringName(str((def as Dictionary).get("track", ""))))
		Music.player().set_volume(_cue_volume.value + float(track.get("volume_db", 0.0)), 0.1)
	lab.notify("cue「%s」音量 %+.1f dB、淡入 %.1f、淡出 %.1f 秒（尚未儲存）" % [cue, _cue_volume.value, _fade_in.value, _fade_out.value])


func save_cue(dry_run: bool) -> Dictionary:
	var cue := selected_cue()
	if cue.is_empty():
		lab.notify("先選一個 cue")
		return {}
	var changes := [
		{"path": ["cues", cue, "volume_db"], "value": _cue_volume.value},
		{"path": ["cues", cue, "fade_in"], "value": _fade_in.value},
		{"path": ["cues", cue, "fade_out"], "value": _fade_out.value}]
	var result := AudioDataWriter.apply(Music.PATH, changes, dry_run)
	if not (result["errors"] as PackedStringArray).is_empty():
		lab.notify("沒有寫入：" + "；".join(result["errors"]))
	elif (result["diff"] as PackedStringArray).is_empty():
		lab.notify("和資料檔一樣，沒有差異")
	else:
		lab.notify(("（預覽）" if dry_run else "已儲存，備份在 %s：" % result["backup"]) + "；".join(result["diff"]))
	return result


func selected_cue() -> String:
	var picked := _cue_list.get_selected_items()
	return str(_cue_list.get_item_metadata(picked[0])) if not picked.is_empty() else ""


func select_cue(cue: String) -> void:
	for i in _cue_list.item_count:
		if str(_cue_list.get_item_metadata(i)) == cue:
			_cue_list.select(i)
			_load_cue_values()


## 選中 cue 的曲子對應的位置登記（BGM 域、target 是曲目 id）；沒有登記回傳空字典。
func slot_for_cue(cue: String) -> Dictionary:
	var track := str(Music.cue_def(StringName(cue)).get("track", ""))
	for slot: Dictionary in lab.catalog.slots_in("BGM"):
		if str(slot["target"]) == track:
			return slot
	return {}


## 這個 cue 的備選曲目編號（不論有沒有預聽檔）。
func candidate_ids(cue: String) -> PackedStringArray:
	var result := PackedStringArray()
	for aid: String in slot_for_cue(cue).get("candidates", []):
		result.append(aid)
	return result


func _fill_candidates() -> void:
	_candidate_list.clear()
	var cue := selected_cue()
	var slot := slot_for_cue(cue)
	if slot.is_empty():
		_candidate_note.text = "這首曲子沒有位置登記，沒有備選（見 data/audio/slots.json）"
		return
	var planned := lab.doc.planned(str(slot["id"]))
	var sting := is_sting(slot)
	_sting_row.visible = sting
	if sting:
		_start_spin.set_value_no_signal(lab.doc.planned_start(str(slot["id"])))
	var hidden := 0
	for aid in candidate_ids(cue):
		if not lab.catalog.has_preview(aid):
			hidden += 1
			continue
		var tag := "（目前）" if (slot["current"] as Array).has(aid) else ""
		var taken := range_text(aid, lab.doc.planned_start(str(slot["id"]))) if sting and planned.has(aid) else ""
		_candidate_list.add_item("%s%s%s%s" % ["★ " if planned.has(aid) else "", tag, lab.asset_line(aid), taken])
		_candidate_list.set_item_metadata(_candidate_list.item_count - 1, aid)
		var a := lab.catalog.asset(aid)
		_candidate_list.set_item_tooltip(_candidate_list.item_count - 1, "%s／%s
%s" % [a.get("pack", ""), a.get("file", ""), a.get("desc", "")])
	_note_base = "%s：%d 首備選" % [slot["id"], _candidate_list.item_count]
	if hidden > 0:
		_note_base += "；另有 %d 首沒有預聽檔而隱藏，補齊：python tools/audio/build_candidates.py" % hidden
	_update_note()


## 備選說明；短曲位置多一句「選中曲目會取用的範圍」。
func _update_note() -> void:
	var text := _note_base
	if _sting_row.visible:
		var aid := selected_candidate()
		var taken := range_text(aid, _start_spin.value) if not aid.is_empty() else ""
		text += "；短曲取用範圍：" + (taken.trim_prefix("（").trim_suffix("）") if not taken.is_empty() else "選一首曲子後顯示（短於 %d 秒的整首使用）" % int(PlacementDoc.STING_SECONDS))
	_candidate_note.text = text


static func is_sting(slot: Dictionary) -> bool:
	return str(slot.get("target", "")).ends_with("_sting")


## 短曲從 start 秒起取用的範圍，例如「（取第 30–42 秒）」；曲子不比取用長度長就是整首，回傳空字串。
func range_text(asset_id: String, start: float) -> String:
	var length := float(lab.catalog.asset(asset_id).get("dur", 0.0))
	if length <= PlacementDoc.STING_SECONDS and start <= 0.0:
		return ""
	return "（取第 %s–%s 秒）" % [PlacementDoc.seconds_text(start), PlacementDoc.seconds_text(minf(length, start + PlacementDoc.STING_SECONDS))]


func selected_candidate() -> String:
	var picked := _candidate_list.get_selected_items()
	return str(_candidate_list.get_item_metadata(picked[0])) if not picked.is_empty() else ""


func audition_candidate() -> bool:
	var aid := selected_candidate()
	if aid.is_empty():
		lab.notify("先在備選曲目選一首")
		return false
	Music.stop(0.3)
	if _sting_row.visible:
		return lab.audition_asset(aid, _start_spin.value, PlacementDoc.STING_SECONDS)
	return lab.audition_asset(aid)


## 把選中的備選曲目設成這個位置的預計使用（只改位置清單文件那一格）。
func pick_candidate() -> bool:
	var aid := selected_candidate()
	var slot := slot_for_cue(selected_cue())
	if aid.is_empty() or slot.is_empty():
		lab.notify("先選一個 cue，再在備選曲目選一首")
		return false
	var start := _start_spin.value if is_sting(slot) else 0.0
	if not lab.doc.set_planned(str(slot["id"]), PackedStringArray([aid]), start):
		lab.notify("寫入失敗：位置清單文件沒有 %s，或無法寫入（看 log）" % slot["id"])
		return false
	lab.notify("已寫入 %s：%s 預計使用 %s%s" % [lab.doc.path.get_file(), slot["id"], aid, range_text(aid, start) if is_sting(slot) else ""])
	_fill_candidates()
	return true


func play_selected() -> bool:
	var cue := selected_cue()
	if cue.is_empty():
		lab.notify("先選一個 cue")
		return false
	var played := Music.play_cue(StringName(cue), true)
	lab.notify("播放 cue「%s」%s" % [cue, "" if played else "（失敗：看 log）"])
	return played


## 把正在播的音樂跳到結尾前幾秒，聽迴圈接縫。
func seek_to_seam() -> bool:
	var stream := Music.player().current_stream()
	if stream == null or not Music.is_playing():
		lab.notify("先播放一個 cue")
		return false
	Music.player().seek(maxf(0.0, stream.get_length() - SEAM_LEAD))
	lab.notify("跳到結尾前 %.0f 秒，聽接縫" % SEAM_LEAD)
	return true


func show_now_playing() -> void:
	_info.text = "目前 cue：%s　狀態：%s　位置：%.1f／%.1f 秒" % [Music.current_cue(), Music.current_state(), Music.player().playback_position(), Music.player().current_stream().get_length() if Music.player().current_stream() != null else 0.0]


func simulate(play := false) -> StringName:
	var cue := Music.resolve_cue(&"", StringName(_zone.get_item_text(_zone.selected)), StringName(_state.get_item_text(_state.selected)), true)
	_resolved.text = "→ %s" % (str(cue) if cue != &"" else "（沒有 cue：維持靜音）")
	if play and cue != &"":
		Music.play_cue(cue)
	return cue


func play_ambience() -> void:
	var zone := StringName(_ambience_zone.get_item_text(_ambience_zone.selected))
	Ambience.set_zone(zone)
	var names := PackedStringArray()
	for layer: Dictionary in Ambience.layers_for(zone):
		names.append("%s（%+.0f dB）" % [layer.get("sound", ""), float(layer.get("volume_db", 0.0))])
	_ambience_info.text = "%s：%s" % [zone, "、".join(names) if not names.is_empty() else "（沒有環境音）"]


func _zone_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for file in DirAccess.get_files_at("res://data/lighting"):
		if file.ends_with(".tres"):
			ids.append(file.trim_suffix(".tres"))
	ids.sort()
	return ids


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
