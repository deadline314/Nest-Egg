extends Node
## 成長進度（本輪）：信用點（貨幣）、武器改裝。義體能力與商店在這裡擴充（見 NE-33）。
## 進度跟著檢查點：死亡重來時還原成檢查點當下的樣子（沒有檢查點則還原成進入關卡時），
## 所以不能靠死亡刷錢；開始新一輪時歸零。快照是簡單的 Dictionary，損毀或缺欄位時退回安全預設值。

signal credits_changed(credits: int, delta: int)
signal upgrades_changed
signal abilities_changed

const UPGRADE_DIR := "res://data/upgrades"
const ABILITY_DIR := "res://data/abilities"
const SNAPSHOT_VERSION := 1
const MAX_CREDITS := 99999

var credits := 0

var _upgrade_catalog: Array[WeaponUpgradeData] = []
var _catalog_loaded := false
## 武器 id -> 已買的改裝 id 清單。
var _upgrades: Dictionary[StringName, Array] = {}
var _ability_catalog: Array[CyberAbilityData] = []
var _ability_catalog_loaded := false
var _unlocked_abilities: Dictionary[StringName, bool] = {}
var _equipped_ability: StringName = &""


# ---------------------------------------------------------------------------
# 信用點
# ---------------------------------------------------------------------------

## 增加信用點（負數與 0 忽略）。回傳實際增加量。
func add_credits(amount: int) -> int:
	if amount <= 0:
		return 0
	var gained := mini(amount, MAX_CREDITS - credits)
	if gained <= 0:
		return 0
	credits += gained
	credits_changed.emit(credits, gained)
	return gained


func can_afford(cost: int) -> bool:
	return cost >= 0 and credits >= cost


## 花費信用點。不足時回傳 false 且不扣款。
func spend(cost: int) -> bool:
	if cost < 0 or credits < cost:
		return false
	if cost > 0:
		credits -= cost
		credits_changed.emit(credits, -cost)
	return true


# ---------------------------------------------------------------------------
# 武器改裝
# ---------------------------------------------------------------------------

## 所有改裝定義（依 order 排序）。讀取失敗的檔案記錄錯誤並略過。
func upgrade_catalog() -> Array[WeaponUpgradeData]:
	if not _catalog_loaded:
		_catalog_loaded = true
		for res in ResourceCatalog.load_dir(UPGRADE_DIR, WeaponUpgradeData, "Progression"):
			_upgrade_catalog.append(res as WeaponUpgradeData)
	return _upgrade_catalog


func find_upgrade(id: StringName) -> WeaponUpgradeData:
	for upgrade in upgrade_catalog():
		if upgrade.id == id:
			return upgrade
	return null


## 這把武器可以買的改裝（依 order）。
func upgrades_for(weapon: WeaponData) -> Array[WeaponUpgradeData]:
	var result: Array[WeaponUpgradeData] = []
	var base := WeaponTuning.base_of(weapon)
	for upgrade in upgrade_catalog():
		if upgrade.applies_to(base):
			result.append(upgrade)
	return result


func has_upgrade(weapon: WeaponData, upgrade_id: StringName) -> bool:
	var base := WeaponTuning.base_of(weapon)
	return base != null and _upgrades.get(base.id, []).has(upgrade_id)


## 這把武器目前的改裝資料。
func owned_upgrades(weapon: WeaponData) -> Array[WeaponUpgradeData]:
	var result: Array[WeaponUpgradeData] = []
	var base := WeaponTuning.base_of(weapon)
	if base == null:
		return result
	for id: StringName in _upgrades.get(base.id, []):
		var upgrade := find_upgrade(id)
		if upgrade != null:
			result.append(upgrade)
	return result


## 回傳不能買的原因（空字串代表可以買）。
func upgrade_block_reason(weapon: WeaponData, upgrade: WeaponUpgradeData) -> String:
	if weapon == null or upgrade == null:
		return "沒有這項改裝"
	if not upgrade.applies_to(WeaponTuning.base_of(weapon)):
		return "這把武器用不到這項改裝"
	if has_upgrade(weapon, upgrade.id):
		return "已經改裝過了"
	if not can_afford(upgrade.cost):
		return "信用點不足（還差 %d）" % (upgrade.cost - credits)
	return ""


## 購買改裝。成功時扣款並通知武器欄重新計算數值。
func buy_upgrade(weapon: WeaponData, upgrade: WeaponUpgradeData) -> bool:
	if not upgrade_block_reason(weapon, upgrade).is_empty():
		return false
	if not spend(upgrade.cost):
		return false
	var base := WeaponTuning.base_of(weapon)
	var list: Array = _upgrades.get(base.id, [])
	list.append(upgrade.id)
	_upgrades[base.id] = list
	upgrades_changed.emit()
	return true


