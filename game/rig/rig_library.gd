class_name RigLibrary
extends RefCounted
## 骨架與外觀定義的載入與快取（全域共用，同一張貼圖只載入一次，節省記憶體）。
## 任何檔案缺失或格式錯誤都會記錄具體位置並回傳安全的替代值，遊戲不會崩潰。

const CHARACTER_PATH := "res://art/characters/%s/character.json"
const WEAPONS_PATH := "res://art/weapons/weapons.json"

static var _json_cache: Dictionary[String, Dictionary] = {}
static var _texture_cache: Dictionary[String, Texture2D] = {}
static var _reported: Dictionary[String, bool] = {}


## 讀取 JSON（以資源方式載入，匯出後也可用）。失敗回傳空字典。
static func load_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	var result: Dictionary = {}
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		_report(path, "[RigLibrary] 無法讀取定義檔：%s" % path)
	else:
		result = json.data
	_json_cache[path] = result
	return result


static func character(id: String) -> Dictionary:
	return load_json(CHARACTER_PATH % id)


static func character_dir(id: String) -> String:
	return (CHARACTER_PATH % id).get_base_dir()


## 外觀是否用自己的骨架（重畫過的角色）；共用的 Q 版骨架（humanoid.json）回傳 false。
static func has_own_rig(id: String) -> bool:
	return str(character(id).get("rig", "")).get_file() != "humanoid.json"


## 站立時從腳底到頭頂的高度（世界像素，含整體縮放）：骨頭靜止位置加上頭部貼圖畫到支點上方的部分。
static func standing_height(id: String) -> float:
	var skin := character(id)
	var rig := load_json(str(skin.get("rig", "")))
	var head: Dictionary = (skin.get("textures", {}) as Dictionary).get("head", {})
	if skin.is_empty() or rig.is_empty() or head.is_empty():
		return 0.0
	var parents: Dictionary = {}
	var rests: Dictionary = {}
	for bone: Dictionary in rig.get("bones", []):
		parents[bone.get("name")] = bone.get("parent", "")
		rests[bone.get("name")] = vec2(bone.get("pos"))
	var y := 0.0
	var name: Variant = "head"
	while str(name) != "":
		y += (rests.get(name, Vector2.ZERO) as Vector2).y
		name = parents.get(name, "")
	var pivot_y := vec2(head.get("pivot")).y
	return (-y + pivot_y * float(skin.get("texture_scale", 0.25))) * float(skin.get("scale", 1.0))


static func weapons() -> Dictionary:
	return load_json(WEAPONS_PATH)


static func weapon(id: String) -> Dictionary:
	var all: Variant = weapons().get("weapons", {})
	if typeof(all) == TYPE_DICTIONARY and (all as Dictionary).has(id):
		return all[id]
	if not id.is_empty():
		_report("weapon:" + id, "[RigLibrary] weapons.json 沒有武器外觀：%s" % id)
	return {}


## 載入貼圖；缺失時回傳醒目的洋紅色替代圖（尺寸與規格一致，位置不會跑掉）。
static func texture(path: String, fallback_size := Vector2i(16, 16)) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex == null:
		_report(path, "[RigLibrary] 找不到零件圖片，改用替代圖：%s" % path)
		tex = _placeholder(fallback_size)
	_texture_cache[path] = tex
	return tex


## 選用貼圖（例如發光層）：不存在時回傳 null，不視為錯誤。
static func optional_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex != null:
		_texture_cache[path] = tex
	return tex


static func vec2(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


## 清除快取（替換美術後在編輯器內重新載入用）。
static func clear_cache() -> void:
	_json_cache.clear()
	_texture_cache.clear()
	_reported.clear()


static func _placeholder(size: Vector2i) -> Texture2D:
	var w := maxi(2, size.x)
	var h := maxi(2, size.y)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var checker := ((x / 4) + (y / 4)) % 2 == 0
			image.set_pixel(x, y, Color(1, 0, 1, 0.9) if checker else Color(0.2, 0, 0.2, 0.9))
	return ImageTexture.create_from_image(image)


static func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(message)
