class_name MeleeData
extends RefCounted
## 近戰資料入口。預設那組（data/feel/melee.json）給沒拿近戰武器時的近戰鍵用；
## 近戰武器各有一組（data/melee/<id>.json），用 set_of(weapon) 取得。實際的招式邏輯見 MeleeSet。

const PATH := "res://data/feel/melee.json"
const PROFILE_DIR := "res://data/melee"
## 預設近戰軌跡的限制（近戰武器的上限較寬，見 MeleeSet）：持續秒數範圍、峰值亮度上限（HDR 泛光下不過曝）、同時最多幾條。
const TRAIL_LIFE_RANGE := Vector2(0.08, 0.12)
const TRAIL_BRIGHTNESS_MAX := MeleeSet.TRAIL_BRIGHTNESS_MAX
const MAX_TRAILS := 2
const DEFAULT_ATTACK := MeleeSet.DEFAULT_ATTACK

static var _default := MeleeSet.new(PATH)
static var _profiles: Dictionary = {}


static func default_set() -> MeleeSet:
	return _default


## 近戰武器的招式組（依 WeaponData.melee_profile 載入並快取）；不是近戰武器或沒指定時回傳預設組。
static func set_of(weapon: WeaponData) -> MeleeSet:
	if weapon == null or not weapon.is_melee():
		return _default
	return profile(weapon.melee_profile)


static func profile(id: String) -> MeleeSet:
	if not _profiles.has(id):
		_profiles[id] = MeleeSet.new("%s/%s.json" % [PROFILE_DIR, id])
	return _profiles[id]


static func reload() -> void:
	_default.reload()
	_profiles.clear()


static func combo() -> Array:
	return _default.combo()


static func combo_window() -> float:
	return _default.combo_window()


static func buffer_time() -> float:
	return InputFeel.window("melee_buffer", 0.2)


static func live_attack(id: String) -> Dictionary:
	return _default.live_attack(id)


static func attack(id: String) -> Dictionary:
	return _default.attack(id)


## 預設組的資料檢查，並額外要求軌跡秒數落在預設近戰的 80~120 毫秒。
static func validate() -> PackedStringArray:
	var errors := _default.validate()
	for id: Variant in _default.combo():
		var life := float((_default.attack(str(id))["trail"] as Dictionary).get("life", 0.0))
		if life < TRAIL_LIFE_RANGE.x - 0.0001 or life > TRAIL_LIFE_RANGE.y + 0.0001:
			errors.append("%s 的招式「%s」的 trail.life 要在 %s 秒之間" % [PATH, id, TRAIL_LIFE_RANGE])
	return errors
