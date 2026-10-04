class_name Chapter2ArtSuite
extends EnemySuiteBase
## 第二章場景美術（NE-55）：環境主題的十個區段各有材質與立面，道具全數找得到資料且站得到位置，前層道具不遮住敵人與危險物，
## 平台道具不卡進地形，覆蓋區蓋在實心格上，各區段用到對應類別的道具；關卡照常進得去。

const LEVEL_2 := "res://data/levels/level_02.tres"
const EXPECTED_ZONES: Array[String] = ["升降井入口", "升降井", "夾層區", "中庭", "回收燈幕", "電力室", "看守長場地", "轉運站", "病房區", "頭目戰"]
## 區段（欄範圍）→ 至少要用到的道具類別。
const SECTION_CATEGORIES: Array = [
	[0, 70, [&"facility"]], [70, 140, [&"facility"]], [140, 215, [&"street", &"interior"]], [215, 263, [&"nature", &"street"]],
	[263, 325, [&"facility"]], [325, 385, [&"facility"]], [385, 415, [&"hangar"]], [415, 440, [&"interior"]], [440, 470, [&"interior"]], [470, 510, [&"hangar"]],
]


func run() -> void:
	_test_theme()
	_test_props()
	_test_regions()
	await _test_level_runs()


func _data() -> LevelData:
	return load(LEVEL_2) as LevelData


func _test_theme() -> void:
	var data := _data()
	check(data.environment != null, "第二章指定了環境主題")
	check(data.environment.validate().is_empty(), "第二章環境主題通過檢查：%s" % ", ".join(data.environment.validate()))
	var labels: PackedStringArray = []
	var materials: Dictionary[StringName, bool] = {}
	for zone in data.environment.zones:
		labels.append(zone.label)
		materials[zone.material.id] = true
	for expected in EXPECTED_ZONES:
		check(labels.has(expected), "第二章有「%s」區段" % expected)
	check(materials.size() >= 5, "第二章用了多種地形材質（%d）" % materials.size())
	# 環境區段的起點和光影區段、地圖上的段落對得上（每個光影區段起點都有環境區段）。
	for zone in data.lighting_zones:
		var env_zone := data.environment.zone_at(zone.start_tile)
		check(env_zone != null and env_zone.from_tile <= zone.start_tile, "光影區段 %d 有對應的環境區段" % zone.start_tile)


func _test_props() -> void:
	var data := _data()
	var layout := LevelBuilder.parse(data)
	var props := data.load_props()
	check(props.size() >= 100, "第二章擺了足夠的道具（%d）" % props.size())
	var danger: Array[Rect2] = []
	for cells in layout.spike_rects + layout.laser_rects:
		danger.append(layout.cells_to_pixels(cells))
	var enemy_boxes: Array[Rect2] = []
	for spawn in layout.spawns:
		if spawn["resource"] is EnemyData:
			enemy_boxes.append(Rect2(spawn["position"] + Vector2(-14, -44), Vector2(28, 44)))
	var solids: Array[Rect2] = []
	for cells in layout.solid_rects:
		solids.append(layout.cells_to_pixels(cells))
	var by_section: Array[Dictionary] = []
	for section in SECTION_CATEGORIES:
		by_section.append({})
	var unresolved := 0
	for entry in props:
		var prop := PropLibrary.find(StringName(str(entry["id"])), data.environment.prop_dir)
		if prop == null:
			unresolved += 1
			continue
		var placed := PropPlacement.resolve(entry, prop, layout)
		if placed.is_empty():
			unresolved += 1
			continue
		var rect: Rect2 = placed["rect"]
		var column := int(entry["x"])
		for i in SECTION_CATEGORIES.size():
			if column >= int(SECTION_CATEGORIES[i][0]) and column < int(SECTION_CATEGORIES[i][1]):
				by_section[i][prop.category] = int(by_section[i].get(prop.category, 0)) + 1
		if prop.layer == PropData.Layer.FRONT:
			for box in enemy_boxes:
				check(not rect.intersects(box), "前層道具 %s（第 %d 欄）不遮住敵人" % [prop.id, column])
			for hazard in danger:
				check(not rect.intersects(hazard), "前層道具 %s（第 %d 欄）不遮住危險物" % [prop.id, column])
		if prop.platform.size.x > 0.0:
			var platform := Rect2(rect.position + prop.platform.position, prop.platform.size)
			for solid in solids:
				check(not platform.intersects(solid), "道具 %s 的平台（第 %d 欄）沒有卡進地形" % [prop.id, column])
		# 道具不蓋在敵人身上（背景層也一樣：敵人的輪廓要清楚）
		for box in enemy_boxes:
			check(not rect.intersects(box.grow(-4.0)) or prop.size.y <= 8.0, "道具 %s（第 %d 欄）沒有蓋住敵人" % [prop.id, column])
	check(unresolved == 0, "第二章所有道具都找得到資料且站得到位置（%d 個有問題）" % unresolved)
	for i in SECTION_CATEGORIES.size():
		for category: StringName in SECTION_CATEGORIES[i][2]:
			check(int(by_section[i].get(category, 0)) >= 2, "欄 %d～%d 用到 %s 類道具（%d）" % [SECTION_CATEGORIES[i][0], SECTION_CATEGORIES[i][1], category, int(by_section[i].get(category, 0))])
	# 病房區：五張病床各一張
	var beds := 0
	for entry in props:
		if str(entry["id"]) == "hospital_bed":
			beds += 1
	check(beds == 5, "病房區有五張病床（%d）" % beds)


func _test_regions() -> void:
	var data := _data()
	var layout := LevelBuilder.parse(data)
	var regions := data.load_regions()
	check(regions.size() >= 6, "第二章有材質覆蓋區（%d）" % regions.size())
	for region in regions:
		var path := "res://data/environment/materials/%s.tres" % region["material"]
		check(ResourceLoader.exists(path), "覆蓋區材質 %s 存在" % region["material"])
		var solid_cells := 0
		for y in range(int(region["y0"]), int(region["y1"]) + 1):
			for x in range(int(region["x0"]), int(region["x1"]) + 1):
				if layout.cell(x, y) == LevelBuilder.SOLID:
					solid_cells += 1
		check(solid_cells > 0, "覆蓋區 %s（%d,%d）蓋在實心格上" % [region["material"], int(region["x0"]), int(region["y0"])])


func _test_level_runs() -> void:
	var level := await start_level(_data())
	check(is_instance_valid(level.player), "套用環境主題的第二章進得去")
	var terrain := level.find_children("*", "Terrain", true, false)
	check(not terrain.is_empty() and terrain[0].get_child_count() > 3, "地形以材質分塊建立")
	var nodes := level.find_children("*", "PropNode", true, false)
	check(nodes.size() >= 100, "道具節點全部生成（%d）" % nodes.size())
	await end_level(level)
