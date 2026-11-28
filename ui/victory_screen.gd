class_name VictoryScreen
extends Control
## 結算畫面：章節名、評價項目一項一項跳出來，最後是敗北圖鑑進度與下一章預告。

signal replay_requested
signal menu_requested

const REVEAL_INTERVAL := 0.22
const VALUE_X := 210.0
const COPY := {
	"results": ["結算", "リザルト", "Run results"],
	"completed": ["任務完成", "任務完了", "Mission complete"],
	"difficulty": ["難度　%s", "難易度　%s", "Difficulty: %s"],
	"edition_end": ["本版本收錄到這裡，進度已保存。", "このエディションはここまでです。進行状況を保存しました。", "This edition ends here. Your progress is saved."],
	"replay": ["再玩一次", "もう一度遊ぶ", "Play again"],
	"replay_hint": ["相同難度重新開始", "同じ難易度で最初から遊びます。", "Start a new run on the same difficulty."],
	"menu": ["回主選單", "メインメニューへ", "Main menu"],
	"menu_hint": ["更換難度或查看圖鑑", "難易度の変更や図鑑の確認ができます。", "Change the difficulty or view the codex."],
	"time": ["通關時間", "クリア時間", "Clear time"],
	"returns": ["回溯次數", "復元回数", "Restorations"],
	"kills": ["擊破數", "撃破数", "Defeated"],
	"finishers": ["終結技", "フィニッシャー", "Finishers"],
	"credits": ["信用點", "クレジット", "Credits"],
	"codex": ["敗北圖鑑", "敗北図鑑", "Defeat codex"],
	"collection": ["背景收集", "資料収集", "Story finds"],
}

## 剛通關的章節（Main 指定），用來取章節名與下一章預告。
var chapter: StringName = &"chapter_01"

var _rows: Array[Control] = []
var _skip_requested := false
var _buttons: Array[Button] = []


static func _text(key: String) -> String:
	var index := maxi(0, StoryLocale.LANGUAGES.find(Story.language))
	return COPY[key][index]


func _ready() -> void:
	# 蓋住遊戲的畫面：疊在遊戲上的演出（地點標示）看到它就藏起來（UiLayers.gameplay_covered）。
	add_to_group(UiLayers.COVER_GROUP)
	UiKit.fill_parent(self)
	if not get_parent() is Control:
		UiKit.fit_to_viewport(self)
	theme = UiKit.theme()
	UiKit.set_cursor_visible(true)
	Music.show_victory()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.95)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiPanel.new(_text("results"))
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var info := Story.chapter_info(chapter)
	# 標題與難度同一列，留出空間給章末的下一步與收錄說明（720p 也放得下按鈕）。
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override(&"separation", 16)
	heading.add_child(UiKit.with_role_font(UiKit.label(str(info.get("end_title", _text("completed"))), UiKit.FS_TITLE, Palette.CYAN), &"title"))
	var difficulty := UiKit.label(_text("difficulty") % GameState.difficulty.display_name_for(Story.language), UiKit.FS_BODY, Palette.UI_MUTED)
	difficulty.size_flags_vertical = Control.SIZE_SHRINK_END
	heading.add_child(difficulty)
	panel.body.add_child(heading)
	panel.body.add_child(UiDivider.new())

	# 評價兩欄排列：放大文字時整張結算仍在畫面內，按鈕不會被擠出畫面。
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override(&"h_separation", 16)
	panel.body.add_child(stats)
	for entry in _stat_entries():
		var row := _stat_row(entry["label"], str(entry["value"]), entry.get("color", Palette.UI_TEXT))
		stats.add_child(row)
		_rows.append(row)
	var teaser := str(info.get("teaser", ""))
	# 累積版本的最後一章交代收錄範圍與保存結果；長預告依欄寬換行。
	if CampaignEdition.current().is_last_chapter(chapter):
		var separator := " " if Story.language == "en" else "　"
		teaser = (teaser + separator if not teaser.is_empty() else "") + _text("edition_end")
	if teaser != "":
		panel.body.add_child(UiDivider.new())
		var teaser_label := UiKit.label(teaser, UiKit.FS_BODY, Palette.NEON_YELLOW)
		teaser_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.body.add_child(teaser_label)
		_rows.append(teaser_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	panel.body.add_child(buttons)
	var replay := UiKit.button(_text("replay"), replay_requested.emit, _text("replay_hint"))
	replay.custom_minimum_size = Vector2(160, 0)
	var menu := UiKit.button(_text("menu"), menu_requested.emit, _text("menu_hint"))
	menu.custom_minimum_size = Vector2(140, 0)
	buttons.add_child(replay)
	buttons.add_child(menu)
	_buttons = [replay, menu]
	for b in _buttons:
		b.disabled = true
	replay.grab_focus.call_deferred()
	# 鍵盤與手把移動焦點時，在底部顯示同一句說明。
	FocusHintBar.attach(self, FocusHintBar.Placement.INLINE, buttons)
	_run_reveal.call_deferred()


func _stat_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{"label": _text("time"), "value": UiKit.format_time(GameState.run_time)},
		{"label": _text("returns"), "value": GameState.deaths, "color": Palette.DANGER if GameState.deaths > 0 else Palette.UI_TEXT},
		{"label": _text("kills"), "value": GameState.kills},
		{"label": _text("finishers"), "value": GameState.finishers},
		{"label": _text("credits"), "value": "¥ %d" % Progression.credits, "color": Palette.NEON_YELLOW},
		{"label": _text("codex"), "value": "%d / %d" % [DefeatCodex.unlocked_count(), DefeatCodex.total_count()]},
	]
	var collection := StoryItems.overall_collection()
	if collection.y > 0:
		entries.insert(5, {"label": _text("collection"), "value": "%d / %d" % [collection.x, collection.y]})
	return entries


func _stat_row(label_text: String, value_text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	var name_label := UiKit.label(label_text, UiKit.FS_BODY, Palette.UI_MUTED)
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)
	row.add_child(UiKit.label(value_text, UiKit.FS_BODY, color))
	return row


## 項目一項一項跳出，結束後才開放按鈕（避免連點直接跳過）。按確認鍵或射擊鍵可以立刻全部顯示。
func _run_reveal() -> void:
	await UiMotion.reveal_sequence(_rows, REVEAL_INTERVAL,
			func(_n: Control) -> void: Sfx.play(&"ui_move", -10.0, 0.0),
			func() -> bool: return _skip_requested)
	for b in _buttons:
		if is_instance_valid(b):
			b.disabled = false
	if is_instance_valid(_buttons[0]):
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _skip_requested and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"shoot")):
		_skip_requested = true
		get_viewport().set_input_as_handled()
