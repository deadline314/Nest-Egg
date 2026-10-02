class_name LitTextures
extends RefCounted
## 受光貼圖：把「<名稱>.png」與同目錄的「<名稱>_n.png」（法線貼圖）組成 CanvasTexture，
## 讓 2D 光源與方向光依法線產生立體的受光（邊緣亮在光來的方向）。
## 缺法線貼圖時照常使用平面貼圖，只記錄一次提示。法線貼圖由 tools/art/paint_normals.tscn 自動產生，
## 也可以用手繪的同名檔案取代。光影品質「低」會整個關閉法線貼圖（見 LightQuality.normal_maps）。

static var _cache: Dictionary[String, Texture2D] = {}
## 路徑 -> 它的 CanvasTexture 與法線貼圖，用來在品質改變時切換。
static var _canvas_textures: Dictionary[String, CanvasTexture] = {}
static var _normals: Dictionary[String, Texture2D] = {}
static var _reported: Dictionary[String, bool] = {}
static var _enabled := true


## 載入受光貼圖。diffuse 缺失時回傳 RigLibrary 的替代圖（沒有法線）。
static func load_texture(path: String, fallback_size := Vector2i(16, 16)) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var diffuse := RigLibrary.texture(path, fallback_size)
	var normal_path := path.get_basename() + "_n." + path.get_extension()
	var result: Texture2D = diffuse
	if ResourceLoader.exists(path):
		var normal: Texture2D = load(normal_path) as Texture2D if ResourceLoader.exists(normal_path) else null
		if normal != null:
			var canvas := CanvasTexture.new()
			canvas.diffuse_texture = diffuse
			canvas.normal_texture = normal if _enabled else null
			_canvas_textures[path] = canvas
			_normals[path] = normal
			result = canvas
		elif not _reported.has(path):
			_reported[path] = true
			push_warning("[LitTextures] 沒有法線貼圖，改用平面貼圖：%s（可用 tools/art/paint_normals.tscn 產生）" % normal_path)
	_cache[path] = result
	return result


## 開關所有已載入貼圖的法線貼圖（光影品質改變時呼叫）。
static func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	for path in _canvas_textures:
		_canvas_textures[path].normal_texture = _normals[path] if enabled else null


static func is_enabled() -> bool:
	return _enabled


## 目前有法線貼圖的貼圖數量（測試用）。
static func normal_count() -> int:
	return _canvas_textures.size()


## 清除快取（替換美術後在編輯器內重新載入用）。
static func clear_cache() -> void:
	_cache.clear()
	_canvas_textures.clear()
	_normals.clear()
	_reported.clear()
