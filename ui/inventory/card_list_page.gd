@abstract
class_name CardListPage
extends InventoryPage
## 「左邊卡片清單＋右邊詳情面板」的分頁基底（武器、消耗品、劇情道具共用）。
## 子類別只需提供項目資料（_build_entries）與確認時的動作（_activate_entry）。
## 方向鍵上下選擇、Enter／左鍵執行；滑鼠移到卡片上即選取；項目多時清單自動捲動。

const LIST_WIDTH := 236.0
const GAP := 12.0
const CARD_GAP := 6

var _entries: Array[InventoryEntry] = []
var _selected := 0
var _cards: Array[ItemCard] = []
var _list: VBoxContainer
var _scroll: ScrollContainer
var _detail: DetailPanel


func _ready() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", int(GAP))
	add_child(row)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	row.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", CARD_GAP)
	# 上方留 2 像素，讓選取時浮起的卡片不會被裁掉。
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_top", 2)
	margin.add_theme_constant_override(&"margin_left", 2)
	_scroll.add_child(margin)
	margin.add_child(_list)
	_detail = DetailPanel.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.action_pressed.connect(activate)
	_detail.action_hovered.connect(func(hint: String) -> void: hint_changed.emit(hint))
	row.add_child(_detail)


## 這一頁沒有任何項目時顯示的文字。
func _empty_text() -> String:
	return "這裡還沒有東西。"


@abstract func _build_entries() -> Array[InventoryEntry]


## 確認某項目。回傳 true 代表資料有變動（會重新整理並讓該卡片閃一下）。
func _activate_entry(_index: int) -> bool:
	return false


## 選取項目改變時（含第一次）。previous = -1 代表之前沒有選取。
func _on_selection_changed(_previous: int, _current: int) -> void:
	pass


## 開啟背包時預設選取哪一個。
func _initial_selection() -> int:
	return 0


func page_shown(animate: bool) -> void:
	_entries = _build_entries()
	_selected = clampi(_initial_selection(), 0, maxi(0, _entries.size() - 1))
	_rebuild_cards()
	_apply_selection(-1, animate)


func page_hidden() -> void:
	_on_selection_changed(_selected, -1)


func refresh() -> void:
	if _list == null:
		return
	_entries = _build_entries()
	_selected = clampi(_selected, 0, maxi(0, _entries.size() - 1))
	_rebuild_cards()
	_apply_selection(_selected, false)


func navigate(direction: Vector2i) -> void:
	if _entries.size() <= 1 or direction.y == 0:
		return
	_select(posmod(_selected + direction.y, _entries.size()))


func activate() -> void:
	if _entries.is_empty():
		return
	_run_action(_selected)


func current_hint() -> String:
	return _entries[_selected].hint if _selected < _entries.size() else ""


func _select(index: int) -> void:
	if index == _selected or index < 0 or index >= _entries.size():
		return
	var previous := _selected
	_selected = index
	Sfx.play(&"ui_move", -14.0, 0.0)
	_apply_selection(previous, true)


func _run_action(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	if _activate_entry(index):
		var flashed := index
		refresh()
		if flashed < _cards.size():
			_cards[flashed].flash()


func _rebuild_cards() -> void:
	# 數量沒變就原地更新卡片，避免重建節點。
	if _cards.size() != _entries.size():
		for card in _cards:
			card.queue_free()
		_cards.clear()
		for i in _entries.size():
			var card := ItemCard.new()
			card.hovered.connect(func(c: ItemCard) -> void: _select(c.index))
			card.activated.connect(func(c: ItemCard) -> void:
				_select(c.index)
				_run_action(c.index))
			_list.add_child(card)
			_cards.append(card)
	for i in _entries.size():
		_cards[i].setup(_entries[i], i)


func _apply_selection(previous: int, animate: bool) -> void:
	for i in _cards.size():
		_cards[i].selected = i == _selected
	var entry: InventoryEntry = _entries[_selected] if _selected < _entries.size() else null
	_detail.show_entry(entry, _empty_text(), animate)
	if _selected < _cards.size():
		_scroll.ensure_control_visible.call_deferred(_cards[_selected])
	if previous != _selected or previous < 0:
		_on_selection_changed(previous, _selected)
	hint_changed.emit(entry.hint if entry != null else "")
