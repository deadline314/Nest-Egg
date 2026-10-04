class_name SoundLabMusicTab
extends ScrollContainer
## 實驗室分頁三：背景音樂與環境音。列出所有 cue 試聽、跳到結尾前幾秒聽迴圈接縫、交叉淡化到另一首；
## 模擬「某個關卡與光影區段、某個狀態」會選到哪個 cue；環境音依光影區段試聽。

const SEAM_LEAD := 5.0

var lab: SoundLab
var _cue_list: ItemList
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
