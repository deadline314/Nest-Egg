class_name ShopPage
extends CardListPage
## 補給點的貨架：用信用點購買消耗品，受攜帶上限限制。商品是資料（ShopData.stock），價格取自 ConsumableData.price。

var shop: ShopData


func tab_title() -> String:
	return shop.display_name if shop != null else "補給點"


func tab_tooltip() -> String:
	return "用信用點購買補給（目前 ¥%d）" % Progression.credits


func _empty_text() -> String:
	return "這個補給點沒有商品。"


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	if shop == null or context == null or not context.is_valid():
		return entries
	for item in shop.stock:
		if item != null:
			entries.append(_entry_for(item))
	return entries


func _entry_for(item: ConsumableData) -> InventoryEntry:
	var bag := context.player.consumables
	var reason := _block_reason(item)
	var entry := InventoryEntry.new()
	entry.id = item.id
	entry.title = item.display_name
	entry.accent = item.color
	entry.icon = ItemIcons.item(item.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = "¥%d　持有 %d／%d" % [item.price, bag.count(item.id), item.max_carry]
	entry.dimmed = not reason.is_empty()
	entry.detail_tag = "補給"
	entry.detail_stats = PackedStringArray(["持有　%d／%d" % [bag.count(item.id), item.max_carry], "持有信用點　¥%d" % Progression.credits])
	entry.detail_body = item.description
	entry.hint = item.description
	entry.action_label = "購買（¥%d）" % item.price
	entry.action_enabled = reason.is_empty()
	entry.action_hint = reason if not reason.is_empty() else "花費 ¥%d" % item.price
	return entry


## 不能買的原因（空字串代表可以買）。
func _block_reason(item: ConsumableData) -> String:
	if context.player.consumables.count(item.id) >= item.max_carry:
		return "已達攜帶上限 %d" % item.max_carry
	if not Progression.can_afford(item.price):
		return "信用點不足（還差 %d）" % (item.price - Progression.credits)
	return ""


func _activate_entry(index: int) -> bool:
	if shop == null or not context.is_valid() or index < 0 or index >= shop.stock.size():
		return false
	var item := shop.stock[index]
	var reason := _block_reason(item)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"empty", -6.0)
		return false
	# 先確認放得進背包再扣款，失敗不會白花錢。
	if not context.player.consumables.add(item):
		context.say("%s 放不進背包" % item.display_name, true)
		return false
	if not Progression.spend(item.price):
		context.player.consumables.take(item.id)
		context.say("信用點不足", true)
		return false
	Sfx.play(&"pickup", -4.0)
	context.say("購買 %s（-¥%d）" % [item.display_name, item.price])
	return true
