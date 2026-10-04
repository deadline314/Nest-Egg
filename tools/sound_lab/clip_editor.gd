class_name SoundLabClipEditor
extends Control
## 音訊片段擷取介面（NE-180）：看原始完整音訊的波形與依靜音找出的各段，選一段或框選、微調起訖、試聽，
## 按「擷取成新素材」後先確認，確認才由 clip_tool.py 輸出成新素材；取消或關閉不寫任何檔案、不改任何清單。
## 工具與資料見 NE-179、design/16-audio/DESIGN.md 5.4。

const MIN_CLIP := 0.01
const PREPARE_HINT := "解出完整波形與各段，長檔案要等幾秒…"

var lab: SoundLab
var runner: ClipToolRunner
var waveform: ClipWaveform
var asset_id := ""

var _info: Dictionary = {}
var _stream: AudioStream
var _player := AudioStreamPlayer.new()
var _play_end := 0.0
var _title: Label
var _details: Label
var _status: Label
var _segment_row: HFlowContainer
var _scroll: HScrollBar
var _start_spin: SpinBox
var _end_spin: SpinBox
var _length_label: Label
var _loop_check: CheckBox
var _play_button: Button
var _note_edit: LineEdit
var _plan_check: CheckBox
var _export_button: Button
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _syncing := false


func setup(p_lab: SoundLab, p_runner: ClipToolRunner) -> void:
	lab = p_lab
	runner = p_runner


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.04
	panel.anchor_right = 0.96
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override(&"font_color", Palette.CYAN)
	header.add_child(_title)
	header.add_child(_button("關閉", close, "關閉擷取介面（不會寫任何檔案；Esc 也可以）"))
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details)
	waveform = ClipWaveform.new()
	waveform.size_flags_vertical = Control.SIZE_EXPAND_FILL
	waveform.range_changed.connect(_on_range_changed)
	waveform.view_changed.connect(_sync_scroll)
	box.add_child(waveform)
	_scroll = HScrollBar.new()
	_scroll.tooltip_text = "拖動捲軸平移波形（放大後才有得捲）"
	_scroll.value_changed.connect(func(value: float) -> void:
		if not _syncing:
			waveform.set_view(value, waveform.view_length))
	box.add_child(_scroll)
	var zoom_row := HBoxContainer.new()
	box.add_child(zoom_row)
	zoom_row.add_child(_button("放大", func() -> void: waveform.zoom(ClipWaveform.ZOOM_STEP * 1.6, _view_center()), "放大波形（滑鼠滾輪也可以）"))
	zoom_row.add_child(_button("縮小", func() -> void: waveform.zoom(1.0 / (ClipWaveform.ZOOM_STEP * 1.6), _view_center()), "縮小波形"))
	zoom_row.add_child(_button("看全部", waveform.zoom_all, "顯示整段音訊"))
	zoom_row.add_child(_button("放大到選取範圍", _zoom_to_range, "把波形放大到剛好看到選取的範圍，方便微調邊緣"))
	var seg_label := Label.new()
	seg_label.text = "各段（依靜音自動找出，點一下選用）："
	box.add_child(seg_label)
	_segment_row = HFlowContainer.new()
	box.add_child(_segment_row)
	var range_row := HBoxContainer.new()
	box.add_child(range_row)
	_start_spin = _spin(range_row, "起點 秒", "選取範圍的起點（秒），可以直接輸入")
	_end_spin = _spin(range_row, "終點 秒", "選取範圍的終點（秒），可以直接輸入")
	_length_label = Label.new()
	_length_label.tooltip_text = "選取的時長"
	range_row.add_child(_length_label)
	var play_row := HBoxContainer.new()
	box.add_child(play_row)
	_play_button = _button("▶ 試聽選取範圍", play_selection, "播放選取的範圍（空白鍵也可以）；播放中調整範圍立刻生效")
	play_row.add_child(_play_button)
	play_row.add_child(_button("■ 停止", stop_playback, "停止試聽"))
	_loop_check = CheckBox.new()
	_loop_check.text = "循環"
	_loop_check.tooltip_text = "試聽到終點時回到起點重播，方便聽邊緣有沒有爆音或殘留"
	play_row.add_child(_loop_check)
	var save_row := HBoxContainer.new()
	box.add_child(save_row)
	_note_edit = LineEdit.new()
	_note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_edit.placeholder_text = "說明（選填，例如：第二發、帶迴響）"
	_note_edit.tooltip_text = "寫進新素材的說明，之後搜尋得到"
	save_row.add_child(_note_edit)
	_plan_check = CheckBox.new()
	_plan_check.text = "擷取後設為這個位置的預計使用"
	_plan_check.tooltip_text = "預設不勾；勾了會把新素材寫進左邊選中位置的「預計使用」"
	save_row.add_child(_plan_check)
	_export_button = _button("✂ 擷取成新素材", request_export, "先出確認，確認後才輸出成新檔案")
	save_row.add_child(_export_button)
	_confirm_box = VBoxContainer.new()
	_confirm_box.visible = false
	box.add_child(_confirm_box)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_box.add_child(_confirm_label)
	var confirm_row := HBoxContainer.new()
	_confirm_box.add_child(confirm_row)
	confirm_row.add_child(_button("確認擷取", func() -> void: confirm_export(), "真的輸出成新素材檔"))
	confirm_row.add_child(_button("取消", cancel_export, "不擷取，什麼都不寫"))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.tooltip_text = "最近一次操作的結果"
	box.add_child(_status)
	_player.finished.connect(func() -> void: waveform.set_cursor(-1.0))
	add_child(_player)
	if not _info.is_empty():
		_show_info()


