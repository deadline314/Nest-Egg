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
	return Labels.get_text(&"story")


func tab_tooltip() -> String:
	var overall := StoryItems.overall_collection()
	if overall.y == 0:
		return Labels.get_text(&"story_help")
	return Labels.get_text(&"story_collection") % [overall.x, overall.y]


func tab_has_alert() -> bool:
	return StoryItems.new_count() > 0


func _empty_text() -> String:
	return Labels.get_text(&"story_empty")


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
	var text := item.body_text()
	entry.detail_body = item.description_text()
	entry.hint = Labels.get_text(&"story_readonly")
	if item.is_collectible():
		var chapter_title := str(Story.chapter_info(item.chapter).get("title", ""))
		entry.detail_tag = "%s　%s" % [kind, chapter_title] if not chapter_title.is_empty() else kind
		entry.detail_stats = PackedStringArray([Labels.get_text(&"story_chapter_count") %
				[StoryItems.collected_count(item.chapter), StoryItems.collectible_total(item.chapter)]])
		if not text.is_empty():
			entry.detail_body = text
	if not text.is_empty():
		var recording := item.category == StoryItemData.Category.RECORDING
		entry.action_label = Labels.get_text(&"story_transcript" if recording else &"story_read")
		entry.action_hint = Labels.get_text(&"story_transcript_help" if recording else &"story_read_help")
		entry.hint = entry.action_hint
	return entry


static func _kind_name(item: StoryItemData) -> String:
	match item.category:
		StoryItemData.Category.DOCUMENT:
			return Labels.get_text(&"story_document")
		StoryItemData.Category.RECORDING:
			return Labels.get_text(&"story_recording")
	return Labels.get_text(&"story_key_item")


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
	if item == null or not StoryItems.owns(item.id):
		return false
	var text := item.body_text()
	if text.is_empty():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	_reader_focus = weakref(focus) if focus != null else null
	_reader.show_document(item.title_text(), text, item.color)
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
