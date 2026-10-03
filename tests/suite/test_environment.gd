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
	_test_sky()
	_test_trees()
	_test_prop_animation()
	_test_foreground()
	await _test_level_with_environment()
	await _test_level_without_environment()
	_test_chapter_one()


func _png_size(path: String) -> Vector2i:
	var tex := load(path) as Texture2D
	return Vector2i(tex.get_size()) if tex != null else Vector2i.ZERO


func _test_materials() -> void:
	var list := ResourceCatalog.load_dir("res://data/environment/materials", TerrainMaterialData, "EnvSuite")
	check(list.size() >= 10, "地形材質至少 10 種（%d）" % list.size())
	for res in list:
		var m := res as TerrainMaterialData
		check(m.validate().is_empty(), "材質 %s 的三張貼圖與法線都存在" % m.id)
		var body := _png_size(m.body)
		check(body.x == body.y and body.x % m.texture_scale == 0 and body.x >= 64 and body.x <= 768, "材質 %s 本體是正方形、邊長是貼圖倍率的整數倍且在 64～768（%s）" % [m.id, body])
		check(_png_size(m.top) == Vector2i(body.x, roundi(m.top_height * m.texture_scale)), "材質 %s 頂面寬同本體、高 = 頂面厚度 × 倍率" % m.id)
		check(_png_size(m.side) == Vector2i(roundi(m.side_width * m.texture_scale), body.y), "材質 %s 側邊寬 = 側邊厚度 × 倍率、高同本體" % m.id)


func _test_facades() -> void:
	var list := ResourceCatalog.load_dir("res://data/environment/facades", FacadeData, "EnvSuite")
	check(list.size() >= 6, "建築立面至少 6 種（%d）" % list.size())
	for res in list:
		var f := res as FacadeData
		check(f.validate().is_empty(), "立面 %s 的模組貼圖都存在" % f.id)
		for group: Array in [[f.ground, FacadeData.GROUND_HEIGHT, "一樓"], [f.body, FacadeData.BODY_HEIGHT, "標準樓層"], [f.cap, FacadeData.CAP_HEIGHT, "女兒牆"]]:
			for path: String in group[0]:
				var size := Vector2(_png_size(path))
				check(size.x >= FacadeData.MODULE_WIDTH * 4.0 and size.x <= 1024.0, "立面 %s %s模組寬度至少 4 倍解析度且不超過 1024（%s）" % [f.id, group[2], size])
				check(absf(size.x / size.y - FacadeData.MODULE_WIDTH / float(group[1])) < 0.03, "立面 %s %s模組長寬比是 %d:%d（%s）" % [f.id, group[2], int(FacadeData.MODULE_WIDTH), int(group[1]), path.get_file()])
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
		var tex := Vector2(_png_size(prop.texture))
		check(tex.x >= prop.size.x * PropData.TEXTURE_SCALE - 1.0 and tex.y >= prop.size.y * PropData.TEXTURE_SCALE - 1.0, "道具 %s 貼圖至少是邏輯大小的 4 倍（%s）" % [prop.id, tex])
		check(maxf(tex.x, tex.y) <= 1024.0, "道具 %s 貼圖不超過 1024 像素" % prop.id)
		check(absf(tex.x / tex.y - prop.size.x / prop.size.y) < 0.03 * prop.size.x / prop.size.y, "道具 %s 貼圖長寬比與邏輯大小一致" % prop.id)
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
		var path := EnvGallery.backdrop_path(id)
		var width := _png_size(path).x
		check(width >= 1280 and width <= 4096 and width % 640 == 0, "背景層 %s 寬是 640 邏輯像素的整數倍解析度（%d）" % [id, width])
		check(ResourceLoader.exists(path.get_basename() + "_glow." + path.get_extension()), "背景層 %s 有窗光層" % id)


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


