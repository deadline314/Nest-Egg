class_name SoundLabApplyPanel
extends Control
## 「套用到遊戲」（NE-186）：列出位置清單裡「預計使用」和遊戲現在用的不一樣的位置，使用者勾選要套用的，
## 確認後才由 apply_placements.py 在背景改寫加工清單、重建音訊檔與音效庫、授權登記。取消或關閉不改任何東西。
## 有警告的位置（例如武器射擊音效只挑了一個素材，音訊測試會失敗）預設不勾，要用的話自己勾。

const POLL_INTERVAL := 0.5
const INTRO := "把位置清單裡你挑的「預計使用」換進遊戲：改寫加工清單、重建全部音訊檔與音效庫、授權登記，並更新「遊戲現在用」。手動放入有勾的位置與沒變的位置不會動。"
const NEXT_STEPS := "接下來：切回 Godot 編輯器等它匯入新的音訊檔，重開實驗室才聽得到；跑一下音訊測試；再提交（改動在 audio/、data/audio、assets_src/audio、design/16-audio）。"

var lab: SoundLab
var runner: ApplyToolRunner

var _changes: Array = []
var _checks: Array[CheckBox] = []
var _rows: VBoxContainer
var _problems: Label
var _apply_button: Button
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _status: Label
var _handle := -1
var _started_msec := 0
var _poll_left := 0.0
var _applying := false


func setup(p_lab: SoundLab, p_runner: ApplyToolRunner) -> void:
	lab = p_lab
	runner = p_runner


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "套用到遊戲"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override(&"font_color", Palette.CYAN)
	header.add_child(title)
	header.add_child(_button("關閉", close, "關閉（套用進行中不能關；Esc 也可以）"))
	var intro := Label.new()
	intro.text = INTRO
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	var pick_row := HBoxContainer.new()
	box.add_child(pick_row)
	pick_row.add_child(_button("全選", func() -> void: set_all(true), "勾選所有位置（包含有警告的）"))
	pick_row.add_child(_button("全不選", func() -> void: set_all(false), "取消所有勾選"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_problems = Label.new()
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.3))
	_problems.tooltip_text = "工具發現的問題（看不懂的編號、素材目錄沒有的編號…）；這些位置不會套用"
	box.add_child(_problems)
	_apply_button = _button("套用", request_apply, "先出確認，確認後才開始套用")
	_apply_button.disabled = true
	box.add_child(_apply_button)
	_confirm_box = VBoxContainer.new()
	_confirm_box.visible = false
	box.add_child(_confirm_box)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_box.add_child(_confirm_label)
	var confirm_row := HBoxContainer.new()
	_confirm_box.add_child(confirm_row)
	confirm_row.add_child(_button("確認套用", func() -> void: confirm_apply(), "開始套用；要重建全部音訊，約一到三分鐘，期間不能操作實驗室"))
	confirm_row.add_child(_button("取消", cancel_apply, "不套用，什麼都不改"))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.tooltip_text = "最近一次操作的結果"
	box.add_child(_status)
	if not _changes.is_empty():
		_show_changes()


func _button(text: String, action: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button


# ---------------------------------------------------------------------------
# 載入
# ---------------------------------------------------------------------------

## 開啟並列出會改的位置（呼叫套用工具的 --dry-run）。回傳是否成功。
func open() -> bool:
	_set_status("讀取位置清單與素材目錄…")
	if is_inside_tree():
		await get_tree().process_frame
	var result := runner.preview()
	if not bool(result["ok"]):
		_set_status("無法套用：" + str(result["error"]))
		if lab != null:
			lab.notify("套用到遊戲：" + str(result["error"]))
		return false
	load_preview(result)
	return true


func load_preview(result: Dictionary) -> void:
	_changes = (result.get("changes", []) as Array).duplicate()  # 套用完會清空，不能動到呼叫端的陣列
	if _rows == null:
		return
	_show_changes()
	var problems: PackedStringArray = result.get("problems", PackedStringArray())
	_problems.text = "注意：\n" + "\n".join(problems) if not problems.is_empty() else ""


func _show_changes() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_checks.clear()
	for change: Dictionary in _changes:
		var warnings: Array = change.get("warnings", [])
		var check := CheckBox.new()
		check.text = "%s %s：%s → %s" % [change["slot"], change["name"], "、".join(change["current"]) if not (change["current"] as Array).is_empty() else "（合成音）", "、".join(change["planned"])]
		check.button_pressed = warnings.is_empty()
		check.tooltip_text = "勾選 = 套用這個位置；%s" % ("有警告，預設不勾" if not warnings.is_empty() else "沒有警告")
		check.toggled.connect(func(_on: bool) -> void: _update_button())
		check.set_meta(&"slot", str(change["slot"]))
		_rows.add_child(check)
		_checks.append(check)
		for warning: Variant in warnings:
			var label := Label.new()
			label.text = "　　⚠ %s" % warning
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.3))
			label.tooltip_text = "這個位置的警告"
			_rows.add_child(label)
	if _changes.is_empty():
		var none := Label.new()
		none.text = "沒有需要套用的位置：預計使用都和遊戲現在用的一樣、已勾手動放入，或還沒挑。"
		none.tooltip_text = "沒有可套用的位置"
		_rows.add_child(none)
	_update_button()
	_set_status("勾選要套用的位置，按「套用」。" if not _changes.is_empty() else "")


