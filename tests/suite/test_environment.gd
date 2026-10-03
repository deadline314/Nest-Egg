class_name EnvironmentSuite
extends TestSuite
## 環境美術元件庫（NE-39）：材質、立面、道具、背景層的數量與規格、缺圖容錯、區段選材、道具生成。
## 缺圖測試用的路徑含 test_missing_prop，執行器會忽略它的錯誤輸出。


func run() -> void:
	_test_materials()
	_test_facades()
	_test_props()
	_test_backdrop()
	_test_theme()
	_test_missing_texture()
	await _test_level_with_environment()
	await _test_level_without_environment()


func _png_size(path: String) -> Vector2i:
	var tex := load(path) as Texture2D
	return Vector2i(tex.get_size()) if tex != null else Vector2i.ZERO


func _test_materials() -> void:
	var list := ResourceCatalog.load_dir("res://data/environment/materials", TerrainMaterialData, "EnvSuite")
	check(list.size() >= 10, "地形材質至少 10 種（%d）" % list.size())
	for res in list:
		var m := res as TerrainMaterialData
		check(m.validate().is_empty(), "材質 %s 的三張貼圖與法線都存在" % m.id)
		check(_png_size(m.body) == Vector2i(64, 64), "材質 %s 本體是 64×64（4 倍解析度）" % m.id)
		check(_png_size(m.top) == Vector2i(64, 24), "材質 %s 頂面是 64×24" % m.id)
		check(_png_size(m.side) == Vector2i(24, 64), "材質 %s 側邊是 24×64" % m.id)


func _test_facades() -> void:
	var list := ResourceCatalog.load_dir("res://data/environment/facades", FacadeData, "EnvSuite")
	check(list.size() >= 6, "建築立面至少 6 種（%d）" % list.size())
	for res in list:
		var f := res as FacadeData
		check(f.validate().is_empty(), "立面 %s 的模組貼圖都存在" % f.id)
		check(_png_size(f.ground[0]) == Vector2i(256, 160), "立面 %s 一樓模組是 256×160" % f.id)
		check(_png_size(f.body[0]) == Vector2i(256, 128), "立面 %s 標準樓層是 256×128" % f.id)
		check(_png_size(f.cap[0]) == Vector2i(256, 32), "立面 %s 女兒牆是 256×32" % f.id)
		check(ResourceLoader.exists(FacadeData.glow_path(f.body[0])), "立面 %s 有自發光層" % f.id)
		check(ResourceLoader.exists(f.body[0].get_basename() + "_n.png"), "立面 %s 有法線貼圖" % f.id)


func _test_props() -> void:
	var list := PropLibrary.all()
	check(list.size() >= 30, "道具至少 30 種（%d）" % list.size())
	var glowing := 0
	var platforms := 0
	var categories: Dictionary[StringName, int] = {}
	for prop in list:
		check(prop.validate().is_empty(), "道具 %s 資料與貼圖完整" % prop.id)
		check(_png_size(prop.texture) == Vector2i(prop.size) * PropData.TEXTURE_SCALE, "道具 %s 貼圖是邏輯大小的 4 倍" % prop.id)
		if prop.has_glow:
			glowing += 1
		if prop.platform.size.x > 0.0:
			platforms += 1
		categories[prop.category] = categories.get(prop.category, 0) + 1
	check(glowing >= 15, "有自發光層的道具至少 15 種（%d）" % glowing)
	check(platforms >= 2, "有可站平台的道具至少 2 種（逃生梯、雨棚…）")
	for category in [&"rooftop", &"street", &"cargo", &"facility", &"hangar"]:
		check(categories.get(category, 0) >= 3, "道具分類 %s 至少 3 種" % category)
	check(PropLibrary.find(&"water_tower") != null, "可用 id 取得道具資料")
	check(PropLibrary.find(&"no_such_prop") == null, "找不到的道具回傳 null 而不是崩潰")


