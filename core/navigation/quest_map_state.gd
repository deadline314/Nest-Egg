class_name QuestMapState
extends RefCounted
## 僅保存導覽狀態，不保存或推進故事。主流程可把 snapshot 放入既有存檔。

signal changed

const VERSION := 1
static var _shared: QuestMapState
static var _run_areas: Dictionary
var pinned_id := ""
var explored: Dictionary = {}
var activated: Dictionary = {}
var revision := 0
var issues := PackedStringArray()


static func for_run() -> QuestMapState:
	# 新遊戲會建立新的 area_states；死亡、重試與章節切換沿用同一份。
	if _shared == null or not is_same(_run_areas, GameState.area_states):
		_run_areas = GameState.area_states
		_shared = QuestMapState.new()
	return _shared


func pin(id: String, catalog: QuestCatalog) -> void:
	pinned_id = id if not catalog.find(id).is_empty() else ""
	_touch()


func target(catalog: QuestCatalog, chapter: String, flags: Dictionary) -> Dictionary:
	var pinned := catalog.find(pinned_id)
	if not pinned.is_empty() and pinned["chapter"] == chapter and QuestCatalog.all_flags(pinned.get("visible_flags", []), flags) and QuestCatalog.status(pinned, flags) != "completed":
		return pinned
	for quest in catalog.list_for(chapter, "main", false, flags):
		if QuestCatalog.status(quest, flags) == "active":
			return quest
	return {}


func reveal(path: String, cells: Array[Vector2i]) -> void:
	if not explored.has(path):
		explored[path] = {}
	var dirty := false
	for cell in cells:
		var key := "%d,%d" % [cell.x, cell.y]
		if not explored[path].has(key):
			explored[path][key] = true
			dirty = true
	if dirty:
		_touch()


func knows(path: String, cell: Vector2i) -> bool:
	return explored.get(path, {}).has("%d,%d" % [cell.x, cell.y])


func activate(path: String, position: Vector2, tile: int) -> void:
	var key := "%s@%d,%d" % [path, int(position.x / tile), int(position.y / tile)]
	if not activated.has(key):
		activated[key] = true
		_touch()


func snapshot() -> Dictionary:
	return {"version": VERSION, "pinned_id": pinned_id, "explored": explored.duplicate(true), "activated": activated.duplicate(true)}


func restore(raw: Variant, catalog: QuestCatalog, maps: QuestMapIndex, notify := true) -> void:
	pinned_id = ""
	explored.clear()
	activated.clear()
	issues.clear()
	if not raw is Dictionary or raw.get("version") != VERSION:
		issues.append("navigation.version: 格式不符，改用預設導覽狀態。")
	else:
		var id: Variant = raw.get("pinned_id", "")
		if id is String and (id.is_empty() or not catalog.find(id).is_empty()):
			pinned_id = id
		else:
			issues.append("navigation.pinned_id: 找不到任務，改為追蹤主線。")
		var areas: Variant = raw.get("explored", {})
		if areas is Dictionary:
			for path: Variant in areas:
				if not path is String or not maps.areas.has(path) or not areas[path] is Dictionary:
					issues.append("navigation.explored.%s: 無效區域，已略過。" % str(path))
					continue
				var layout: LevelLayout = maps.areas[path]["layout"]
				for key: Variant in areas[path]:
					var cell := _parse_cell(key, layout)
					if cell != Vector2i(-1, -1) and areas[path][key] == true:
						if not explored.has(path):
							explored[path] = {}
						explored[path][key] = true
					else:
						issues.append("navigation.explored.%s.%s: 無效格座標，已略過。" % [path, key])
		else:
			issues.append("navigation.explored: 必須是物件，改用未探索狀態。")
		var points: Variant = raw.get("activated", {})
		if points is Dictionary:
			for key: Variant in points:
				if key is String and points[key] == true and maps.checkpoint_keys.has(key):
					activated[key] = true
				else:
					issues.append("navigation.activated.%s: 找不到存檔點，已略過。" % str(key))
		else:
			issues.append("navigation.activated: 必須是物件，改用未啟用狀態。")
	for issue in issues:
		push_warning("[QuestMap] %s" % issue)
	if notify:
		_touch()
	else:
		revision += 1


static func _parse_cell(key: Variant, layout: LevelLayout) -> Vector2i:
	if not key is String:
		return Vector2i(-1, -1)
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	var cell := Vector2i(int(parts[0]), int(parts[1]))
	return cell if cell.x >= 0 and cell.y >= 0 and cell.x < layout.width and cell.y < layout.height else Vector2i(-1, -1)


func _touch() -> void:
	revision += 1
	changed.emit()
