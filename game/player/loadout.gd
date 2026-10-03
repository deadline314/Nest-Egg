class_name Loadout
extends RefCounted
## 玩家武器欄：第 1 欄為主武器（備彈無限），其餘最多 3 把撿到的武器。
## 每把武器各自保留「彈匣」與「備彈」；彈匣打空要換彈，彈匣與備彈都打光的武器會自動切回主武器。
## 滾輪循環切換、數字鍵直選；可序列化成 Dictionary 存到檢查點，重生時還原。

signal changed
signal reload_started
signal reload_finished

const PRIMARY := 0
const MAX_SLOTS := 4
## 快照格式版本（舊版只有總彈量 "ammo"）。
const SNAPSHOT_VERSION := 2

var active_slot := PRIMARY

## 改裝後的實際武器（讀數值用）；沒有改裝時與 _bases 是同一個物件。
var _weapons: Array[WeaponData] = []
## 原始武器資料（存檔、比對 id 用）。
var _bases: Array[WeaponData] = []
var _mag: Array[int] = []
## -1 代表無限備彈。
var _reserve: Array[int] = []
var _reload_left := 0.0
var _reload_total := 0.0


func reset(primary: WeaponData) -> void:
	_weapons.clear()
	_bases.clear()
	_mag.clear()
	_reserve.clear()
	_cancel_reload()
	if primary != null:
		_append(primary)
	active_slot = PRIMARY
	changed.emit()


func slot_count() -> int:
	return _weapons.size()


func weapon_in(slot: int) -> WeaponData:
	return _weapons[slot] if slot >= 0 and slot < _weapons.size() else null


func mag_in(slot: int) -> int:
	return _mag[slot] if slot >= 0 and slot < _mag.size() else 0


## -1 代表無限。
func reserve_in(slot: int) -> int:
	return _reserve[slot] if slot >= 0 and slot < _reserve.size() else 0


func active_weapon() -> WeaponData:
	return weapon_in(active_slot)


func find_slot(weapon_id: StringName) -> int:
	for i in _weapons.size():
		if _weapons[i] != null and _weapons[i].id == weapon_id:
			return i
	return -1


## 撿到武器：已有同款則補滿備彈；有空位就加入；滿了就取代目前手上的非主武器。
## 撿到後自動切換過去。回傳放入的欄位。
func equip(weapon: WeaponData) -> int:
	if weapon == null:
		return -1
	var slot := find_slot(weapon.id)
	if slot >= 0:
		_reserve[slot] = weapon.max_reserve
		if not weapon.has_magazine():
			_mag[slot] = 0
	elif _weapons.size() < MAX_SLOTS:
		_append(weapon)
		slot = _weapons.size() - 1
	else:
		slot = active_slot if active_slot != PRIMARY else _weapons.size() - 1
		_bases[slot] = weapon
		_weapons[slot] = _effective(weapon)
		_mag[slot] = _weapons[slot].magazine_size
		_reserve[slot] = weapon.max_reserve
	_cancel_reload()
	active_slot = slot
	changed.emit()
	return slot


## 循環切換到下一把（direction = 1）或上一把（-1）還有彈藥的武器。換武器會中斷換彈。
func cycle(direction: int) -> void:
	var count := _weapons.size()
	if count <= 1:
		return
	for step in range(1, count):
		var slot := posmod(active_slot + step * signi(direction), count)
		if _is_usable(slot):
			_switch_to(slot)
			return


func select(slot: int) -> void:
	if can_select(slot):
		_switch_to(slot)


## 這一欄可以換成手上武器嗎（有武器、有彈藥、而且不是目前這一把）。
func can_select(slot: int) -> bool:
	return slot != active_slot and _is_usable(slot)


## 改裝變動後重新計算每把武器的實際數值。彈匣變大時，多出來的子彈直接補進彈匣。
func retune() -> void:
	for i in _weapons.size():
		var before := _weapons[i]
		var after := _effective(_bases[i])
		if after.magazine_size > before.magazine_size:
			_mag[i] += after.magazine_size - before.magazine_size
		_weapons[i] = after
		if after.has_magazine():
			_mag[i] = mini(_mag[i], after.magazine_size)
	changed.emit()


# ---------------------------------------------------------------------------
# 射擊與換彈
# ---------------------------------------------------------------------------

## 射擊前呼叫。換彈中或彈匣不足回傳 false；彈匣空了會自動開始換彈。
func consume_ammo() -> bool:
	var weapon := active_weapon()
	if weapon == null or is_reloading():
		return false
	if not weapon.has_magazine():
		return true
	var cost := maxi(1, weapon.ammo_per_shot)
	if _mag[active_slot] < cost:
		if not start_reload() and _reserve[active_slot] == 0:
			select(PRIMARY)
		return false
	_mag[active_slot] -= cost
	if _mag[active_slot] < cost:
		if _reserve[active_slot] == 0:
			# 彈匣與備彈都打光：切回主武器。
			if active_slot != PRIMARY:
				active_slot = PRIMARY
		else:
			_begin_reload(weapon)
	changed.emit()
	return true


## 手動換彈。沒有彈匣、彈匣已滿、沒有備彈或正在換彈時回傳 false。
func start_reload() -> bool:
	var weapon := active_weapon()
	if weapon == null or not weapon.has_magazine() or is_reloading():
		return false
	if _mag[active_slot] >= weapon.magazine_size or _reserve[active_slot] == 0:
		return false
	_begin_reload(weapon)
	changed.emit()
	return true


