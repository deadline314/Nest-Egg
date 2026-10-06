class_name PawnPage
extends CardListPage
## 典當與贖回（老 K 的當舖）：身上的補給可以當成現金（當價是售價的一半），之後加利息贖回。
## 上半是「可以典當的」（背包裡有、當舖肯收的），下半是「當票」（已經當出去、可以贖回的）。
## 規則與數字在 Progression（PAWN_RATE、PAWN_INTEREST、MAX_PAWNED）；這裡只負責顯示與操作，錢與當票一定一起動，失敗不會白花錢。

## 與 _entries 對應：{ "kind": &"pawn" 或 &"redeem", "item": ConsumableData }。
var _targets: Array[Dictionary] = []


func tab_title() -> String:
	return "典當"


func tab_tooltip() -> String:
	return "把補給當成現金，之後加利息贖回（目前 ¥%d，當票 %d／%d）" % [Progression.credits, Progression.total_pawned(), Progression.MAX_PAWNED]


func _empty_text() -> String:
	return "身上沒有當舖肯收的東西，也沒有當票。"


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
	var reason := Progression.pawn_block_reason(item)
	var value := Progression.pawn_value(item)
	var entry := _base_entry(item)
	entry.title = "典當：%s" % item.display_name
	entry.subtitle = "+¥%d　持有 %d" % [value, context.player.consumables.count(item.id)]
	entry.detail_tag = "典當"
	entry.detail_stats = PackedStringArray([
		"當價　¥%d（售價的一半）" % value, "贖回　¥%d（含利息 %d%%）" % [Progression.redeem_cost(item), int(Progression.PAWN_INTEREST * 100.0)],
		"當票　%d／%d" % [Progression.total_pawned(), Progression.MAX_PAWNED]])
	entry.detail_body = "把它押在櫃台換現金。想要回來就加利息贖回；當票有張數上限，所以這是週轉，不是生意。"
	entry.hint = "押一個%s換 ¥%d，之後加利息贖回" % [item.display_name, value]
	entry.action_label = "典當（+¥%d）" % value
	entry.action_enabled = reason.is_empty()
	entry.action_hint = reason if not reason.is_empty() else "拿到 ¥%d，記一張當票" % value
	entry.dimmed = not reason.is_empty()
	return entry


func _redeem_entry(item: ConsumableData) -> InventoryEntry:
	var reason := _redeem_reason(item)
	var cost := Progression.redeem_cost(item)
	var entry := _base_entry(item)
	entry.title = "贖回：%s" % item.display_name
	entry.subtitle = "-¥%d　當票 ×%d" % [cost, Progression.pawned_count(item.id)]
	entry.badge = "當票"
	entry.badge_color = Palette.NEON_YELLOW
	entry.detail_tag = "贖回"
	entry.detail_stats = PackedStringArray([
		"贖回　¥%d（當價 ¥%d + 利息）" % [cost, Progression.pawn_value(item)], "持有　%d／%d" % [context.player.consumables.count(item.id), item.max_carry],
		"持有信用點　¥%d" % Progression.credits])
	entry.detail_body = "老 K 把它收在櫃台後面。付當價加利息，原樣拿回去。"
	entry.hint = "付 ¥%d 把%s贖回來" % [cost, item.display_name]
	entry.action_label = "贖回（¥%d）" % cost
	entry.action_enabled = reason.is_empty()
	entry.action_hint = reason if not reason.is_empty() else "花費 ¥%d" % cost
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
	var reason := Progression.redeem_block_reason(item)
	if reason.is_empty() and context.player.consumables.count(item.id) >= item.max_carry:
		return "已達攜帶上限 %d" % item.max_carry
	return reason


func _activate_entry(index: int) -> bool:
	if not context.is_valid() or index < 0 or index >= _targets.size():
		return false
	var item: ConsumableData = _targets[index]["item"]
	if _targets[index]["kind"] == &"pawn":
		return _do_pawn(item)
	return _do_redeem(item)


func _do_pawn(item: ConsumableData) -> bool:
	var reason := Progression.pawn_block_reason(item)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"empty", -6.0)
		return false
	# 先從背包拿走再記帳；記帳失敗就還回去，不會讓東西憑空消失。
	if not context.player.consumables.take(item.id):
		context.say("身上沒有%s" % item.display_name, true)
		return false
	var gained := Progression.pawn(item)
	if gained <= 0:
		context.player.consumables.add(item)
		context.say("當舖沒收", true)
		return false
	Sfx.play(&"pickup", -4.0)
	context.say("典當 %s（+¥%d）" % [item.display_name, gained])
	return true


func _do_redeem(item: ConsumableData) -> bool:
	var reason := _redeem_reason(item)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"empty", -6.0)
		return false
	# 先確認放得進背包再扣款，失敗不會白花錢。
	if not context.player.consumables.add(item):
		context.say("%s 放不進背包" % item.display_name, true)
		return false
	if not Progression.redeem(item):
		context.player.consumables.take(item.id)
		context.say("信用點不足", true)
		return false
	Sfx.play(&"pickup", -4.0)
	context.say("贖回 %s（-¥%d）" % [item.display_name, Progression.redeem_cost(item)])
	return true
