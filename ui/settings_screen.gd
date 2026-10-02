class_name SettingsScreen
extends Control
## 設定畫面（主選單與暫停選單共用）：音量、按鍵綁定。
## 所有變更即時生效並自動存檔。暫停中也能操作（process_mode = ALWAYS）。

signal closed

const JOY_SLOT := -1
const LABEL_WIDTH := 120.0
const BINDING_WIDTH := 92.0

var _tabs: TabContainer
var _status: Label
var _sliders: Dictionary[StringName, HSlider] = {}
var _slider_values: Dictionary[StringName, Label] = {}
## "action:slot" -> Button
var _binding_buttons: Dictionary[String, Button] = {}

var _capturing := false
var _capture_action: StringName = &""
var _capture_slot := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(Palette.BG_FAR, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 24
	layout.offset_right = -24
	layout.offset_top = 14
	layout.offset_bottom = -12
	layout.add_theme_constant_override(&"separation", 6)
	add_child(layout)
	layout.add_child(UiKit.label("設定", 16, Palette.CYAN))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_tab: int) -> void: _cancel_capture())
	layout.add_child(_tabs)
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_bindings_tab())

	_status = UiKit.label("", 10, Palette.UI_MUTED)
	layout.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	layout.add_child(buttons)
	buttons.add_child(UiKit.button("恢復預設", _reset_current_tab, "只重設目前分頁"))
	var back := UiKit.button("返回", close, "設定已自動儲存")
	buttons.add_child(back)

	InputBindings.bindings_changed.connect(_refresh_bindings)
	_refresh_bindings()
	_set_status("所有變更即時生效並自動儲存。")
	_focus_first.call_deferred()


func close() -> void:
	_cancel_capture()
	Settings.save_now()
	closed.emit()
	queue_free()


# ---------------------------------------------------------------------------
# 音量
# ---------------------------------------------------------------------------

func _build_audio_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "音量"
	box.add_theme_constant_override(&"separation", 10)
	for entry in Settings.AUDIO_BUSES:
		var bus: StringName = entry["bus"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.tooltip_text = entry["tooltip"]
		var name_label := UiKit.label(entry["label"], 12)
		name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(260, 16)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_ALL
		slider.tooltip_text = entry["tooltip"]
		slider.value = roundf(Settings.get_volume(bus) * 100.0)
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		row.add_child(slider)
		var value_label := UiKit.label("", 12, Palette.CYAN)
		value_label.custom_minimum_size = Vector2(48, 0)
		row.add_child(value_label)
		box.add_child(row)
		_sliders[bus] = slider
		_slider_values[bus] = value_label
		_update_volume_label(bus)
	return box


func _on_volume_changed(value: float, bus: StringName) -> void:
	Settings.set_volume(bus, value / 100.0)
	_update_volume_label(bus)
	# 試聽：用介面音效讓玩家立刻聽到差異。
	Sfx.play(&"ui_confirm", -6.0, 0.0)


func _update_volume_label(bus: StringName) -> void:
	if _slider_values.has(bus):
		var value := Settings.get_volume(bus)
		_slider_values[bus].text = "靜音" if value <= 0.001 else "%d%%" % roundi(value * 100.0)


# ---------------------------------------------------------------------------
# 按鍵
# ---------------------------------------------------------------------------

func _build_bindings_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "按鍵"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2 + InputBindings.KEY_SLOTS
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 4)
	scroll.add_child(grid)

	var headers: Array[String] = ["動作"]
	for slot in InputBindings.KEY_SLOTS:
		headers.append("鍵盤 %d" % (slot + 1))
	headers.append("手把")
	for header in headers:
		grid.add_child(UiKit.label(header, 10, Palette.UI_MUTED))

	for entry in InputBindings.ACTIONS:
		var action: StringName = entry["id"]
		var label := UiKit.label(entry["label"], 11)
		label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		grid.add_child(label)
		for slot in InputBindings.KEY_SLOTS:
			grid.add_child(_make_binding_button(action, slot, "點擊後按下新按鍵；Backspace 清除"))
		grid.add_child(_make_binding_button(action, JOY_SLOT, "點擊後按下手把按鈕；搖桿方向固定不可改"))
	return scroll