func _spin(parent: Control, title: String, tip: String) -> SpinBox:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.step = 0.001
	spin.min_value = 0.0
	spin.max_value = 0.0
	spin.custom_minimum_size = Vector2(120, 0)
	spin.tooltip_text = tip
	spin.value_changed.connect(func(_v: float) -> void: _on_spin_changed())
	parent.add_child(spin)
	return spin


func _button(text: String, action: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button


# ---------------------------------------------------------------------------
# 載入
# ---------------------------------------------------------------------------

## 開啟並載入這個素材（呼叫擷取工具解出完整波形，可能要幾秒）。回傳是否成功。
func open(p_asset_id: String) -> bool:
	asset_id = p_asset_id
	_set_status(PREPARE_HINT)
	if is_inside_tree():
		_title.text = "擷取片段：%s" % asset_id
		await get_tree().process_frame
	var result := runner.prepare(asset_id)
	if not bool(result["ok"]):
		_fail_open(str(result["error"]))
		return false
	var dir := str((result["data"] as Dictionary).get("dir", ""))
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(dir.path_join("info.json"))) == OK else null
	var stream := AudioStreamOggVorbis.load_from_file(dir.path_join("long.ogg")) if FileAccess.file_exists(dir.path_join("long.ogg")) else null
	if typeof(parsed) != TYPE_DICTIONARY or stream == null:
		_fail_open("擷取工具的輸出讀不了（%s 缺少 info.json 或 long.ogg），重跑：python tools/audio/clip_tool.py prepare %s" % [dir, asset_id])
		return false
	load_prepared(parsed, stream)
	return true


## 載入準備好的資料（info 的格式見 clip_tool.py prepare）與完整長預聽。
func load_prepared(info: Dictionary, stream: AudioStream) -> void:
	_info = info
	_stream = stream
	asset_id = str(info.get("asset", asset_id))
	_player.bus = &"Music" if asset_id.begins_with("MUS-") else &"SFX"
	if waveform != null:
		_show_info()


