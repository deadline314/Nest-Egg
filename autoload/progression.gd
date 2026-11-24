extends Node
## 成長進度（本輪）：信用點（貨幣）、武器改裝。義體能力與商店在這裡擴充（見 NE-33）。
## 進度跟著檢查點：死亡重來時還原成檢查點當下的樣子（沒有檢查點則還原成進入關卡時），
## 所以不能靠死亡刷錢；開始新一輪時歸零。快照是簡單的 Dictionary，損毀或缺欄位時退回安全預設值。

signal credits_changed(credits: int, delta: int)
signal upgrades_changed
signal abilities_changed
signal pawned_changed
## 0元結果也需要保存；主流程接線由後續Story owner處理。
signal story_transaction_committed(id: StringName)

const UPGRADE_DIR := "res://data/upgrades"
const ABILITY_DIR := "res://data/abilities"
## 臂盾零件（NE-269）。存檔裡只有買過零件才會出現 arm_shield 欄位，沒買時存檔內容和以前完全一樣。
const ARM_SHIELD_DIR := "res://data/arm_shield"
const SNAPSHOT_VERSION := 1
const MAX_CREDITS := 99999

enum UpgradeBlock { NONE, MISSING, INCOMPATIBLE, OWNED, SHORT_CREDITS }
enum PawnBlock { NONE, NOT_ACCEPTED, TICKET_LIMIT, WALLET_FULL, NO_TICKET, SHORT_CREDITS }
## 典當：當價 = 售價 × PAWN_RATE；贖回 = 當價 × (1 + PAWN_INTEREST)（進位）。同時最多 MAX_PAWNED 張當票，
## 這樣典當不能變成「無限換錢」，也一定比直接買貴一點點的反面：當了再贖是週轉，不是賺錢。
const PAWN_RATE := 0.5
const PAWN_INTEREST := 0.2
const MAX_PAWNED := 6

var credits := 0

var _upgrade_catalog: Array[WeaponUpgradeData] = []
var _catalog_loaded := false
## 武器 id -> 已買的改裝 id 清單。
var _upgrades: Dictionary[StringName, Array] = {}
var _ability_catalog: Array[CyberAbilityData] = []
var _ability_catalog_loaded := false
var _unlocked_abilities: Dictionary[StringName, bool] = {}
var _equipped_ability: StringName = &""
## 當票：消耗品 id -> 張數。
var _pawned: Dictionary[StringName, int] = {}
var _story_transactions := StoryTransactionLedger.new()
var _story_transaction_busy := false
var _arm_shield_catalog: Array[ArmShieldPartData] = []
var _arm_shield_catalog_loaded := false
## 已裝的臂盾零件 id（依購買順序）。
var _arm_shield_parts: Array[StringName] = []

## Opaque owner state: only the synchronous install bundle may hand this back.
class PreparedInstall extends RefCounted:
	var credits: int
	var upgrades: Dictionary[StringName, Array] = {}
	var abilities: Dictionary[StringName, bool] = {}
	var equipped: StringName = &""
	var pawned: Dictionary[StringName, int] = {}
	var arm_shield: Array[StringName] = []
	var ledger: StoryTransactionLedger


## Valid only for a single synchronous install proof. Each snapshot is still
## proved against the same authored data without rebuilding the catalogs.
class InstallCatalog extends RefCounted:
	var weapons: Dictionary = {}
	var upgrades: Dictionary = {}
	var ledger_context: Dictionary = {}


