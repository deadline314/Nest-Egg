class_name PauseMenu
extends CanvasLayer
## 暫停選單：暫停鍵開關。顯示操作說明，避免玩家忘記按鍵。

signal retry_requested
signal menu_requested
## 確認略過目前這一段（序章）；只有區域資料提供略過出口時才會出現。
signal skip_requested

## 長按略過按鈕多久直接略過（秒）；短按改開確認畫面（XAG107：長按要有單次確認的替代方式）。
const SKIP_HOLD := 1.0
const COPY := {
	"title": ["暫停", "ポーズ", "Paused"],
	"progress": ["目前進度", "現在の進行状況", "Run progress"],
	"controls": ["操作", "操作", "Controls"],
	"resume": ["繼續", "再開", "Resume"],
	"resume_hint": ["回到遊戲", "ゲームに戻ります。", "Return to the game."],
	"quests": ["任務", "クエスト", "Quests"],
	"quests_hint": ["查看任務步驟並釘選目標。", "手順を確認して目標を追跡します。", "Review steps and track a quest."],
	"quests_keyboard": ["查看任務並釘選目標；快捷鍵 {quests}。", "{quests} でクエストを開けます。", "Open quests with {quests}."],
	"map": ["地圖", "地図", "Map"],
	"map_hint": ["查看目前區域與世界地圖。", "エリアと全体の地図を確認します。", "View the area and world maps."],
	"map_keyboard": ["查看區域與世界地圖；快捷鍵 {map}。", "{map} で地図を開けます。", "Open the map with {map}."],
	"settings": ["設定", "設定", "Settings"],
	"settings_hint": ["音量、按鍵、顯示", "音量、操作、表示を調整します。", "Adjust sound, controls and display."],
	"codex": ["圖鑑", "図鑑", "Codex"],
	"codex_hint": ["查看敗北紀錄，重看本輪看過的故事", "敗北記録や今回見た物語を確認します。", "Review defeats and replay seen stories."],
	"retry": ["從檢查點重來", "復帰地点から再開", "Retry checkpoint"],
	"retry_hint": ["保留檢查點保存的武器。", "セーブ時の武器を引き継ぎます。", "Keep the weapons saved there."],
	"restart": ["重新開始區域", "エリアの最初から再開", "Restart area"],
	"restart_hint": ["尚未啟用檢查點。", "チェックポイントがありません。", "No checkpoint yet."],
	"menu": ["回主選單", "メインメニューに戻る", "Main menu"],
	"menu_hint": ["返回主選單；會嘗試保存進度", "進行状況の保存を試みてメニューに戻ります。", "Return to the menu and try to save progress."],
	"time": ["遊玩時間　%s", "プレイ時間　%s", "Play time  %s"],
	"deaths": ["回溯次數　%d", "リトライ　%d", "Retries  %d"],
	"credits": ["信用點　　%d", "クレジット　%d", "Credits  %d"],
	"skip_hint": ["短按確認，長按直接略過。", "短く押すと確認、長押しでスキップ。", "Press to review, hold to skip."],
	"keep": ["繼續練習", "練習を続ける", "Keep practicing"],
	"keep_hint": ["返回暫停選單。", "ポーズ画面に戻ります。", "Return to the pause menu."],
	"skip_confirm": ["確認%s", "%s", "%s"],
	"skip_confirm_hint": ["略過這一段。", "この区間をスキップします。", "Skip this section."],
}

static var _navigation_warmed := false

## 死亡或過關畫面出現時由關卡關閉，避免同時開兩個選單。
var allowed := true

## 目前章節（Level 建立時指定），暫停畫面右側顯示章節名。
var chapter: StringName = &"chapter_01"
## 略過按鈕的文字（例如「略過序章」）；空白＝這個區域不能略過。
var skip_label := ""
## 確認畫面上的一句說明：略過後去哪裡、保留什麼。
var skip_note := ""
var skip_label_i18n: Dictionary[String, String] = {}
var skip_note_i18n: Dictionary[String, String] = {}

var _root: Control
var _menu_panel: UiPanel
var _info_panel: UiPanel
var _locale := ""
var _locale_index := 0
var _actions: Dictionary[String, Button] = {}
var _controls_heading: Label
var _menu_hints: FocusHintBar
var _resume_button: Button
var _controls_label: Label
var _status_label: Label
var _navigation: QuestMapScreen
var _settings: SettingsScreen
var _codex: CodexScreen
var _quest_button: Button
var _map_button: Button
var _skip_confirm: UiPanel
var _skip_note_label: Label
var _skip_keep: Button
var _skip_action: Button
var _skip_hints: FocusHintBar
var _skip_button: Button
var _skip_held := -1.0
var _skip_hold_done := false


