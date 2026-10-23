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
	return "改裝"


func tab_tooltip() -> String:
	return "用信用點改裝攜帶中的武器（目前 ¥%d）" % Progression.credits


func _empty_text() -> String:
	return "目前攜帶的武器沒有可改裝的項目。"


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
	var reason := Progression.arm_shield_block_reason(part)
	var entry := InventoryEntry.new()
	entry.id = StringName("arm_shield:%s" % part.id)
	entry.title = "臂盾・%s" % part.display_name
	entry.accent = Palette.CYAN
	entry.icon = ItemIcons.item(ARM_SHIELD_ICON)
	entry.detail_icon = ItemIcons.item_hd(ARM_SHIELD_ICON)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 2
	entry.subtitle = "已裝上" if owned else "¥%d" % part.cost
	if owned:
		entry.badge = "已裝上"
		entry.badge_color = Palette.NEON_GREEN
	entry.dimmed = owned
	entry.detail_tag = "改裝・機械臂臂盾"
	entry.detail_stats = _arm_preview(part, owned)
	entry.detail_body = "格擋時凜的機械左臂展開臂盾。%s。" % part.description
	entry.hint = part.description
	entry.action_label = "已裝上" if owned else "安裝（¥%d）" % part.cost
	entry.action_enabled = reason.is_empty()
	entry.action_hint = "這個零件已經裝上了" if owned else (reason if not reason.is_empty() else "花費 ¥%d，立刻生效" % part.cost)
	return entry


