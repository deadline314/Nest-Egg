class_name SoundLabScenesTab
extends HSplitContainer
## 實驗室分頁：情境清單。列出所有畫面情境（依類別分組），點一個就在右側的畫面舞台執行，
## 顯示它做了什麼、對應哪些聲音位置、上次實際響了哪些音效。

var lab: SoundLab
var _group: OptionButton
var _search: LineEdit
var _list: ItemList
var _title: Label
var _tip: Label
var _detail: Label
var _slots: ItemList
var _shown: Array[String] = []
var _selected := ""


func _init(p_lab: SoundLab) -> void:
	lab = p_lab


func _ready() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	add_child(left)
	_group = OptionButton.new()
	_group.tooltip_text = "只看某一類情境：武器、命中、角色、移動、機關、介面、環境、音樂"
	_group.add_item("全部情境")
	for group: String in StageScenes.shared().groups().keys():
		_group.add_item("%s　%s" % [group, StageScenes.shared().groups()[group]])
		_group.set_item_metadata(_group.item_count - 1, group)
	_group.item_selected.connect(func(_i: int) -> void: _fill())
	left.add_child(_group)
	_search = LineEdit.new()
	_search.placeholder_text = "搜尋情境（名稱、說明）"
	_search.tooltip_text = "輸入情境名稱或說明的一部分"
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	left.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.tooltip_text = "每個情境是一段在畫面裡做的真實動作；點一下顯示說明，按「在畫面執行」或雙擊執行"
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: play_selected())
	left.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	right.add_child(_title)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.tooltip_text = "這個情境做了什麼"
	right.add_child(_tip)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.tooltip_text = "情境用的動作與參數（資料在 data/audio/stage_scenes.json）"
	right.add_child(_detail)
	var buttons := HBoxContainer.new()
	right.add_child(buttons)
	var play := Button.new()
	play.text = "▶ 在畫面執行"
	play.tooltip_text = "在右側畫面舞台執行這個情境，聲音和動畫一起出現"
	play.pressed.connect(play_selected)
	buttons.add_child(play)
	var heading := Label.new()
	heading.text = "這個情境對應的聲音位置（雙擊跳到位置分頁）"
	heading.add_theme_color_override(&"font_color", Palette.CYAN)
	right.add_child(heading)
	_slots = ItemList.new()
	_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots.tooltip_text = "這個情境會響出來的聲音位置；雙擊跳到「位置與備選」分頁挑素材"
	_slots.item_activated.connect(_on_slot_activated)
	right.add_child(_slots)
	_fill()


func _fill() -> void:
	var scenes := StageScenes.shared()
	var group := ""
	if _group.selected > 0:
		group = str(_group.get_item_metadata(_group.selected))
	var query := _search.text.strip_edges().to_lower()
	_list.clear()
	_shown.clear()
	for id: String in scenes.ids():
		var scene := scenes.scene(id)
		if not group.is_empty() and str(scene.get("group", "")) != group:
			continue
		if not query.is_empty() and not (str(scene.get("name", "")) + str(scene.get("tip", "")) + id).to_lower().contains(query):
			continue
		_list.add_item("%s　%s" % [scene.get("group", ""), scene.get("name", id)])
		_shown.append(id)
	if not _selected.is_empty() and _shown.has(_selected):
		_list.select(_shown.find(_selected))


func select_scene(scene_id: String) -> void:
	_selected = scene_id
	var scenes := StageScenes.shared()
	var scene := scenes.scene(scene_id)
	_title.text = str(scene.get("name", scene_id))
	_tip.text = str(scene.get("tip", ""))
	_detail.text = "動作：%s　參數：%s" % [scene.get("action", ""), JSON.stringify(scene.get("params", {}))]
	_slots.clear()
	for slot_id in scenes.slots_for_scene(scene_id):
		var slot := lab.catalog.slot(slot_id)
		_slots.add_item("%s　%s" % [slot_id, slot.get("name", "")])
		_slots.set_item_metadata(_slots.item_count - 1, slot_id)
	if _shown.has(scene_id):
		_list.select(_shown.find(scene_id))


func selected_scene() -> String:
	return _selected


func _on_selected(index: int) -> void:
	if index >= 0 and index < _shown.size():
		select_scene(_shown[index])


func play_selected() -> void:
	if _selected.is_empty():
		lab.notify("先在左邊選一個情境")
		return
	if lab.dock == null:
		lab.notify("畫面舞台沒有開啟")
		return
	await lab.dock.play_scene(_selected)


func _on_slot_activated(index: int) -> void:
	var slot_id := str(_slots.get_item_metadata(index))
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.slots_tab)
	lab.slots_tab.select_slot(slot_id)
