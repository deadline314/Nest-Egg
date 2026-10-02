class_name SettingsScreen
extends Control
## 設定畫面（主選單與暫停選單共用）：音量、按鍵綁定、顯示。
## 所有變更即時生效並自動存檔。暫停中也能操作（process_mode = ALWAYS）。

signal closed

const JOY_SLOT := -1
const LABEL_WIDTH := 120.0
const BINDING_WIDTH := 92.0

var _tabs: TabContainer
var _status: Label
var _sliders: Dictionary[StringName, HSlider] = {}
var _slider_values: Dictionary[StringName, Label] = {}
var _hud_auto_hide: CheckButton
var _quality_option: OptionButton
var _brightness_slider: HSlider
var _brightness_value: Label
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
	_tabs.add_child(_build_display_tab())

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
# 顯示
# ---------------------------------------------------------------------------

func _build_display_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "顯示"
	box.add_theme_constant_override(&"separation", 10)
	_hud_auto_hide = CheckButton.new()
	_hud_auto_hide.text = "HUD 自動隱藏"
	_hud_auto_hide.tooltip_text = "開啟：生命與護盾閒置時淡出，受傷或格擋時才出現；關閉：一律顯示"
	_hud_auto_hide.focus_mode = Control.FOCUS_ALL
	_hud_auto_hide.button_pressed = Settings.get_hud_auto_hide()
	_hud_auto_hide.toggled.connect(func(on: bool) -> void:
		Settings.set_hud_auto_hide(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_hud_auto_hide)
	box.add_child(_build_brightness_row())
	box.add_child(_build_quality_row())
	return box


func _build_quality_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.tooltip_text = "光影品質：機器跑不順時調低；每一檔的差異見選項說明"
	var name_label := UiKit.label("光影品質", 12)
	name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(name_label)
	_quality_option = OptionButton.new()
	_quality_option.focus_mode = Control.FOCUS_ALL
	_quality_option.custom_minimum_size = Vector2(120, 0)
	for tier in [LightQuality.Tier.HIGH, LightQuality.Tier.MEDIUM, LightQuality.Tier.LOW]:
		_quality_option.add_item(LightQuality.NAMES[tier], tier)
		_quality_option.set_item_tooltip(_quality_option.item_count - 1, LightQuality.DESCRIPTIONS[tier])
	_quality_option.tooltip_text = LightQuality.DESCRIPTIONS[Settings.get_light_quality()]
	_select_quality_item()
	_quality_option.item_selected.connect(_on_quality_selected)
	row.add_child(_quality_option)
	return row


func _select_quality_item() -> void:
	_quality_option.select(_quality_option.get_item_index(Settings.get_light_quality()))


func _on_quality_selected(index: int) -> void:
	var tier := _quality_option.get_item_id(index)
	Settings.set_light_quality(tier)
	_quality_option.tooltip_text = LightQuality.DESCRIPTIONS[tier]
	_set_status("光影品質「%s」：%s" % [LightQuality.NAMES[tier], LightQuality.DESCRIPTIONS[tier]], Palette.CYAN)


func _build_brightness_row() -> Control:
	var tooltip := "調整暗場的明暗；預設（50%）就是設計的壓抑程度，覺得太暗可以調高"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.tooltip_text = tooltip
	var name_label := UiKit.label("亮度", 12)
	name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(name_label)
	_brightness_slider = HSlider.new()
	_brightness_slider.min_value = 0
	_brightness_slider.max_value = 100
	_brightness_slider.step = 5
	_brightness_slider.custom_minimum_size = Vector2(260, 16)
	_brightness_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_brightness_slider.focus_mode = Control.FOCUS_ALL
	_brightness_slider.tooltip_text = tooltip
	_brightness_slider.value = roundf(Settings.get_brightness() * 100.0)
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	row.add_child(_brightness_slider)
	_brightness_value = UiKit.label("", 12, Palette.CYAN)
	_brightness_value.custom_minimum_size = Vector2(48, 0)
	row.add_child(_brightness_value)
	_update_brightness_label()
	return row


func _on_brightness_changed(value: float) -> void:
	Settings.set_brightness(value / 100.0)
	_update_brightness_label()


func _update_brightness_label() -> void:
	_brightness_value.text = "%d%%" % roundi(Settings.get_brightness() * 100.0)


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
		headers.append("鍵盤／滑鼠 %d" % (slot + 1))
	headers.append("手把")
	for header in headers:
		grid.add_child(UiKit.label(header, 10, Palette.UI_MUTED))

	for entry in InputBindings.ACTIONS:
		var action: StringName = entry["id"]
		var label := UiKit.label(entry["label"], 11)
		label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		grid.add_child(label)
		for slot in InputBindings.KEY_SLOTS:
			grid.add_child(_make_binding_button(action, slot, "點擊後按下新按鍵或滑鼠鍵；Backspace 清除"))
		grid.add_child(_make_binding_button(action, JOY_SLOT, "點擊後按下手把按鈕；搖桿與扳機固定不可改"))
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
			_binding_buttons[_binding_key(action, slot)].text = InputBindings.code_label(InputBindings.get_code(action, slot))
		_binding_buttons[_binding_key(action, JOY_SLOT)].text = InputBindings.joy_label(action)


func _begin_capture(action: StringName, slot: int) -> void:
	_cancel_capture()
	_capturing = true
	_capture_action = action
	_capture_slot = slot
	_binding_buttons[_binding_key(action, slot)].text = "按下…"
	if slot == JOY_SLOT:
		_set_status("為「%s」按下手把按鈕（Esc 取消）" % InputBindings.action_label(action), Palette.WARNING)
	else:
		_set_status("為「%s」按下按鍵或滑鼠鍵（Esc 取消、Backspace 清除）" % InputBindings.action_label(action), Palette.WARNING)


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
	var pressed_key: bool = event is InputEventKey and event.is_pressed() and not event.is_echo()
	var pressed_mouse: bool = event is InputEventMouseButton and event.is_pressed()
	if pressed_key or pressed_mouse:
		get_viewport().set_input_as_handled()
		_capture_code(InputBindings.code_from_event(event))
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		if _capture_slot == JOY_SLOT:
			_finish_capture(InputBindings.set_joy_button(_capture_action, (event as InputEventJoypadButton).button_index))


func _capture_code(code: int) -> void:
	if code == KEY_ESCAPE:
		_cancel_capture()
		return
	if _capture_slot == JOY_SLOT or code == InputBindings.NONE:
		return
	if code == KEY_BACKSPACE:
		_finish_capture(InputBindings.set_code(_capture_action, _capture_slot, InputBindings.NONE))
		return
	if InputBindings.is_reserved(code):
		_set_status("此按鍵保留給系統（Esc、數字鍵 1～4、F 鍵），請換一個。", Palette.DANGER)
		return
	_finish_capture(InputBindings.set_code(_capture_action, _capture_slot, code))


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
	elif _tabs.current_tab == 1:
		InputBindings.reset_to_defaults()
		_set_status("按鍵已恢復預設。", Palette.CYAN)
	else:
		Settings.reset_display()
		_hud_auto_hide.set_pressed_no_signal(Settings.get_hud_auto_hide())
		_brightness_slider.set_value_no_signal(roundf(Settings.get_brightness() * 100.0))
		_update_brightness_label()
		_select_quality_item()
		_quality_option.tooltip_text = LightQuality.DESCRIPTIONS[Settings.get_light_quality()]
		_set_status("顯示已恢復預設。", Palette.CYAN)


func _set_status(text: String, color := Palette.UI_MUTED) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _focus_first() -> void:
	if not _sliders.is_empty():
		_sliders.values()[0].grab_focus()