func _ready() -> void:
	layer = UiLayers.PAUSE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = UiKit.full_rect_root(self)
	_set_display_language()
	var shade := SceneBackdrop.new()
	# Keep the pause modal's existing click barrier over the frozen world.
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)

	var menu := UiPanel.new(_text("title"))
	# 右上留給計時器，放大文字時也保留完整進度面板。
	menu.position = Vector2(36, 28)
	menu.custom_minimum_size = Vector2(190, 0)
	_root.add_child(menu)
	_menu_panel = menu
	_resume_button = _add_action("resume", close)
	menu.body.add_child(_resume_button)
	_quest_button = _add_action("quests", _open_navigation.bind("quests"))
	_map_button = _add_action("map", _open_navigation.bind("region"))
	menu.body.add_child(_quest_button)
	menu.body.add_child(_map_button)
	menu.body.add_child(_add_action("settings", _open_settings))
	menu.body.add_child(_add_action("codex", _open_codex))
	if not skip_label.is_empty():
		menu.body.add_theme_constant_override(&"separation", 5)
		_skip_button = UiKit.button(_skip_text(), _on_skip_pressed, _text("skip_hint"))
		_skip_button.button_down.connect(_on_skip_down)
		_skip_button.button_up.connect(_reset_skip_hold)
		_skip_button.focus_exited.connect(_reset_skip_hold)
		menu.body.add_child(_skip_button)
	menu.body.add_child(_add_action("retry", _on_retry))
	menu.body.add_child(_add_action("menu", _on_menu))

	var info := UiPanel.new(_text("progress"), Palette.NEON_YELLOW)
	info.position = Vector2(250, 28)
	info.custom_minimum_size = Vector2(354, 0)
	_root.add_child(info)
	_info_panel = info
	_status_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	info.body.add_child(_status_label)
	info.body.add_child(UiDivider.new())
	_controls_heading = UiKit.label(_text("controls"), UiKit.FS_BODY, Palette.CYAN)
	info.body.add_child(_controls_heading)
	_controls_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.body.add_child(_controls_label)
	# 鍵盤與手把移動焦點時，在底部顯示同一句說明。
	_menu_hints = FocusHintBar.attach(_root, FocusHintBar.Placement.BELOW, menu)
	_root.visible = false
	InputBindings.bindings_changed.connect(_on_bindings_changed)
	_on_bindings_changed()
	# Warm the actual first journal layout during level loading, then release it.
	if not _navigation_warmed:
		_open_navigation("quests")
		if is_instance_valid(_navigation):
			_refresh_info()
			_warm_text(_root)
			_navigation.free()
			_navigation = null
			_navigation_warmed = true


## Hidden layout alone does not rasterize the viewport-sized glyphs used on first display.
## This unparented canvas never reaches the screen; the Font owns its bounded startup cache.
func _warm_text(root: Control) -> void:
	var viewport := root.get_viewport()
	var oversampling := 1.0
	if viewport.is_using_oversampling():
		oversampling = viewport.oversampling_override if viewport.oversampling_override > 0.0 else viewport.get_final_transform().get_scale().x
	var canvas := RenderingServer.canvas_item_create()
	if not canvas.is_valid():
		push_warning("[PauseMenu] Cannot prepare journal glyphs: temporary canvas unavailable.")
		return
	for node in root.find_children("*", "Control", true, false):
		var text := ""
		if node is Label:
			text = node.text
		elif node is Button:
			text = node.text
		if text.is_empty():
			continue
		var control := node as Control
		var font := control.get_theme_font(&"font")
		var size := control.get_theme_font_size(&"font_size")
		if font == null or size <= 0:
			push_warning("[PauseMenu] Cannot prepare glyphs for %s: missing font or invalid size." % control.get_path())
			continue
		var line := text.replace("\n", " ")
		font.draw_string(canvas, Vector2.ZERO, line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE,
			TextServer.JUSTIFICATION_WORD_BOUND | TextServer.JUSTIFICATION_KASHIDA, TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, oversampling)
		if control.has_theme_constant(&"outline_size") and control.get_theme_constant(&"outline_size") > 0 \
				and control.has_theme_color(&"font_outline_color") and control.get_theme_color(&"font_outline_color").a > 0.0:
			font.draw_string_outline(canvas, Vector2.ZERO, line, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				control.get_theme_constant(&"outline_size"), Color.WHITE, TextServer.JUSTIFICATION_WORD_BOUND | TextServer.JUSTIFICATION_KASHIDA,
				TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, oversampling)
	RenderingServer.free_rid(canvas)


