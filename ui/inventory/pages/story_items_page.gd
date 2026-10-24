class_name StoryItemsPage
extends CardListPage
## 劇情道具：只能查看。新取得的道具標記 NEW，看過（移開選取或關閉背包）後取消。


const Reader := preload("res://ui/inventory/document_reader.gd")

var _reader: Reader
var _reader_focus: WeakRef


func _ready() -> void:
	super._ready()
	# Story-item icons remain in the list; keep this column for readable text.
	_detail._plate.hide()
	_reader = Reader.new()
	add_child(_reader)
	_reader.dismissed.connect(_close_reader)


func tab_title() -> String:
	return "劇情道具"


func tab_tooltip() -> String:
	var overall := StoryItems.overall_collection()
	if overall.y == 0:
		return "回顧旅途中取得的關鍵物品"
	return "回顧關鍵物品與收集的文件、錄音（已收集 %d／%d）" % [overall.x, overall.y]


func tab_has_alert() -> bool:
	return StoryItems.new_count() > 0


func _empty_text() -> String:
	return "還沒有取得任何劇情道具。"


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	for item in StoryItems.owned_items():
		entries.append(_entry_for(item))
	return entries


func _entry_for(item: StoryItemData) -> InventoryEntry:
	var entry := InventoryEntry.new()
	entry.id = item.id
	entry.title = item.title_text()
	entry.accent = item.color
	entry.icon = ItemIcons.item(item.icon)
	entry.detail_icon = ItemIcons.item_hd(item.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	var kind := _kind_name(item)
	entry.subtitle = kind
	if StoryItems.is_new(item.id):
		entry.badge = "NEW"
		entry.badge_color = Palette.MAGENTA
	entry.detail_tag = kind
	if item.is_collectible():
		var chapter_title := str(Story.chapter_info(item.chapter).get("title", ""))
		entry.detail_tag = "%s　%s" % [kind, chapter_title] if not chapter_title.is_empty() else kind
		entry.detail_stats = PackedStringArray(["本章收集　%d／%d" % [StoryItems.collected_count(item.chapter), StoryItems.collectible_total(item.chapter)]])
		entry.detail_body = item.body_text()
		entry.hint = "%s只能閱讀；散落在關卡裡，隱藏房間裡也有" % kind
	else:
		entry.detail_body = item.description_text()
		entry.hint = "劇情道具只能查看，不會被消耗"
		if not item.body_text().is_empty():
			entry.action_label = _copy("閱讀全文", "全文を読む", "Read full text")
			entry.action_hint = _copy("閱讀完整記錄，不會消耗物品", "全文を読む。アイテムは消費しません", "Read full text; keep this item.")
			entry.hint = entry.action_hint
	return entry


static func _kind_name(item: StoryItemData) -> String:
	match item.category:
		StoryItemData.Category.DOCUMENT:
			return "文件"
		StoryItemData.Category.RECORDING:
			return "錄音"
	return "劇情道具"


func _on_selection_changed(previous: int, _current: int) -> void:
	if previous < 0 or previous >= _entries.size():
		return
	StoryItems.mark_seen(_entries[previous].id)
	# 看過了：立刻拿掉卡片上的 NEW。
	_entries[previous].badge = ""
	if previous < _cards.size():
		_cards[previous].setup(_entries[previous], previous)


func _activate_entry(index: int) -> bool:
	if index < 0 or index >= _entries.size() or _entries[index].action_label.is_empty():
		return false
	var item := StoryItems.find(_entries[index].id)
	if item == null or not StoryItems.owns(item.id) or item.body_text().is_empty():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	_reader_focus = weakref(focus) if focus != null else null
	_reader.show_document(item.title_text(), item.body_text(), item.color)
	return false # Reading never refreshes or mutates the item transaction.


func navigate(direction: Vector2i) -> void:
	if _reader.visible:
		_reader.scroll(direction.y)
	else:
		super.navigate(direction)


func activate() -> void:
	if not handle_back():
		super.activate()


func handle_back() -> bool:
	if _reader == null or not _reader.visible:
		return false
	_close_reader()
	return true


func page_hidden() -> void:
	_close_reader(false)
	super.page_hidden()


func _close_reader(restore_focus := true) -> void:
	if _reader == null:
		return
	_reader.hide()
	if restore_focus and _reader_focus != null:
		var previous := _reader_focus.get_ref() as Control
		if is_instance_valid(previous) and previous.is_visible_in_tree() and previous.focus_mode != Control.FOCUS_NONE:
			previous.grab_focus()
	_reader_focus = null


static func _copy(zh: String, ja: String, en: String) -> String:
	return ja if Story.language == "ja" else (en if Story.language == "en" else zh)
