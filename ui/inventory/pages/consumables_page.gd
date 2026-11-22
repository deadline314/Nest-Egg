class_name ConsumablesPage
extends CardListPage
## 消耗品：數量、效果與使用按鈕。數量 0 的種類也會列出（變暗），讓玩家知道有哪些東西可以撿。


const TEXT := {
	"zh": {"title": "消耗品", "help": "查看攜帶的消耗品並直接使用", "empty": "沒有可用的消耗品。",
		"count": "持有 %d／%d", "count_detail": "持有　%d ／ %d", "quick": "・快速鍵 %s",
		"use": "使用", "use_item": "使用一個%s", "pick_up": "沒有存貨，到關卡中撿取",
		"healed": "使用 %s，回復 %d 格生命", "restored": "使用 %s，護盾已充滿", "out": "沒有%s",
		"health_full": "生命已滿", "shield_full": "護盾已滿"},
	"ja": {"title": "消耗品", "help": "所持している消耗品を確認して使う", "empty": "使える消耗品がありません。",
		"count": "所持 %d／%d", "count_detail": "所持　%d ／ %d", "quick": "・クイックキー %s",
		"use": "使う", "use_item": "%sを1個使う", "pick_up": "ステージで拾うと使えます",
		"healed": "%sでライフを%d回復した", "restored": "%sでシールドを全回復した", "out": "%sを持っていません",
		"health_full": "ライフは満タンです", "shield_full": "シールドは満タンです"},
	"en": {"title": "Supplies", "help": "View and use carried consumables", "empty": "No consumables available.",
		"count": "Carried %d/%d", "count_detail": "Carried %d / %d", "quick": " · Quick key %s",
		"use": "Use", "use_item": "Use one %s", "pick_up": "Pick one up during a run",
		"healed": "%s restored %d health", "restored": "%s fully restored the shield", "out": "No %s carried",
		"health_full": "Health is full", "shield_full": "Shield is full"},
}


func _text(key: String) -> String:
	return TEXT.get(Story.language, TEXT[StoryLocale.SOURCE_LANGUAGE])[key]


func tab_title() -> String:
	return _text("title")


func tab_tooltip() -> String:
	return _text("help")


func _empty_text() -> String:
	return _text("empty")


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
	entry.title = item.display_name_for(Story.language)
	entry.accent = item.color
	entry.icon = ItemIcons.item(item.icon)
	entry.detail_icon = ItemIcons.item_hd(item.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = _text("count") % [count, item.max_carry]
	entry.dimmed = count <= 0
	entry.badge = InputBindings.primary_label(&"use_item") if item.quick_use else ""
	entry.badge_color = Palette.WARNING
	entry.detail_tag = _text("title") + (_text("quick") % entry.badge if item.quick_use else "")
	entry.detail_stats = PackedStringArray([_text("count_detail") % [count, item.max_carry]])
	entry.detail_body = item.description_for(Story.language)
	entry.hint = entry.detail_body
	entry.action_label = _text("use")
	entry.action_enabled = count > 0
	entry.action_hint = _text("use_item") % entry.title if count > 0 else _text("pick_up")
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
		return _text("healed") % [item.display_name_for(Story.language), item.heal_amount]
	return _text("restored") % item.display_name_for(Story.language)


func _failure_text(item: ConsumableData) -> String:
	if context.player.consumables.count(item.id) <= 0:
		return _text("out") % item.display_name_for(Story.language)
	return _text("health_full") if item.heal_amount > 0 else _text("shield_full")
