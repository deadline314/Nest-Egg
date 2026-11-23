class_name ShopPage
extends CardListPage
## 補給點的貨架：用信用點購買消耗品，受攜帶上限限制。商品是資料（ShopData.stock），價格取自 ConsumableData.price。

var shop: ShopData
var _stock_targets: Array[ConsumableData] = []


func tab_title() -> String:
	if shop != null and (shop.pawn or shop.workbench):
		return Labels.get_text(&"stock")  # 用短名稱，避免重複櫃台標題。
	return shop.display_name_for(Story.language) if shop != null else Labels.get_text(&"counter_title")


func tab_tooltip() -> String:
	return Labels.get_text(&"stock_help") % Progression.credits


func _empty_text() -> String:
	return Labels.get_text(&"shop_empty")


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	_stock_targets.clear()
	if shop == null or context == null or not context.is_valid():
		return entries
	for item in shop.stock:
		if item != null and item.price > 0:
			_stock_targets.append(item)
			entries.append(_entry_for(item))
	return entries


func _entry_for(item: ConsumableData) -> InventoryEntry:
	var bag := context.player.consumables
	var reason := _block_reason(item)
	var entry := InventoryEntry.new()
	entry.id = item.id
	entry.title = item.display_name_for(Story.language)
	entry.accent = item.color
	entry.icon = ItemIcons.item(item.icon)
	entry.detail_icon = ItemIcons.item_hd(item.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = Labels.get_text(&"shop_offer") % [item.price, bag.count(item.id), item.max_carry]
	entry.dimmed = not reason.is_empty()
	entry.detail_tag = Labels.get_text(&"stock")
	entry.detail_stats = PackedStringArray([Labels.get_text(&"shop_owned") % [bag.count(item.id), item.max_carry], Labels.get_text(&"credits") % Progression.credits])
	entry.detail_body = item.description_for(Story.language)
	entry.hint = item.description_for(Story.language)
	entry.action_label = Labels.get_text(&"shop_buy") % item.price
	entry.action_enabled = reason.is_empty()
	entry.action_hint = reason if not reason.is_empty() else Labels.get_text(&"shop_cost") % item.price
	return entry


## 不能買的原因（空字串代表可以買）。
func _block_reason(item: ConsumableData) -> String:
	if context.player.consumables.count(item.id) >= item.max_carry:
		return Labels.get_text(&"shop_limit") % item.max_carry
	if not Progression.can_afford(item.price):
		return Labels.get_text(&"shop_short") % (item.price - Progression.credits)
	return ""


func _activate_entry(index: int) -> bool:
	if shop == null or context == null or not context.is_valid() or index < 0 or index >= _stock_targets.size():
		return false
	var item := _stock_targets[index]
	var reason := _block_reason(item)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"ui_error", -6.0)
		return false
	# 先確認放得進背包再扣款，失敗不會白花錢。
	if not context.player.consumables.add(item):
		context.say(Labels.get_text(&"shop_no_room") % item.display_name_for(Story.language), true)
		return false
	if not Progression.spend(item.price):
		context.player.consumables.take(item.id)
		context.say(Labels.get_text(&"shop_short") % (item.price - Progression.credits), true)
		return false
	Sfx.play(&"pickup", -4.0)
	context.say(Labels.get_text(&"shop_buy_notice") % [item.display_name_for(Story.language), item.price])
	return true
