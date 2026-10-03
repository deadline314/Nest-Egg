class_name CyberPage
extends CardListPage
## 義體能力：查看、用信用點解鎖、裝備。一次只能裝備一種，使用鍵見操作說明（預設 C）。
## 能力清單是資料（data/abilities/），這裡不寫死任何一項。


func tab_title() -> String:
	return "義體"


func tab_tooltip() -> String:
	return "解鎖並裝備義體能力（目前 ¥%d）" % Progression.credits


func _empty_text() -> String:
	return "還沒有任何義體能力。"


func _initial_selection() -> int:
	var equipped := Progression.equipped_ability()
	if equipped == null:
		return 0
	for i in Progression.ability_catalog().size():
		if Progression.ability_catalog()[i].id == equipped.id:
			return i
	return 0


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	for ability in Progression.ability_catalog():
		entries.append(_entry_for(ability))
	return entries


func _entry_for(ability: CyberAbilityData) -> InventoryEntry:
	var unlocked := Progression.is_ability_unlocked(ability.id)
	var equipped := Progression.equipped_ability() != null and Progression.equipped_ability().id == ability.id
	var entry := InventoryEntry.new()
	entry.id = ability.id
	entry.title = ability.display_name
	entry.accent = ability.color
	entry.icon = ItemIcons.item(ability.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = "裝備中" if equipped else ("已解鎖" if unlocked else "未解鎖　¥%d" % ability.unlock_cost)
	if equipped:
		entry.badge = "裝備中"
		entry.badge_color = Palette.CYAN
	entry.dimmed = not unlocked
	entry.detail_tag = "義體能力"
	entry.detail_stats = PackedStringArray([
		"耗電　%d／100" % roundi(ability.charge_cost),
		"冷卻　%.0f 秒" % ability.cooldown,
		"持有　¥%d" % Progression.credits,
	])
	entry.detail_body = ability.description
	entry.hint = ability.description
	if equipped:
		entry.action_label = "裝備中"
		entry.action_enabled = false
		entry.action_hint = "已經裝備"
	elif unlocked:
		entry.action_label = "裝備"
		entry.action_hint = "改用這個能力（取代目前裝備的）"
	else:
		var reason := Progression.ability_unlock_block_reason(ability)
		entry.action_label = "解鎖（¥%d）" % ability.unlock_cost
		entry.action_enabled = reason.is_empty()
		entry.action_hint = reason if not reason.is_empty() else "花費 ¥%d 解鎖，第一個解鎖的會自動裝備" % ability.unlock_cost
	return entry


func _activate_entry(index: int) -> bool:
	var catalog := Progression.ability_catalog()
	if index < 0 or index >= catalog.size():
		return false
	var ability := catalog[index]
	if Progression.is_ability_unlocked(ability.id):
		if not Progression.equip_ability(ability.id):
			return false
		Sfx.play(&"ui_confirm", -6.0)
		context.say("已裝備 %s" % ability.display_name)
		return true
	var reason := Progression.ability_unlock_block_reason(ability)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"empty", -6.0)
		return false
	if not Progression.unlock_ability(ability):
		return false
	Sfx.play(&"overclock", -6.0)
	context.say("已解鎖 %s（-¥%d）" % [ability.display_name, ability.unlock_cost])
	return true
