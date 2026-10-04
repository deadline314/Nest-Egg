class_name SoundLabMixerTab
extends ScrollContainer
## 實驗室分頁四：混音與診斷。各匯流排的音量與靜音（和設定頁同一份）、即時音量表、同時發聲數與被丟棄數、
## 音效來源統計（檔案或合成音）、缺檔與缺預聽檔的數量。

var lab: SoundLab
var _meters: Dictionary = {}
var _diag: Label
var _refresh_left := 0.0


func _init(p_lab: SoundLab) -> void:
	lab = p_lab
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ready() -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	for entry in Settings.AUDIO_BUSES:
		var bus: StringName = entry["bus"]
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = entry["label"]
		label.custom_minimum_size = Vector2(90, 0)
		label.tooltip_text = entry["tooltip"]
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.value = roundf(Settings.get_volume(bus) * 100.0)
		slider.custom_minimum_size = Vector2(320, 0)
		slider.tooltip_text = "%s（和設定選單同一份）" % entry["tooltip"]
		slider.value_changed.connect(func(v: float) -> void: Settings.set_volume(bus, v / 100.0))
		row.add_child(slider)
		var mute := CheckBox.new()
		mute.text = "靜音"
		mute.tooltip_text = "暫時靜音這條匯流排（只在實驗室裡，不存檔）"
		mute.toggled.connect(func(on: bool) -> void: AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), on))
		row.add_child(mute)
		var meter := ProgressBar.new()
		meter.min_value = -60.0
		meter.max_value = 0.0
		meter.show_percentage = false
		meter.custom_minimum_size = Vector2(240, 18)
		meter.tooltip_text = "即時音量（dBFS）"
		row.add_child(meter)
		_meters[bus] = meter
	_diag = Label.new()
	_diag.tooltip_text = "發聲位使用、被丟棄的聲音、音效來源統計"
	box.add_child(_diag)
	update_diagnostics()


func _process(delta: float) -> void:
	for bus: StringName in _meters.keys():
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			(_meters[bus] as ProgressBar).value = maxf(AudioServer.get_bus_peak_volume_left_db(index, 0), AudioServer.get_bus_peak_volume_right_db(index, 0))
	_refresh_left -= delta
	if _refresh_left <= 0.0 and is_visible_in_tree():
		_refresh_left = 0.5
		update_diagnostics()


func update_diagnostics() -> String:
	var counts: Dictionary = Sfx.source_counts()
	var missing_previews := 0
	for id: String in lab.catalog.assets.keys():
		missing_previews += 0 if lab.catalog.has_preview(id) else 1
	_diag.text = "同時發聲 %d／%d　被丟棄 %d　音效來源：檔案 %d、合成音 %d、載入失敗 %d　缺預聽檔 %d／%d" % [
			Sfx.voices_playing(), Sfx.VOICES, Sfx.dropped_count, int(counts["file"]), int(counts["synth"]), int(counts["failed"]), missing_previews, lab.catalog.assets.size()]
	return _diag.text
