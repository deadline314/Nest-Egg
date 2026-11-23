class_name WeaponsPage
extends CardListPage
## 武器與彈藥：每個武器欄一張卡片（像素圖示、彈匣／備彈、類型），可直接設為手上武器。


func tab_title() -> String:
	return Labels.get_text(&"weapons")


func tab_tooltip() -> String:
	return Labels.get_text(&"weapons_help")


func _empty_text() -> String:
	return Labels.get_text(&"weapon_empty")


func _initial_selection() -> int:
	return context.player.loadout.active_slot if context != null and context.is_valid() else 0


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	if context == null or not context.is_valid():
		return entries
	var loadout := context.player.loadout
	for slot in Loadout.MAX_SLOTS:
		entries.append(_entry_for_slot(loadout, slot))
	return entries


func _entry_for_slot(loadout: Loadout, slot: int) -> InventoryEntry:
	var entry := InventoryEntry.new()
	var weapon := loadout.weapon_in(slot)
	entry.id = StringName("slot_%d" % slot)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 2
	if weapon == null:
		entry.title = Labels.get_text(&"weapon_slot_empty") % (slot + 1)
		entry.subtitle = Labels.get_text(&"weapon_slot_prompt")
		entry.accent = Palette.UI_MUTED
		entry.dimmed = true
		entry.hint = Labels.get_text(&"weapon_slot_help") % Loadout.MAX_SLOTS
		entry.detail_tag = Labels.get_text(&"weapon_slot_number") % (slot + 1)
		entry.detail_body = entry.hint
		return entry
	var is_active := slot == loadout.active_slot
	entry.title = weapon.display_name_for(Story.language)
	entry.accent = weapon.color
	entry.icon = ItemIcons.for_weapon(weapon)
	entry.detail_icon = ItemIcons.for_weapon_hd(weapon)
	entry.ammo_icon = AmmoIcons.for_weapon(weapon)
	var kind := _kind_text(weapon)
	var ammo := _ammo_text(loadout, slot, weapon)
	entry.subtitle = kind if ammo.is_empty() else "%s　%s" % [ammo, kind]
	if is_active:
		entry.badge = Labels.get_text(&"weapon_active_badge")
		entry.badge_color = Palette.CYAN
	entry.detail_tag = Labels.get_text(&"weapon_slot_kind") % [kind, slot + 1]
	entry.detail_stats = _stats(loadout, slot, weapon)
	entry.detail_body = weapon.description_for(Story.language)
	entry.hint = entry.detail_body
	entry.action_label = Labels.get_text(&"weapon_active" if is_active else &"weapon_equip")
	entry.action_enabled = loadout.can_select(slot)
	var hint := &"weapon_active_help" if is_active else (&"weapon_equip_help" if entry.action_enabled else &"weapon_ammo_missing_help")
	entry.action_hint = Labels.get_text(hint)
	return entry


func _stats(loadout: Loadout, slot: int, weapon: WeaponData) -> PackedStringArray:
	var lines := PackedStringArray()
	if weapon.is_melee():
		return _melee_stats(loadout, slot, weapon)
	if weapon.has_magazine():
		var reserve := loadout.reserve_in(slot)
		lines.append(Labels.get_text(&"weapon_magazine") % [loadout.mag_in(slot), weapon.magazine_size])
		lines.append(Labels.get_text(&"weapon_reserve") % ("∞" if reserve < 0 else str(reserve)))
		lines.append(Labels.get_text(&"weapon_reload_energy" if weapon.is_energy else &"weapon_reload") % weapon.reload_time)
	else:
		lines.append(Labels.get_text(&"weapon_no_reload"))
	lines.append(Labels.get_text(&"weapon_fire_rate") % (1.0 / maxf(0.01, weapon.fire_interval)))
	return lines


## 近戰武器的數字：連段、每秒傷害、最遠距離與電量（沒有電量限制的不顯示）。
func _melee_stats(loadout: Loadout, slot: int, weapon: WeaponData) -> PackedStringArray:
	var set := MeleeData.set_of(weapon)
	var sequence := set.combo(Progression.has_upgrade(weapon, set.extension_upgrade()))
	var lines := PackedStringArray()
	lines.append(Labels.get_text(&"weapon_combo") % sequence.size())
	lines.append(Labels.get_text(&"weapon_dps") % set.damage_per_second(sequence))
	lines.append(Labels.get_text(&"weapon_reach") % roundi(set.max_range(sequence)))
	if weapon.has_magazine():
		lines.append(Labels.get_text(&"weapon_charge") % [loadout.mag_in(slot), weapon.magazine_size, maxi(1, weapon.ammo_per_shot)])
		lines.append(Labels.get_text(&"weapon_recharge") % weapon.reload_time)
	else:
		lines.append(Labels.get_text(&"weapon_no_charge"))
	return lines


func _ammo_text(loadout: Loadout, slot: int, weapon: WeaponData) -> String:
	if weapon.is_melee() and not weapon.has_magazine():
		return ""
	if not weapon.has_magazine():
		return Labels.get_text(&"weapon_ammo_infinite")
	var reserve := loadout.reserve_in(slot)
	return "%d／%s" % [loadout.mag_in(slot), "∞" if reserve < 0 else str(reserve)]


func _kind_text(weapon: WeaponData) -> String:
	if weapon.is_melee():
		return Labels.get_text(&"weapon_melee")
	return Labels.get_text(&"weapon_energy" if weapon.is_energy else &"weapon_ballistic")


func _activate_entry(index: int) -> bool:
	if not context.is_valid():
		return false
	var loadout := context.player.loadout
	var weapon := loadout.weapon_in(index)
	if weapon == null:
		context.say(Labels.get_text(&"weapon_slot_warning"), true)
		return false
	var weapon_name := weapon.display_name_for(Story.language)
	if index == loadout.active_slot:
		context.say(Labels.get_text(&"weapon_active_notice") % weapon_name)
		return false
	loadout.select(index)
	if loadout.active_slot != index:
		context.say(Labels.get_text(&"weapon_no_ammo_notice") % weapon_name, true)
		return false
	context.say(Labels.get_text(&"weapon_equipped_notice") % weapon_name)
	return true
