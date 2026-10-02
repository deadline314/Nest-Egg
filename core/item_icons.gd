class_name ItemIcons
extends RefCounted
## 背包用的像素圖示載入（快取在 RigLibrary，同一張只載入一次）。
## 缺檔時記錄具體路徑並改用同尺寸的替代圖，位置不會跑掉。以同名 PNG 覆蓋即可換成正式美術。
##   消耗品與劇情道具：art/items/icons/<icon>.png（32×32）
##   武器：art/items/weapons/<外觀 id>.png（64×24）
##   角色立繪的分層：art/items/portraits/<角色>_<層>.png（96×128，層見 portrait_layers）

const ICON_DIR := "res://art/items/icons"
const ICON_SIZE := Vector2i(32, 32)
const WEAPON_DIR := "res://art/items/weapons"
const WEAPON_SIZE := Vector2i(64, 24)
const PORTRAIT_DIR := "res://art/items/portraits"
const PORTRAIT_SIZE := Vector2i(96, 128)
## 立繪由這幾層疊成（畫布大小相同、位置對齊）：後髮、身體、頭（睜眼）、頭（閉眼，眨眼時取代睜眼）。
const PORTRAIT_LAYERS: Array[StringName] = [&"hair_back", &"body", &"head", &"head_blink"]


## 消耗品與劇情道具的圖示（32×32）。
static func item(icon: String) -> Texture2D:
	var file := icon if not icon.is_empty() else "unset"
	return RigLibrary.texture(ICON_DIR.path_join(file + ".png"), ICON_SIZE)


## 武器圖示（64×24）；visual_id 是 WeaponData.visual_id。
static func weapon(visual_id: String) -> Texture2D:
	var file := visual_id if not visual_id.is_empty() else "unset"
	return RigLibrary.texture(WEAPON_DIR.path_join(file + ".png"), WEAPON_SIZE)


## 角色立繪的一層（96×128）。
static func portrait_layer(character: String, layer: StringName) -> Texture2D:
	return RigLibrary.texture(PORTRAIT_DIR.path_join("%s_%s.png" % [character, layer]), PORTRAIT_SIZE)
