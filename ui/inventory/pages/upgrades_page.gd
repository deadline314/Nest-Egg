class_name UpgradesPage
extends CardListPage
## 武器改裝：列出攜帶中每把武器可買的改裝（擴充彈匣、穩定槍管、快速換彈…），顯示花費與改裝前後的數值，
## 信用點足夠就能購買；改裝立刻生效並存進檢查點。改裝項目是資料（data/upgrades/），這裡不寫死任何一項。
## 最後列出機械臂臂盾的零件（NE-269，data/arm_shield/）：每個零件改格擋的一項數值，同樣顯示前後對照。

const ARM_SHIELD_ICON := "shield_cell"

## 與 _entries 的前段對應：{ "slot": int, "weapon": WeaponData, "upgrade": WeaponUpgradeData }。
var _targets: Array[Dictionary] = []
## 接在武器改裝後面的臂盾零件（_entries 的後段，索引 = _targets.size() + i）。
var _arm_targets: Array[ArmShieldPartData] = []


func tab_title() -> String:
	return Labels.get_text(&"mods")


func tab_tooltip() -> String:
	return Labels.get_text(&"mods_help") % Progression.credits


func _empty_text() -> String:
	return Labels.get_text(&"mods_empty")


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	_targets.clear()
	_arm_targets.clear()
	if context == null or not context.is_valid():
		return entries
	var loadout := context.player.loadout
	for slot in Loadout.MAX_SLOTS:
		var weapon := loadout.weapon_in(slot)
		if weapon == null:
			continue
		for upgrade in Progression.upgrades_for(weapon):
			_targets.append({"slot": slot, "weapon": weapon, "upgrade": upgrade})
			entries.append(_entry_for(weapon, upgrade))
	for part in Progression.arm_shield_catalog():
		_arm_targets.append(part)
		entries.append(_arm_entry_for(part))
	return entries


func _arm_entry_for(part: ArmShieldPartData) -> InventoryEntry:
	var owned := Progression.has_arm_shield_part(part.id)
	var reason := _block_text(Progression.arm_shield_block(part), part.cost, true)
	var entry := InventoryEntry.new()
	entry.id = StringName("arm_shield:%s" % part.id)
	entry.title = part.display_name_for(Story.language)
	entry.accent = Palette.CYAN
	entry.icon = ItemIcons.item(ARM_SHIELD_ICON)
	entry.detail_icon = ItemIcons.item_hd(ARM_SHIELD_ICON)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 2
	entry.subtitle = Labels.get_text(&"mods_arm_owned") if owned else "¥%d" % part.cost
	if owned:
		entry.badge = Labels.get_text(&"mods_arm_owned")
		entry.badge_color = Palette.NEON_GREEN
	entry.dimmed = owned
	entry.detail_tag = Labels.get_text(&"mods_shield")
	entry.detail_stats = _arm_preview(part, owned)
	entry.detail_body = part.description_for(Story.language)
	entry.hint = _effect_hint(entry)
	entry.action_label = Labels.get_text(&"mods_arm_owned") if owned else Labels.get_text(&"mods_arm_buy") % part.cost
	entry.action_enabled = reason.is_empty()
	entry.action_hint = Labels.get_text(&"mods_arm_owned_help") if owned else (reason if not reason.is_empty() else Labels.get_text(&"mods_instant") % part.cost)
	return entry


