class_name CyberPage
extends CardListPage
## 義體能力：查看、用信用點解鎖、裝備。一次只能裝備一種，使用鍵見操作說明（預設 C）。
## 能力清單是資料（data/abilities/），這裡不寫死任何一項。


func tab_title() -> String:
	return Labels.get_text(&"cyberware")


func tab_tooltip() -> String:
	return Labels.get_text(&"cyberware_help") % Progression.credits


func _empty_text() -> String:
	return Labels.get_text(&"cyber_empty")


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
	var active := Progression.equipped_ability()
	var equipped := active != null and active.id == ability.id
	var entry := InventoryEntry.new()
	entry.id = ability.id
	entry.title = ability.display_name_for(Story.language)
	entry.accent = ability.color
	entry.icon = ItemIcons.item(ability.icon)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 3
	entry.subtitle = Labels.get_text(&"cyber_unlocked") if unlocked else Labels.get_text(&"cyber_locked") % ability.unlock_cost
	if equipped:
		entry.badge = Labels.get_text(&"cyber_equipped")
		entry.subtitle = entry.badge
		entry.badge_color = Palette.CYAN
	entry.dimmed = not unlocked
	entry.detail_tag = Labels.get_text(&"cyber_ability")
	entry.detail_stats = PackedStringArray([
		Labels.get_text(&"cyber_power") % roundi(ability.charge_cost),
		Labels.get_text(&"cyber_cooldown") % ability.cooldown,
		Labels.get_text(&"cyber_balance") % Progression.credits,
	])
	entry.detail_body = ability.description_for(Story.language)
	entry.hint = entry.detail_body
	if equipped:
		entry.action_label = entry.badge
		entry.action_enabled = false
		entry.action_hint = entry.badge
	elif unlocked:
		entry.action_label = Labels.get_text(&"cyber_equip")
		entry.action_hint = Labels.get_text(&"cyber_equip_help")
	else:
		var reason := Progression.ability_unlock_block_reason(ability, Story.language)
		var help := &"cyber_unlock_first_help" if active == null else &"cyber_unlock_help"
		entry.action_label = Labels.get_text(&"cyber_unlock") % ability.unlock_cost
		entry.action_enabled = reason.is_empty()
		entry.action_hint = reason if not reason.is_empty() else Labels.get_text(help) % ability.unlock_cost
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
		context.say(Labels.get_text(&"cyber_equipped_notice") % ability.display_name_for(Story.language))
		return true
	var reason := Progression.ability_unlock_block_reason(ability, Story.language)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"ui_error", -6.0)
		return false
	if not Progression.unlock_ability(ability):
		return false
	Sfx.play(&"overclock", -6.0)
	context.say(Labels.get_text(&"cyber_unlocked_notice") % [ability.display_name_for(Story.language), ability.unlock_cost])
	return true