## Strict additive interface; legacy restore's repair/notification policy stays unchanged.
func prepare_install(raw: Variant, catalog: InstallCatalog = null) -> Dictionary:
	var errors := RunSaveCodec.validate_tree(raw)
	if not errors.is_empty():
		return {"error": errors[0]}
	if not raw is Dictionary:
		return {"error": "install/progression must be an object"}
	if raw.has("version"):
		if not RunSaveCodec.valid_version(raw["version"]):
			return {"error": "install/progression/version invalid"}
		if raw["version"] != SNAPSHOT_VERSION:
			return {"error": "install/progression/version unsupported", "unknown_version": true}
	for key: Variant in raw:
		if not key is String or key not in ["version", "credits", "upgrades", "abilities", "equipped", "pawned", "story_transactions", "arm_shield"]:
			return {"error": "install/progression unknown field: %s" % key}
	if not StoryTransactionData.integer_in(raw.get("credits"), 0, MAX_CREDITS):
		return {"error": "install/progression/credits invalid"}
	if not raw.get("upgrades", {}) is Dictionary or not raw.get("abilities", []) is Array or not raw.get("pawned", {}) is Dictionary or not raw.get("equipped", "") is String:
		return {"error": "install/progression containers invalid"}
	var prepared := PreparedInstall.new()
	prepared.credits = int(raw["credits"])
	if catalog == null:
		catalog = InstallCatalog.new()
	var saved_upgrades: Dictionary = raw.get("upgrades", {})
	if not saved_upgrades.is_empty() and catalog.weapons.is_empty():
		var weapon_catalog := WeaponCatalog.load_all()
		if not weapon_catalog.issues.is_empty():
			return {"error": "install/progression weapon catalog: " + weapon_catalog.issues[0]}
		for weapon: WeaponData in weapon_catalog.weapons:
			catalog.weapons[String(weapon.id)] = weapon
		for upgrade: WeaponUpgradeData in weapon_catalog.upgrades:
			catalog.upgrades[String(upgrade.id)] = upgrade
	for weapon: Variant in saved_upgrades:
		if not weapon is String or not catalog.weapons.has(weapon) or not saved_upgrades[weapon] is Array:
			return {"error": "install/progression/upgrades unknown weapon or invalid list: %s" % weapon}
		var ids: Array = []
		for id: Variant in saved_upgrades[weapon]:
			var upgrade: WeaponUpgradeData = catalog.upgrades.get(id) if id is String else null
			if upgrade == null or ids.has(StringName(id)):
				return {"error": "install/progression/upgrades unknown or repeated upgrade: %s/%s" % [weapon, id]}
			if not upgrade.applies_to(catalog.weapons[weapon]):
				return {"error": "install/progression/upgrades does not apply to this weapon"}
			ids.append(StringName(id))
		if not ids.is_empty():
			prepared.upgrades[StringName(weapon)] = ids
	for id: Variant in raw.get("abilities", []):
		if not id is String or find_ability(StringName(id)) == null or prepared.abilities.has(StringName(id)):
			return {"error": "install/progression/abilities unknown or repeated ability"}
		prepared.abilities[StringName(id)] = true
	prepared.equipped = StringName(raw.get("equipped", ""))
	if prepared.equipped != &"" and not prepared.abilities.has(prepared.equipped):
		return {"error": "install/progression/equipped is not unlocked"}
	var total := 0
	for id: Variant in raw.get("pawned", {}):
		var count: Variant = raw["pawned"][id]
		if not id is String or ConsumableBag.find(StringName(id)) == null or not StoryTransactionData.integer_in(count, 1, MAX_PAWNED):
			return {"error": "install/progression/pawned unknown consumable or invalid count"}
		total += int(count)
		if total > MAX_PAWNED:
			return {"error": "install/progression/pawned exceeds capacity"}
		prepared.pawned[StringName(id)] = int(count)
	var arm_raw: Variant = raw.get("arm_shield", [])
	if not arm_raw is Array:
		return {"error": "install/progression/arm_shield must be a list"}
	for id: Variant in arm_raw:
		if not id is String or find_arm_shield_part(StringName(id)) == null or prepared.arm_shield.has(StringName(id)):
			return {"error": "install/progression/arm_shield unknown or repeated part: %s" % [id]}
		prepared.arm_shield.append(StringName(id))
	var ledger: Variant = raw.get("story_transactions", {"version": StoryTransactionLedger.VERSION, "receipts": {}})
	var checked := StoryTransactionLedger.validate_snapshot(ledger)
	if not checked["valid"]:
		return {"error": checked["issues"][0], "unknown_version": not checked["supported"]}
	if catalog.ledger_context.is_empty():
		var definitions: Dictionary = {}
		for resource: StoryTransactionData in ResourceCatalog.load_dir("res://data/story_transactions", StoryTransactionData, "StoryInstall"):
			var description := resource.descriptor()
			if description.has("error") or definitions.has(String(resource.id)):
				return {"error": "install/progression canonical transaction resources invalid"}
			definitions[String(resource.id)] = description
		catalog.ledger_context = {"ledger_locked": false, "transaction_definitions": definitions}
	var proof := StoryConditionTree.verify_ledger({"ledger": ledger}, catalog.ledger_context)
	if not proof["valid"]:
		return {"error": "install/progression " + proof["error"]}
	prepared.ledger = StoryTransactionLedger.new()
	# The snapshot was fully proved; restore cannot warn or lock this local ledger.
	prepared.ledger.restore(ledger, true)
	return {"data": prepared}


## No loading, validation, allocation, reset, notification or save here.
func _install_prepared(prepared: PreparedInstall) -> void:
	credits = prepared.credits
	_upgrades = prepared.upgrades
	_unlocked_abilities = prepared.abilities
	_equipped_ability = prepared.equipped
	_pawned = prepared.pawned
	_arm_shield_parts = prepared.arm_shield
	_story_transactions = prepared.ledger


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