## 裝上前後的格擋數值（已裝上時只顯示目前數值）。
func _arm_preview(part: ArmShieldPartData, owned: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(Labels.get_text(&"credits") % Progression.credits)
	var tuning: PlayerTuning = context.player.tuning if context != null and context.is_valid() else null
	var installed := Progression.owned_arm_shield_parts()
	var before := GuardStats.build(tuning, installed)
	if not owned:
		installed.append(part)
	var after := GuardStats.build(tuning, installed)
	match part.effect:
		ArmShieldPartData.Effect.PARRY_WINDOW:
			lines.append(_diff(Labels.get_text(&"mods_parry"), Labels.get_text(&"mods_seconds") % before.parry_window(), Labels.get_text(&"mods_seconds") % after.parry_window(), owned))
		ArmShieldPartData.Effect.BLOCK_ARC:
			lines.append(_diff(Labels.get_text(&"mods_arc"), "%d°" % roundi(before.block_arc_degrees()), "%d°" % roundi(after.block_arc_degrees()), owned))
		ArmShieldPartData.Effect.CUSHION:
			lines.append(_diff(Labels.get_text(&"mods_guard_capacity"), "%d" % roundi(before.guard_max()), "%d" % roundi(after.guard_max()), owned))
			lines.append(_diff(Labels.get_text(&"mods_stun"), Labels.get_text(&"mods_seconds") % before.guard_break_stun(), Labels.get_text(&"mods_seconds") % after.guard_break_stun(), owned))
		ArmShieldPartData.Effect.HEAT_SINK:
			lines.append(_diff(Labels.get_text(&"mods_regen_delay"), Labels.get_text(&"mods_seconds") % before.guard_regen_delay(), Labels.get_text(&"mods_seconds") % after.guard_regen_delay(), owned))
			lines.append(_diff(Labels.get_text(&"mods_regen_rate"), Labels.get_text(&"mods_per_second") % roundi(before.guard_regen_per_second()), Labels.get_text(&"mods_per_second") % roundi(after.guard_regen_per_second()), owned))
		ArmShieldPartData.Effect.LIGHT_FRAME:
			lines.append(_diff(Labels.get_text(&"mods_guard_speed"), "%d%%" % roundi(before.block_speed_multiplier() * 100.0), "%d%%" % roundi(after.block_speed_multiplier() * 100.0), owned))
		ArmShieldPartData.Effect.DEFLECT:
			lines.append(_diff(Labels.get_text(&"mods_blocked_bullet"), _block_result(before.deflect_on_block), _block_result(after.deflect_on_block), owned))
	return lines


func _entry_for(weapon: WeaponData, upgrade: WeaponUpgradeData) -> InventoryEntry:
	var base := WeaponTuning.base_of(weapon)
	var owned := Progression.has_upgrade(weapon, upgrade.id)
	var reason := _block_text(Progression.upgrade_block(weapon, upgrade), upgrade.cost)
	var entry := InventoryEntry.new()
	entry.id = StringName("%s:%s" % [base.id, upgrade.id])
	entry.title = Labels.get_text(&"mods_name") % [base.short_name_for(Story.language), upgrade.display_name_for(Story.language)]
	entry.accent = base.color
	entry.icon = ItemIcons.for_weapon(base)
	entry.detail_icon = ItemIcons.for_weapon_hd(base)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 2
	entry.subtitle = Labels.get_text(&"mods_owned") if owned else "¥%d" % upgrade.cost
	if owned:
		entry.badge = Labels.get_text(&"mods_owned")
		entry.badge_color = Palette.NEON_GREEN
	entry.dimmed = owned
	entry.detail_tag = Labels.get_text(&"mods_weapon_tag") % base.display_name_for(Story.language)
	entry.detail_stats = _preview(weapon, upgrade, owned)
	entry.detail_body = upgrade.description_for(Story.language)
	entry.hint = _effect_hint(entry)
	entry.action_label = Labels.get_text(&"mods_owned") if owned else Labels.get_text(&"mods_buy") % upgrade.cost
	entry.action_enabled = reason.is_empty()
	entry.action_hint = Labels.get_text(&"mods_owned_help") if owned else (reason if not reason.is_empty() else Labels.get_text(&"mods_instant") % upgrade.cost)
	return entry


## 改裝前後的數值對照（已改裝時只顯示目前數值）。
func _preview(weapon: WeaponData, upgrade: WeaponUpgradeData, owned: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(Labels.get_text(&"credits") % Progression.credits)
	if upgrade.effect == WeaponUpgradeData.Effect.MELEE_TECHNIQUE:
		lines.append_array(_technique_preview(weapon, upgrade, owned))
		return lines
	var base := WeaponTuning.base_of(weapon)
	var after: WeaponData = weapon if owned else WeaponTuning.apply(base, _owned_with(weapon, upgrade))
	match upgrade.effect:
		WeaponUpgradeData.Effect.MAGAZINE:
			lines.append(_diff(Labels.get_text(&"mods_magazine"), str(weapon.magazine_size), str(after.magazine_size), owned))
		WeaponUpgradeData.Effect.SPREAD:
			lines.append(_diff(Labels.get_text(&"mods_spread"), "%.1f°" % _total_spread(weapon), "%.1f°" % _total_spread(after), owned))
		WeaponUpgradeData.Effect.RELOAD:
			lines.append(_diff(Labels.get_text(&"mods_reload"), Labels.get_text(&"mods_seconds") % weapon.reload_time, Labels.get_text(&"mods_seconds") % after.reload_time, owned))
	return lines


func _technique_preview(weapon: WeaponData, upgrade: WeaponUpgradeData, owned: bool) -> PackedStringArray:
	var moves := MeleeData.set_of(weapon)
	var matches := upgrade.id == moves.extension_upgrade()
	var current := moves.combo(owned and matches)
	var preview := current if owned else moves.combo(matches)
	return PackedStringArray([
		_technique_value(&"technique_moves", str(current.size()), str(preview.size())),
		_technique_value(&"technique_dps",
			"%.1f" % moves.damage_per_second(current), "%.1f" % moves.damage_per_second(preview)),
		_technique_value(&"technique_reach",
			str(roundi(moves.max_range(current))), str(roundi(moves.max_range(preview)))),
	])


func _technique_value(key: StringName, before: String, after: String) -> String:
	return _diff(Labels.get_text(key), before, after, before == after)


func _owned_with(weapon: WeaponData, upgrade: WeaponUpgradeData) -> Array[WeaponUpgradeData]:
	var list := Progression.owned_upgrades(weapon)
	list.append(upgrade)
	return list


static func _total_spread(weapon: WeaponData) -> float:
	return weapon.spread_degrees + weapon.random_spread_degrees


static func _diff(label: String, before: String, after: String, owned: bool) -> String:
	return "%s　%s" % [label, before] if owned else "%s　%s → %s" % [label, before, after]


## The first row is the wallet. The next row shows this modification's main effect.
static func _effect_hint(entry: InventoryEntry) -> String:
	return entry.detail_stats[1] if entry.detail_stats.size() > 1 else entry.detail_body


func _block_result(reflects: bool) -> String:
	return Labels.get_text(&"mods_block_reflect" if reflects else &"mods_block_catch")


func _block_text(block: Progression.UpgradeBlock, cost: int, arm: bool = false) -> String:
	match block:
		Progression.UpgradeBlock.MISSING:
			return Labels.get_text(&"mods_arm_missing" if arm else &"mods_missing")
		Progression.UpgradeBlock.INCOMPATIBLE:
			return Labels.get_text(&"mods_unsuitable")
		Progression.UpgradeBlock.OWNED:
			return Labels.get_text(&"mods_arm_owned_help" if arm else &"mods_owned_help")
		Progression.UpgradeBlock.SHORT_CREDITS:
			return Labels.get_text(&"shop_short") % (cost - Progression.credits)
	return ""


func _activate_entry(index: int) -> bool:
	if not context.is_valid() or index < 0:
		return false
	if index >= _targets.size():
		var arm_index := index - _targets.size()
		return arm_index < _arm_targets.size() and _activate_arm(_arm_targets[arm_index])
	var target := _targets[index]
	var weapon: WeaponData = target["weapon"]
	var upgrade: WeaponUpgradeData = target["upgrade"]
	var reason := _block_text(Progression.upgrade_block(weapon, upgrade), upgrade.cost)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"ui_error", -6.0)
		return false
	if not Progression.buy_upgrade(weapon, upgrade):
		context.say(Labels.get_text(&"mods_buy_error"), true)
		return false
	Sfx.play(&"ui_confirm", -4.0)
	context.say(Labels.get_text(&"mods_installed") % [WeaponTuning.base_of(weapon).short_name_for(Story.language), upgrade.display_name_for(Story.language), upgrade.cost])
	return true


func _activate_arm(part: ArmShieldPartData) -> bool:
	var reason := _block_text(Progression.arm_shield_block(part), part.cost, true)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"ui_error", -6.0)
		return false
	if not Progression.buy_arm_shield_part(part):
		context.say(Labels.get_text(&"mods_arm_error"), true)
		return false
	Sfx.play(&"ui_confirm", -4.0)
	context.say(Labels.get_text(&"mods_arm_installed") % [part.display_name_for(Story.language), part.cost])
	return true

