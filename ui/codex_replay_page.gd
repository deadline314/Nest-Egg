extends HBoxContainer
## 圖鑑的唯讀回顧清單。解鎖、名稱與排序都來自 Story，不建立第二份進度。

signal replay_requested(id: StringName)

const DESCRIPTIONS := {
	&"ch1_p01_door": ["重看凜在雨夜來到店門口的那一刻。", "雨の夜、凜が店の戸口に来た瞬間を振り返る。", "Rin reaches the shop on a rainy night."],
	&"ch1_c09_wake": ["重看凜醒來後第一次建檔的經過。", "凜が目覚め、初めて登録される場面を振り返る。", "Rin wakes up for her first registration."],
	&"ch1_c14_home": ["重看第一章結束時，凜回到店裡的那一刻。", "第一章の終わり、凜が店に帰る瞬間を振り返る。", "Rin returns to the shop after Chapter 1."],
}

var entries: Array[Dictionary] = []
var buttons: Array[Button] = []
var selected := 0
var _scroll: ScrollContainer
var _title: Label
var _description: Label
var _play: Button
var _detail_scroll: ScrollContainer


static func copy(zh: String, ja: String, en: String) -> String:
	return ja if Story.language == "ja" else (en if Story.language == "en" else zh)


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 12)
	entries = Story.replayable_scenes()
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(list)
	var group := ButtonGroup.new()
	for i in entries.size():
		var entry := entries[i]
		var button := UiKit.button(str(entry["title"]), _request.bind(i))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 38
		button.toggle_mode = true
		button.button_group = group
		button.focus_entered.connect(_select.bind(i))
		button.mouse_entered.connect(_select.bind(i))
		button.tooltip_text = description(entry)
		list.add_child(button)
		buttons.append(button)
	# 分頁已標示類別，不再重複標題帶；把高度留給放大文字與固定的返回列。
	var detail := UiPanel.new()
	detail.custom_minimum_size.x = 260
	detail.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(detail)
	# 說明區可獨立捲動，長翻譯不能把重看與整頁返回推出畫面。
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.body.add_child(_detail_scroll)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 6)
	_detail_scroll.add_child(text)
	_title = UiKit.heading("")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_title)
	_description = UiKit.label("")
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_description)
	var note := UiKit.label(copy("不影響本輪進度。", "進行状況は変わりません。", "Progress stays unchanged."), UiKit.FS_BODY, Palette.UI_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.body.add_child(note)
	_play = UiKit.button(copy("重看", "もう一度見る", "Rewatch"), _request_selected)
	detail.body.add_child(_play)
	if entries.is_empty():
		var empty := UiKit.label(copy("本輪還沒有可重看的過場。\n看完故事後會收錄在這裡。", "まだ回想できる場面はありません。\n物語で見終えた場面がここに並びます。", "No memories yet in this run.\nFinish a story scene to find it here."), UiKit.FS_BODY, Palette.UI_TEXT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty)
		_title.text = copy("尚未收錄", "記録はありません", "No memories yet")
		_play.disabled = true
	else:
		_select(0)


func description(entry: Dictionary) -> String:
	var lines: Array = DESCRIPTIONS.get(entry["id"], [])
	if lines.size() == 3:
		return copy(str(lines[0]), str(lines[1]), str(lines[2]))
	return copy("重看「%s」的演出。", "「%s」の場面を振り返る。", "Rewatch the scene: %s.") % str(entry["title"])


func focus_selected() -> void:
	if not buttons.is_empty():
		buttons[selected].grab_focus.call_deferred()


func _select(index: int) -> void:
	selected = index
	buttons[index].button_pressed = true
	_title.text = str(entries[index]["title"])
	_description.text = description(entries[index])
	_detail_scroll.scroll_vertical = 0


func _request(index: int) -> void:
	_select(index)
	replay_requested.emit(entries[index]["id"])


func _request_selected() -> void:
	if not entries.is_empty():
		_request(selected)


func show_failure(reading := false) -> void:
	_description.text = copy("請先讀完目前的對話，再回來重看。", "今の会話を読み終えてから、回想してください。", "Finish the current conversation before rewatching.") if reading else copy("目前無法重看，請稍後再試。", "今は回想できません。後でもう一度お試しください。", "This scene cannot be replayed right now. Try again later.")
