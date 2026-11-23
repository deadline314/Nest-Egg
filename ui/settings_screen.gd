class_name SettingsScreen
extends Control
## 設定畫面（主選單與暫停選單共用）：音量、按鍵綁定、顯示。
## 所有變更自動存檔，劇情語言於下次啟動套用。暫停中也能操作（process_mode = ALWAYS）。

signal closed

const JOY_SLOT := -1
const LABEL_WIDTH := 120.0
## 列標題的左內距，與切換鈕的內距相同，整頁每一列的文字對齊。
const ROW_INDENT := 6.0
static var _indent_box: StyleBoxEmpty
const BINDING_WIDTH := 92.0
const COPY := {
	"audio_master_label": ["主音量", "マスター", "Master"],
	"audio_master_hint": ["所有聲音的整體音量", "すべての音の音量を調整します。", "Overall volume."],
	"audio_music_label": ["音樂", "音楽", "Music"],
	"audio_music_hint": ["各場景的背景音樂", "背景音楽の音量を調整します。", "Background music volume."],
	"audio_sfx_label": ["音效", "効果音", "Sound effects"],
	"audio_sfx_hint": ["射擊、爆炸、介面等音效", "射撃、爆発、操作音などの音量です。", "Shots, explosions and interface sounds."],
	"audio_ambience_label": ["環境音", "環境音", "Ambience"],
	"audio_ambience_hint": ["雨聲、風聲、機械嗡鳴等場景底噪", "雨、風、機械の音などの音量です。", "Rain, wind and machinery."],
	"muted": ["靜音", "ミュート", "Muted"],
	"fullscreen": ["全螢幕", "フルスクリーン", "Fullscreen"],
	"fullscreen_hint": ["維持畫面比例。按 F11 切換。", "画面比率を保ちます。F11 で切り替え。", "Keep the aspect ratio. Press F11 to switch."],
	"story_language": ["劇情語言", "シナリオ言語", "Story language"],
	"language_hint": ["重新啟動後套用。", "再起動後に反映されます。", "Restart to apply."],
	"language_saved": ["已儲存。重新啟動後套用。", "保存しました。再起動後に反映されます。", "Saved. Restart to apply."],
	"hud": ["HUD 自動隱藏", "HUD を自動で隠す", "Auto-hide HUD"],
	"hud_hint": ["閒置時淡出生命與護盾，受傷或格擋時顯示。", "待機中は体力とシールドを隠し、被弾・ガード時に表示します。", "Fade health and shield while idle. Show them on a hit or block."],
	"quest_objective": ["顯示任務目標列", "現在の目標を表示", "Show quest objective"],
	"quest_objective_hint": ["顯示追蹤中的目標，閒置時淡出。", "追跡中の目標を表示し、待機中は薄くします。", "Show the tracked goal and fade it while idle."],
	"quest_arrows": ["顯示目標方向箭頭", "目標への矢印を表示", "Show objective arrows"],
	"quest_arrows_hint": ["目標在畫面外時指向目標，跨區時指向出口。", "画面外の目標を指します。別エリアなら出口を指します。", "Point to off-screen goals or the exit to their area."],
	"brightness": ["亮度", "明るさ", "Brightness"],
	"brightness_hint": ["調整暗處亮度。50% 為預設。", "暗い場所の明るさを調整します。初期値は 50% です。", "Adjust dark areas. The default is 50%."],
	"quality": ["光影品質", "照明品質", "Lighting quality"],
	"quality_hint": ["降低光影品質可減少繪製負擔。", "品質を下げると描画負荷が軽くなります。", "Lower this setting to reduce rendering load."],
	"quality_high": ["高", "高", "High"],
	"quality_high_hint": ["", "すべての照明効果を使います。", "Use all lighting effects."],
	"quality_medium": ["中", "中", "Medium"],
	"quality_medium_hint": ["", "光源と影を減らし、粒状効果と色収差を無効にします。", "Use fewer lights and shadows. Disable grain and color fringing."],
	"quality_low": ["低", "低", "Low"],
	"quality_low_hint": ["", "基本照明と影一つを使い、体積光と法線マップを無効にします。", "Use basic lights and one shadow. Disable volumetrics and normal maps."],
	"reduce_flashes": ["減少閃光", "閃光を減らす", "Reduce flashes"],
	"reduce_flashes_hint": ["減弱命中、爆炸與閃電的光。閃電只閃一次。", "被弾・爆発・雷の閃光を弱め、雷の点滅を一回にします。", "Dim hit, explosion and lightning flashes. Lightning flashes once."],
	"reduce_motion": ["減少動態", "画面の動きを減らす", "Reduce motion"],
	"reduce_motion_hint": ["減少介面動畫與演出鏡頭移動。", "メニューや演出カメラの動きを抑えます。", "Reduce interface animation and cinematic camera movement."],
	"afterimages": ["衝刺殘影", "ダッシュの残像", "Dash afterimages"],
	"afterimages_hint": ["關閉後隱藏殘影，衝刺動作照常。", "オフにすると残像だけが消えます。", "Hide the afterimages while keeping the dash animation."],
	"smooth_font": ["平滑字型", "滑らかな文字", "Smooth font"],
	"smooth_font_hint": ["開啟使用平滑字型，關閉使用像素字。", "オンで滑らかな文字、オフでドット文字を使います。", "Switch between smooth and pixel fonts."],
	"text_scale": ["介面文字", "UI の文字", "UI text size"],
	"text_normal": ["標準（100%）", "標準（100%）", "Standard (100%)"],
	"text_large": ["放大（120%）", "拡大（120%）", "Large (120%)"],
	"text_scale_hint": ["只改變介面文字大小。", "UI の文字だけを拡大します。", "Scale interface text only."],
	"skip_scenes": ["略過過場動畫", "カットシーンをスキップ", "Skip cutscenes"],
	"skip_scenes_hint": ["自動略過過場與劇情對話。", "カットシーンと会話を自動でスキップします。", "Automatically skip cutscenes and story dialogue."],
	"feel_shake": ["畫面震動", "画面の揺れ", "Screen shake"],
	"feel_shake_hint": ["調整震動強度。0% 仍保留少量鏡頭後座。", "揺れの強さを調整します。0% でもカメラの反動は少し残ります。", "Adjust impact shake. At 0%, some camera recoil remains."],
	"feel_hitstop": ["命中停頓", "ヒットストップ", "Hit stop"],
	"feel_hitstop_hint": ["調整命中時的短暫停頓。0% 關閉。", "命中時の一瞬の停止を調整します。0% で無効。", "Adjust the brief pause on impact. Set 0% to turn it off."],
	"feel_particles": ["粒子", "パーティクル", "Particles"],
	"feel_particles_hint": ["調整火花與碎片的數量。", "火花や破片の量を調整します。", "Adjust the amount of sparks and debris."],
	"zoom": ["縮放脈衝", "命中時のズーム", "Impact zoom"],
	"zoom_hint": ["命中時輕微縮放。畫面震動為 0% 時停用。", "命中時に少し拡大します。画面の揺れが 0% の場合は無効です。", "Briefly zoom on impact. Off when screen shake is 0%."],
	"damage_numbers": ["傷害數字", "ダメージ表示", "Damage numbers"],
	"damage_numbers_hint": ["標出弱點、重擊及格擋的傷害。", "弱点への攻撃、強打、ガード時のダメージを表示します。", "Show damage on weak-point hits, heavy hits and blocks."],
	"reset_audio": ["音量已恢復預設。", "音量を初期設定に戻しました。", "Audio restored to defaults."],
	"reset_bindings": ["按鍵已恢復預設。", "キー設定を初期設定に戻しました。", "Bindings restored to defaults."],
	"reset_display": ["顯示已恢復預設。", "表示を初期設定に戻しました。", "Display restored to defaults."],
	"reset_controller": ["手把選項已恢復預設。", "コントローラーを初期設定に戻しました。", "Controller restored to defaults."],
	"settings": ["設定", "設定", "Settings"],
	"audio": ["音量", "音量", "Audio"],
	"display": ["顯示", "表示", "Display"],
	"reset": ["恢復預設", "初期設定に戻す", "Reset defaults"],
	"reset_hint": ["只重設目前分頁", "表示中の項目だけを初期設定に戻します。", "Reset the current tab only."],
	"back": ["返回", "戻る", "Back"],
	"back_hint": ["設定已自動儲存", "設定は自動的に保存されます。", "Changes are saved automatically."],
	"saved": ["設定自動儲存。劇情語言於下次啟動套用。", "設定は自動保存です。言語は再起動後に反映されます。", "Changes save automatically. Restart to apply the language."],
	"keys": ["按鍵", "キー設定", "Bindings"],
	"controller": ["手把", "コントローラー", "Controller"],
	"hold": ["按住與連按", "長押しと先行入力", "Hold and queue"],
	"aim_deadzone": ["瞄準死區", "照準のデッドゾーン", "Aim deadzone"],
	"aim_deadzone_hint": ["忽略右搖桿中心的微小偏移。", "右スティックのわずかなずれを無視します。", "Ignore small movements near the right stick’s center."],
	"invert": ["反轉瞄準上下", "上下の照準反転", "Invert vertical aim"],
	"invert_hint": ["反轉右搖桿上下瞄準方向。", "右スティックで照準する上下方向を反転します。", "Reverse vertical aiming on the right stick."],
	"vibration": ["震動強度", "振動の強さ", "Vibration"],
	"vibration_hint": ["調整射擊、受擊與格擋震動；0為關閉。", "射撃・被弾・ガードの振動を調整します。0 で無効になります。", "Adjust the rumble for shots, hits and blocks. Set 0 to turn it off."],
	"note": ["{inventory_prev_tab}/{inventory_next_tab} 切換分頁。右搖桿或 Page Up／Down 捲動。改鍵時短按 %s 綁定，長按取消。",
		"{inventory_prev_tab}/{inventory_next_tab} で切り替え、右スティックか Page Up／Down でスクロールします。割り当て時は %s を短く押すと登録、長押しで取り消し。",
		"{inventory_prev_tab}/{inventory_next_tab} switches tabs. Scroll with the right stick or Page Up/Down. When rebinding, tap %s to assign it or hold it to cancel."],
	"binding_action": ["動作", "アクション", "Action"],
	"binding_key": ["鍵盤／滑鼠 %d", "キー／マウス %d", "Key / Mouse %d"],
	"binding_key_hint": ["選取後輸入新按鍵。Backspace 清除。", "選択して新しいキーを押します。Backspace で解除。", "Select and press a key or mouse button. Backspace clears."],
	"binding_pad_hint": ["選取後按新手把按鈕。搖桿和扳機維持固定。", "選択して新しいボタンを押します。スティックとトリガーは固定です。", "Select and press a button. Sticks and triggers stay fixed."],
	"binding_cancel": ["已取消。", "取り消しました。", "Binding canceled."],
	"binding_updated": ["已更新「%s」。", "「%s」を更新しました。", "%s binding updated."],
	"binding_swapped": [" 與「%s」交換鍵位。", "「%s」と入れ替えました。", " Swapped with %s."],
	"waiting": ["按下…", "入力待ち…", "Waiting…"],
	"capture_pad": ["按新手把按鈕；%s短按綁定、長按0.6秒取消；Esc取消。",
		"新しいボタンを押します。%s は短く押すと登録、0.6 秒長押しで取り消し。Esc でも取り消せます。",
		"Press a controller button. Tap %s to assign it. Hold it for 0.6 s or press Esc to cancel."],
	"capture_key": ["按新按鍵或滑鼠鍵；Esc或%s取消，Backspace清除。",
		"キーかマウスボタンを押します。Esc または %s で取り消し、Backspace で解除。",
		"Press a key or mouse button. Esc or %s cancels. Backspace clears the binding."],
}