## 裝上前後的格擋數值（已裝上時只顯示目前數值）。
func _arm_preview(part: ArmShieldPartData, owned: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("持有　¥%d" % Progression.credits)
	var tuning: PlayerTuning = context.player.tuning if context != null and context.is_valid() else null
	var installed := Progression.owned_arm_shield_parts()
	var before := GuardStats.build(tuning, installed)
	if not owned:
		installed.append(part)
	var after := GuardStats.build(tuning, installed)
	match part.effect:
		ArmShieldPartData.Effect.PARRY_WINDOW:
			lines.append(_diff("完美格擋時間窗", "%.2f 秒" % before.parry_window(), "%.2f 秒" % after.parry_window(), owned))
		ArmShieldPartData.Effect.BLOCK_ARC:
			lines.append(_diff("擋得住的角度", "%d°" % roundi(before.block_arc_degrees()), "%d°" % roundi(after.block_arc_degrees()), owned))
		ArmShieldPartData.Effect.CUSHION:
			lines.append(_diff("防禦量上限", "%d" % roundi(before.guard_max()), "%d" % roundi(after.guard_max()), owned))
			lines.append(_diff("被打穿的硬直", "%.2f 秒" % before.guard_break_stun(), "%.2f 秒" % after.guard_break_stun(), owned))
		ArmShieldPartData.Effect.HEAT_SINK:
			lines.append(_diff("開始回復", "%.2f 秒後" % before.guard_regen_delay(), "%.2f 秒後" % after.guard_regen_delay(), owned))
			lines.append(_diff("回復速度", "每秒 %d" % roundi(before.guard_regen_per_second()), "每秒 %d" % roundi(after.guard_regen_per_second()), owned))
		ArmShieldPartData.Effect.LIGHT_FRAME:
			lines.append(_diff("舉盾移動速度", "%d%%" % roundi(before.block_speed_multiplier() * 100.0), "%d%%" % roundi(after.block_speed_multiplier() * 100.0), owned))
		ArmShieldPartData.Effect.DEFLECT:
			lines.append(_diff("一般格擋的子彈", "擋下" if not before.deflect_on_block else "彈回", "擋下" if not after.deflect_on_block else "彈回", owned))
	return lines


func _entry_for(weapon: WeaponData, upgrade: WeaponUpgradeData) -> InventoryEntry:
	var base := WeaponTuning.base_of(weapon)
	var owned := Progression.has_upgrade(weapon, upgrade.id)
	var reason := Progression.upgrade_block_reason(weapon, upgrade)
	var entry := InventoryEntry.new()
	entry.id = StringName("%s:%s" % [base.id, upgrade.id])
	entry.title = "%s・%s" % [base.short_name if not base.short_name.is_empty() else base.display_name, upgrade.display_name]
	entry.accent = base.color
	entry.icon = ItemIcons.for_weapon(base)
	entry.detail_icon = ItemIcons.for_weapon_hd(base)
	entry.card_icon_scale = 1
	entry.detail_icon_scale = 2
	entry.subtitle = "已改裝" if owned else "¥%d" % upgrade.cost
	if owned:
		entry.badge = "已改裝"
		entry.badge_color = Palette.NEON_GREEN
	entry.dimmed = owned
	entry.detail_tag = "改裝・%s" % base.display_name
	entry.detail_stats = _preview(weapon, upgrade, owned)
	entry.detail_body = upgrade.description
	entry.hint = upgrade.description
	entry.action_label = "已改裝" if owned else "改裝（¥%d）" % upgrade.cost
	entry.action_enabled = reason.is_empty()
	entry.action_hint = "這項改裝已經買過了" if owned else (reason if not reason.is_empty() else "花費 ¥%d，立刻生效" % upgrade.cost)
	return entry


## 改裝前後的數值對照（已改裝時只顯示目前數值）。
func _preview(weapon: WeaponData, upgrade: WeaponUpgradeData, owned: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("持有　¥%d" % Progression.credits)
	var base := WeaponTuning.base_of(weapon)
	var after: WeaponData = weapon if owned else WeaponTuning.apply(base, _owned_with(weapon, upgrade))
	match upgrade.effect:
		WeaponUpgradeData.Effect.MAGAZINE:
			lines.append(_diff("彈匣", str(weapon.magazine_size), str(after.magazine_size), owned))
		WeaponUpgradeData.Effect.SPREAD:
			lines.append(_diff("散佈", "%.1f°" % _total_spread(weapon), "%.1f°" % _total_spread(after), owned))
		WeaponUpgradeData.Effect.RELOAD:
			lines.append(_diff("換彈", "%.2f 秒" % weapon.reload_time, "%.2f 秒" % after.reload_time, owned))
	return lines


func _owned_with(weapon: WeaponData, upgrade: WeaponUpgradeData) -> Array[WeaponUpgradeData]:
	var list := Progression.owned_upgrades(weapon)
	list.append(upgrade)
	return list


static func _total_spread(weapon: WeaponData) -> float:
	return weapon.spread_degrees + weapon.random_spread_degrees


static func _diff(label: String, before: String, after: String, owned: bool) -> String:
	return "%s　%s" % [label, before] if owned else "%s　%s → %s" % [label, before, after]


func _activate_entry(index: int) -> bool:
	if not context.is_valid() or index < 0:
		return false
	if index >= _targets.size():
		var arm_index := index - _targets.size()
		return arm_index < _arm_targets.size() and _activate_arm(_arm_targets[arm_index])
	var target := _targets[index]
	var weapon: WeaponData = target["weapon"]
	var upgrade: WeaponUpgradeData = target["upgrade"]
	var reason := Progression.upgrade_block_reason(weapon, upgrade)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"empty", -6.0)
		return false
	if not Progression.buy_upgrade(weapon, upgrade):
		context.say("改裝失敗", true)
		return false
	Sfx.play(&"reload_done", -4.0)
	context.say("已替 %s 安裝 %s，花費 ¥%d。" % [WeaponTuning.base_of(weapon).display_name, upgrade.display_name, upgrade.cost])
	return true


func _activate_arm(part: ArmShieldPartData) -> bool:
	var reason := Progression.arm_shield_block_reason(part)
	if not reason.is_empty():
		context.say(reason, true)
		Sfx.play(&"empty", -6.0)
		return false
	if not Progression.buy_arm_shield_part(part):
		context.say("安裝失敗", true)
		return false
	Sfx.play(&"reload_done", -4.0)
	context.say("臂盾裝上了%s，花費 ¥%d。%s。" % [part.display_name, part.cost, part.description])
	return true

