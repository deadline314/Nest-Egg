class_name AmmoIcons
extends RefCounted
## 彈種圖示：武器資料指定圖示 id（WeaponData.ammo_icon），圖片在 art/ammo/<id>.png（滿）、
## <id>_empty.png（空槽）、<id>_low.png（彈量低）。每張 40×56（4 倍解析度），HUD 以 10×14 顯示。
## 缺圖時回傳洋紅色替代圖並記錄具體路徑（RigLibrary 負責），不會讓介面崩潰。

enum State { FULL, EMPTY, LOW }

const DIR := "res://art/ammo"
const TEXTURE_SIZE := Vector2i(40, 56)
## 顯示大小（邏輯像素）。
const CELL := Vector2(10, 14)
## 武器沒有指定圖示時的預設：能量武器用電池，其餘用手槍彈。
const DEFAULT_ACTION := &"pistol"
const DEFAULT_ENERGY := &"energy"


static func icon_id_for(weapon: WeaponData) -> StringName:
	if weapon == null:
		return DEFAULT_ACTION
	if weapon.ammo_icon != &"":
		return weapon.ammo_icon
	return DEFAULT_ENERGY if weapon.is_energy else DEFAULT_ACTION


static func path_of(icon_id: StringName, state: State) -> String:
	match state:
		State.EMPTY:
			return "%s/%s_empty.png" % [DIR, icon_id]
		State.LOW:
			return "%s/%s_low.png" % [DIR, icon_id]
	return "%s/%s.png" % [DIR, icon_id]


static func texture(icon_id: StringName, state: State = State.FULL) -> Texture2D:
	return RigLibrary.texture(path_of(icon_id, state), TEXTURE_SIZE)


static func has_icon(icon_id: StringName) -> bool:
	return ResourceLoader.exists(path_of(icon_id, State.FULL))


static func for_weapon(weapon: WeaponData, state: State = State.FULL) -> Texture2D:
	return texture(icon_id_for(weapon), state)
