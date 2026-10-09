class_name ItemIcons
extends RefCounted
## 背包用的像素圖示載入（快取在 RigLibrary，同一張只載入一次）。
## 缺檔時記錄具體路徑並改用同尺寸的替代圖，位置不會跑掉。以同名 PNG 覆蓋即可換成正式美術。
##   消耗品與劇情道具：art/items/icons/<icon>.png（32×32）
##   武器：art/items/weapons/<外觀 id>.png（64×24）
##   角色立繪的分層：art/items/portraits/<角色>_<層>.png（96×128，層見 portrait_layers）

const ICON_DIR := "res://art/items/icons"
const ICON_SIZE := Vector2i(32, 32)
## 詳情面板的大圖（384×384 原生繪製，顯示為 96×96 邏輯像素）：<icon>_hd.png；沒有就用卡片圖示放大。
const HD_SUFFIX := "_hd"
## 場景裡的拾取小圖（24×24）：<key>.png，另有 <key>_glow.png 自發光層。
const WORLD_DIR := "res://art/items/world"
const WEAPON_DIR := "res://art/items/weapons"
const WEAPON_SIZE := Vector2i(64, 24)
const PORTRAIT_DIR := "res://art/items/portraits"
const PORTRAIT_SIZE := Vector2i(96, 128)
## 立繪由這幾層疊成（畫布大小相同、位置對齊）：後髮、身體、頭（睜眼）、頭（閉眼，眨眼時取代睜眼）。
const PORTRAIT_LAYERS: Array[StringName] = [&"hair_back", &"body", &"head", &"head_blink"]


static var _world_cache: Dictionary[String, Dictionary] = {}


## 消耗品與劇情道具的圖示（32×32）。
static func item(icon: String) -> Texture2D:
	var file := icon if not icon.is_empty() else "unset"
	return RigLibrary.texture(ICON_DIR.path_join(file + ".png"), ICON_SIZE)


## 詳情面板用的大圖；沒有這張圖（舊的道具）回傳 null，由呼叫端改用卡片圖示放大。不記錄缺檔，因為缺檔是正常情況。
static func item_hd(icon: String) -> Texture2D:
	if icon.is_empty():
		return null
	var path := ICON_DIR.path_join(icon + HD_SUFFIX + ".png")
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 場景裡的拾取小圖：{"base": Texture2D, "glow": Texture2D（可能是 null）}；沒有圖回傳空字典，呼叫端改用程式繪製。
static func world(key: String) -> Dictionary:
	if key.is_empty():
		return {}
	if _world_cache.has(key):
		return _world_cache[key]
	var result: Dictionary = {}
	var base_path := WORLD_DIR.path_join(key + ".png")
	if ResourceLoader.exists(base_path):
		var base := load(base_path) as Texture2D
		if base != null:
			var glow_path := WORLD_DIR.path_join(key + "_glow.png")
			result = {"base": base, "glow": load(glow_path) as Texture2D if ResourceLoader.exists(glow_path) else null}
			result["outline"] = _world_outline(base)
	_world_cache[key] = result
	return result


## One world-pixel contour, built once per cached sprite, never a full-body glow.
static func _world_outline(base: Texture2D) -> Texture2D:
	var image := base.get_image()
	if image == null:
		return null
	if image.is_compressed() and image.decompress() != OK:
		push_warning("[ItemIcons] 無法讀取拾取輪廓：%s" % base.resource_path)
		return null
	var pad := maxi(1, ceili(float(image.get_width()) / 24.0))
	var outline := Image.create(image.get_width() + pad * 2, image.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
	const DIRECTIONS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	for y in outline.get_height():
		for x in outline.get_width():
			var source := Vector2i(x - pad, y - pad)
			if _world_alpha(image, source) > 0.01:
				continue
			var alpha := 0.0
			for direction: Vector2i in DIRECTIONS:
				alpha = maxf(alpha, _world_alpha(image, source + direction * pad))
			if alpha > 0.01:
				outline.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(outline)


static func _world_alpha(image: Image, at: Vector2i) -> float:
	if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
		return 0.0
	return image.get_pixelv(at).a


## 武器圖示（64×24）；visual_id 是 WeaponData.visual_id。
static func weapon(visual_id: String) -> Texture2D:
	var file := visual_id if not visual_id.is_empty() else "unset"
	return RigLibrary.texture(WEAPON_DIR.path_join(file + ".png"), WEAPON_SIZE)


## 某把武器的背包圖示：槍械用外觀圖，近戰武器用剪影（MeleeArt）。
static func for_weapon(weapon: WeaponData) -> Texture2D:
	if weapon != null:
		var key := str(weapon.melee_profile) if weapon.is_melee() else weapon.visual_id
		if ResourceLoader.exists(ICON_DIR.path_join(key + ".png")):
			return item(key)
	if weapon != null and weapon.is_melee():
		return MeleeArt.item_icon(weapon)
	return ItemIcons.weapon(weapon.visual_id if weapon != null else "")


## 武器詳細圖沿用同一個高清載入入口；外觀或近戰招式資料決定素材名稱。
static func for_weapon_hd(weapon: WeaponData) -> Texture2D:
	if weapon == null:
		return null
	return item_hd(str(weapon.melee_profile) if weapon.is_melee() else weapon.visual_id)


## 角色立繪的一層（96×128）。
static func portrait_layer(character: String, layer: StringName) -> Texture2D:
	return RigLibrary.texture(PORTRAIT_DIR.path_join("%s_%s.png" % [character, layer]), PORTRAIT_SIZE)
