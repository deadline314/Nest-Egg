class_name SettingsScreen
extends Control
## 設定畫面（主選單與暫停選單共用）：音量、按鍵綁定、顯示。
## 所有變更即時生效並自動存檔。暫停中也能操作（process_mode = ALWAYS）。

signal closed

const JOY_SLOT := -1
const LABEL_WIDTH := 120.0
## 列標題的左內距，與切換鈕的內距相同，整頁每一列的文字對齊。
const ROW_INDENT := 6.0
static var _indent_box: StyleBoxEmpty
const BINDING_WIDTH := 92.0

var _tabs: TabContainer
var _status: Label
var _sliders: Dictionary[StringName, HSlider] = {}
var _slider_values: Dictionary[StringName, Label] = {}
var _fullscreen: CheckButton
var _hud_auto_hide: CheckButton
var _quality_option: OptionButton
var _reduce_flashes: CheckButton
var _reduce_ui_motion: CheckButton
var _dash_silhouettes: CheckButton
var _skip_cutscenes: CheckButton
var _smooth_font: CheckButton
var _text_scale_option: OptionButton
var _zoom_pulse: CheckButton
var _damage_numbers: CheckButton
var _feel_sliders: Dictionary[String, HSlider] = {}
var _feel_values: Dictionary[String, Label] = {}
var _quest_toggles: Dictionary[String, CheckButton] = {}
var _brightness_slider: HSlider
var _brightness_value: Label
## "action:slot" -> Button
var _binding_buttons: Dictionary[String, Button] = {}
var _controller_sliders: Dictionary[String, HSlider] = {}
var _controller_values: Dictionary[String, Label] = {}
var _controller_invert: CheckButton
var _controller_note: Label
## 「按鍵」與「手把」分頁底部的按住／連按規則（NE-229）。
var _hold_rule_labels: Array[Label] = []
var _cancel_hold: Timer
var _cancel_hold_pressed := false

var _capturing := false
var _capture_action: StringName = &""
var _capture_slot := 0


func _ready() -> void:
	# 本頁底部已有聚焦說明，疊在暫停頁裡時不讓暫停頁的說明列重複顯示。
	add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cancel_hold = Timer.new()
	_cancel_hold.one_shot = true
	_cancel_hold.wait_time = 0.6
	_cancel_hold.ignore_time_scale = true
	_cancel_hold.timeout.connect(_cancel_capture)
	add_child(_cancel_hold)
	UiKit.fill_parent(self)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.065, 1.0)
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
	layout.add_child(UiKit.label("設定", UiKit.FS_TITLE, Palette.CYAN))
	layout.add_child(UiDivider.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_tab: int) -> void:
		_cancel_capture()
		_focus_first.call_deferred())
	layout.add_child(_tabs)
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_bindings_tab())
	_tabs.add_child(_build_display_tab())
	_tabs.add_child(_build_controller_tab())

	_status = UiKit.label("", 10, Palette.UI_MUTED)
	layout.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	layout.add_child(buttons)
	buttons.add_child(UiKit.button("恢復預設", _reset_current_tab, "只重設目前分頁"))
	var back := UiKit.button("返回", close, "設定已自動儲存")
	buttons.add_child(back)

	_bind_hints(_tabs)
	InputBindings.bindings_changed.connect(_refresh_bindings)
	InputBindings.controller_options_changed.connect(_sync_controller_options)
	_refresh_bindings()
	_set_status("所有變更即時生效並自動儲存。")
	_focus_first.call_deferred()


## 每個有說明的控制項，游標或焦點移上去時把那句說明顯示在底部（手把沒有 tooltip 也看得到）。
func _bind_hints(node: Node) -> void:
	if node is Control and (node as Control).tooltip_text != "":
		var control := node as Control
		var text := control.tooltip_text
		control.focus_entered.connect(_set_status.bind(text))
		control.mouse_entered.connect(_set_status.bind(text))
	for child in node.get_children():
		_bind_hints(child)


