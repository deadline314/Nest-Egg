class_name StoryItemsPage
extends CardListPage
## 劇情道具：只能查看。新取得的道具標記 NEW，看過（移開選取或關閉背包）後取消。


func tab_title() -> String:
	return "劇情道具"


func tab_tooltip() -> String:
	return "回顧旅途中取得的關鍵物品"


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
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = "劇情道具"
	if StoryItems.is_new(item.id):
		entry.badge = "NEW"
		entry.badge_color = Palette.MAGENTA
	entry.detail_tag = "劇情道具"
	entry.detail_body = item.description
	entry.hint = "劇情道具只能查看，不會被消耗"
	return entry


func _on_selection_changed(previous: int, _current: int) -> void:
	if previous < 0 or previous >= _entries.size():
		return
	StoryItems.mark_seen(_entries[previous].id)
	# 看過了：立刻拿掉卡片上的 NEW。
	_entries[previous].badge = ""
	if previous < _cards.size():
		_cards[previous].setup(_entries[previous], previous)