func _show_info() -> void:
	var segments: Array = _info.get("segments", [])
	var seconds := float(_info.get("preview_duration", 0.0))
	_title.text = "擷取片段：%s" % lab.asset_line(asset_id).strip_edges() if lab != null else "擷取片段：%s" % asset_id
	var text := "原檔 %.2f 秒、%d Hz、%d 聲道；依靜音找到 %d 段。" % [float(_info.get("duration", 0.0)), int(_info.get("sample_rate", 0)), int(_info.get("channels", 1)), segments.size()]
	if bool(_info.get("truncated", false)):
		text += "　⚠ 檔案太長，只載入前 %.0f 秒，後面的部分選不到。" % seconds
	_details.text = text
	waveform.set_data(_info.get("peaks", []), segments, seconds)
	_syncing = true
	_start_spin.max_value = seconds
	_end_spin.max_value = seconds
	_syncing = false
	for child in _segment_row.get_children():
		child.queue_free()
	for i in segments.size():
		var index := i
		var button := _button("第 %d 段  %.2f–%.2f" % [i + 1, float(segments[i][0]), float(segments[i][1])], func() -> void: select_segment(index), "選用這一段（再用把手或輸入微調）")
		_segment_row.add_child(button)
	if segments.is_empty():
		var none := Label.new()
		none.text = "（沒有找到分段：直接在波形上框選）"
		_segment_row.add_child(none)
	else:
		select_segment(0)
	_set_status("拖動波形上的綠色把手，或點一段，再按「試聽選取範圍」。")
	_update_buttons()


func _fail_open(message: String) -> void:
	_info = {}
	_stream = null
	if waveform != null:
		waveform.set_data([], [], 0.0)
	_set_status("無法擷取：" + message)
	if lab != null:
		lab.notify("擷取介面：" + message)
	_update_buttons()


# ---------------------------------------------------------------------------
# 選取範圍
# ---------------------------------------------------------------------------

func select_segment(index: int) -> void:
	var segments: Array = _info.get("segments", [])
	if index < 0 or index >= segments.size():
		return
	waveform.set_range(float(segments[index][0]), float(segments[index][1]))
	_on_range_changed(waveform.range_start, waveform.range_end)


func set_range(start: float, end: float) -> void:
	waveform.set_range(start, end)
	_on_range_changed(waveform.range_start, waveform.range_end)


func selected_range() -> Vector2:
	return Vector2(waveform.range_start, waveform.range_end)


func _on_range_changed(start: float, end: float) -> void:
	_syncing = true
	_start_spin.set_value_no_signal(start)
	_end_spin.set_value_no_signal(end)
	_syncing = false
	_length_label.text = "時長 %.3f 秒" % (end - start)
	_update_buttons()


func _on_spin_changed() -> void:
	if not _syncing:
		set_range(_start_spin.value, _end_spin.value)


func _update_buttons() -> void:
	var usable := _stream != null and waveform != null and waveform.range_end - waveform.range_start >= MIN_CLIP
	_export_button.disabled = not usable
	_play_button.disabled = not usable


func _zoom_to_range() -> void:
	var length := waveform.range_end - waveform.range_start
	if length > 0.0:
		waveform.set_view(waveform.range_start - length * 0.25, length * 1.5)


func _view_center() -> float:
	return waveform.view_start + waveform.view_length / 2.0


func _sync_scroll() -> void:
	_syncing = true
	_scroll.max_value = maxf(waveform.duration, 0.001)
	_scroll.page = waveform.view_length
	_scroll.value = waveform.view_start
	_scroll.visible = waveform.view_length < waveform.duration - 0.0001
	_syncing = false


# ---------------------------------------------------------------------------
# 試聽
# ---------------------------------------------------------------------------

func play_selection() -> bool:
	if _stream == null or waveform.range_end - waveform.range_start < MIN_CLIP:
		_set_status("先選一段（至少 %.2f 秒）" % MIN_CLIP)
		return false
	if lab != null:
		lab.audition.stop()
	Music.stop(0.2)
	_play_end = waveform.range_end
	_player.stream = _stream
	_player.play(waveform.range_start)
	return true


func stop_playback() -> void:
	if _player.playing:
		_player.stop()
	waveform.set_cursor(-1.0)


func is_playing() -> bool:
	return _player.playing


func _process(_delta: float) -> void:
	if not _player.playing:
		return
	var at := _player.get_playback_position()
	if at >= waveform.range_end or at < waveform.range_start - 0.05:
		if _loop_check.button_pressed and waveform.range_end - waveform.range_start >= MIN_CLIP:
			_player.seek(waveform.range_start)
			at = waveform.range_start
		else:
			stop_playback()
			return
	waveform.set_cursor(at)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		if _confirm_box.visible:
			cancel_export()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_SPACE and not (get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is SpinBox):
		if is_playing():
			stop_playback()
		else:
			play_selection()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 擷取（先確認，確認才輸出）