func checked_slots() -> PackedStringArray:
	var result := PackedStringArray()
	for check in _checks:
		if check.button_pressed:
			result.append(str(check.get_meta(&"slot")))
	return result


func set_all(on: bool) -> void:
	for check in _checks:
		check.button_pressed = on
	_update_button()


func _update_button() -> void:
	var count := checked_slots().size()
	_apply_button.text = "套用選中的 %d 個位置" % count
	_apply_button.disabled = count == 0 or _applying


# ---------------------------------------------------------------------------
# 套用（先確認，確認才開始）
# ---------------------------------------------------------------------------

## 顯示確認內容；什麼都還沒改。回傳是否進入確認。
func request_apply() -> bool:
	var slots := checked_slots()
	if slots.is_empty():
		_set_status("先勾選要套用的位置")
		return false
	if _applying:
		return false
	_confirm_label.text = "確認套用 %d 個位置？\n會改寫 assets_src/audio/pipeline.json，重建 audio/ 的音訊檔、data/audio/sound_bank.json、授權登記與位置清單；要重建全部音訊，約一到三分鐘。\n（改動都在版本控制裡，不滿意可以還原。）" % slots.size()
	_confirm_box.visible = true
	_apply_button.disabled = true
	return true


func cancel_apply() -> void:
	_confirm_box.visible = false
	_update_button()
	_set_status("已取消，什麼都沒改。")


func is_confirming() -> bool:
	return _confirm_box.visible


func is_applying() -> bool:
	return _applying


## 確認後在背景開始套用；回傳是否啟動。完成由 _process 輪詢。
func confirm_apply() -> bool:
	_confirm_box.visible = false
	var started := runner.start(checked_slots())
	if not bool(started["ok"]):
		_set_status("無法套用：" + str(started["error"]))
		_update_button()
		return false
	_handle = int(started["handle"])
	_applying = true
	_started_msec = Time.get_ticks_msec()
	_poll_left = 0.0
	_apply_button.disabled = true
	_set_status("套用中…（重建全部音訊，約一到三分鐘；期間請不要操作實驗室）")
	return true


func _process(delta: float) -> void:
	if not _applying:
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_INTERVAL
	poll_now()


## 檢查背景的套用有沒有結束；結束就顯示結果並重新載入實驗室的資料。
func poll_now() -> void:
	if not _applying:
		return
	var state := runner.poll(_handle)
	if bool(state.get("running", false)):
		_set_status("套用中…已經 %d 秒（重建全部音訊，約一到三分鐘；期間請不要操作實驗室）" % int((Time.get_ticks_msec() - _started_msec) / 1000.0))
		return
	_applying = false
	finish(state.get("result", {}))


func finish(result: Dictionary) -> void:
	var applied: Array = result.get("applied", [])
	if bool(result.get("ok", false)):
		_set_status("已套用 %d 個位置。\n%s" % [applied.size(), NEXT_STEPS])
	else:
		_set_status("套用失敗：%s" % result.get("error", "不明原因"))
	if lab != null:
		lab.catalog.load_all()
		lab.doc.reload_if_changed()
		lab.slots_tab.refresh()
		lab.notify("套用到遊戲：" + _status.text.split("\n")[0])
	_changes.clear()
	for check in _checks:
		check.disabled = true
	_apply_button.disabled = true


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if _confirm_box.visible:
			cancel_apply()
		else:
			close()
		get_viewport().set_input_as_handled()


## 關閉；套用進行中不能關（改了一半的資料不能丟下不管）。
func close() -> bool:
	if _applying:
		_set_status("套用還在進行，等它結束再關閉。")
		return false
	if lab != null and lab.apply_panel == self:
		lab.apply_panel = null
	queue_free()
	return true


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
