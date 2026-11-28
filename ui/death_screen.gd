class_name DeathScreen
extends CanvasLayer
## 失敗畫面：雜訊溶解進入、標題「NEST 回溯紀錄 #n」（n 是本輪累計死亡次數）、敗北圖鑑卡片像檔案一樣展開。
## 累計死亡達到章節劇本設定的次數後，標題下多一行小字（Story.death_note），不解釋。
## 每次死亡都有收穫：新卡片標示 NEW，附一句攻略。

signal retry_requested
signal menu_requested

const NOISE_SHADER := "res://ui/transition/transition.gdshader"
const NOISE_TIME := 0.45
## Mandatory explanation is brief; the original sequence stays available to read.
const BRIEF_MANDATORY_MAX := 1.2
const CARD_OPEN_TIME := 0.28
const CARD_WIDTH := 380.0
const VERTICAL_INSET := 6.0
const COPY := {
	"record": ["NEST 回溯紀錄 #%d", "NEST 復元記録 #%d", "NEST Restoration Log #%d"],
	"failed": ["任務失敗", "任務失敗", "Mission failed"],
	"retry": ["從檢查點重來", "チェックポイントから再開", "Retry from checkpoint"],
	"retry_hint": ["回到最近的檢查點", "最後のチェックポイントに戻ります。", "Return to your last checkpoint."],
	"restart": ["重新開始關卡", "エリアの最初から再開", "Restart area"],
	"restart_hint": ["從目前區域的開頭重新開始", "現在のエリアを最初からやり直します。", "Start this area again."],
	"menu": ["回主選單", "メインメニューへ", "Main menu"],
	"menu_hint": ["可在主選單查看所有敗北圖鑑", "メインメニューから敗北図鑑を開けます。", "Open the defeat codex from the main menu."],
	"codex": ["敗北圖鑑 No.%02d", "敗北図鑑 No.%02d", "Defeat Codex No.%02d"],
	"new": ["NEW　新解鎖", "新規解放", "New entry"],
	"tip": ["攻略　%s", "攻略　%s", "Tip: %s"],
	"out_of_lives": ["殘機用盡，將從關卡開頭重新開始。", "残機が尽きました。エリアの最初から再開します。", "No lives left. Restart from the beginning of the area."],
	"sequence_pending": ["復原程序正在啟動。", "復元を開始します。", "Starting restoration."],
}

var _card: Dictionary = {}
var _can_continue := true
var sequence: Dictionary = {}
var sequence_index := -1
var sequence_complete := true
var _sequence_label: Label
var _sequence_card: Control
var _file_scroll: ScrollContainer
var _sequence_buttons: Control
## 按鈕說明的固定列（NE-229）；死亡序列播完、按鈕出現時一起出現。
var _hint_slot: Control
var _sequence_left := 0.0
var _brief_left := 0.0



static func _text(key: String) -> String:
	var index := maxi(0, StoryLocale.LANGUAGES.find(Story.language))
	return COPY[key][index]


static func record_title(deaths: int) -> String:
	return _text("record") % deaths


func setup(card: Dictionary, can_continue: bool) -> void:
	_card = card
	_can_continue = can_continue


