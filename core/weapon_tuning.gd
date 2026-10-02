class_name WeaponTuning
extends RefCounted
## 把改裝套用到武器：回傳「改裝後的武器」副本（原資料不動）。副本記得自己的原始資料（base_of）。
## 沒有任何改裝時直接回傳原物件，不複製。

const META_BASE := &"tuning_base"


## upgrades：該武器已有的 WeaponUpgradeData。
static func apply(base: WeaponData, upgrades: Array[WeaponUpgradeData]) -> WeaponData:
	if base == null:
		return null
	var effective: Array[WeaponUpgradeData] = []
	for upgrade in upgrades:
		if upgrade != null and upgrade.applies_to(base):
			effective.append(upgrade)
	if effective.is_empty():
		return base
	var tuned := base.duplicate() as WeaponData
	tuned.set_meta(META_BASE, base)
	for upgrade in effective:
		match upgrade.effect:
			WeaponUpgradeData.Effect.MAGAZINE:
				tuned.magazine_size = maxi(base.magazine_size + 1, roundi(base.magazine_size * (1.0 + upgrade.amount)))
			WeaponUpgradeData.Effect.SPREAD:
				tuned.spread_degrees = base.spread_degrees * (1.0 - upgrade.amount)
				tuned.random_spread_degrees = base.random_spread_degrees * (1.0 - upgrade.amount)
			WeaponUpgradeData.Effect.RELOAD:
				tuned.reload_time = maxf(0.2, base.reload_time * (1.0 - upgrade.amount))
	return tuned


## 改裝後武器的原始資料；沒被改裝過的武器就是它自己。
static func base_of(weapon: WeaponData) -> WeaponData:
	if weapon != null and weapon.has_meta(META_BASE):
		return weapon.get_meta(META_BASE) as WeaponData
	return weapon
