class_name QuestMapIndex
extends RefCounted
## 從真實 LevelData / LevelLayout 建立只讀索引與路線，不載入關卡節點。

const LevelCatalog := preload("res://core/navigation/level_resource_index.gd")
const AREA_DIRECTORY := LevelCatalog.DIRECTORY

static var _chapters: Dictionary = {}


static func for_chapter(chapter: StringName) -> QuestMapIndex:
	if not _chapters.has(chapter):
		var index := QuestMapIndex.new()
		index.load_chapter(chapter)
		_chapters[chapter] = index
	return _chapters[chapter]


## Save validation only needs authored geometry for the areas the slot refers to.
static func for_navigation_restore(raw: Variant, chapters: Array[StringName]) -> QuestMapIndex:
	var index := QuestMapIndex.new()
	if not raw is Dictionary or raw.get("version") != QuestMapState.VERSION or not raw.get("layout_revisions", {}) is Dictionary:
		return index
	var paths: Dictionary[String, bool] = {}
	var explored: Variant = raw.get("explored", {})
	if explored is Dictionary:
		for path: Variant in explored:
			if path is String and explored[path] is Dictionary:
				paths[path] = true
	var activated: Variant = raw.get("activated", {})
	if activated is Dictionary:
		for key: Variant in activated:
			if key is String:
				paths[key.get_slice("@", 0)] = true
	if paths.is_empty():
		return index
	# Visit the authored directory, so arbitrary slot references cannot expand the load.
	for file: String in ResourceLoader.list_directory(AREA_DIRECTORY):
		var path := AREA_DIRECTORY.path_join(file)
		if not file.ends_with(".tres") or not paths.has(path):
			continue
		var data := RunSaveCodec.resource(path, "level", AREA_DIRECTORY + "/") as LevelData
		if data != null and chapters.has(data.chapter):
			index.add_area(data)
	return index


var areas: Dictionary = {}
var checkpoint_keys := PackedStringArray()
var parse_count := 0


func load_chapter(chapter: StringName) -> void:
	areas.clear()
	checkpoint_keys.clear()
	for path in LevelCatalog.chapter_paths(chapter):
		var data := LevelCatalog.load_level(path)
		if data != null and data.chapter == chapter:
			add_area(data)


func add_area(data: LevelData) -> void:
	if areas.has(data.resource_path):
		return
	var layout := LevelBuilder.parse(data)
	parse_count += 1
	if not layout.is_valid():
		return
	var markers: Array[Dictionary] = []
	for position in layout.checkpoints:
		markers.append(_marker("checkpoint", "在這裡啟用復原點。", position, data.tile_size))
		checkpoint_keys.append("%s@%d,%d" % [data.resource_path, int(position.x / data.tile_size), int(position.y / data.tile_size)])
	for position in layout.health_pickups:
		markers.append(_marker("pickup", "在這裡拾取回復道具。", position, data.tile_size))
	for spawn in layout.spawns:
		var resource: Resource = spawn["resource"]
		if resource is MechanismData and resource.is_retired_arena_gate():
			continue
		var marker := _marker("", "", spawn["position"], data.tile_size)
		marker["resource"] = resource
		marker["cell"] = spawn["cell"]
		if resource is PortalData:
			marker["kind"] = "exit"
			marker["text"] = InputBindings.format(resource.default_prompt())
		elif resource is ShopData:
			marker["kind"] = "shop"
			marker["text"] = "在%s購買補給或查看服務。" % resource.display_name
		elif resource is MechanismData and resource.kind == MechanismData.Kind.GATE:
			marker["kind"] = "gate"
			marker["text"] = resource.hint if not resource.hint.is_empty() else "查看%s的開啟條件。" % resource.display_name
		elif resource is WeaponData or resource is ConsumableData or resource is StoryItemData or resource is CreditPileData:
			marker["kind"] = "pickup"
			marker["text"] = "在這裡拾取%s。" % ("信用點" if resource is CreditPileData else resource.display_name)
		elif resource is BreakableData and resource.look == BreakableData.Look.WALL:
			marker["kind"] = "secret_wall"
			marker["text"] = resource.hint
		if marker["kind"] != "":
			markers.append(marker)
	areas[data.resource_path] = {"data": data, "layout": layout, "markers": markers}


static func _marker(kind: String, text: String, position: Vector2, tile: int) -> Dictionary:
	return {"kind": kind, "text": text, "position": position, "cell": Vector2i(int(position.x / tile), int(ceilf(position.y / tile)) - 1)}


func source_location(id: StringName) -> Dictionary:
	for path: String in areas:
		var layout: LevelLayout = areas[path]["layout"]
		for spawn: Dictionary in layout.spawns:
			var actor := spawn["resource"] as NpcData
			if actor != null and actor.id == id:
				var cell: Vector2i = spawn["cell"]
				return {"level": path, "cell": [cell.x, cell.y]}
	return {}