## 改裝後的武器（沒有改裝就是原物件）。武器欄用它計算實際數值。
func tuned(base: WeaponData) -> WeaponData:
	if base == null or not _upgrades.has(base.id):
		return base
	return WeaponTuning.apply(base, owned_upgrades(base))


# ---------------------------------------------------------------------------
# 義體能力
# ---------------------------------------------------------------------------

## 所有義體能力定義（依 order 排序）。
func ability_catalog() -> Array[CyberAbilityData]:
	if not _ability_catalog_loaded:
		_ability_catalog_loaded = true
		for res in ResourceCatalog.load_dir(ABILITY_DIR, CyberAbilityData, "Progression"):
			_ability_catalog.append(res as CyberAbilityData)
	return _ability_catalog


func find_ability(id: StringName) -> CyberAbilityData:
	for ability in ability_catalog():
		if ability.id == id:
			return ability
	return null


func is_ability_unlocked(id: StringName) -> bool:
	return _unlocked_abilities.has(id)


## 目前裝備的義體能力（沒有裝備回傳 null）。
func equipped_ability() -> CyberAbilityData:
	return find_ability(_equipped_ability) if _unlocked_abilities.has(_equipped_ability) else null


## 回傳不能解鎖的原因（空字串代表可以）。
func ability_unlock_block_reason(ability: CyberAbilityData) -> String:
	if ability == null:
		return "沒有這項能力"
	if is_ability_unlocked(ability.id):
		return "已經解鎖了"
	if not can_afford(ability.unlock_cost):
		return "信用點不足（還差 %d）" % (ability.unlock_cost - credits)
	return ""


## 解鎖能力並自動裝備（第一個解鎖的能力才自動裝備，之後由玩家選擇）。
func unlock_ability(ability: CyberAbilityData) -> bool:
	if not ability_unlock_block_reason(ability).is_empty() or not spend(ability.unlock_cost):
		return false
	_unlocked_abilities[ability.id] = true
	if equipped_ability() == null:
		_equipped_ability = ability.id
	abilities_changed.emit()
	return true


## 裝備已解鎖的能力。回傳是否成功。
func equip_ability(id: StringName) -> bool:
	if not _unlocked_abilities.has(id) or find_ability(id) == null:
		return false
	_equipped_ability = id
	abilities_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 存檔
# ---------------------------------------------------------------------------

func reset_run() -> void:
	credits = 0
	_upgrades.clear()
	_unlocked_abilities.clear()
	_equipped_ability = &""
	credits_changed.emit(credits, 0)
	upgrades_changed.emit()
	abilities_changed.emit()


func snapshot() -> Dictionary:
	var upgrades: Dictionary = {}
	for weapon_id in _upgrades:
		upgrades[String(weapon_id)] = (_upgrades[weapon_id] as Array).map(func(id: StringName) -> String: return String(id))
	var abilities: Array[String] = []
	for id in _unlocked_abilities:
		abilities.append(String(id))
	return {"version": SNAPSHOT_VERSION, "credits": credits, "upgrades": upgrades, "abilities": abilities, "equipped": String(_equipped_ability)}


## 從快照還原；資料損毀、型別不符或引用到已不存在的改裝時略過該部分，保證不崩潰。
func restore(data: Dictionary) -> void:
	credits = clampi(int(data.get("credits", 0)) if typeof(data.get("credits", 0)) in [TYPE_INT, TYPE_FLOAT] else 0, 0, MAX_CREDITS)
	_upgrades.clear()
	var raw: Variant = data.get("upgrades", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for weapon_id: Variant in raw:
			var ids: Variant = raw[weapon_id]
			if typeof(ids) != TYPE_ARRAY:
				continue
			var valid: Array = []
			for id: Variant in ids:
				var upgrade_id := StringName(str(id))
				if find_upgrade(upgrade_id) != null and not valid.has(upgrade_id):
					valid.append(upgrade_id)
			if not valid.is_empty():
				_upgrades[StringName(str(weapon_id))] = valid
	_restore_abilities(data)
	credits_changed.emit(credits, 0)
	upgrades_changed.emit()
	abilities_changed.emit()


func _restore_abilities(data: Dictionary) -> void:
	_unlocked_abilities.clear()
	_equipped_ability = &""
	var raw: Variant = data.get("abilities", [])
	if typeof(raw) == TYPE_ARRAY:
		for id: Variant in raw:
			var ability_id := StringName(str(id))
			if find_ability(ability_id) != null:
				_unlocked_abilities[ability_id] = true
	var equipped := StringName(str(data.get("equipped", "")))
	if _unlocked_abilities.has(equipped):
		_equipped_ability = equipped
	elif not _unlocked_abilities.is_empty():
		_equipped_ability = _unlocked_abilities.keys()[0]
