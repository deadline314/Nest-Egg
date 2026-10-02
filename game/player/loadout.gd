class_name Loadout
extends RefCounted
## 玩家武器欄：第 1 欄為主武器（無限彈藥），其餘最多 3 把撿到的武器，各自保留彈藥。
## 滾輪循環切換、數字鍵直選；可序列化成 Dictionary 存到檢查點，重生時還原。

signal changed

const PRIMARY := 0
const MAX_SLOTS := 4

var active_slot := PRIMARY

var _weapons: Array[WeaponData] = []
## -1 代表無限彈藥。
var _ammo: Array[int] = []


func reset(primary: WeaponData) -> void:
	_weapons.clear()
	_ammo.clear()
	if primary != null:
		_weapons.append(primary)
		_ammo.append(-1)
	active_slot = PRIMARY
	changed.emit()


func slot_count() -> int:
	return _weapons.size()


func weapon_in(slot: int) -> WeaponData:
	return _weapons[slot] if slot >= 0 and slot < _weapons.size() else null


func ammo_in(slot: int) -> int:
	return _ammo[slot] if slot >= 0 and slot < _ammo.size() else 0


func active_weapon() -> WeaponData:
	return weapon_in(active_slot)


func find_slot(weapon_id: StringName) -> int:
	for i in _weapons.size():
		if _weapons[i] != null and _weapons[i].id == weapon_id:
			return i
	return -1


## 撿到武器：已有同款則補滿彈藥；有空位就加入；滿了就取代目前手上的非主武器。
## 撿到後自動切換過去。回傳放入的欄位。
func equip(weapon: WeaponData) -> int:
	if weapon == null:
		return -1
	var full_ammo := -1 if weapon.has_infinite_ammo() else weapon.max_ammo
	var slot := find_slot(weapon.id)
	if slot >= 0:
		_ammo[slot] = full_ammo
	elif _weapons.size() < MAX_SLOTS:
		_weapons.append(weapon)
		_ammo.append(full_ammo)
		slot = _weapons.size() - 1
	else:
		slot = active_slot if active_slot != PRIMARY else _weapons.size() - 1
		_weapons[slot] = weapon
		_ammo[slot] = full_ammo
	active_slot = slot
	changed.emit()
	return slot


## 循環切換到下一把（direction = 1）或上一把（-1）有彈藥的武器。
func cycle(direction: int) -> void:
	var count := _weapons.size()
	if count <= 1:
		return
	for step in range(1, count):
		var slot := posmod(active_slot + step * signi(direction), count)
		if _is_usable(slot):
			active_slot = slot
			changed.emit()
			return


func select(slot: int) -> void:
	if slot != active_slot and _is_usable(slot):
		active_slot = slot
		changed.emit()


## 射擊前呼叫。彈藥不足回傳 false；打空後自動切回主武器。
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
	if _ammo[active_slot] <= 0:
		active_slot = PRIMARY
	changed.emit()
	return true


## 依最大彈藥的比例回補目前武器（若為主武器則回補第一把有限彈藥武器）。終結技獎勵。
func refill_ratio(ratio: float) -> void:
	if ratio <= 0.0:
		return
	var target := active_slot
	if _ammo_is_infinite(target):
		target = -1
		for i in _weapons.size():
			if not _ammo_is_infinite(i):
				target = i
				break
	if target < 0:
		return
	var weapon := _weapons[target]
	_ammo[target] = mini(weapon.max_ammo, _ammo[target] + ceili(weapon.max_ammo * ratio))
	changed.emit()


func snapshot() -> Dictionary:
	var paths: Array[String] = []
	for weapon in _weapons:
		paths.append(weapon.resource_path if weapon != null else "")
	return {"weapons": paths, "ammo": _ammo.duplicate(), "active": active_slot}


## 從快照還原；資料不完整或資源遺失時略過該武器並保證主武器存在。
func restore(data: Dictionary, default_primary: WeaponData) -> void:
	reset(default_primary)
	var paths: Variant = data.get("weapons", [])
	var ammo: Variant = data.get("ammo", [])
	if typeof(paths) != TYPE_ARRAY or typeof(ammo) != TYPE_ARRAY:
		return
	_weapons.clear()
	_ammo.clear()
	for i in mini(MAX_SLOTS, (paths as Array).size()):
		var path := str(paths[i])
		var weapon: WeaponData = load(path) as WeaponData if not path.is_empty() and ResourceLoader.exists(path) else null
		if weapon == null:
			continue
		_weapons.append(weapon)
		_ammo.append(int(ammo[i]) if i < (ammo as Array).size() else (-1 if weapon.has_infinite_ammo() else weapon.max_ammo))
	if _weapons.is_empty() or (default_primary != null and _weapons[0] != default_primary and find_slot(default_primary.id) < 0):
		_weapons.insert(0, default_primary)
		_ammo.insert(0, -1)
	var wanted := int(data.get("active", PRIMARY))
	active_slot = wanted if _is_usable(wanted) else PRIMARY
	changed.emit()


func _ammo_is_infinite(slot: int) -> bool:
	return _ammo[slot] < 0


func _is_usable(slot: int) -> bool:
	return slot >= 0 and slot < _weapons.size() and _weapons[slot] != null and _ammo[slot] != 0