const QUALITY_COPY := {
	LightQuality.Tier.LOW: "quality_low",
	LightQuality.Tier.MEDIUM: "quality_medium",
	LightQuality.Tier.HIGH: "quality_high",
}

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
var _story_language_option: OptionButton
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
var _capture_error := ""


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
	layout.add_child(UiKit.label(_text("settings"), UiKit.FS_TITLE, Palette.CYAN))
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
	for index in _tabs.get_tab_count():
		_tabs.set_tab_title(index, _text(["audio", "keys", "display", "controller"][index]))

	_status = UiKit.label("", 10, Palette.UI_MUTED)
	layout.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	layout.add_child(buttons)
	buttons.add_child(UiKit.button(_text("reset"), _reset_current_tab, _text("reset_hint")))
	var back := UiKit.button(_text("back"), close, _text("back_hint"))
	buttons.add_child(back)

	_bind_hints(_tabs)
	InputBindings.bindings_changed.connect(_refresh_bindings)
	InputBindings.controller_options_changed.connect(_sync_controller_options)
	_refresh_bindings()
	_set_status(_text("saved"))
	_focus_first.call_deferred()


## 每個有說明的控制項，游標或焦點移上去時把那句說明顯示在底部（手把沒有 tooltip 也看得到）。
func _bind_hints(node: Node) -> void:
	if node is Control and (node as Control).tooltip_text != "":
		var control := node as Control
		control.focus_entered.connect(_show_control_hint.bind(control))
		control.mouse_entered.connect(_show_control_hint.bind(control))
	for child in node.get_children():
		_bind_hints(child)