## 扣掉信用點的一個比例（死亡的代價）。cap > 0 時單次最多扣這麼多（死亡不會把存了很久的錢一次吃光）。
## 回傳實際扣掉的量；永遠不超過身上的現金、不會負債；沒有信用點或比例為 0 時不動。
func lose_credits_fraction(ratio: float, cap := 0) -> int:
	var amount := int(floor(float(credits) * clampf(ratio, 0.0, 1.0)))
	if cap > 0:
		amount = mini(amount, cap)
	amount = mini(amount, credits)
	if amount <= 0:
		return 0
	spend(amount)
	return amount


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


## 唯讀預檢不保證其後必定成功；提交時重新核對當刻餘額與收據。
func story_transaction_status(transaction: StoryTransactionData) -> Dictionary:
	return _story_transactions.status(transaction, credits, MAX_CREDITS)


func story_receipt_status(id: StringName) -> Dictionary:
	return _story_transactions.receipt_status(id)


## 收據與錢包在同步段內全部完成後才通知，避免回呼重入再領。
func apply_story_transaction(transaction: StoryTransactionData) -> Dictionary:
	if _story_transaction_busy or Story.result_publication_active():
		return StoryTransactionLedger.result("busy", String(transaction.id).left(64) if transaction != null else "", credits)
	_story_transaction_busy = true
	var committed := _story_transactions.commit(transaction, credits, MAX_CREDITS)
	if committed["applied"]:
		var before: int = committed["credits_before"]
		var after: int = committed["credits_after"]
		credits = after
		if after != before:
			credits_changed.emit(after, after - before)
		story_transaction_committed.emit(StringName(committed["id"]))
	_story_transaction_busy = false
	return committed


# ---------------------------------------------------------------------------
# 典當與贖回（老 K 的當舖）
# ---------------------------------------------------------------------------

## 這個消耗品的當價（售價的一半，至少 1）；不販售的東西（售價 0）不能典當，回傳 0。
func pawn_value(item: ConsumableData) -> int:
	if item == null or item.price <= 0:
		return 0
	return maxi(1, int(floor(float(item.price) * PAWN_RATE)))


## 贖回要付的錢：當價加利息（進位）。不能典當的東西回傳 0。
func redeem_cost(item: ConsumableData) -> int:
	var value := pawn_value(item)
	return 0 if value <= 0 else int(ceil(float(value) * (1.0 + PAWN_INTEREST)))


func pawned_count(id: StringName) -> int:
	return _pawned.get(id, 0)


func total_pawned() -> int:
	var total := 0
	for id in _pawned:
		total += _pawned[id]
	return total


## 有當票的消耗品 id（排序，顯示用）。
func pawned_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _pawned:
		if _pawned[id] > 0:
			ids.append(id)
	ids.sort()
	return ids


## 實收金額受錢包容量限制。贖回費用仍由原當價與利息決定。
func pawn_payout(item: ConsumableData) -> int:
	return mini(pawn_value(item), MAX_CREDITS - credits)


func pawn_block(item: ConsumableData) -> PawnBlock:
	if item == null or pawn_value(item) <= 0:
		return PawnBlock.NOT_ACCEPTED
	if total_pawned() >= MAX_PAWNED:
		return PawnBlock.TICKET_LIMIT
	if credits >= MAX_CREDITS:
		return PawnBlock.WALLET_FULL
	return PawnBlock.NONE


func pawn_block_reason(item: ConsumableData) -> String:
	match pawn_block(item):
		PawnBlock.NOT_ACCEPTED: return "這個東西當舖不收"
		PawnBlock.TICKET_LIMIT: return "當票滿了（最多 %d 張），先贖回幾樣" % MAX_PAWNED
		PawnBlock.WALLET_FULL: return "身上的錢已經滿了"
	return ""


## 典當：加錢、記一張當票。回傳實際拿到的錢（失敗回傳 0）。
func pawn(item: ConsumableData) -> int:
	if pawn_block(item) != PawnBlock.NONE:
		return 0
	var gained := add_credits(pawn_payout(item))
	_pawned[item.id] = pawned_count(item.id) + 1
	pawned_changed.emit()
	return gained


func redeem_block(item: ConsumableData) -> PawnBlock:
	if item == null or pawned_count(item.id) <= 0:
		return PawnBlock.NO_TICKET
	if not can_afford(redeem_cost(item)):
		return PawnBlock.SHORT_CREDITS
	return PawnBlock.NONE


