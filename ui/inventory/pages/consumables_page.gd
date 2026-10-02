class_name ConsumablesPage
extends CardListPage
## 消耗品：數量、效果與使用按鈕。數量 0 的種類也會列出（變暗），讓玩家知道有哪些東西可以撿。


func tab_title() -> String:
	return "消耗品"


func tab_tooltip() -> String:
	return "查看攜帶的消耗品並直接使用"


func _empty_text() -> String:
	return "沒有可用的消耗品。"


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	if context == null or not context.is_valid():
		return entries
	for item in ConsumableBag.catalog():
		entries.append(_entry_for(item))
	return entries


func _entry_for(item: ConsumableData) -> InventoryEntry:
	var bag := context.player.consumables
	var count := bag.count(item.id)
	var entry := InventoryEntry.new()
	entry.id = item.id
	entry.title = item.display_name
	entry.accent = item.color
	entry.icon = ItemIcons.item(item.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = "持有 %d／%d" % [count, item.max_carry]
	entry.dimmed = count <= 0
	entry.badge = InputBindings.primary_label(&"use_item") if item.quick_use else ""
	entry.badge_color = Palette.WARNING
	entry.detail_tag = "消耗品" + ("・快速鍵 %s" % InputBindings.primary_label(&"use_item") if item.quick_use else "")
	entry.detail_stats = PackedStringArray(["持有　%d ／ %d" % [count, item.max_carry]])
	entry.detail_body = item.description
	entry.hint = item.description
	entry.action_label = "使用"
	entry.action_enabled = count > 0
	entry.action_hint = "使用一個%s" % item.display_name if count > 0 else "沒有存貨，到關卡中撿取"
	return entry


func _activate_entry(index: int) -> bool:
	if not context.is_valid():
		return false
	var item := ConsumableBag.catalog()[index]
	if context.player.use_consumable(item.id):
		context.say(_success_text(item))
		return true
	context.say(_failure_text(item), true)
	return false


func _success_text(item: ConsumableData) -> String:
	if item.heal_amount > 0:
		return "使用 %s，回復 %d 格生命" % [item.display_name, item.heal_amount]
	return "使用 %s，護盾已充滿" % item.display_name


func _failure_text(item: ConsumableData) -> String:
	if context.player.consumables.count(item.id) <= 0:
		return "沒有%s" % item.display_name
	return "生命已滿" if item.heal_amount > 0 else "護盾已滿"
