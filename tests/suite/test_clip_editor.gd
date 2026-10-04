class_name ClipEditorSuite
extends TestSuite
## 音訊片段擷取介面（NE-180）：波形與各段、拖動與輸入微調起訖、試聽、確認後才輸出（取消不寫任何東西）、錯誤顯示、
## 擷取後的搜尋與預計使用；測試不依賴本機素材與外部程式：擷取工具換成假的，音訊用合成的。

const LAB_SCENE := "res://tools/sound_lab/sound_lab.tscn"
const COPY_PATH := "user://test_audio_clip_placements.md"
const LAYOUT_PATH := "user://test_audio_clip_layout.cfg"
const DURATION := 2.0


## 假的擷取工具：記錄呼叫，回傳事先設定好的結果。
class FakeRunner:
	extends ClipToolRunner
	var prepare_result := {"ok": false, "error": "未設定", "data": {}}
	var export_result := {"ok": true, "error": "", "data": {"id": "GUN-9990", "existing": false, "duration": 0.4, "preview": true}}
	var prepare_calls := 0
	var export_calls: Array = []

	func prepare(_asset_id: String) -> Dictionary:
		prepare_calls += 1
		return prepare_result

	func export_clip(asset_id: String, start: float, end: float, note := "") -> Dictionary:
		export_calls.append([asset_id, start, end, note])
		return export_result


## 假的命令列結果：測試 ClipToolRunner 怎麼解讀工具的輸出。
class ScriptedRunner:
	extends ClipToolRunner
	var run_result := {"exit_code": 0, "output": ""}
	var last_args := PackedStringArray()

	func _run(args: PackedStringArray) -> Dictionary:
		last_args = args
		return run_result


func run() -> void:
	_test_runner()
	await _test_editor()
	_cleanup()


func _cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))


func _test_runner() -> void:
	var runner := ScriptedRunner.new()
	runner.run_result = {"exit_code": 0, "output": "some warning\n{\"id\": \"GUN-1\", \"existing\": false}\n"}
	var ok := runner.export_clip("GUN-0031", 0.5, 0.9, "第二發")
	check(bool(ok["ok"]) and str(ok["data"]["id"]) == "GUN-1", "a result line after warnings is read")
	check(runner.last_args.has("--start") and runner.last_args.has("0.5000") and runner.last_args.has("--note") and runner.last_args.has("--json"), "the export arguments carry the range, note and --json")
	runner.run_result = {"exit_code": 1, "output": "{\"error\": \"GUN-0031：起訖不合法\"}"}
	var bad := runner.prepare("GUN-0031")
	check(not bool(bad["ok"]) and str(bad["error"]).contains("起訖不合法"), "the tool's error message is passed on")
	runner.run_result = {"exit_code": -1, "output": ""}
	check(str(runner.prepare("GUN-0031")["error"]).contains("Python"), "a missing Python explains what to install")
	runner.run_result = {"exit_code": 0, "output": "not json at all"}
	check(not bool(runner.prepare("GUN-0031")["ok"]), "unreadable output is a failure, not a crash")
	runner.run_result = {"exit_code": 3, "output": "{\"id\": \"x\"}"}
	check(not bool(runner.prepare("GUN-0031")["ok"]), "a non-zero exit code is a failure")


func _tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(int(DURATION * 22050.0) * 2)
	stream.data = data
	return stream


func _info() -> Dictionary:
	var peaks: Array = []
	for i in 2000:
		peaks.append([-0.5, 0.5])
	return {"asset": "GUN-0031", "duration": DURATION, "preview_duration": DURATION, "truncated": false, "sample_rate": 96000, "channels": 2,
		"peaks": peaks, "segments": [[0.0, 0.4], [1.0, 1.5]]}


