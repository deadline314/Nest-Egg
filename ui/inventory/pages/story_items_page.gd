class_name StoryItemsPage
extends CardListPage
## 劇情道具：只能查看。新取得的道具標記 NEW，看過（移開選取或關閉背包）後取消。


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
	entry.title = item.display_name
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
		entry.detail_body = item.body
		entry.hint = "%s只能閱讀；散落在關卡裡，隱藏房間裡也有" % kind
	else:
		entry.detail_body = item.description
		entry.hint = "劇情道具只能查看，不會被消耗"
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