func close() -> void:
	_cancel_capture()
	InputBindings.clear_held_inputs()
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
		_indent(name_label)
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
	# 項目多時可以捲動，底下的按鈕不會被擠出畫面。
	var scroll := ScrollContainer.new()
	scroll.name = "顯示"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 4)
	scroll.add_child(box)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "全螢幕"
	_fullscreen.tooltip_text = "填滿整個螢幕，畫面等比放到最大；F11 隨時切換"
	_fullscreen.focus_mode = Control.FOCUS_ALL
	_fullscreen.button_pressed = Settings.get_fullscreen()
	_fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.set_fullscreen(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_fullscreen)
	Settings.display_changed.connect(_sync_fullscreen)
	tree_exiting.connect(func() -> void: Settings.display_changed.disconnect(_sync_fullscreen))
	_hud_auto_hide = CheckButton.new()
	_hud_auto_hide.text = "HUD 自動隱藏"
	_hud_auto_hide.tooltip_text = "開啟後生命與護盾會在閒置時淡出，受傷或格擋時顯示；關閉後持續顯示。"
	_hud_auto_hide.focus_mode = Control.FOCUS_ALL
	_hud_auto_hide.button_pressed = Settings.get_hud_auto_hide()
	_hud_auto_hide.toggled.connect(func(on: bool) -> void:
		Settings.set_hud_auto_hide(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_hud_auto_hide)
	for entry in [["quest_objective", "顯示任務目標列", "顯示追蹤中的一句話目標，閒置時淡出。"], ["quest_arrows", "顯示目標方向箭頭", "目標在螢幕外時顯示箭頭，跨區時指向出口。"]]:
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.tooltip_text = entry[2]
		var raw: Variant = Settings.get_value(Settings.DISPLAY_SECTION, entry[0], true)
		toggle.button_pressed = raw if raw is bool else true
		toggle.toggled.connect(func(on: bool) -> void:
			Settings.set_value(Settings.DISPLAY_SECTION, entry[0], on)
			Settings.display_changed.emit())
		box.add_child(toggle)
		_quest_toggles[entry[0]] = toggle
	box.add_child(_build_brightness_row())
	box.add_child(_build_quality_row())
	_reduce_flashes = CheckButton.new()
	_reduce_flashes.text = "減少閃光"
	_reduce_flashes.tooltip_text = "降低爆炸與閃電的畫面閃光強度，閃電只閃一次；對閃光敏感時開啟"
	_reduce_flashes.focus_mode = Control.FOCUS_ALL
	_reduce_flashes.button_pressed = Settings.get_reduce_flashes()
	_reduce_flashes.toggled.connect(func(on: bool) -> void:
		Settings.set_reduce_flashes(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_reduce_flashes)
	_reduce_ui_motion = CheckButton.new()
	_reduce_ui_motion.text = "減少介面動態"
	_reduce_ui_motion.tooltip_text = "選單直接顯示，關閉滑入與數字跳動；遊戲動作照常。"
	_reduce_ui_motion.focus_mode = Control.FOCUS_ALL
	_reduce_ui_motion.button_pressed = Settings.get_reduce_ui_motion()
	_reduce_ui_motion.toggled.connect(func(on: bool) -> void:
		Settings.set_reduce_ui_motion(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_reduce_ui_motion)
	_dash_silhouettes = CheckButton.new()
	_dash_silhouettes.text = "衝刺殘影"
	_dash_silhouettes.tooltip_text = "關閉衝刺殘影，角色動作照常"
	_dash_silhouettes.focus_mode = Control.FOCUS_ALL
	_dash_silhouettes.button_pressed = Settings.get_dash_silhouettes()
	_dash_silhouettes.toggled.connect(func(on: bool) -> void:
		Settings.set_dash_silhouettes(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_dash_silhouettes)
	Settings.display_changed.connect(_sync_dash_silhouettes)
	tree_exiting.connect(func() -> void: Settings.display_changed.disconnect(_sync_dash_silhouettes))
	_smooth_font = CheckButton.new()
	_smooth_font.text = "平滑字型"
	_smooth_font.tooltip_text = "開啟後立即改用平滑黑體，關閉後改用像素字。"
	_smooth_font.focus_mode = Control.FOCUS_ALL
	_smooth_font.button_pressed = Settings.get_ui_font() == "smooth"
	_smooth_font.toggled.connect(func(on: bool) -> void:
		Settings.set_ui_font("smooth" if on else "pixel")
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_smooth_font)
	var text_row := HBoxContainer.new()
	var text_label := UiKit.label("介面文字")
	text_label.custom_minimum_size.x = LABEL_WIDTH
	_indent(text_label)
	text_row.add_child(text_label)
	_text_scale_option = OptionButton.new()
	_text_scale_option.add_item("標準（100%）", 100)
	_text_scale_option.add_item("放大（120%）", 120)
	_text_scale_option.tooltip_text = "只放大介面文字，圖示與遊戲畫面保持原尺寸。"
	_text_scale_option.select(1 if Settings.get_ui_text_scale() > 1.1 else 0)
	_text_scale_option.item_selected.connect(func(index: int) -> void:
		Settings.set_ui_text_scale(float(_text_scale_option.get_item_id(index)) / 100.0))
	text_row.add_child(_text_scale_option)
	box.add_child(text_row)
	_skip_cutscenes = CheckButton.new()
	_skip_cutscenes.text = "略過過場動畫"
	_skip_cutscenes.tooltip_text = "開啟：每次都直接略過過場動畫與劇情對話；已看過的演出重來時本來就不會重播"
	_skip_cutscenes.focus_mode = Control.FOCUS_ALL
	_skip_cutscenes.button_pressed = Settings.get_skip_cutscenes()
	_skip_cutscenes.toggled.connect(func(on: bool) -> void:
		Settings.set_skip_cutscenes(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_skip_cutscenes)
	for entry: Array in FEEL_ROWS:
		box.add_child(_build_feel_row(entry[0], entry[1], entry[2]))
	_zoom_pulse = CheckButton.new()
	_zoom_pulse.text = "縮放脈衝"
	_zoom_pulse.tooltip_text = "命中時畫面微微縮放；畫面震動調到 0% 時一律關閉"
	_zoom_pulse.focus_mode = Control.FOCUS_ALL
	_zoom_pulse.button_pressed = Settings.get_zoom_pulse()
	_zoom_pulse.toggled.connect(func(on: bool) -> void:
		Settings.set_zoom_pulse(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_zoom_pulse)
	_damage_numbers = CheckButton.new()
	_damage_numbers.text = "傷害數字"
	_damage_numbers.tooltip_text = "打中弱點、重擊或被擋時顯示數字；預設關閉，一般命中看準星的標記就好"
	_damage_numbers.focus_mode = Control.FOCUS_ALL
	_damage_numbers.button_pressed = Settings.get_damage_numbers()
	_damage_numbers.toggled.connect(func(on: bool) -> void:
		Settings.set_damage_numbers(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_damage_numbers)
	ScrollCue.attach(scroll)
	return scroll


## F11 或「恢復預設」改了全螢幕時，勾選框跟著更新（不重複觸發設定）。
func _sync_fullscreen() -> void:
	if is_instance_valid(_fullscreen):
		_fullscreen.set_pressed_no_signal(Settings.get_fullscreen())


func _sync_dash_silhouettes() -> void:
	if is_instance_valid(_dash_silhouettes):
		_dash_silhouettes.set_pressed_no_signal(Settings.get_dash_silhouettes())


## 打擊回饋強度滑桿：[設定鍵, 名稱, 提示]。
const FEEL_ROWS: Array[Array] = [
	["shake", "畫面震動", "命中與爆炸時的畫面震動強度；怕暈可以調低，0% 時鏡頭後座仍保留約一半"],
	["hitstop", "命中停頓", "打中時畫面的短暫停頓強度；0% 完全沒有停頓"],
	["particles", "粒子", "火花與碎片的數量；機器跑不順或畫面太雜時調低"],
]


func _build_feel_row(key: String, label: String, tooltip: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.tooltip_text = tooltip
	var name_label := UiKit.label(label, 12)
	name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	_indent(name_label)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 10
	slider.custom_minimum_size = Vector2(260, 16)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = tooltip
	slider.value = roundf(Settings.get_feel_scale(key) * 100.0)
	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_feel_scale(key, value / 100.0)
		_update_feel_label(key))
	row.add_child(slider)
	var value_label := UiKit.label("", 12, Palette.CYAN)
	value_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(value_label)
	_feel_sliders[key] = slider
	_feel_values[key] = value_label
	_update_feel_label(key)
	return row


func _update_feel_label(key: String) -> void:
	_feel_values[key].text = "%d%%" % roundi(Settings.get_feel_scale(key) * 100.0)


func _build_quality_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.tooltip_text = "光影品質：機器跑不順時調低；每一檔的差異見選項說明"
	var name_label := UiKit.label("光影品質", 12)
	name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	_indent(name_label)
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
	_indent(name_label)
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
	scroll.follow_focus = true
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 10)
	scroll.add_child(column)
	var grid := GridContainer.new()
	grid.columns = 2 + InputBindings.KEY_SLOTS
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 4)
	column.add_child(grid)

	var headers: Array[String] = ["動作"]
	for slot in InputBindings.KEY_SLOTS:
		headers.append("鍵盤／滑鼠 %d" % (slot + 1))
	headers.append("手把")
	for i in headers.size():
		var head := UiKit.label(headers[i], 10, Palette.UI_MUTED)
		if i == 0:
			_indent(head)
		grid.add_child(head)

	for entry in InputBindings.ACTIONS:
		var action: StringName = entry["id"]
		var label := UiKit.label(entry["label"], 11)
		label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		_indent(label)
		grid.add_child(label)
		for slot in InputBindings.KEY_SLOTS:
			grid.add_child(_make_binding_button(action, slot, "點擊後按下新按鍵或滑鼠鍵；Backspace 清除"))
		grid.add_child(_make_binding_button(action, JOY_SLOT, "點擊後按下手把按鈕；搖桿與扳機固定不可改"))
	column.add_child(_hold_rules_block())
	ScrollCue.attach(scroll)
	return scroll


## 按住與連按的規則：標題一行，下面每條一句；文字在 _refresh_bindings 依目前裝置更新。
func _hold_rules_block() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", 2)
	var title := UiKit.label("按住與連按", 11, Palette.CYAN)
	_indent(title)
	block.add_child(title)
	var rules := UiKit.label("", 11, Palette.UI_MUTED)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_indent(rules)
	block.add_child(rules)
	_hold_rule_labels.append(rules)
	return block


func _build_controller_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "手把"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 10)
	scroll.add_child(box)
	box.add_child(_controller_row("aim_deadzone", "瞄準死區", "忽略右搖桿中心的微小偏移。", 10, 60))
	_controller_invert = CheckButton.new()
	_controller_invert.text = "反轉瞄準上下"
	_controller_invert.tooltip_text = "反轉右搖桿上下瞄準方向。"
	_controller_invert.focus_mode = Control.FOCUS_ALL
	_controller_invert.button_pressed = InputBindings.get_invert_aim_y()
	_controller_invert.toggled.connect(InputBindings.set_invert_aim_y)
	box.add_child(_controller_invert)
	box.add_child(_controller_row("vibration_strength", "震動強度", "調整射擊、受擊與格擋震動；0為關閉。", 0, 100))
	_controller_note = UiKit.label("", 11, Palette.UI_MUTED)
	_controller_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_controller_note)
	box.add_child(_hold_rules_block())
	ScrollCue.attach(scroll)
	return scroll


func _controller_row(key: String, title: String, hint: String, minimum: float, maximum: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var label := UiKit.label(title, 12)
	label.custom_minimum_size.x = LABEL_WIDTH
	_indent(label)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1
	slider.custom_minimum_size = Vector2(260, 16)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = hint
	slider.value = (InputBindings.get_aim_deadzone() if key == "aim_deadzone" else InputBindings.get_vibration_strength()) * 100.0
	slider.value_changed.connect(func(value: float) -> void:
		if key == "aim_deadzone":
			InputBindings.set_aim_deadzone(value / 100.0)
		else:
			InputBindings.set_vibration_strength(value / 100.0))
	row.add_child(slider)
	var value_label := UiKit.label("%d%%" % roundi(slider.value), 12, Palette.CYAN)
	value_label.custom_minimum_size.x = 48
	row.add_child(value_label)
	_controller_sliders[key] = slider
	_controller_values[key] = value_label
	return row


func _sync_controller_options() -> void:
	for key: String in _controller_sliders:
		var value := InputBindings.get_aim_deadzone() if key == "aim_deadzone" else InputBindings.get_vibration_strength()
		_controller_sliders[key].set_value_no_signal(value * 100.0)
		_controller_values[key].text = "%d%%" % roundi(value * 100.0)
	_controller_invert.set_pressed_no_signal(InputBindings.get_invert_aim_y())


func _make_binding_button(action: StringName, slot: int, tooltip: String) -> Button:
	var button := UiKit.button("", _begin_capture.bind(action, slot), tooltip)
	button.custom_minimum_size = Vector2(BINDING_WIDTH, 0)
	_binding_buttons[_binding_key(action, slot)] = button
	return button


func _binding_key(action: StringName, slot: int) -> String:
	return "%s:%d" % [action, slot]


func _refresh_bindings() -> void:
	_controller_note.text = InputBindings.format("{inventory_prev_tab}/{inventory_next_tab}切換分頁；改鍵時短按{ui_cancel}可綁定，長按取消。")
	var rules := Hud.hold_rules()
	for label in _hold_rule_labels:
		label.text = rules
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
		_set_status(InputBindings.format("按新按鈕；{ui_cancel}短按可綁，長按0.6秒取消。"), Palette.WARNING)
	else:
		_set_status(InputBindings.format("按新按鍵；{ui_cancel}或Esc取消，Backspace清除。"), Palette.WARNING)


func _cancel_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	_cancel_hold_pressed = false
	_cancel_hold.stop()
	_refresh_bindings()
	_set_status("已取消。")


func _input(event: InputEvent) -> void:
	AimInput.observe(event)
	if not _capturing:
		if event.is_action_pressed(&"ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"inventory_prev_tab") or event.is_action_pressed(&"inventory_next_tab"):
			var step := -1 if event.is_action_pressed(&"inventory_prev_tab") else 1
			_tabs.current_tab = posmod(_tabs.current_tab + step, _tabs.get_tab_count())
			get_viewport().set_input_as_handled()
		return
	if event is InputEventAction:
		# 類比導航轉出的邏輯事件不能移走改鍵視窗焦點。
		get_viewport().set_input_as_handled()
		return
	var pressed_key: bool = event is InputEventKey and event.is_pressed() and not event.is_echo()
	var pressed_mouse: bool = event is InputEventMouseButton and event.is_pressed()
	if pressed_key or pressed_mouse:
		get_viewport().set_input_as_handled()
		_capture_code(InputBindings.code_from_event(event))
	elif event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		var button := event as InputEventJoypadButton
		if button.button_index == JOY_BUTTON_B:
			if _capture_slot != JOY_SLOT and button.pressed:
				_cancel_capture()
			elif button.pressed:
				_cancel_hold_pressed = true
				_cancel_hold.start()
			elif _cancel_hold_pressed:
				_cancel_hold_pressed = false
				_cancel_hold.stop()
				_capture_joy(button.button_index)
		elif button.pressed and _capture_slot == JOY_SLOT:
			_capture_joy(button.button_index)


func _capture_joy(button: int) -> void:
	var reason := InputBindings.joy_binding_error(_capture_action, button)
	if not reason.is_empty():
		_set_status(reason, Palette.DANGER)
		return
	_finish_capture(InputBindings.set_joy_button(_capture_action, button))


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
	_cancel_hold_pressed = false
	_cancel_hold.stop()
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
	elif _tabs.current_tab == 3:
		InputBindings.set_aim_deadzone(InputBindings.AIM_DEADZONE_DEFAULT)
		InputBindings.set_invert_aim_y(false)
		InputBindings.set_vibration_strength(1.0)
		_set_status("手把選項已恢復預設。", Palette.CYAN)
	else:
		Settings.reset_display()
		for key: String in _quest_toggles:
			_quest_toggles[key].set_pressed_no_signal(true)
		_hud_auto_hide.set_pressed_no_signal(Settings.get_hud_auto_hide())
		_sync_fullscreen()
		_brightness_slider.set_value_no_signal(roundf(Settings.get_brightness() * 100.0))
		_update_brightness_label()
		_select_quality_item()
		_reduce_flashes.set_pressed_no_signal(Settings.get_reduce_flashes())
		_reduce_ui_motion.set_pressed_no_signal(Settings.get_reduce_ui_motion())
		_sync_dash_silhouettes()
		_skip_cutscenes.set_pressed_no_signal(Settings.get_skip_cutscenes())
		_smooth_font.set_pressed_no_signal(Settings.get_ui_font() == "smooth")
		_text_scale_option.select(1 if Settings.get_ui_text_scale() > 1.1 else 0)
		_zoom_pulse.set_pressed_no_signal(Settings.get_zoom_pulse())
		_damage_numbers.set_pressed_no_signal(Settings.get_damage_numbers())
		for key: String in _feel_sliders.keys():
			_feel_sliders[key].set_value_no_signal(roundf(Settings.get_feel_scale(key) * 100.0))
			_update_feel_label(key)
		_quality_option.tooltip_text = LightQuality.DESCRIPTIONS[Settings.get_light_quality()]
		_set_status("顯示已恢復預設。", Palette.CYAN)


func _set_status(text: String, color := Palette.UI_MUTED) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _focus_first() -> void:
	var page := _tabs.get_current_tab_control()
	if page == null:
		return
	for control: Control in page.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL:
			control.grab_focus()
			return


static func _indent(label: Label) -> void:
	if _indent_box == null:
		_indent_box = StyleBoxEmpty.new()
		_indent_box.content_margin_left = ROW_INDENT
	label.add_theme_stylebox_override(&"normal", _indent_box)
