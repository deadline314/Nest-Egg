class_name PropLibrary
extends RefCounted
## 道具資料庫：把資料夾裡的 PropData 讀成 id -> 資料，依資料夾快取（同一個資料夾只掃描一次）。

const DEFAULT_DIR := "res://data/environment/props"

static var _cache: Dictionary[String, Dictionary] = {}


## 取得 id 對應的道具資料；找不到時回傳 null 並記錄。
static func find(id: StringName, dir := DEFAULT_DIR) -> PropData:
	var table := _table(dir)
	if not table.has(id):
		push_warning("[PropLibrary] 找不到道具「%s」（%s）" % [id, dir])
		return null
	return table[id]


static func has(id: StringName, dir := DEFAULT_DIR) -> bool:
	return _table(dir).has(id)


static func all(dir := DEFAULT_DIR) -> Array[PropData]:
	var result: Array[PropData] = []
	for id in _table(dir):
		result.append(_table(dir)[id])
	return result


static func clear_cache() -> void:
	_cache.clear()


static func _table(dir: String) -> Dictionary:
	if _cache.has(dir):
		return _cache[dir]
	var table: Dictionary[StringName, PropData] = {}
	for res in ResourceCatalog.load_dir(dir, PropData, "PropLibrary"):
		var data := res as PropData
		table[data.id] = data
	_cache[dir] = table
	return table