func _ready() -> void:
	# 蓋住遊戲的畫面：疊在遊戲上的演出（地點標示）看到它就藏起來（UiLayers.gameplay_covered）。
	add_to_group(UiLayers.COVER_GROUP)
	layer = UiLayers.DEATH
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.set_cursor_visible(true)
	var root := UiKit.full_rect_root(self)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.03, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = VERTICAL_INSET
	center.offset_bottom = -VERTICAL_INSET
	root.add_child(center)
	# Recovery text needs its own surface above transient gameplay notices.
	var recovery := UiPanel.new("", Palette.DANGER)
	center.add_child(recovery)
	var column := recovery.body
	column.add_theme_constant_override(&"separation", 8)
	column.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	column.add_child(UiKit.with_role_font(UiKit.label(record_title(GameState.deaths), UiKit.FS_TITLE, Palette.DANGER, HORIZONTAL_ALIGNMENT_CENTER), &"title"))
	column.add_child(UiKit.label(_text("failed"), UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var note := Story.death_note()
	if not note.is_empty():
		var note_label := UiKit.label(note, UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(note_label)

	var file := _make_file_card()
	_file_scroll = ScrollContainer.new()
	_file_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_file_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_scroll.add_child(file)
	column.add_child(_file_scroll)
	ScrollCue.attach(_file_scroll)
	var checkpoint_available := _can_continue and GameState.has_checkpoint
	var retry_key := "retry" if checkpoint_available else "restart"
	var retry := UiKit.button(_text(retry_key), retry_requested.emit, _text(retry_key + "_hint"))
	var menu := UiKit.button(_text("menu"), menu_requested.emit, _text("menu_hint"))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 8)
	retry.custom_minimum_size = Vector2(170, 0)
	menu.custom_minimum_size = Vector2(140, 0)
	buttons.add_child(retry)
	buttons.add_child(menu)
	column.add_child(buttons)
	# 鍵盤與手把移動焦點時，在按鈕下方的固定一列顯示同一句說明：列高先保留，
	# 說明出現或收起時版面不跳動；文字放大、卡片變高時也不會蓋到按鈕。
	var hint_slot := CenterContainer.new()
	hint_slot.custom_minimum_size.y = UiKit.scaled_size(UiKit.FS_BODY) + 8
	column.add_child(hint_slot)
	FocusHintBar.attach(root, FocusHintBar.Placement.INLINE, hint_slot)
	_hint_slot = hint_slot

	# Recompute only after geometry or content changes, preserving space outside the file.
	var fit := _fit_file_height.bind(center, recovery, file)
	center.resized.connect(fit)
	recovery.minimum_size_changed.connect(fit)
	file.minimum_size_changed.connect(fit)
	_file_scroll.visibility_changed.connect(fit)
	fit.call_deferred()
	_play_noise_in(root)
	if sequence.get("steps") is Array and not sequence.steps.is_empty():
		_sequence_label = UiKit.label("", UiKit.FS_BODY, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		_sequence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(_sequence_label)
		column.move_child(_sequence_label, 2)
		_sequence_card = file
		_sequence_buttons = buttons
		_file_scroll.hide()
		buttons.hide()
		hint_slot.hide()
		sequence_complete = false
		_advance_sequence()
		_brief_left = minf(BRIEF_MANDATORY_MAX, maxf(0.0, _sequence_left))
	else:
		_open_card(file)
		retry.grab_focus.call_deferred()


func _fit_file_height(frame: Control, recovery: Control, file: Control) -> void:
	if not _file_scroll.visible:
		return
	var fixed_height := recovery.get_combined_minimum_size().y - _file_scroll.get_combined_minimum_size().y
	var affordable := maxf(0.0, frame.size.y - fixed_height)
	var height := minf(affordable, file.get_combined_minimum_size().y)
	if not is_equal_approx(_file_scroll.custom_minimum_size.y, height):
		_file_scroll.custom_minimum_size.y = height


func _make_file_card() -> Control:
	var panel := UiPanel.new(_text("codex") % int(_card.get("number", 0)), Palette.WARNING)
	if bool(_card.get("is_new", false)):
		panel.body.add_child(UiKit.label(_text("new"), UiKit.FS_BODY, Palette.NEON_YELLOW))
	var title := UiKit.with_role_font(UiKit.label(str(_card.get("title", "???")), UiKit.FS_TITLE, Palette.UI_TEXT), &"title") as Label
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(title)
	var text := UiKit.label(str(_card.get("text", "")), UiKit.FS_BODY, Palette.UI_MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.body.add_child(text)
	var hint_text := str(_card.get("hint", ""))
	if not hint_text.is_empty():
		panel.body.add_child(UiDivider.new())
		var hint := UiKit.label(_text("tip") % hint_text, UiKit.FS_BODY, Palette.CYAN)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.body.add_child(hint)
	if not _can_continue:
		panel.body.add_child(UiKit.label(_text("out_of_lives"), UiKit.FS_BODY, Palette.DANGER))
	return panel


## 檔案卡展開：以上緣為軸從壓扁展開。
func _open_card(card: Control) -> void:
	if Settings.get_reduce_ui_motion():
		card.scale = Vector2.ONE
		card.modulate = Color.WHITE
		return
	card.pivot_offset_ratio = Vector2(0.5, 0.0)
	card.scale = Vector2(1.0, 0.05)
	card.modulate.a = 0.0
	var tween := card.create_tween().set_parallel(true)
	tween.tween_property(card, "scale:y", 1.0, CARD_OPEN_TIME).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.12).set_delay(0.25)


## 進入時的回溯（NE-472）：和死亡重來的轉場同一種語言——冷色、追蹤線、從下往上讓出；減少動態時直接出現、減少閃光時單純淡入。
func _play_noise_in(root: Control) -> void:
	if Settings.get_reduce_ui_motion():
		return
	if Settings.get_reduce_flashes():
		root.modulate.a = 0.0
		root.create_tween().tween_property(root, "modulate:a", 1.0, NOISE_TIME)
		return
	var shader := load(NOISE_SHADER) as Shader
	if shader == null:
		return
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"kind", int(Transition.RETRY))
	material.set_shader_parameter(&"accent", Palette.CYAN)
	material.set_shader_parameter(&"flip", 1.0)
	material.set_shader_parameter(&"seed", randf() * 10.0)
	material.set_shader_parameter(&"aspect", 640.0 / 360.0)
	material.set_shader_parameter(&"progress", 1.0)
	rect.material = material
	root.add_child(rect)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		material.set_shader_parameter(&"progress", v)
		material.set_shader_parameter(&"time_s", Time.get_ticks_msec() * 0.001), 0.75, 0.0, NOISE_TIME)
	tween.tween_callback(rect.queue_free)


func _advance_sequence() -> void:
	sequence_index += 1
	var steps: Array = sequence.get("steps", [])
	if sequence_index >= steps.size():
		sequence_index = maxi(0, steps.size() - 1)
		_finish_sequence()
		return
	var step: Variant = steps[sequence_index]
	if not step is Dictionary:
		push_warning("[DeathScreen] sequence/steps/%d 不是物件，已略過" % sequence_index)
		_sequence_left = 0.0
		return
	var seconds: Variant = step.get("time", 0.6)
	_sequence_left = clampf(float(seconds), 0.0, 3.0) if seconds is int or seconds is float else 0.6
	var kind := str(step.get("kind", "line"))
	if kind == "card":
		_sequence_label.hide()
		_file_scroll.show()
		_open_card(_sequence_card)
	else:
		var speaker := Story.speaker(str(step.get("speaker", "system")))
		var prefix := str(speaker.get("name", "")) + "：" if kind == "line" else ""
		_sequence_label.text = prefix + str(step.get("text", _text("sequence_pending")))
		_sequence_label.show()
		var sound := StringName(str(step.get("sfx", "")))
		if sound != &"":
			Sfx.play(sound, -12.0, 0.0)


func _finish_sequence() -> void:
	sequence_complete = true
	_sequence_label.hide()
	_file_scroll.show()
	_show_sequence_actions()


## Opening the same actions twice must not steal a player-selected menu focus.
func _show_sequence_actions() -> void:
	if not is_instance_valid(_sequence_buttons) or _sequence_buttons.visible:
		return
	_sequence_buttons.show()
	if is_instance_valid(_hint_slot):
		_hint_slot.show()
	(_sequence_buttons.get_child(0) as Button).grab_focus()


func _process(delta: float) -> void:
	if sequence_complete:
		return
	_brief_left = maxf(0.0, _brief_left - delta)
	if _brief_left <= 0.0:
		_show_sequence_actions()
	_sequence_left -= delta
	if _sequence_left <= 0.0:
		_advance_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if _file_scroll.visible:
		var direction := 1 if event.is_action_pressed(&"aim_down") or event.is_action_pressed(&"ui_page_down") else -1 if event.is_action_pressed(&"aim_up") or event.is_action_pressed(&"ui_page_up") else 0
		if direction != 0 and ScrollCue.step(_file_scroll, direction):
			get_viewport().set_input_as_handled()
			return
	if sequence_complete or not bool(sequence.get("skippable", false)):
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact"):
		_finish_sequence()
		get_viewport().set_input_as_handled()
