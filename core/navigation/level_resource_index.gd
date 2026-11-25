extends RefCounted
## 索引只保存關卡路徑。存讀檔與 HUD 依需求載入資源，避免反覆讀取其他章節的素材。

const DIRECTORY := "res://data/levels"
const MANIFEST := "res://data/navigation/level_index.json"
const FORMAT := 2

static var _indexed := false
static var _files: PackedStringArray
static var _areas: Dictionary[StringName, String] = {}
static var _chapters: Dictionary[StringName, PackedStringArray] = {}
static var _layouts: Dictionary[String, Dictionary] = {}


static func saved_paths(areas: Dictionary, checkpoint: String) -> PackedStringArray:
	var result := PackedStringArray()
	if areas.is_empty() and checkpoint.is_empty():
		return result
	_refresh()
	for id: StringName in _areas:
		var path := _areas[id]
		if areas.has(String(id)) or path == checkpoint:
			result.append(path)
	return result


static func chapter_paths(chapter: StringName) -> PackedStringArray:
	_refresh()
	return _chapters.get(chapter, PackedStringArray())


## Lightweight authored inputs for save migration and exploration snapshots.
static func layout_fields(path: String) -> Dictionary:
	_refresh()
	return _layouts.get(path, {})


static func load_level(path: String) -> LevelData:
	var data := RunSaveCodec.resource(path, "level", DIRECTORY + "/") as LevelData
	if data == null:
		push_error("[LevelCatalog] 無法讀取關卡：%s" % path)
	return data


static func authored_manifest() -> Dictionary:
	var levels: Array[Dictionary] = []
	for resource in ResourceCatalog.load_dir(DIRECTORY, LevelData, "LevelCatalog"):
		var data := resource as LevelData
		# Match the numeric type used by Godot's JSON parser.
		levels.append({"id": String(data.id), "chapter": String(data.chapter),
				"file": data.resource_path.get_file(), "sha256": FileAccess.get_sha256(data.resource_path),
				"layout_path": data.layout_path, "tile_size": float(data.tile_size), "height": float(data.height)})
	return {"version": FORMAT, "levels": levels}


static func _refresh() -> void:
	var files := ResourceLoader.list_directory(DIRECTORY)
	files.sort()
	if _indexed and files == _files:
		return
	_files = files
	_areas.clear()
	_chapters.clear()
	_layouts.clear()
	var manifest := _read_manifest(files)
	if manifest.is_empty():
		push_warning("[LevelCatalog] %s 已過期或無法讀取，直接驗證關卡資料。" % MANIFEST)
		manifest = authored_manifest()
	for entry: Dictionary in manifest["levels"]:
		var path := DIRECTORY.path_join(entry["file"])
		_areas[StringName(entry["id"])] = path
		_layouts[path] = entry
		var chapter := StringName(entry["chapter"])
		var paths: PackedStringArray = _chapters.get(chapter, PackedStringArray())
		paths.append(path)
		_chapters[chapter] = paths
	_indexed = true


static func _read_manifest(files: PackedStringArray) -> Dictionary:
	var manifest := load(MANIFEST) as JSON if ResourceLoader.exists(MANIFEST) else null
	if manifest == null or not manifest.data is Dictionary:
		return {}
	var raw: Dictionary = manifest.data
	if raw.get("version") != FORMAT or not raw.get("levels") is Array:
		return {}
	var authored_files: Dictionary[String, bool] = {}
	for file in files:
		if file.ends_with(".tres"):
			authored_files[file] = true
	var ids: Dictionary[String, bool] = {}
	var levels: Array[Dictionary] = []
	var editor := OS.has_feature("editor")
	for item: Variant in raw["levels"]:
		if not item is Dictionary or not item.get("file") is String or not item.get("id") is String or not item.get("chapter") is String:
			return {}
		if not item.get("layout_path") is String or not RunSaveCodec.valid_version(item.get("tile_size")) \
				or not RunSaveCodec.valid_version(item.get("height")):
			return {}
		var file: String = item["file"]
		var id: String = item["id"]
		if id.is_empty() or item["chapter"].is_empty() or ids.has(id):
			return {}
		ids[id] = true
		if not authored_files.erase(file):
			if editor or files.has(file):
				return {}
			continue  # An exported edition may omit unshipped areas.
		if editor and FileAccess.get_sha256(DIRECTORY.path_join(file)) != item.get("sha256", ""):
			return {}
		levels.append(item)
	return {"levels": levels} if authored_files.is_empty() else {}