func _mouse(x: float, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(x, 20)
	return event


func _motion(x: float) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(x, 20)
	return event


func _tooltip_gaps(node: Node, into: PackedStringArray) -> void:
	if node is Button or node is LineEdit or node is SpinBox or node is CheckBox or node is HScrollBar or node is ClipWaveform:
		if (node as Control).tooltip_text.is_empty():
			into.append("%s（%s）" % [node.name, node.get_class()])
	for child in node.get_children():
		_tooltip_gaps(child, into)


func _test_editor() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(COPY_PATH))
	var lab := (load(LAB_SCENE) as PackedScene).instantiate() as SoundLab
	lab.doc_path = COPY_PATH
	lab.stage_enabled = false
	lab.layout_path = LAYOUT_PATH
	var fake := FakeRunner.new()
	lab.clip_runner = fake
	runner.get_tree().root.add_child(lab)
	await frames(3)

	# ---- 開啟失敗：工具回報錯誤、輸出讀不了；都只顯示說明
	fake.prepare_result = {"ok": false, "error": "找不到 GUN-0031 的原始檔（先執行 fetch_audio.py）", "data": {}}
	check(not await lab.open_clip_editor("GUN-0031"), "opening fails when the tool reports an error")
	var editor := lab.clip_editor
	check(editor != null and editor._status.text.contains("原始檔") and editor._export_button.disabled and editor._play_button.disabled, "the error is shown and export and play stay disabled")
	check(lab.status_label.text.contains("原始檔"), "the lab status line repeats the error")
	fake.prepare_result = {"ok": true, "error": "", "data": {"dir": "user://test_audio_no_such_clip_dir"}}
	check(not await lab.open_clip_editor("GUN-0031") and lab.clip_editor._status.text.contains("info.json"), "unreadable tool output says which files are missing")
	check(fake.prepare_calls == 2, "each open asks the tool once")
	editor = lab.clip_editor
	await frames(2)

	# ---- 載入：波形、各段、預設選第一段
	editor.load_prepared(_info(), _tone())
	await frames(2)
	var wave := editor.waveform
	check(wave.peaks.size() == 2000 and is_equal_approx(wave.duration, DURATION) and wave.size.x > 50.0, "the waveform shows the whole original")
	check(editor._segment_row.get_child_count() == 2 and editor._details.text.contains("2 段"), "each silence-separated segment gets a button")
	check(is_equal_approx(wave.range_start, 0.0) and is_equal_approx(wave.range_end, 0.4) and editor._length_label.text.contains("0.400"), "the first segment is selected at the start")
	check(not editor._export_button.disabled and not editor._play_button.disabled, "export and play are enabled with a valid range")
	editor.select_segment(1)
	check(is_equal_approx(wave.range_start, 1.0) and is_equal_approx(wave.range_end, 1.5) and is_equal_approx(editor._start_spin.value, 1.0), "choosing a segment selects it and fills the boxes")

	# ---- 滑鼠：框選、拖把手、點選一段
	wave._gui_input(_mouse(wave.x_at_time(0.5), true))
	wave._gui_input(_motion(wave.x_at_time(0.9)))
	wave._gui_input(_mouse(wave.x_at_time(0.9), false))
	check(absf(wave.range_start - 0.5) < 0.01 and absf(wave.range_end - 0.9) < 0.01, "dragging on empty waveform selects a new range")
	wave._gui_input(_mouse(wave.x_at_time(0.5), true))
	wave._gui_input(_motion(wave.x_at_time(0.3)))
	wave._gui_input(_mouse(wave.x_at_time(0.3), false))
	check(absf(wave.range_start - 0.3) < 0.01 and absf(wave.range_end - 0.9) < 0.01, "dragging the start handle moves only the start")
	wave._gui_input(_mouse(wave.x_at_time(0.3), true))
	wave._gui_input(_motion(wave.x_at_time(1.5)))
	wave._gui_input(_mouse(wave.x_at_time(1.5), false))
	check(wave.range_start < wave.range_end and wave.range_end - wave.range_start >= ClipWaveform.MIN_RANGE - 0.0001, "a handle cannot cross the other one")
	wave._gui_input(_mouse(wave.x_at_time(1.2), true))
	wave._gui_input(_mouse(wave.x_at_time(1.2), false))
	check(is_equal_approx(wave.range_start, 1.0) and is_equal_approx(wave.range_end, 1.5), "clicking inside a segment selects the whole segment")
	wave._gui_input(_mouse(wave.x_at_time(0.7), true))
	wave._gui_input(_mouse(wave.x_at_time(0.7), false))
	check(is_equal_approx(wave.range_start, 1.0), "clicking in a gap changes nothing")
	editor.set_range(-1.0, 9.0)
	check(is_equal_approx(wave.range_start, 0.0) and is_equal_approx(wave.range_end, DURATION), "a range is clamped to the audio")

	# ---- 輸入秒數、縮放與捲動
	editor._start_spin.value = 0.25
	check(is_equal_approx(wave.range_start, 0.25), "typing a start time moves the selection")
	wave.zoom(2.0, 1.0)
	check(is_equal_approx(wave.view_length, 1.0) and wave.view_start >= 0.0 and editor._scroll.visible, "zooming in shows a part and the scroll bar")
	editor._scroll.value = 0.5
	check(is_equal_approx(wave.view_start, 0.5), "the scroll bar pans the waveform")
	editor.set_range(0.5, 0.9)
	editor._zoom_to_range()
	check(wave.view_length < DURATION, "zooming to the selection shows a narrower view")
	wave.zoom_all()
	check(is_equal_approx(wave.view_length, DURATION) and not editor._scroll.visible, "showing everything hides the scroll bar")

	# ---- 太短的範圍不能擷取
	editor.set_range(0.5, 0.5)
	check(editor._export_button.disabled and not editor.request_export() and editor._status.text.contains("太短"), "an empty range cannot be exported")
	check(not editor.play_selection(), "an empty range cannot be played")

	# ---- 試聽：單次到終點停、循環回到起點
	editor.set_range(0.2, 0.6)
	check(editor.play_selection() and editor.is_playing(), "the selection plays")
	editor._player.seek(0.61)
	editor._process(0.0)
	check(not editor.is_playing() and wave.cursor < 0.0, "playback stops at the end of the selection")
	editor._loop_check.button_pressed = true
	check(editor.play_selection(), "the selection plays again with loop on")
	editor._player.seek(0.61)
	editor._process(0.0)
	check(editor.is_playing() and wave.cursor >= 0.2 - 0.001 and wave.cursor < 0.6, "looping returns to the start (cursor %.3f)" % wave.cursor)
	editor.stop_playback()
	editor._loop_check.button_pressed = false

	# ---- 確認前什麼都不輸出；取消不輸出；確認才輸出
	editor.set_range(1.0, 1.5)
	editor._note_edit.text = "第二發"
	check(editor.request_export() and editor.is_confirming() and fake.export_calls.is_empty(), "asking to export only shows the confirmation")
	check(editor._confirm_label.text.contains("GUN-0031") and editor._confirm_label.text.contains("1.000") and editor._confirm_label.text.contains("1.500") and editor._confirm_label.text.contains(editor.next_id_preview()) and editor._confirm_label.text.contains("第二發"),
		"the confirmation lists the source, range, new id and note")
	check(editor.next_id_preview().begins_with("GUN-") and not lab.catalog.assets.has(editor.next_id_preview()), "the new id preview is an unused id of the same category")
	editor.cancel_export()
	check(not editor.is_confirming() and fake.export_calls.is_empty() and editor._status.text.contains("取消"), "cancelling writes nothing")
	var assets_before := lab.catalog.assets.size()
	editor.request_export()
	var result: Dictionary = await editor.confirm_export()
	check(bool(result["ok"]) and fake.export_calls.size() == 1, "confirming exports once")
	check(fake.export_calls[0][0] == "GUN-0031" and absf(float(fake.export_calls[0][1]) - 1.0) < 0.001 and absf(float(fake.export_calls[0][2]) - 1.5) < 0.001 and fake.export_calls[0][3] == "第二發", "the confirmed range and note are what is exported")
	check(editor._status.text.contains("GUN-9990") and lab.status_label.text.contains("GUN-9990"), "the new asset id is reported")
	check(lab.slots_tab._result_tabs.current_tab == 1 and lab.slots_tab._search_edit.text == "GUN-9990", "the search tab lists the new asset")
	check(lab.catalog.assets.size() == assets_before, "the test did not change the real catalog")

	# ---- 設為預計使用（預設不勾）、已存在、失敗
	lab.slots_tab.select_slot("P-WPN-001")
	var planned_before := lab.doc.planned("P-WPN-001")
	check(not editor._plan_check.button_pressed, "setting the planned asset is off by default")
	editor._plan_check.button_pressed = true
	editor.request_export()
	await editor.confirm_export()
	check(lab.doc.planned("P-WPN-001") == PackedStringArray(["GUN-9990"]) and planned_before != lab.doc.planned("P-WPN-001"), "the plan option writes the new asset to the selected slot")
	editor._plan_check.button_pressed = false
	fake.export_result = {"ok": true, "error": "", "data": {"id": "GUN-0400", "existing": true}}
	editor.request_export()
	await editor.confirm_export()
	check(editor._status.text.contains("已經擷取過") and editor._status.text.contains("GUN-0400"), "an existing clip is reported, not duplicated")
	fake.export_result = {"ok": false, "error": "GUN-0031：寫入失敗（disk full）", "data": {}}
	var calls := fake.export_calls.size()
	editor.request_export()
	var failed: Dictionary = await editor.confirm_export()
	check(not bool(failed["ok"]) and editor._status.text.contains("擷取失敗") and editor._status.text.contains("disk full") and fake.export_calls.size() == calls + 1, "a failed export shows the tool's reason")
	check(not editor._export_button.disabled, "the editor stays usable after a failure")

	# ---- tooltip 與關閉
	var gaps := PackedStringArray()
	_tooltip_gaps(editor, gaps)
	check(gaps.is_empty(), "every control of the editor has a tooltip: %s" % ", ".join(gaps.slice(0, 5)))
	lab.slots_tab._candidate_list.deselect_all()
	lab.slots_tab._search_list.deselect_all()
	lab.slots_tab._open_clip_editor()
	check(lab.clip_editor == editor and lab.status_label.text.contains("先在下面"), "the button without a selected asset only explains")
	editor.close()
	await frames(2)
	check(lab.clip_editor == null and not is_instance_valid(editor), "closing removes the editor")
	lab.audition.stop()
	lab.queue_free()
	await frames(2)
