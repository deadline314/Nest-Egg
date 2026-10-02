class_name UpgradesPage
extends CardListPage
## 武器改裝：列出攜帶中每把武器可買的改裝（擴充彈匣、穩定槍管、快速換彈…），顯示花費與改裝前後的數值，
## 信用點足夠就能購買；改裝立刻生效並存進檢查點。改裝項目是資料（data/upgrades/），這裡不寫死任何一項。

## 與 _entries 對應：{ "slot": int, "weapon": WeaponData, "upgrade": WeaponUpgradeData }。
var _targets: Array[Dictionary] = []


func tab_title() -> String:
	return "改裝"


func tab_tooltip() -> String:
	return "用信用點改裝攜帶中的武器（目前 ¥%d）" % Progression.credits


func _empty_text() -> String:
	return "目前攜帶的武器沒有可改裝的項目。"


func _build_entries() -> Array[InventoryEntry]:
	var entries: Array[InventoryEntry] = []
	_targets.clear()
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
	return entries


func _entry_for(weapon: WeaponData, upgrade: WeaponUpgradeData) -> InventoryEntry:
	var base := WeaponTuning.base_of(weapon)
	var owned := Progression.has_upgrade(weapon, upgrade.id)
	var reason := Progression.upgrade_block_reason(weapon, upgrade)
	var entry := InventoryEntry.new()
	entry.id = StringName("%s:%s" % [base.id, upgrade.id])
	entry.title = "%s・%s" % [base.short_name if not base.short_name.is_empty() else base.display_name, upgrade.display_name]
	entry.accent = base.color
	entry.icon = ItemIcons.weapon(base.visual_id)
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
	if not context.is_valid() or index < 0 or index >= _targets.size():
		return false
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
	context.say("已改裝：%s・%s（-¥%d）" % [WeaponTuning.base_of(weapon).display_name, upgrade.display_name, upgrade.cost])
	return true
