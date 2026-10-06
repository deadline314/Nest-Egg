class_name WeaponIcons
extends RefCounted
## 武器欄用的「槍的圖示」：就是那把槍在角色手上的外觀（art/weapons/weapons.json 的 visual_id 指到的圖）。
## 沒有外觀的武器（近戰武器、缺圖）回傳 null，由呼叫端改用彈種圖示，不會讓介面崩潰。

## 圖示畫在這個大小的框裡（邏輯像素），依圖的長寬比等比縮放、置中。
const BOX := Vector2(30, 14)


## 這把武器的槍圖示；沒有外觀回傳 null。
static func texture(weapon: WeaponData) -> Texture2D:
	if weapon == null or weapon.visual_id.is_empty():
		return null
	var def := RigLibrary.weapon(weapon.visual_id)
	var file := str(def.get("file", ""))
	if file.is_empty():
		return null
	return RigLibrary.optional_texture(RigLibrary.WEAPONS_PATH.get_base_dir().path_join(file))


## 圖示放進 BOX 之後的矩形（相對於框的左上角），等比縮放並置中。
static func fit(tex: Texture2D) -> Rect2:
	var size := tex.get_size()
	var scale := minf(BOX.x / maxf(1.0, size.x), BOX.y / maxf(1.0, size.y))
	var fitted := size * scale
	return Rect2((BOX - fitted) * 0.5, fitted)