func redeem_block_reason(item: ConsumableData) -> String:
	match redeem_block(item):
		PawnBlock.NO_TICKET: return "沒有這張當票"
		PawnBlock.SHORT_CREDITS: return "信用點不足（還差 %d）" % (redeem_cost(item) - credits)
	return ""


## 贖回：扣錢、收回當票。回傳是否成功（失敗不扣款）。
func redeem(item: ConsumableData) -> bool:
	if redeem_block(item) != PawnBlock.NONE or not spend(redeem_cost(item)):
		return false
	var left := pawned_count(item.id) - 1
	if left > 0:
		_pawned[item.id] = left
	else:
		_pawned.erase(item.id)
	pawned_changed.emit()
	return true


# ---------------------------------------------------------------------------
# 武器改裝
# ---------------------------------------------------------------------------

## 所有改裝定義（依 order 排序）。讀取失敗的檔案記錄錯誤並略過。
func upgrade_catalog() -> Array[WeaponUpgradeData]:
	if not _catalog_loaded:
		_catalog_loaded = true
		for res: WeaponUpgradeData in WeaponCatalog.load_all().upgrades:
			_upgrade_catalog.append(res)
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


func upgrade_block(weapon: WeaponData, upgrade: WeaponUpgradeData) -> UpgradeBlock:
	if weapon == null or upgrade == null:
		return UpgradeBlock.MISSING
	if not upgrade.applies_to(WeaponTuning.base_of(weapon)):
		return UpgradeBlock.INCOMPATIBLE
	if has_upgrade(weapon, upgrade.id):
		return UpgradeBlock.OWNED
	if not can_afford(upgrade.cost):
		return UpgradeBlock.SHORT_CREDITS
	return UpgradeBlock.NONE


## 舊呼叫端仍可取得原本的中文理由。
func upgrade_block_reason(weapon: WeaponData, upgrade: WeaponUpgradeData) -> String:
	match upgrade_block(weapon, upgrade):
		UpgradeBlock.MISSING: return "沒有這項改裝"
		UpgradeBlock.INCOMPATIBLE: return "這把武器用不到這項改裝"
		UpgradeBlock.OWNED: return "已經改裝過了"
		UpgradeBlock.SHORT_CREDITS: return "信用點不足（還差 %d）" % (upgrade.cost - credits)
	return ""


## 購買改裝。成功時扣款並通知武器欄重新計算數值。
func buy_upgrade(weapon: WeaponData, upgrade: WeaponUpgradeData) -> bool:
	if upgrade_block(weapon, upgrade) != UpgradeBlock.NONE:
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
# 臂盾零件（NE-269）
# ---------------------------------------------------------------------------

## 所有臂盾零件（依 order）。資料不合理的零件記錄錯誤並不列入，商店不會賣、存檔也不會認。
func arm_shield_catalog() -> Array[ArmShieldPartData]:
	if not _arm_shield_catalog_loaded:
		_arm_shield_catalog_loaded = true
		for res: Resource in ResourceCatalog.load_dir(ARM_SHIELD_DIR, ArmShieldPartData, "ArmShield"):
			var part := res as ArmShieldPartData
			if part != null and part.validate().is_empty():
				_arm_shield_catalog.append(part)
	return _arm_shield_catalog


func find_arm_shield_part(id: StringName) -> ArmShieldPartData:
	for part in arm_shield_catalog():
		if part.id == id:
			return part
	return null


func has_arm_shield_part(id: StringName) -> bool:
	return _arm_shield_parts.has(id)


## 已裝的零件資料（依購買順序）；給 Player 算格擋的有效數值。
func owned_arm_shield_parts() -> Array[ArmShieldPartData]:
	var result: Array[ArmShieldPartData] = []
	for id in _arm_shield_parts:
		var part := find_arm_shield_part(id)
		if part != null:
			result.append(part)
	return result


func arm_shield_block(part: ArmShieldPartData) -> UpgradeBlock:
	if part == null or find_arm_shield_part(part.id) == null:
		return UpgradeBlock.MISSING
	if has_arm_shield_part(part.id):
		return UpgradeBlock.OWNED
	if not can_afford(part.cost):
		return UpgradeBlock.SHORT_CREDITS
	return UpgradeBlock.NONE


func arm_shield_block_reason(part: ArmShieldPartData) -> String:
	match arm_shield_block(part):
		UpgradeBlock.MISSING: return "沒有這個零件"
		UpgradeBlock.OWNED: return "已經裝上了"
		UpgradeBlock.SHORT_CREDITS: return "信用點不足（還差 %d）" % (part.cost - credits)
	return ""


