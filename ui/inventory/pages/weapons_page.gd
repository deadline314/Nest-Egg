class_name WeaponsPage
extends CardListPage
## 武器與彈藥：每個武器欄一張卡片（像素圖示、彈匣／備彈、類型），可直接設為手上武器。


func tab_title() -> String:
	return "武器與彈藥"


func tab_tooltip() -> String:
	return "查看攜帶的武器與彈藥，並換成手上武器"


func _empty_text() -> String:
	return "沒有武器。"


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
		entry.title = "空欄位 %d" % (slot + 1)
		entry.subtitle = "撿到武器會放在這裡"
		entry.accent = Palette.UI_MUTED
		entry.dimmed = true
		entry.hint = "撿到武器後放在這裡；最多攜帶 %d 把" % Loadout.MAX_SLOTS
		entry.detail_tag = "欄位 %d" % (slot + 1)
		entry.detail_body = "這個欄位還是空的。關卡中撿到的武器會依序放進來。"
		return entry
	var is_active := slot == loadout.active_slot
	entry.title = weapon.display_name
	entry.accent = weapon.color
	entry.icon = ItemIcons.weapon(weapon.visual_id)
	entry.ammo_icon = AmmoIcons.for_weapon(weapon)
	entry.subtitle = "%s　%s" % [_ammo_text(loadout, slot, weapon), _kind_text(weapon)]
	if is_active:
		entry.badge = "手上"
		entry.badge_color = Palette.CYAN
	entry.detail_tag = "%s・欄位 %d" % [_kind_text(weapon), slot + 1]
	entry.detail_stats = _stats(loadout, slot, weapon)
	entry.detail_body = weapon.description
	entry.hint = weapon.description
	entry.action_label = "目前手上武器" if is_active else "設為手上武器"
	entry.action_enabled = loadout.can_select(slot)
	entry.action_hint = "已經拿在手上" if is_active else ("彈藥用完了，無法換上" if not entry.action_enabled else "關閉背包後直接使用這把武器")
	return entry


func _stats(loadout: Loadout, slot: int, weapon: WeaponData) -> PackedStringArray:
	var lines := PackedStringArray()
	if weapon.has_magazine():
		var reserve := loadout.reserve_in(slot)
		lines.append("彈匣　%d ／ %d" % [loadout.mag_in(slot), weapon.magazine_size])
		lines.append("備彈　%s" % ("∞" if reserve < 0 else str(reserve)))
		lines.append("換%s　%.1f 秒" % ["電池" if weapon.is_energy else "彈", weapon.reload_time])
	else:
		lines.append("彈藥　∞（不需換彈）")
	lines.append("射速　%.1f 發／秒" % (1.0 / maxf(0.01, weapon.fire_interval)))
	return lines


func _ammo_text(loadout: Loadout, slot: int, weapon: WeaponData) -> String:
	if not weapon.has_magazine():
		return "彈藥 ∞"
	var reserve := loadout.reserve_in(slot)
	return "%d／%s" % [loadout.mag_in(slot), "∞" if reserve < 0 else str(reserve)]


func _kind_text(weapon: WeaponData) -> String:
	return "能量" if weapon.is_energy else "實彈"


func _activate_entry(index: int) -> bool:
	if not context.is_valid():
		return false
	var loadout := context.player.loadout
	var weapon := loadout.weapon_in(index)
	if weapon == null:
		context.say("這個欄位是空的", true)
		return false
	if index == loadout.active_slot:
		context.say("%s 已經在手上" % weapon.display_name)
		return false
	loadout.select(index)
	if loadout.active_slot != index:
		context.say("%s 沒有彈藥了" % weapon.display_name, true)
		return false
	Sfx.play(&"reload_done", -6.0)
	context.say("已換成 %s" % weapon.display_name)
	return true
