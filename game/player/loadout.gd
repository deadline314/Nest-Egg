class_name Loadout
extends RefCounted
## 玩家武器配置：主武器（無限彈藥）＋ 一把特殊武器（有限彈藥）。
## 可序列化成 Dictionary 存到檢查點，重生時還原。

signal changed

const PRIMARY := 0
const SPECIAL := 1
const SLOT_COUNT := 2

var active_slot := PRIMARY

var _weapons: Array[WeaponData] = [null, null]
## -1 代表無限彈藥。
var _ammo: Array[int] = [0, 0]


func reset(primary: WeaponData) -> void:
	_weapons[PRIMARY] = primary
	_weapons[SPECIAL] = null
	_ammo[PRIMARY] = -1
	_ammo[SPECIAL] = 0
	active_slot = PRIMARY
	changed.emit()


func weapon_in(slot: int) -> WeaponData:
	return _weapons[slot] if slot >= 0 and slot < SLOT_COUNT else null


func ammo_in(slot: int) -> int:
	return _ammo[slot] if slot >= 0 and slot < SLOT_COUNT else 0


func active_weapon() -> WeaponData:
	return _weapons[active_slot]


## 撿到特殊武器：取代特殊欄位並補滿彈藥，自動切換過去。
func equip_special(weapon: WeaponData) -> void:
	if weapon == null:
		return
	_weapons[SPECIAL] = weapon
	_ammo[SPECIAL] = -1 if weapon.has_infinite_ammo() else weapon.max_ammo
	active_slot = SPECIAL
	changed.emit()


func swap() -> void:
	var other := SPECIAL if active_slot == PRIMARY else PRIMARY
	if _is_usable(other):
		active_slot = other
		changed.emit()


func select(slot: int) -> void:
	if slot != active_slot and _is_usable(slot):
		active_slot = slot
		changed.emit()


## 射擊前呼叫。彈藥不足回傳 false；特殊武器打空後自動切回主武器。
func consume_ammo() -> bool:
	var weapon := active_weapon()
	if weapon == null:
		return false
	if _ammo[active_slot] < 0:
		return true
	if _ammo[active_slot] < weapon.ammo_per_shot:
		select(PRIMARY)
		return false
	_ammo[active_slot] -= weapon.ammo_per_shot
	if _ammo[active_slot] <= 0 and active_slot == SPECIAL:
		active_slot = PRIMARY
	changed.emit()
	return true


## 依最大彈藥的比例回補特殊武器（終結技獎勵）。
func refill_special(ratio: float) -> void:
	var weapon := _weapons[SPECIAL]
	if weapon == null or weapon.has_infinite_ammo() or ratio <= 0.0:
		return
	_ammo[SPECIAL] = mini(weapon.max_ammo, _ammo[SPECIAL] + ceili(weapon.max_ammo * ratio))
	changed.emit()


func snapshot() -> Dictionary:
	var paths: Array[String] = []
	for weapon in _weapons:
		paths.append(weapon.resource_path if weapon != null else "")
	return {"weapons": paths, "ammo": _ammo.duplicate(), "active": active_slot}


## 從快照還原；資料不完整或資源遺失時退回預設主武器，保證一定可用。
func restore(data: Dictionary, default_primary: WeaponData) -> void:
	reset(default_primary)
	var paths: Variant = data.get("weapons", [])
	var ammo: Variant = data.get("ammo", [])
	if typeof(paths) != TYPE_ARRAY or typeof(ammo) != TYPE_ARRAY:
		return
	for slot in mini(SLOT_COUNT, (paths as Array).size()):
		var path := str(paths[slot])
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var weapon := load(path) as WeaponData
		if weapon == null:
			continue
		_weapons[slot] = weapon
		if slot < (ammo as Array).size():
			_ammo[slot] = int(ammo[slot])
	if _weapons[PRIMARY] == null:
		_weapons[PRIMARY] = default_primary
		_ammo[PRIMARY] = -1
	var wanted := int(data.get("active", PRIMARY))
	active_slot = wanted if _is_usable(wanted) else PRIMARY
	changed.emit()


func _is_usable(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT or _weapons[slot] == null:
		return false
	return _ammo[slot] != 0