func edges(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker: Dictionary in areas.get(path, {}).get("markers", []):
		if marker["kind"] == "exit" and areas.has(marker["resource"].target_level):
			result.append(marker)
	return result


## 優先走可通行路線；若沒有則指出第一個鎖住的出口，讓玩家看得到原因。
func next_exit(from: String, to: String, flags: Dictionary, allow_locked := false) -> Dictionary:
	if from == to or not areas.has(from) or not areas.has(to):
		return {}
	var queue: Array[String] = [from]
	var first: Dictionary = {from: {}}
	while not queue.is_empty():
		var path: String = queue.pop_front()
		for marker in edges(path):
			var portal := marker["resource"] as PortalData
			if not allow_locked and portal.requires_flag != &"" and not QuestCatalog.flag_set(flags, String(portal.requires_flag)):
				continue
			if first.has(portal.target_level):
				continue
			first[portal.target_level] = marker if path == from else first[path]
			if portal.target_level == to:
				return first[to]
			queue.append(portal.target_level)
	return next_exit(from, to, flags, true) if not allow_locked else {}


func marker_text(marker: Dictionary, flags: Dictionary, language := StoryLocale.SOURCE_LANGUAGE) -> String:
	var resource: Resource = marker.get("resource")
	if resource is PortalData:
		var portal := resource as PortalData
		if portal.is_locked_door() or (portal.requires_flag != &"" and not QuestCatalog.flag_set(flags, String(portal.requires_flag))):
			return portal.locked_text_for(language)
		var target: LevelData = areas.get(portal.target_level, {}).get("data")
		if target != null:
			return _marker_copy(["從這裡前往%s。", "ここから%sへ移動できます。", "Leads to %s."], language) % target.display_name_for(language)
		return InputBindings.format(portal.default_prompt(language))
	if resource is ShopData:
		return _marker_copy(["在%s購買補給或查看服務。", "%sで物資やサービスを確認できます。", "Browse supplies and services at %s."], language) % resource.display_name
	if resource is MechanismData and resource.kind == MechanismData.Kind.GATE and resource.hint.is_empty():
		return _marker_copy(["查看%s的開啟條件。", "%sを開ける条件を確認できます。", "Check the requirement to open %s."], language) % resource.display_name
	match marker.get("kind", ""):
		"checkpoint":
			return _marker_copy(["在這裡啟用復原點。", "ここで復帰地点を有効にできます。", "Activate the checkpoint here."], language)
		"pickup":
			if resource == null:
				return _marker_copy(["在這裡拾取回復道具。", "ここで回復アイテムを入手できます。", "Pick up a healing item here."], language)
			var name: String = _marker_copy(["信用點", "クレジット", "credits"], language) if resource is CreditPileData else resource.display_name
			return _marker_copy(["在這裡拾取%s。", "ここで%sを入手できます。", "Pick up %s here."], language) % name
	return InputBindings.format(str(marker["text"]))


static func _marker_copy(copy: Array, language: String) -> String:
	return copy[1] if language == "ja" else copy[2] if language == "en" else copy[0]


## 探索只揭露玩家周圍可見的格子，實心地形與未破壞的秘密牆會遮擋視線。
func visible_cells(path: String, position: Vector2, world: Dictionary, radius := 8) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not areas.has(path):
		return result
	var layout: LevelLayout = areas[path]["layout"]
	var origin := Vector2i(position / layout.tile_size)
	var blockers: Array[Rect2i] = []
	for marker: Dictionary in areas[path]["markers"]:
		if marker["kind"] != "secret_wall":
			continue
		var cell: Vector2i = marker["cell"]
		var key := "breakable@%d,%d" % [cell.x, cell.y]
		if world.get(key, false) == true:
			continue
		var dims: Vector2i = marker["resource"].size_tiles
		blockers.append(Rect2i(cell - Vector2i(dims.x / 2, dims.y - 1), dims))
	for y in range(maxi(0, origin.y - radius), mini(layout.height, origin.y + radius + 1)):
		for x in range(maxi(0, origin.x - radius), mini(layout.width, origin.x + radius + 1)):
			var cell := Vector2i(x, y)
			if Vector2(cell - origin).length() <= radius and _line_visible(layout, origin, cell, blockers):
				result.append(cell)
	return result


static func _line_visible(layout: LevelLayout, from: Vector2i, to: Vector2i, blockers: Array[Rect2i]) -> bool:
	var count := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, count):
		var point := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / count).round())
		if layout.cell(point.x, point.y) == "#" or blockers.any(func(rect: Rect2i) -> bool: return rect.has_point(point)):
			return false
	return true