## 購買零件：成功時扣款、立刻生效並通知（與武器改裝同一個訊號，介面與玩家會重新計算）。
func buy_arm_shield_part(part: ArmShieldPartData) -> bool:
	if arm_shield_block(part) != UpgradeBlock.NONE:
		return false
	if not spend(part.cost):
		return false
	_arm_shield_parts.append(part.id)
	upgrades_changed.emit()
	return true


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
func ability_unlock_block_reason(ability: CyberAbilityData, language: String = StoryLocale.SOURCE_LANGUAGE) -> String:
	if ability == null:
		return StoryLocale.optional_text({"ja": "この能力は存在しない", "en": "Ability unavailable"}, language, "沒有這項能力")
	if is_ability_unlocked(ability.id):
		return StoryLocale.optional_text({"ja": "解放済み", "en": "Already unlocked"}, language, "已經解鎖了")
	if not can_afford(ability.unlock_cost):
		return StoryLocale.optional_text({"ja": "クレジット不足（あと ¥%d）", "en": "Not enough credits (need ¥%d more)"},
				language, "信用點不足（還差 %d）") % (ability.unlock_cost - credits)
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
	_story_transactions.reset()
	credits = 0
	_upgrades.clear()
	_unlocked_abilities.clear()
	_equipped_ability = &""
	_pawned.clear()
	_arm_shield_parts.clear()
	credits_changed.emit(credits, 0)
	upgrades_changed.emit()
	abilities_changed.emit()
	pawned_changed.emit()


func snapshot() -> Dictionary:
	var upgrades: Dictionary = {}
	for weapon_id in _upgrades:
		upgrades[String(weapon_id)] = (_upgrades[weapon_id] as Array).map(func(id: StringName) -> String: return String(id))
	var abilities: Array[String] = []
	for id in _unlocked_abilities:
		abilities.append(String(id))
	var pawned: Dictionary = {}
	for id in _pawned:
		pawned[String(id)] = _pawned[id]
	var result := {"version": SNAPSHOT_VERSION, "credits": credits, "upgrades": upgrades, "abilities": abilities, "equipped": String(_equipped_ability), "pawned": pawned, "story_transactions": _story_transactions.snapshot()}
	if not _arm_shield_parts.is_empty():
		result["arm_shield"] = _arm_shield_parts.map(func(id: StringName) -> String: return String(id))
	return result


## 從快照還原；資料損毀、型別不符或引用到已不存在的改裝時略過該部分，保證不崩潰。
func restore(data: Dictionary, notify := true) -> void:
	_story_transactions.restore(data.get("story_transactions"), data.has("story_transactions"))
	credits = int(RunSaveCodec.number(data.get("credits"), 0, 0, MAX_CREDITS))
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
	_restore_pawned(data)
	_restore_arm_shield(data)
	if notify:
		publish_restored()


## 整輪還原先裝齊故事、物品及世界，再通知介面與存檔監聽者。
func publish_restored() -> void:
	credits_changed.emit(credits, 0)
	upgrades_changed.emit()
	abilities_changed.emit()
	pawned_changed.emit()


## 臂盾零件：舊存檔沒有這個欄位時視為沒有；不是清單、重複或引用到不存在的零件時略過那一項。
func _restore_arm_shield(data: Dictionary) -> void:
	_arm_shield_parts.clear()
	var raw: Variant = data.get("arm_shield", [])
	if typeof(raw) != TYPE_ARRAY:
		if data.has("arm_shield"):
			push_warning("[Progression] 存檔的 arm_shield 不是清單，臂盾零件視為沒有")
		return
	for id: Variant in raw:
		var part_id := StringName(str(id))
		if find_arm_shield_part(part_id) != null and not _arm_shield_parts.has(part_id):
			_arm_shield_parts.append(part_id)
		else:
			push_warning("[Progression] 存檔裡的臂盾零件「%s」不存在或重複，已略過" % [id])


## 當票：舊存檔沒有這個欄位時視為沒有；數量不是正整數、引用到不存在的消耗品時略過，總數不超過上限。
func _restore_pawned(data: Dictionary) -> void:
	_pawned.clear()
	var raw: Variant = data.get("pawned", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for id: Variant in raw:
		var count: Variant = raw[id]
		if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(count)) or count <= 0 or ConsumableBag.find(StringName(str(id))) == null:
			continue
		var room := MAX_PAWNED - total_pawned()
		if room <= 0:
			break
		_pawned[StringName(str(id))] = int(RunSaveCodec.number(count, 0, 0, room))


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