## 每個物理影格呼叫，推進換彈計時。換彈完成回傳 true。
func tick(delta: float) -> bool:
	if not is_reloading():
		return false
	_reload_left -= delta
	if _reload_left > 0.0:
		return false
	_finish_reload()
	return true


func is_reloading() -> bool:
	return _reload_total > 0.0


## 換彈進度 0~1（沒在換彈時為 0）。
func reload_progress() -> float:
	return clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0) if is_reloading() else 0.0


## 依備彈上限的比例回補備彈（目前武器備彈無限時，回補第一把有限備彈的武器）。終結技獎勵。
func refill_ratio(ratio: float) -> void:
	if ratio <= 0.0:
		return
	var target := active_slot
	if _reserve_is_infinite(target):
		target = -1
		for i in _weapons.size():
			if not _reserve_is_infinite(i):
				target = i
				break
	if target < 0:
		return
	var weapon := _weapons[target]
	_reserve[target] = mini(weapon.max_reserve, _reserve[target] + ceili(weapon.max_reserve * ratio))
	changed.emit()


## 全部武器的彈匣與備彈補滿（電話亭整備）。換彈中就取消這次換彈（彈匣已經是滿的）。
func refill_all() -> void:
	for i in _weapons.size():
		var weapon := _weapons[i]
		if weapon.has_magazine():
			_mag[i] = weapon.magazine_size
		if not _reserve_is_infinite(i):
			_reserve[i] = weapon.max_reserve
	_cancel_reload()
	changed.emit()


# ---------------------------------------------------------------------------
# 存檔
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var paths: Array[String] = []
	for weapon in _bases:
		paths.append(weapon.resource_path if weapon != null else "")
	return {"version": SNAPSHOT_VERSION, "weapons": paths, "mag": _mag.duplicate(), "reserve": _reserve.duplicate(), "active": active_slot}


## 從快照還原；資料不完整或資源遺失時略過該武器並保證主武器存在。
## 相容舊版快照（只有總彈量）：總彈量先填彈匣，剩下的當備彈。
func restore(data: Dictionary, default_primary: WeaponData) -> void:
	reset(default_primary)
	var paths: Variant = data.get("weapons", [])
	if typeof(paths) != TYPE_ARRAY:
		return
	var mags: Array = _int_array(data.get("mag", []))
	var reserves: Array = _int_array(data.get("reserve", []))
	var legacy: Array = _int_array(data.get("ammo", [])) if not data.has("mag") else []
	_weapons.clear()
	_bases.clear()
	_mag.clear()
	_reserve.clear()
	for i in mini(MAX_SLOTS, (paths as Array).size()):
		var path := str(paths[i])
		var weapon: WeaponData = load(path) as WeaponData if not path.is_empty() and ResourceLoader.exists(path) else null
		if weapon == null:
			continue
		_append(weapon)
		var slot := _weapons.size() - 1
		if i < legacy.size():
			_apply_legacy_ammo(slot, int(legacy[i]))
		else:
			if i < mags.size():
				_mag[slot] = clampi(int(mags[i]), 0, weapon.magazine_size)
			if i < reserves.size():
				_reserve[slot] = -1 if weapon.has_infinite_reserve() else clampi(int(reserves[i]), 0, weapon.max_reserve)
	if _weapons.is_empty() or (default_primary != null and _bases[0] != default_primary and find_slot(default_primary.id) < 0):
		var primary := _effective(default_primary)
		_bases.insert(0, default_primary)
		_weapons.insert(0, primary)
		_mag.insert(0, primary.magazine_size)
		_reserve.insert(0, default_primary.max_reserve)
	var wanted := int(data.get("active", PRIMARY))
	active_slot = wanted if _is_usable(wanted) else PRIMARY
	changed.emit()


# ---------------------------------------------------------------------------

func _append(weapon: WeaponData) -> void:
	var effective := _effective(weapon)
	_bases.append(weapon)
	_weapons.append(effective)
	_mag.append(effective.magazine_size)
	_reserve.append(weapon.max_reserve)


static func _effective(base: WeaponData) -> WeaponData:
	return Progression.tuned(base)


func _switch_to(slot: int) -> void:
	_cancel_reload()
	active_slot = slot
	changed.emit()


func _begin_reload(weapon: WeaponData) -> void:
	_reload_total = maxf(0.01, weapon.reload_time)
	_reload_left = _reload_total
	reload_started.emit()


func _finish_reload() -> void:
	var weapon := active_weapon()
	_cancel_reload()
	if weapon == null or not weapon.has_magazine():
		return
	var need := weapon.magazine_size - _mag[active_slot]
	var take := need if _reserve[active_slot] < 0 else mini(need, _reserve[active_slot])
	_mag[active_slot] += take
	if _reserve[active_slot] >= 0:
		_reserve[active_slot] -= take
	reload_finished.emit()
	changed.emit()


func _cancel_reload() -> void:
	_reload_left = 0.0
	_reload_total = 0.0


func _apply_legacy_ammo(slot: int, total: int) -> void:
	var weapon := _weapons[slot]
	if total < 0 or weapon.has_infinite_reserve():
		return
	_mag[slot] = mini(total, weapon.magazine_size)
	_reserve[slot] = clampi(total - _mag[slot], 0, weapon.max_reserve)


func _reserve_is_infinite(slot: int) -> bool:
	return _reserve[slot] < 0


func _is_usable(slot: int) -> bool:
	if slot < 0 or slot >= _weapons.size() or _weapons[slot] == null:
		return false
	return not _weapons[slot].has_magazine() or _mag[slot] > 0 or _reserve[slot] != 0


static func _int_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