func _text(key: String) -> String:
	return COPY[key][_locale_index]


func _set_display_language() -> void:
	_locale = Story.language
	_locale_index = 1 if _locale == "ja" else 2 if _locale == "en" else 0


func _add_action(key: String, callback: Callable) -> Button:
	var button := UiKit.button(_text(key), callback, _text(key + "_hint"))
	_actions[key] = button
	return button


func _refresh_language() -> void:
	if _locale == Story.language:
		return
	_set_display_language()
	_menu_panel.set_title(_text("title"))
	_info_panel.set_title(_text("progress"))
	_controls_heading.text = _text("controls")
	for key: String in _actions:
		var button: Button = _actions[key]
		button.text = _text(key)
		button.tooltip_text = _text(key + "_hint")
	if is_instance_valid(_skip_button):
		_skip_button.text = _skip_text()
		_skip_button.tooltip_text = _text("skip_hint")
	_refresh_skip_copy()
	_on_bindings_changed()
	_refresh_retry_copy()
	_menu_hints.refresh_visible_hint()


func _refresh_retry_copy() -> void:
	var key := "retry" if GameState.has_checkpoint else "restart"
	var button := _actions["retry"]
	button.text = _text(key)
	button.tooltip_text = _text(key + "_hint")


func _on_bindings_changed() -> void:
	_quest_button.tooltip_text = _text("quests_hint") if InputBindings.using_gamepad else InputBindings.format(_text("quests_keyboard"))
	_map_button.tooltip_text = _text("map_hint") if InputBindings.using_gamepad else InputBindings.format(_text("map_keyboard"))
	if _root.visible:
		_refresh_info()


func _unhandled_input(event: InputEvent) -> void:
	# 設定畫面開啟時由它自己處理輸入（Esc 會先關閉設定）。
	if is_instance_valid(_navigation) or is_instance_valid(_settings) or is_instance_valid(_codex) or not GameplayLock.menu_allowed() or Story.is_cinematic_active():
		return
	if is_instance_valid(_skip_confirm):
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			_cancel_skip()
		get_viewport().set_input_as_handled()
		return
	if allowed and (event.is_action_pressed(&"quests") or event.is_action_pressed(&"map")) and (not get_tree().paused or _root.visible):
		if not _root.visible:
			open()
		_open_navigation("quests" if event.is_action_pressed(&"quests") else "region")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause") or (_root.visible and event.is_action_pressed(&"ui_cancel")):
		if _root.visible:
			close()
		elif allowed:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if not GameplayLock.menu_allowed():
		return
	_refresh_language()
	_refresh_retry_copy()
	Fx.reset_time()
	# 經過 GameplayLock：重要通訊凍結時開關選單，世界仍維持凍結到讀完。
	GameplayLock.set_base_paused(true)
	UiKit.set_cursor_visible(true)
	_root.visible = true
	Sfx.play(&"ui_confirm", -8.0, 0.0)
	_refresh_info()
	_resume_button.grab_focus()
	UiMotion.stagger_in([_menu_panel, _info_panel], 0.08, 16.0)


func close() -> void:
	_reset_skip_hold()
	if is_instance_valid(_skip_confirm):
		_skip_confirm.queue_free()
		_skip_confirm = null
		_menu_panel.visible = true
		_info_panel.visible = true
	if is_instance_valid(_navigation):
		_navigation.queue_free()
		_navigation = null
	if is_instance_valid(_settings):
		_settings.close()
	if is_instance_valid(_codex):
		_codex.queue_free()
		_codex = null
	if _root.visible:
		Sfx.play(&"ui_cancel", -8.0, 0.0)
	_root.visible = false
	InputBindings.clear_held_inputs()
	GameplayLock.set_base_paused(false)
	UiKit.set_cursor_visible(false)


## 章節、時間、死亡次數、信用點與操作說明。
func _refresh_info() -> void:
	var info := Story.chapter_info(chapter)
	var lines: Array[String] = [
		str(info.get("title", "")),
		_text("time") % UiKit.format_time(GameState.run_time),
		_text("deaths") % GameState.deaths,
		_text("credits") % Progression.credits,
	]
	_status_label.text = "\n".join(lines)
	_controls_label.text = _controls_text()


