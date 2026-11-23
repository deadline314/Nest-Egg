extends RefCounted
## 索引只保存關卡路徑。存讀檔與 HUD 依需求載入資源，避免反覆讀取其他章節的素材。

const DIRECTORY := "res://data/levels"

static var _indexed := false
static var _files: PackedStringArray
static var _areas: Dictionary[StringName, String] = {}
static var _chapters: Dictionary[StringName, PackedStringArray] = {}


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


static func load_level(path: String) -> LevelData:
	var data := RunSaveCodec.resource(path, "level", DIRECTORY + "/") as LevelData
	if data == null:
		push_error("[LevelCatalog] 無法讀取關卡：%s" % path)
	return data


static func _refresh() -> void:
	var files := ResourceLoader.list_directory(DIRECTORY)
	files.sort()
	if _indexed and files == _files:
		return
	_areas.clear()
	_chapters.clear()
	for resource in ResourceCatalog.load_dir(DIRECTORY, LevelData, "LevelCatalog"):
		var data := resource as LevelData
		_areas[data.id] = data.resource_path
		var paths: PackedStringArray = _chapters.get(data.chapter, PackedStringArray())
		paths.append(data.resource_path)
		_chapters[data.chapter] = paths
	_files = files
	_indexed = true