# ---------------------------------------------------------------------------

## 顯示確認內容；什麼都還沒寫。回傳是否進入確認。
func request_export() -> bool:
	var span := selected_range()
	if _stream == null or asset_id.is_empty():
		_set_status("還沒有載入音訊")
		return false
	if span.y - span.x < MIN_CLIP:
		_set_status("選取範圍太短，至少 %.2f 秒" % MIN_CLIP)
		return false
	stop_playback()
	var note := _note_edit.text.strip_edges()
	_confirm_label.text = "確認擷取？\n來源：%s\n範圍：%.3f – %.3f 秒（%.3f 秒）\n新素材編號：%s（實際以輸出為準）\n說明：%s\n確認後才會輸出成新檔案；取消不會寫任何東西。" % [
		lab.asset_line(asset_id).strip_edges() if lab != null else asset_id, span.x, span.y, span.y - span.x, next_id_preview(), note if not note.is_empty() else "（沒有）"]
	_confirm_box.visible = true
	_export_button.disabled = true
	return true


func cancel_export() -> void:
	_confirm_box.visible = false
	_update_buttons()
	_set_status("已取消，沒有寫任何東西。")


func is_confirming() -> bool:
	return _confirm_box.visible


## 確認後真的輸出；回傳工具的結果（{"ok", "error", "data"}）。
func confirm_export() -> Dictionary:
	var span := selected_range()
	_confirm_box.visible = false
	_set_status("輸出中…")
	if is_inside_tree():
		await get_tree().process_frame
	var result := runner.export_clip(asset_id, span.x, span.y, _note_edit.text.strip_edges())
	_update_buttons()
	if not bool(result["ok"]):
		_set_status("擷取失敗：%s" % result["error"])
		if lab != null:
			lab.notify("擷取失敗：%s" % result["error"])
		return result
	var data: Dictionary = result["data"]
	var new_id := str(data.get("id", ""))
	var message := "這個範圍已經擷取過，既有素材是 %s。" % new_id if bool(data.get("existing", false)) else "已擷取成新素材 %s（%.3f 秒），左邊的搜尋已列出它。" % [new_id, float(data.get("duration", span.y - span.x))]
	if not bool(data.get("existing", false)) and not bool(data.get("preview", false)):
		message += "　預聽檔沒做成，補上：python tools/audio/build_candidates.py --only %s" % new_id
	if lab != null:
		lab.catalog.load_all()
		lab.slots_tab.show_in_search(new_id)
		if _plan_check.button_pressed:
			message += "　" + ("已設為預計使用。" if lab.slots_tab.plan_asset(new_id) else "沒能設為預計使用（先在左邊選一個位置）。")
		lab.notify(message)
	_set_status(message)
	return result


## 新素材編號的預覽：類別與原檔相同、接在該類最大編號後面（片段清單裡記得的編號也算，不重用）。
func next_id_preview() -> String:
	var prefix := asset_id.split("-")[0]
	var highest := 0
	var ids: Array = lab.catalog.assets.keys() if lab != null else []
	var clips: Variant = JSON.parse_string(FileAccess.get_file_as_string(AudioCatalog.CLIPS_PATH)) if FileAccess.file_exists(AudioCatalog.CLIPS_PATH) else null
	if typeof(clips) == TYPE_DICTIONARY and typeof((clips as Dictionary).get("clips")) == TYPE_ARRAY:
		for clip: Variant in (clips as Dictionary)["clips"]:
			if typeof(clip) == TYPE_DICTIONARY:
				ids.append(str((clip as Dictionary).get("id", "")))
	for id: String in ids:
		if id.begins_with(prefix + "-"):
			highest = maxi(highest, int(id.split("-")[1]))
	return "%s-%04d" % [prefix, highest + 1]


func close() -> void:
	stop_playback()
	if lab != null and lab.clip_editor == self:
		lab.clip_editor = null
	queue_free()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