## 操作提示排成兩欄，項目變多時暫停選單也不會撐滿畫面。
func _controls_text() -> String:
	var items := Hud.controls_hint().split("　", false)
	var lines := PackedStringArray()
	var spacing := "      " if _locale == "en" else "　　　"
	for i in range(0, items.size(), 2):
		var pair := items[i]
		if i + 1 < items.size():
			pair += spacing + items[i + 1]
		lines.append(pair)
	return "\n".join(lines)


func _open_settings() -> void:
	_settings = SettingsScreen.new()
	_settings.closed.connect(_on_settings_closed)
	UiOverlay.open(_root, _settings)


func _on_settings_closed() -> void:
	_settings = null
	if _root.visible:
		_refresh_info()


func _open_codex() -> void:
	_codex = CodexScreen.new()
	_codex.tree_exited.connect(func() -> void: _codex = null)
	UiOverlay.open(_root, _codex)


## 略過前先確認：預設焦點在「繼續練習」，取消就回到原本的選單，完全不改進度。
func _ask_skip() -> void:
	if is_instance_valid(_skip_confirm):
		return
	var panel := UiPanel.new(_skip_text(), Palette.NEON_YELLOW)
	panel.position = Vector2(250, 48)
	panel.custom_minimum_size = Vector2(354, 0)
	_skip_note_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	_skip_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skip_note_label.custom_minimum_size = Vector2(330, 0)
	panel.body.add_child(_skip_note_label)
	_skip_keep = UiKit.button("", _cancel_skip)
	_skip_action = UiKit.button("", _confirm_skip)
	panel.body.add_child(_skip_keep)
	panel.body.add_child(_skip_action)
	panel.add_to_group(FocusHintBar.OWN_HINTS_GROUP)
	_skip_hints = FocusHintBar.attach(panel, FocusHintBar.Placement.INLINE, panel.body)
	_root.add_child(panel)
	_skip_confirm = panel
	_refresh_skip_copy()
	_menu_panel.visible = false
	_info_panel.visible = false
	_skip_keep.grab_focus()


func _skip_text() -> String:
	return StoryLocale.optional_text(skip_label_i18n, _locale, skip_label)


func _refresh_skip_copy() -> void:
	if not is_instance_valid(_skip_confirm):
		return
	_skip_confirm.set_title(_skip_text())
	_skip_note_label.text = StoryLocale.optional_text(skip_note_i18n, _locale, skip_note)
	_skip_keep.text = _text("keep")
	_skip_keep.tooltip_text = _text("keep_hint")
	_skip_action.text = _text("skip_confirm") % _skip_text()
	_skip_action.tooltip_text = _text("skip_confirm_hint")
	_skip_hints.refresh_visible_hint()


func _on_skip_down() -> void:
	_skip_held = 0.0
	_skip_hold_done = false


func _reset_skip_hold() -> void:
	_skip_held = -1.0
	if is_instance_valid(_skip_button):
		_skip_button.text = _skip_text()


## 長按時按鈕上顯示進度；滿了就直接略過，不再跳確認。
func _process(delta: float) -> void:
	if not _root.visible:
		return
	_refresh_language()
	if _skip_held < 0.0:
		return
	_skip_held += delta
	if _skip_held >= SKIP_HOLD:
		_skip_hold_done = true
		_reset_skip_hold()
		_confirm_skip()
		return
	_skip_button.text = "%s…%d%%" % [_skip_text(), int(_skip_held / SKIP_HOLD * 100.0)]


func _on_skip_pressed() -> void:
	if _skip_hold_done:
		_skip_hold_done = false
		return
	_ask_skip()


func _cancel_skip() -> void:
	if not is_instance_valid(_skip_confirm):
		return
	_skip_confirm.queue_free()
	_skip_confirm = null
	_menu_panel.visible = true
	_info_panel.visible = true
	_skip_button.grab_focus()


func _confirm_skip() -> void:
	_cancel_skip()
	close()
	skip_requested.emit()


func _on_retry() -> void:
	close()
	retry_requested.emit()


func _on_menu() -> void:
	close()
	menu_requested.emit()


func _open_navigation(page: String) -> void:
	var level := get_parent() as Level
	if level == null:
		return
	_navigation = QuestMapScreen.for_level(level)
	if _navigation == null:
		return
	_navigation.start_page = page
	_navigation.closed.connect(func() -> void: _navigation = null)
	UiOverlay.open(_root, _navigation)