func _test_backdrop() -> void:
	for id in EnvGallery.BACKDROP_IDS:
		var path := "res://art/environment/backdrop/%s.png" % id
		check(_png_size(path) .x == 1280, "背景層 %s 寬 1280（640 邏輯像素 × 2）" % id)
		check(ResourceLoader.exists(path.get_basename() + "_glow.png"), "背景層 %s 有窗光層" % id)


func _test_theme() -> void:
	var theme := EnvGallery.theme()
	check(theme.validate().is_empty(), "畫廊主題通過檢查：%s" % ", ".join(theme.validate()))
	check(theme.zone_at(0) == theme.zones[0], "第 0 欄屬於第一個區段")
	check(theme.zone_at(EnvGallery.ZONE_TILES) == theme.zones[1], "區段依起點切換")
	check(theme.zone_at(9999) == theme.zones[theme.zones.size() - 1], "超出範圍沿用最後一個區段")
	var bad := EnvironmentTheme.new()
	check(not bad.validate().is_empty(), "沒有區段的主題會被指出")
	var zone := EnvZone.new()
	zone.label = "壞掉的區段"
	bad.zones.append(zone)
	check("\n".join(bad.validate()).contains("壞掉的區段"), "缺材質的區段會指出名稱")


func _test_missing_texture() -> void:
	var prop := PropData.new()
	prop.id = &"test_missing_prop"
	prop.texture = "res://art/environment/props/test_missing_prop.png"
	prop.size = Vector2(16, 16)
	check("\n".join(prop.validate()).contains("test_missing_prop.png"), "缺圖時檢查會指出具體路徑")
	var node := PropNode.new()
	node.setup(prop, Vector2(10, 10))
	runner.add_child(node)
	check(is_instance_valid(node) and node.get_child_count() >= 1, "缺圖的道具仍然建立（顯示替代圖）")
	node.queue_free()
	var material := TerrainMaterialData.new()
	material.id = &"test_missing_prop_material"
	check(not material.validate().is_empty(), "缺貼圖的材質會被指出")


func _test_level_with_environment() -> void:
	var data := EnvGallery.level_data("props")
	var level := await start_level(data)
	var expected := data.load_props().size()
	var props := 0
	var platforms := 0
	var static_props := 0
	for node in level.find_children("*", "PropNode", true, false):
		props += 1
		var prop := node as PropNode
		if prop.data.platform.size.x > 0.0:
			platforms += 1
		if not prop.data.has_glow and prop.data.light_radius <= 0.0:
			static_props += 1
			check(not prop.is_processing(), "靜態道具 %s 不跑每影格更新" % prop.data.id)
	check(props == expected, "地圖的道具清單全部生成（%d / %d）" % [props, expected])
	check(platforms >= 2, "有平台的道具帶單向碰撞")
	check(static_props >= 5, "多數道具沒有每影格開銷（%d）" % static_props)
	var terrain := level.find_child("Terrain", true, false) as Terrain
	check(terrain != null and terrain.get_child_count() > 3, "地形以材質分塊建立")
	var one_way := false
	for body in level.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			if child is CollisionShape2D and (child as CollisionShape2D).one_way_collision and body.get_parent() is PropNode:
				one_way = true
	check(one_way, "道具平台是單向碰撞")
	await end_level(level)

	var gallery := EnvGallery.level_data("materials")
	var level2 := await start_level(gallery)
	check(is_instance_valid(level2.player), "材質畫廊關卡可以進入")
	await frames(10)
	await end_level(level2)


func _test_level_without_environment() -> void:
	var data := LevelData.new()
	data.id = &"env_legacy"
	data.layout_path = EnvGallery.PROPS_MAP
	check(data.environment == null, "沒有指定環境時維持原本的繪製")
	var level := await start_level(data)
	check(is_instance_valid(level.player), "沒有環境主題的關卡照常運作")
	await end_level(level)
