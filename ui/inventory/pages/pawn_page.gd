class_name PawnPage
extends CardListPage
## 典當與贖回（老 K 的當舖）：身上的補給可以當成現金（當價是售價的一半），之後加利息贖回。
## 上半是「可以典當的」（背包裡有、當舖肯收的），下半是「當票」（已經當出去、可以贖回的）。
## 規則與數字在 Progression（PAWN_RATE、PAWN_INTEREST、MAX_PAWNED）；這裡只負責顯示與操作，錢與當票一定一起動，失敗不會白花錢。

## 與 _entries 對應：{ "kind": &"pawn" 或 &"redeem", "item": ConsumableData }。
var _targets: Array[Dictionary] = []


func tab_title() -> String:
	return Labels.get_text(&"pawn")


func tab_tooltip() -> String:
	return Labels.get_text(&"pawn_help") % [Progression.credits, Progression.total_pawned(), Progression.MAX_PAWNED]


func _empty_text() -> String:
	return Labels.get_text(&"pawn_empty")


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	_targets.clear()
	if context == null or not context.is_valid():
		return entries
	for item in ConsumableBag.catalog():
		if item.price > 0 and context.player.consumables.count(item.id) > 0:
			_targets.append({"kind": &"pawn", "item": item})
			entries.append(_pawn_entry(item))
	for id in Progression.pawned_ids():
		var item := ConsumableBag.find(id)
		if item != null:
			_targets.append({"kind": &"redeem", "item": item})
			entries.append(_redeem_entry(item))
	return entries


func _pawn_entry(item: ConsumableData) -> InventoryEntry:
	var reason := _block_text(Progression.pawn_block(item), item)
	var base_value := Progression.pawn_value(item)
	var value := Progression.pawn_payout(item)
	var entry := _base_entry(item)
	entry.title = Labels.get_text(&"pawn_title") % item.display_name_for(Story.language)
	entry.subtitle = Labels.get_text(&"pawn_offer") % [value, context.player.consumables.count(item.id)]
	entry.detail_tag = Labels.get_text(&"pawn")
	entry.detail_stats = PackedStringArray([
		Labels.get_text(&"pawn_base") % base_value,
		Labels.get_text(&"pawn_interest") % [Progression.redeem_cost(item), int(Progression.PAWN_INTEREST * 100.0)],
		Labels.get_text(&"pawn_ticket_count") % [Progression.total_pawned(), Progression.MAX_PAWNED]])
	entry.detail_body = Labels.get_text(&"pawn_rule_capped" if value > 0 and value < base_value else &"pawn_rule")
	entry.hint = Labels.get_text(&"pawn_hint") % [item.display_name_for(Story.language), value]
	entry.action_label = Labels.get_text(&"pawn_action") % value
	entry.action_enabled = reason.is_empty()
	entry.action_hint = reason if not reason.is_empty() else Labels.get_text(&"pawn_action_hint") % value
	entry.dimmed = not reason.is_empty()
	return entry


func _redeem_entry(item: ConsumableData) -> InventoryEntry:
	var reason := _redeem_reason(item)
	var cost := Progression.redeem_cost(item)
	var entry := _base_entry(item)
	entry.title = Labels.get_text(&"redeem_title") % item.display_name_for(Story.language)
	entry.subtitle = Labels.get_text(&"redeem_offer") % [cost, Progression.pawned_count(item.id)]
	entry.badge = Labels.get_text(&"redeem_ticket")
	entry.badge_color = Palette.NEON_YELLOW
	entry.detail_tag = Labels.get_text(&"redeem")
	entry.detail_stats = PackedStringArray([
		Labels.get_text(&"redeem_cost") % [cost, Progression.pawn_value(item)],
		Labels.get_text(&"shop_owned") % [context.player.consumables.count(item.id), item.max_carry],
		Labels.get_text(&"credits") % Progression.credits])
	entry.detail_body = Labels.get_text(&"redeem_rule")
	entry.hint = Labels.get_text(&"redeem_hint") % [cost, item.display_name_for(Story.language)]
	entry.action_label = Labels.get_text(&"redeem_action") % cost
	entry.action_enabled = reason.is_empty()
	entry.action_hint = reason if not reason.is_empty() else Labels.get_text(&"shop_cost") % cost
	entry.dimmed = not reason.is_empty()
	return entry


func _base_entry(item: ConsumableData) -> InventoryEntry:
	var entry := InventoryEntry.new()
	entry.id = item.id
	entry.accent = item.color
	entry.icon = ItemIcons.item(item.icon)
	entry.detail_icon = ItemIcons.item_hd(item.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	return entry


## 贖回不了的原因：錢不夠、或背包放不下（放不下就不扣款）。
func _redeem_reason(item: ConsumableData) -> String:
	var reason := _block_text(Progression.redeem_block(item), item)
	if reason.is_empty() and context.player.consumables.count(item.id) >= item.max_carry:
		return Labels.get_text(&"shop_limit") % item.max_carry
	return reason


func _block_text(reason: Progression.PawnBlock, item: ConsumableData) -> String:
	match reason:
		Progression.PawnBlock.NOT_ACCEPTED:
			return Labels.get_text(&"pawn_refused")
		Progression.PawnBlock.TICKET_LIMIT:
			return Labels.get_text(&"pawn_tickets_full") % Progression.MAX_PAWNED
		Progression.PawnBlock.WALLET_FULL:
			return Labels.get_text(&"pawn_wallet_full")
		Progression.PawnBlock.NO_TICKET:
			return Labels.get_text(&"redeem_ticket_missing")
		Progression.PawnBlock.SHORT_CREDITS:
			return Labels.get_text(&"shop_short") % (Progression.redeem_cost(item) - Progression.credits)
	return ""


func _activate_entry(index: int) -> bool:
	if not context.is_valid() or index < 0 or index >= _targets.size():
		return false
	var item: ConsumableData = _targets[index]["item"]
	if _targets[index]["kind"] == &"pawn":
		return _do_pawn(item)
	return _do_redeem(item)


func _do_pawn(item: ConsumableData) -> bool:
	var reason := _block_text(Progression.pawn_block(item), item)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"ui_error", -6.0)
		return false
	# 先從背包拿走再記帳；記帳失敗就還回去，不會讓東西憑空消失。
	if not context.player.consumables.take(item.id):
		context.say(Labels.get_text(&"pawn_item_missing") % item.display_name_for(Story.language), true)
		return false
	var gained := Progression.pawn(item)
	if gained <= 0:
		context.player.consumables.add(item)
		context.say(Labels.get_text(&"pawn_refused"), true)
		return false
	Sfx.play(&"pickup", -4.0)
	context.say(Labels.get_text(&"pawn_notice") % [item.display_name_for(Story.language), gained])
	return true


func _do_redeem(item: ConsumableData) -> bool:
	var reason := _redeem_reason(item)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"ui_error", -6.0)
		return false
	# 先確認放得進背包再扣款，失敗不會白花錢。
	if not context.player.consumables.add(item):
		context.say(Labels.get_text(&"shop_no_room") % item.display_name_for(Story.language), true)
		return false
	if not Progression.redeem(item):
		context.player.consumables.take(item.id)
		var rejected := _block_text(Progression.redeem_block(item), item)
		context.say(Labels.get_text(&"redeem_failed") if rejected.is_empty() else rejected, true)
		return false
	Sfx.play(&"pickup", -4.0)
	context.say(Labels.get_text(&"redeem_notice") % [item.display_name_for(Story.language), Progression.redeem_cost(item)])
	return true