## 照片天空（NE-60）：第一章主題有天空、貼圖規格正確；缺圖時退回程式天空而不是崩潰。
func _test_sky() -> void:
	var theme := load("res://data/environment/themes/chapter1.tres") as EnvironmentTheme
	check(theme != null and theme.validate().is_empty(), "第一章主題（含天空）通過檢查")
	check(theme.sky != null, "第一章主題指定了照片天空")
	var tex := Vector2(_png_size(theme.sky.texture))
	check(tex.x >= 2048.0 and tex.x <= 4096.0 and tex.y >= 200.0, "天空貼圖是左右環繞的長條，寬 2048～4096（%s）" % tex)
	var control := LevelBackground.new()
	runner.add_child(control)
	var with_sky := LevelBackground.new()
	with_sky.sky = theme.sky
	runner.add_child(with_sky)
	check(with_sky.get_child_count() == control.get_child_count() + 1, "有天空時多一層視差天空")
	var broken := BackdropLayer.new()
	broken.texture = "res://art/environment/backdrop/test_missing_prop_sky.webp"
	check("
".join(broken.validate()).contains("test_missing_prop_sky.webp"), "缺天空貼圖時檢查會指出具體路徑")
	var fallback := LevelBackground.new()
	fallback.sky = broken
	runner.add_child(fallback)
	check(fallback.get_child_count() == control.get_child_count(), "缺天空貼圖時退回程式天空，不多也不少一層")
	for node in [control, with_sky, fallback]:
		node.queue_free()


## 樹木與植被（NE-64）：數量、前景樹半透明、搖動用共用著色器、不增加每影格開銷、第一章有擺放。
func _test_trees() -> void:
	var trees: Array[PropData] = []
	for prop in PropLibrary.all():
		if prop.category == &"nature":
			trees.append(prop)
	check(trees.size() >= 6, "樹與植被至少 6 種（%d）" % trees.size())
	var swaying := 0
	var front := 0
	for prop in trees:
		check(prop.validate().is_empty(), "植物 %s 資料與貼圖完整" % prop.id)
		check(ResourceLoader.exists(prop.texture.get_basename() + "_n.png"), "植物 %s 有法線貼圖" % prop.id)
		if prop.sway > 0.0:
			swaying += 1
		if prop.layer == PropData.Layer.FRONT:
			front += 1
			check(prop.front_alpha < 1.0, "前景植物 %s 半透明，不遮住敵人與子彈" % prop.id)
	check(swaying >= 4, "會被風吹動的植物至少 4 種（%d）" % swaying)
	check(front >= 1, "至少有一種前景植物")
	var swaying_prop := PropLibrary.find(&"tree_island")
	var first := PropNode.new()
	first.setup(swaying_prop, Vector2(10, 10))
	runner.add_child(first)
	var second := PropNode.new()
	second.setup(swaying_prop, Vector2(200, 10))
	runner.add_child(second)
	var sprite_a := first.get_child(0) as Sprite2D
	var sprite_b := second.get_child(0) as Sprite2D
	check(sprite_a.material is ShaderMaterial, "會搖動的植物用著色器搖動")
	check(sprite_a.material == sprite_b.material, "同幅度的植物共用同一份材質（數量多也不增加配置）")
	check(not first.is_processing(), "搖動由著色器處理，沒有每影格腳本")
	first.queue_free()
	second.queue_free()
	var level_map: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/level_01_map.json")).get("props", [])
	var placed := 0
	for entry: Dictionary in level_map:
		var prop := PropLibrary.find(StringName(entry["id"]))
		if prop != null and prop.category == &"nature":
			placed += 1
	check(placed >= 6, "第一章地圖擺了植物（%d）" % placed)


## 道具動畫（NE-62／63）：懸掛物搖擺、窗光生命、螢幕掃描、蒸汽，全部走共用著色器或事件，不多配置、不加每影格腳本。
func _test_prop_animation() -> void:
	var hanging := 0
	var life := 0
	var scan := 0
	var steam := 0
	for prop in PropLibrary.all():
		hanging += 1 if prop.sway_hang else 0
		life += 1 if prop.glow_life else 0
		scan += 1 if prop.glow_scan > 0.0 else 0
		steam += 1 if prop.steam else 0
		if prop.sway_hang:
			check(prop.sway > 0.0, "懸掛物 %s 有設定搖動幅度" % prop.id)
		if prop.glow_life or prop.glow_scan > 0.0:
			check(prop.has_glow, "道具 %s 的光影動畫需要自發光層" % prop.id)
	check(hanging >= 3 and life >= 4 and scan >= 3 and steam >= 1, "有動畫的道具：懸掛 %d、窗光生命 %d、螢幕掃描 %d、蒸汽 %d" % [hanging, life, scan, steam])

	var base := PropLibrary.find(&"street_lamp")
	var swing := base.duplicate() as PropData
	swing.sway = 1.5
	swing.sway_hang = true
	var plain := base.duplicate() as PropData
	plain.sway = 1.5
	var a := PropNode.new()
	a.setup(swing, Vector2(10, 10))
	runner.add_child(a)
	var b := PropNode.new()
	b.setup(swing, Vector2(90, 10))
	runner.add_child(b)
	var c := PropNode.new()
	c.setup(plain, Vector2(170, 10))
	runner.add_child(c)
	var sprite_a := a.get_child(0) as Sprite2D
	check(sprite_a.material == (b.get_child(0) as Sprite2D).material, "同設定的懸掛物共用同一份搖動材質")
	check(sprite_a.material != (c.get_child(0) as Sprite2D).material, "懸掛與直立的搖動材質不同")
	check(bool((sprite_a.material as ShaderMaterial).get_shader_parameter(&"hang")), "懸掛物的材質是頂端固定")
	var glow_a := a.get_child(1) as Sprite2D
	check(glow_a.material is ShaderMaterial, "搖動的道具，自發光層跟著一起搖")
	for node: Node in [a, b, c]:
		node.queue_free()

	var lively := base.duplicate() as PropData
	lively.glow_life = true
	lively.sway = 0.0
	var d := PropNode.new()
	d.setup(lively, Vector2(10, 10))
	runner.add_child(d)
	check((d.get_child(1) as Sprite2D).material == LightKit.window_life_material(), "窗光生命的道具自發光層用共用的窗光材質")
	d.queue_free()
	var scanning := base.duplicate() as PropData
	scanning.glow_scan = 0.4
	scanning.sway = 0.0
	var e := PropNode.new()
	e.setup(scanning, Vector2(10, 10))
	runner.add_child(e)
	var f := PropNode.new()
	f.setup(scanning, Vector2(90, 10))
	runner.add_child(f)
	check((e.get_child(1) as Sprite2D).material is ShaderMaterial and (e.get_child(1) as Sprite2D).material == (f.get_child(1) as Sprite2D).material, "螢幕掃描的道具共用同一份材質")
	e.queue_free()
	f.queue_free()
	var vent := base.duplicate() as PropData
	vent.steam = true
	var g := PropNode.new()
	g.setup(vent, Vector2(10, 10))
	runner.add_child(g)
	check(g.is_processing(), "冒蒸汽的道具會處理")
	var has_gate := false
	for child in g.get_children():
		has_gate = has_gate or child is VisibleOnScreenNotifier2D
	check(has_gate, "蒸汽只在畫面內發射（有螢幕範圍偵測）")
	g.queue_free()


## 近景（NE-61）：貼圖剪影條左右鏡像排滿一段、缺圖退回程式剪影不崩潰。
func _test_foreground() -> void:
	var layer := ForegroundLayer.new()
	runner.add_child(layer)
	var sprites := 0
	for child in layer._static.get_children():
		sprites += 1 if child is Sprite2D else 0
	check(sprites >= 4, "近景剪影由貼圖條組成（%d 個精靈）" % sprites)
	check(layer._static._add_strip("res://art/test_missing_prop_fg.webp", 0.0, false) == false, "前景貼圖缺失時回報失敗並退回程式剪影")
	layer.queue_free()


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
		if not prop.data.has_glow and prop.data.light_radius <= 0.0 and not prop.data.steam:  # 蒸汽要計時，所以會處理
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


## 第一章（NE-40）：六個區段的主題、道具擺放不遮住敵人與危險物、不卡進地形、覆蓋區的材質存在。
func _test_chapter_one() -> void:
	var data := load("res://data/levels/level_01.tres") as LevelData
	check(data.environment != null, "第一章指定了環境主題")
	check(data.environment.validate().is_empty(), "第一章環境主題通過檢查：%s" % ", ".join(data.environment.validate()))
	var labels: PackedStringArray = []
	for zone in data.environment.zones:
		labels.append(zone.label)
	for expected in ["屋頂巷弄", "霓虹市集", "貨運站", "設施入口", "停電走廊", "頭目機庫"]:
		check(labels.has(expected), "第一章有「%s」區段" % expected)
	var layout := LevelBuilder.parse(data)
	var props := data.load_props()
	check(props.size() >= 60, "第一章擺了足夠的道具（%d）" % props.size())
	var categories: Dictionary[StringName, int] = {}
	var danger: Array[Rect2] = []
	for cells in layout.spike_rects + layout.laser_rects:
		danger.append(layout.cells_to_pixels(cells))
	var enemy_boxes: Array[Rect2] = []
	for spawn in layout.spawns:
		enemy_boxes.append(Rect2(spawn["position"] + Vector2(-14, -44), Vector2(28, 44)))
	var solids: Array[Rect2] = []
	for cells in layout.solid_rects:
		solids.append(layout.cells_to_pixels(cells))
	var unresolved := 0
	for entry in props:
		var prop := PropLibrary.find(StringName(str(entry["id"])), data.environment.prop_dir)
		if prop == null:
			unresolved += 1
			continue
		categories[prop.category] = categories.get(prop.category, 0) + 1
		var placed := PropPlacement.resolve(entry, prop, layout)
		if placed.is_empty():
			unresolved += 1
			continue
		var rect: Rect2 = placed["rect"]
		if prop.layer == PropData.Layer.FRONT:
			for box in enemy_boxes:
				check(not rect.intersects(box), "前層道具 %s（第 %d 欄）不遮住敵人" % [prop.id, int(entry["x"])])
			for hazard in danger:
				check(not rect.intersects(hazard), "前層道具 %s（第 %d 欄）不遮住危險物" % [prop.id, int(entry["x"])])
		if prop.platform.size.x > 0.0:
			var platform := Rect2(rect.position + prop.platform.position, prop.platform.size)
			for solid in solids:
				check(not platform.intersects(solid), "道具 %s 的平台（第 %d 欄）沒有卡進地形" % [prop.id, int(entry["x"])])
	check(unresolved == 0, "第一章所有道具都找得到資料且站得到地表（%d 個有問題）" % unresolved)
	for category in [&"rooftop", &"street", &"cargo", &"facility", &"hangar"]:
		check(categories.get(category, 0) >= 3, "第一章用到 %s 類道具" % category)
	for region in data.load_regions():
		var path := "res://data/environment/materials/%s.tres" % region["material"]
		check(ResourceLoader.exists(path), "覆蓋區材質 %s 存在" % region["material"])
		var solid_cells := 0
		for y in range(int(region["y0"]), int(region["y1"]) + 1):
			for x in range(int(region["x0"]), int(region["x1"]) + 1):
				if layout.cell(x, y) == LevelBuilder.SOLID:
					solid_cells += 1
		check(solid_cells > 0, "覆蓋區 %s（%d,%d）蓋在實心格上" % [region["material"], int(region["x0"]), int(region["y0"])])