func _show_control_hint(control: Control) -> void:
	if not _capturing:
		_set_status(control.tooltip_text)


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
		var tooltip := _audio_text(bus, "hint", entry["tooltip"])
		row.tooltip_text = tooltip
		var name_label := UiKit.label(_audio_text(bus, "label", entry["label"]), 12)
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
		slider.tooltip_text = tooltip
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


func _audio_text(bus: StringName, field: String, fallback: String) -> String:
	var key := "audio_%s_%s" % [String(bus).to_lower(), field]
	return _text(key) if COPY.has(key) else fallback


func _on_volume_changed(value: float, bus: StringName) -> void:
	Settings.set_volume(bus, value / 100.0)
	_update_volume_label(bus)
	# 試聽：用介面音效讓玩家立刻聽到差異。
	Sfx.play(&"ui_confirm", -6.0, 0.0)


func _update_volume_label(bus: StringName) -> void:
	if _slider_values.has(bus):
		var value := Settings.get_volume(bus)
		_slider_values[bus].text = _text("muted") if value <= 0.001 else "%d%%" % roundi(value * 100.0)


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
	_fullscreen.text = _text("fullscreen")
	_fullscreen.tooltip_text = _text("fullscreen_hint")
	_fullscreen.focus_mode = Control.FOCUS_ALL
	_fullscreen.button_pressed = Settings.get_fullscreen()
	_fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.set_fullscreen(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_fullscreen)
	box.add_child(_build_story_language_row())
	Settings.display_changed.connect(_sync_fullscreen)
	tree_exiting.connect(func() -> void: Settings.display_changed.disconnect(_sync_fullscreen))
	_hud_auto_hide = CheckButton.new()
	_hud_auto_hide.text = _text("hud")
	_hud_auto_hide.tooltip_text = _text("hud_hint")
	_hud_auto_hide.focus_mode = Control.FOCUS_ALL
	_hud_auto_hide.button_pressed = Settings.get_hud_auto_hide()
	_hud_auto_hide.toggled.connect(func(on: bool) -> void:
		Settings.set_hud_auto_hide(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_hud_auto_hide)
	for key: String in ["quest_objective", "quest_arrows"]:
		var toggle := CheckButton.new()
		toggle.text = _text(key)
		toggle.tooltip_text = _text(key + "_hint")
		var raw: Variant = Settings.get_value(Settings.DISPLAY_SECTION, key, true)
		toggle.button_pressed = raw if raw is bool else true
		toggle.toggled.connect(func(on: bool) -> void:
			Settings.set_value(Settings.DISPLAY_SECTION, key, on)
			Settings.display_changed.emit())
		box.add_child(toggle)
		_quest_toggles[key] = toggle
	box.add_child(_build_brightness_row())
	box.add_child(_build_quality_row())
	_reduce_flashes = CheckButton.new()
	_reduce_flashes.text = _text("reduce_flashes")
	_reduce_flashes.tooltip_text = _text("reduce_flashes_hint")
	_reduce_flashes.focus_mode = Control.FOCUS_ALL
	_reduce_flashes.button_pressed = Settings.get_reduce_flashes()
	_reduce_flashes.toggled.connect(func(on: bool) -> void:
		Settings.set_reduce_flashes(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_reduce_flashes)
	_reduce_ui_motion = CheckButton.new()
	_reduce_ui_motion.text = _text("reduce_motion")
	_reduce_ui_motion.tooltip_text = _text("reduce_motion_hint")
	_reduce_ui_motion.focus_mode = Control.FOCUS_ALL
	_reduce_ui_motion.button_pressed = Settings.get_reduce_ui_motion()
	_reduce_ui_motion.toggled.connect(func(on: bool) -> void:
		Settings.set_reduce_ui_motion(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_reduce_ui_motion)
	_dash_silhouettes = CheckButton.new()
	_dash_silhouettes.text = _text("afterimages")
	_dash_silhouettes.tooltip_text = _text("afterimages_hint")
	_dash_silhouettes.focus_mode = Control.FOCUS_ALL
	_dash_silhouettes.button_pressed = Settings.get_dash_silhouettes()
	_dash_silhouettes.toggled.connect(func(on: bool) -> void:
		Settings.set_dash_silhouettes(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_dash_silhouettes)
	Settings.display_changed.connect(_sync_dash_silhouettes)
	tree_exiting.connect(func() -> void: Settings.display_changed.disconnect(_sync_dash_silhouettes))
	_smooth_font = CheckButton.new()
	_smooth_font.text = _text("smooth_font")
	_smooth_font.tooltip_text = _text("smooth_font_hint")
	_smooth_font.focus_mode = Control.FOCUS_ALL
	_smooth_font.button_pressed = Settings.get_ui_font() == "smooth"
	_smooth_font.toggled.connect(func(on: bool) -> void:
		Settings.set_ui_font("smooth" if on else "pixel")
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_smooth_font)
	var text_row := HBoxContainer.new()
	var text_label := UiKit.label(_text("text_scale"))
	text_label.custom_minimum_size.x = LABEL_WIDTH
	_indent(text_label)
	text_row.add_child(text_label)
	_text_scale_option = OptionButton.new()
	_text_scale_option.add_item(_text("text_normal"), 100)
	_text_scale_option.add_item(_text("text_large"), 120)
	_text_scale_option.tooltip_text = _text("text_scale_hint")
	_text_scale_option.select(1 if Settings.get_ui_text_scale() > 1.1 else 0)
	_text_scale_option.item_selected.connect(func(index: int) -> void:
		Settings.set_ui_text_scale(float(_text_scale_option.get_item_id(index)) / 100.0))
	text_row.add_child(_text_scale_option)
	box.add_child(text_row)
	_skip_cutscenes = CheckButton.new()
	_skip_cutscenes.text = _text("skip_scenes")
	_skip_cutscenes.tooltip_text = _text("skip_scenes_hint")
	_skip_cutscenes.focus_mode = Control.FOCUS_ALL
	_skip_cutscenes.button_pressed = Settings.get_skip_cutscenes()
	_skip_cutscenes.toggled.connect(func(on: bool) -> void:
		Settings.set_skip_cutscenes(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_skip_cutscenes)
	for entry: Array in FEEL_ROWS:
		var copy_key := "feel_" + String(entry[0])
		if COPY.has(copy_key):
			box.add_child(_build_feel_row(entry[0], _text(copy_key), _text(copy_key + "_hint")))
		else:
			box.add_child(_build_feel_row(entry[0], entry[1], entry[2]))
	_zoom_pulse = CheckButton.new()
	_zoom_pulse.text = _text("zoom")
	_zoom_pulse.tooltip_text = _text("zoom_hint")
	_zoom_pulse.focus_mode = Control.FOCUS_ALL
	_zoom_pulse.button_pressed = Settings.get_zoom_pulse()
	_zoom_pulse.toggled.connect(func(on: bool) -> void:
		Settings.set_zoom_pulse(on)
		Sfx.play(&"ui_confirm", -6.0, 0.0))
	box.add_child(_zoom_pulse)
	_damage_numbers = CheckButton.new()
	_damage_numbers.text = _text("damage_numbers")
	_damage_numbers.tooltip_text = _text("damage_numbers_hint")
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
	row.tooltip_text = _text("quality_hint")
	var name_label := UiKit.label(_text("quality"), 12)
	name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	_indent(name_label)
	row.add_child(name_label)
	_quality_option = OptionButton.new()
	_quality_option.focus_mode = Control.FOCUS_ALL
	_quality_option.custom_minimum_size = Vector2(120, 0)
	for tier in [LightQuality.Tier.HIGH, LightQuality.Tier.MEDIUM, LightQuality.Tier.LOW]:
		_quality_option.add_item(_text(QUALITY_COPY[tier]), tier)
		_quality_option.set_item_tooltip(_quality_option.item_count - 1, _quality_hint(tier))
	_quality_option.tooltip_text = _quality_hint(Settings.get_light_quality())
	_select_quality_item()
	_quality_option.item_selected.connect(_on_quality_selected)
	row.add_child(_quality_option)
	return row


func _quality_hint(tier: int) -> String:
	if Story.language != "ja" and Story.language != "en":
		return LightQuality.DESCRIPTIONS[tier]
	return _text(QUALITY_COPY[tier] + "_hint")


func _select_quality_item() -> void:
	_quality_option.select(_quality_option.get_item_index(Settings.get_light_quality()))


func _on_quality_selected(index: int) -> void:
	var tier := _quality_option.get_item_id(index)
	Settings.set_light_quality(tier)
	_quality_option.tooltip_text = _quality_hint(tier)
	_set_status(_quality_option.tooltip_text, Palette.CYAN)


func _build_story_language_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := UiKit.label(_text("story_language"))
	_indent(label)
	row.add_child(label)
	_story_language_option = OptionButton.new()
	_story_language_option.focus_mode = Control.FOCUS_ALL
	_story_language_option.tooltip_text = _text("language_hint")
	for caption: String in ["繁體中文", "日本語", "English"]:
		_story_language_option.add_item(caption)
	_sync_story_language_selection()
	_story_language_option.item_selected.connect(func(index: int) -> void:
		if Settings.set_story_language(StoryLocale.LANGUAGES[index]):
			_set_status(_text("language_saved"), Palette.CYAN))
	row.add_child(_story_language_option)
	return row


func _sync_story_language_selection() -> void:
	_story_language_option.select(maxi(0, StoryLocale.LANGUAGES.find(Settings.get_story_language())))


func _build_brightness_row() -> Control:
	var tooltip := _text("brightness_hint")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.tooltip_text = tooltip
	var name_label := UiKit.label(_text("brightness"), 12)
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

	var headers: Array[String] = [_text("binding_action")]
	for slot in InputBindings.KEY_SLOTS:
		headers.append(_text("binding_key") % (slot + 1))
	headers.append(_text("controller"))
	for i in headers.size():
		var head := UiKit.label(headers[i], 10, Palette.UI_MUTED)
		if i == 0:
			_indent(head)
		grid.add_child(head)

	for entry in InputBindings.ACTIONS:
		var action: StringName = entry["id"]
		var label := UiKit.label(InputBindings.action_label(action), 11)
		label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		_indent(label)
		grid.add_child(label)
		for slot in InputBindings.KEY_SLOTS:
			grid.add_child(_make_binding_button(action, slot, _text("binding_key_hint")))
		grid.add_child(_make_binding_button(action, JOY_SLOT, _text("binding_pad_hint")))
	column.add_child(_hold_rules_block())
	ScrollCue.attach(scroll)
	return scroll


## 按住與連按的規則：標題一行，下面每條一句；文字在 _refresh_bindings 依目前裝置更新。
func _hold_rules_block() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", 2)
	var title := UiKit.label(_text("hold"), 11, Palette.CYAN)
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
	box.add_child(_controller_row("aim_deadzone", _text("aim_deadzone"), _text("aim_deadzone_hint"), 10, 60))
	_controller_invert = CheckButton.new()
	_controller_invert.text = _text("invert")
	_controller_invert.tooltip_text = _text("invert_hint")
	_controller_invert.focus_mode = Control.FOCUS_ALL
	_controller_invert.button_pressed = InputBindings.get_invert_aim_y()
	_controller_invert.toggled.connect(InputBindings.set_invert_aim_y)
	box.add_child(_controller_invert)
	box.add_child(_controller_row("vibration_strength", _text("vibration"), _text("vibration_hint"), 0, 100))
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


func _text(key: String) -> String:
	var language := Story.language
	return COPY[key][1 if language == "ja" else 2 if language == "en" else 0]


func _refresh_bindings() -> void:
	_controller_note.text = InputBindings.format(_text("note")) % InputBindings.joy_label(&"ui_cancel")
	var rules := Hud.hold_rules()
	for label in _hold_rule_labels:
		label.text = rules
	for entry in InputBindings.ACTIONS:
		var action: StringName = entry["id"]
		for slot in InputBindings.KEY_SLOTS:
			_binding_buttons[_binding_key(action, slot)].text = InputBindings.code_label(InputBindings.get_code(action, slot))
		_binding_buttons[_binding_key(action, JOY_SLOT)].text = InputBindings.joy_label(action)
	_refresh_capture_prompt()


func _refresh_capture_prompt() -> void:
	if not _capturing:
		return
	_binding_buttons[_binding_key(_capture_action, _capture_slot)].text = _text("waiting")
	if not _capture_error.is_empty():
		_set_status(_capture_error, Palette.DANGER)
		return
	var cancel_button := InputBindings.joy_label(&"ui_cancel")
	if _capture_slot == JOY_SLOT:
		_set_status(_text("capture_pad") % cancel_button, Palette.WARNING)
	else:
		_set_status(_text("capture_key") % cancel_button, Palette.WARNING)


func _begin_capture(action: StringName, slot: int) -> void:
	_cancel_capture()
	_capturing = true
	_capture_action = action
	_capture_slot = slot
	_refresh_capture_prompt()


func _cancel_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	_capture_error = ""
	_cancel_hold_pressed = false
	_cancel_hold.stop()
	_refresh_bindings()
	_set_status(_text("binding_cancel"))


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
		else:
			var direction := 0
			if event.is_action_pressed(&"aim_down") or event.is_action_pressed(&"ui_page_down"):
				direction = 1
			elif event.is_action_pressed(&"aim_up") or event.is_action_pressed(&"ui_page_up"):
				direction = -1
			if direction != 0:
				var scroll := _tabs.get_tab_control(_tabs.current_tab) as ScrollContainer
				if ScrollCue.step(scroll, direction):
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
		_capture_error = reason
		_refresh_capture_prompt()
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
	var reason := InputBindings.key_binding_error(_capture_action, _capture_slot, code)
	if not reason.is_empty():
		_capture_error = reason
		_refresh_capture_prompt()
		return
	_finish_capture(InputBindings.set_code(_capture_action, _capture_slot, code))


func _finish_capture(swapped: StringName) -> void:
	var action := _capture_action
	_capturing = false
	_capture_error = ""
	_cancel_hold_pressed = false
	_cancel_hold.stop()
	_refresh_bindings()
	var message := _text("binding_updated") % InputBindings.action_label(action)
	if swapped != &"":
		message += _text("binding_swapped") % InputBindings.action_label(swapped)
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
		_set_status(_text("reset_audio"), Palette.CYAN)
	elif _tabs.current_tab == 1:
		InputBindings.reset_to_defaults()
		_set_status(_text("reset_bindings"), Palette.CYAN)
	elif _tabs.current_tab == 3:
		InputBindings.set_aim_deadzone(InputBindings.AIM_DEADZONE_DEFAULT)
		InputBindings.set_invert_aim_y(false)
		InputBindings.set_vibration_strength(1.0)
		_set_status(_text("reset_controller"), Palette.CYAN)
	else:
		Settings.reset_display()
		_sync_story_language_selection()
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
		_quality_option.tooltip_text = _quality_hint(Settings.get_light_quality())
		_set_status(_text("reset_display"), Palette.CYAN)


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