func _make_binding_button(action: StringName, slot: int, tooltip: String) -> Button:
	var button := UiKit.button("", _begin_capture.bind(action, slot), tooltip)
	button.custom_minimum_size = Vector2(BINDING_WIDTH, 0)
	_binding_buttons[_binding_key(action, slot)] = button
	return button


func _binding_key(action: StringName, slot: int) -> String:
	return "%s:%d" % [action, slot]


func _refresh_bindings() -> void:
	for entry in InputBindings.ACTIONS:
		var action: StringName = entry["id"]
		for slot in InputBindings.KEY_SLOTS:
			_binding_buttons[_binding_key(action, slot)].text = InputBindings.key_label(InputBindings.get_key(action, slot))
		_binding_buttons[_binding_key(action, JOY_SLOT)].text = InputBindings.joy_label(InputBindings.get_joy_button(action))


func _begin_capture(action: StringName, slot: int) -> void:
	_cancel_capture()
	_capturing = true
	_capture_action = action
	_capture_slot = slot
	_binding_buttons[_binding_key(action, slot)].text = "按下…"
	if slot == JOY_SLOT:
		_set_status("為「%s」按下手把按鈕（Esc 取消）" % InputBindings.action_label(action), Palette.WARNING)
	else:
		_set_status("為「%s」按下鍵盤按鍵（Esc 取消、Backspace 清除）" % InputBindings.action_label(action), Palette.WARNING)


func _cancel_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	_refresh_bindings()
	_set_status("已取消。")


func _input(event: InputEvent) -> void:
	if not _capturing:
		if event.is_action_pressed(&"ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		_capture_key(event as InputEventKey)
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		if _capture_slot == JOY_SLOT:
			_finish_capture(InputBindings.set_joy_button(_capture_action, (event as InputEventJoypadButton).button_index))
	elif event is InputEventMouseButton and event.pressed:
		_cancel_capture()


func _capture_key(event: InputEventKey) -> void:
	var keycode := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if keycode == KEY_ESCAPE:
		_cancel_capture()
		return
	if _capture_slot == JOY_SLOT:
		return
	if keycode == KEY_BACKSPACE:
		_finish_capture(InputBindings.set_key(_capture_action, _capture_slot, KEY_NONE))
		return
	if keycode in InputBindings.RESERVED_KEYS:
		_set_status("此按鍵保留給系統，請換一個。", Palette.DANGER)
		return
	_finish_capture(InputBindings.set_key(_capture_action, _capture_slot, keycode))


func _finish_capture(swapped: StringName) -> void:
	var action := _capture_action
	_capturing = false
	_refresh_bindings()
	var message := "已更新「%s」。" % InputBindings.action_label(action)
	if swapped != &"":
		message += "原本的按鍵已與「%s」互換。" % InputBindings.action_label(swapped)
	_set_status(message, Palette.CYAN)
	Sfx.play(&"ui_confirm", -6.0, 0.0)


# ---------------------------------------------------------------------------

func _reset_current_tab() -> void:
	_cancel_capture()
	if _tabs.current_tab == 0:
		Settings.reset_audio()
		for bus: StringName in _sliders.keys():
			_sliders[bus].set_value_no_signal(roundf(Settings.get_volume(bus) * 100.0))
			_update_volume_label(bus)
		_set_status("音量已恢復預設。", Palette.CYAN)
	else:
		InputBindings.reset_to_defaults()
		_set_status("按鍵已恢復預設。", Palette.CYAN)


func _set_status(text: String, color := Palette.UI_MUTED) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _focus_first() -> void:
	if not _sliders.is_empty():
		_sliders.values()[0].grab_focus()
