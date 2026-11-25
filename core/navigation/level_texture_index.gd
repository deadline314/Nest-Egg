extends RefCounted
## Data-only input for neighbor texture discovery. Gameplay resources still load on entry.

const LevelIndex := preload("res://core/navigation/level_resource_index.gd")
const PATH := "res://data/navigation/level_texture_index.json"
const VERSION := 1

static var _loaded := false
static var _levels: Dictionary = {}


static func prepare() -> void:
	if _loaded:
		return
	_loaded = true
	var manifest := load(PATH) as JSON if ResourceLoader.exists(PATH) else null
	if manifest == null or not manifest.data is Dictionary or manifest.data.get("version") != VERSION \
			or not manifest.data.get("levels") is Dictionary:
		push_warning("[LevelTextureIndex] %s 無法讀取，沿用鄰區資源查詢。" % PATH)
		return
	_levels = manifest.data["levels"]


## Null selects the original discovery path. An empty dictionary is a valid record.
static func candidates(level_path: String) -> Variant:
	var entry: Variant = _levels.get(level_path)
	if not entry is Dictionary or not entry.get("paths") is Dictionary \
			or not ResourceLoader.exists(level_path):
		return null
	if OS.has_feature("editor"):
		var layout: Variant = entry.get("layout")
		if not layout is String or LevelIndex.source_digest(level_path) != entry.get("level_sha256") \
				or _layout_sha256(layout) != entry.get("layout_sha256"):
			return null
	var paths: Dictionary = entry["paths"]
	for path: Variant in paths:
		if not path is String or not path.begins_with("res://") or not paths[path] is bool:
			push_warning("[LevelTextureIndex] %s 的貼圖清單無效，沿用鄰區資源查詢。" % level_path)
			return null
	return paths


static func authored_entry(data: LevelData, paths: Dictionary[String, bool]) -> Dictionary:
	return {"layout": data.layout_path, "level_sha256": LevelIndex.source_digest(data.resource_path),
		"layout_sha256": _layout_sha256(data.layout_path), "paths": paths}


static func _layout_sha256(path: String) -> String:
	return "" if path.is_empty() else LevelIndex.source_digest(path)
