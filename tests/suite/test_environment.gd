class_name EnvironmentSuite
extends TestSuite
## 環境美術元件庫（NE-39）：材質、立面、道具、背景層的數量與規格、缺圖容錯、區段選材、道具生成。
## 缺圖測試用的路徑含 test_missing_prop，執行器會忽略它的錯誤輸出。


func run() -> void:
	_test_materials()
	_test_facades()
	_test_props()
	_test_lit_coverage()
	_test_backdrop()
	_test_theme()
	_test_missing_texture()
	_test_sky()
	_test_backdrop_import_scale()
	_test_trees()
	_test_prop_animation()
	await _test_local_water_flow()
	await _test_kettle_steam_anchor()
	_test_foreground()
	await _test_level_with_environment()
	await _test_level_without_environment()
	_test_chapter_one()
	await _test_contact_shadow()
	_test_fixture_art()
	await _test_local_drip()
	await _test_lamp_fixtures()
	await _test_lamp_flicker()
	await _test_wall_shadows()
	_test_import_policy("res://art/environment")


func _test_import_policy(directory: String) -> void:
	for child in DirAccess.get_directories_at(directory):
		_test_import_policy(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		if not file.ends_with(".import"):
			continue
		var path := directory.path_join(file)
		var config := ConfigFile.new()
		check(config.load(path) == OK, "環境匯入設定可讀：%s" % path)
		check(config.get_value("params", "compress/mode", -1) == 0, "環境使用無損匯入：%s" % file)
		check(not config.get_value("params", "mipmaps/generate", true), "環境 linear／nearest 取樣不配置未用 mipmaps：%s" % file)
		if directory.ends_with("materials"):
			check(config.get_value("params", "process/size_limit", -1) == 0, "區域取樣／視差層保留尺寸：%s" % file)


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


## 統一光影整合（NE-66）：每個道具（共用庫與各場景包）都有法線貼圖，標示有自發光的都真的有；
## 共用庫的道具載入後是帶法線的受光貼圖，不會退成不受光的平面。
func _test_lit_coverage() -> void:
	var props: Array[PropData] = []
	props.append_array(PropLibrary.all())
	for dir in DirAccess.get_directories_at("res://data/environment/scene_props"):
		for file in DirAccess.get_files_at("res://data/environment/scene_props/" + dir):
			if file.ends_with(".tres"):
				var prop := load("res://data/environment/scene_props/%s/%s" % [dir, file]) as PropData
				if prop != null:
					props.append(prop)
	var no_normal: PackedStringArray = []
	var no_glow: PackedStringArray = []
	for prop in props:
		if not ResourceLoader.exists(prop.texture.get_basename() + "_n.png"):
			no_normal.append(String(prop.id))
		if prop.has_glow and not ResourceLoader.exists(prop.glow_path()):
			no_glow.append(String(prop.id))
	check(props.size() >= 100, "道具資料（共用庫＋場景包）至少 100 件（%d）" % props.size())
	check(no_normal.is_empty(), "所有道具都有法線貼圖，沒有不受光的平面（缺：%s）" % ", ".join(no_normal))
	check(no_glow.is_empty(), "標示有自發光的道具都有自發光層（缺：%s）" % ", ".join(no_glow))
	var flat: PackedStringArray = []
	for prop in PropLibrary.all():
		var texture := LitTextures.load_texture(prop.texture, Vector2i(prop.size) * PropData.TEXTURE_SCALE)
		if not (texture is CanvasTexture and (texture as CanvasTexture).normal_texture != null):
			flat.append(String(prop.id))
	check(flat.is_empty(), "共用庫道具載入後都是帶法線的受光貼圖（平面：%s）" % ", ".join(flat))


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


func _test_backdrop_import_scale() -> void:
	var layer := BackdropLayer.new()
	layer.texture_scale = 4
	layer.source_width = 128
	var texture := ImageTexture.create_from_image(Image.create(64, 32, false, Image.FORMAT_RGBA8))
	check(is_equal_approx(layer.pixel_scale(texture) * texture.get_width(), 32.0), "視差背景縮小匯入後仍保持原本世界寬度")
	layer.source_width = 0
	check(is_equal_approx(layer.pixel_scale(texture), 0.25), "舊背景資料未記錄來源尺寸時保留原倍率")
	check(is_equal_approx(StageLayers.sprite_scale({"source_width": 128, "scale": 0.25}, texture) * texture.get_width(), 32.0), "舞台縮圖不改家具世界寬度")
	check(is_equal_approx(StageLayers.sprite_scale({"scale": 0.25}, texture), 0.25), "舊舞台資料保留原倍率")


func _test_local_water_flow() -> void:
	var source := load("res://data/environment/scene_props/anchor_phone_booth/anchor_phone_booth__gutter_downpipe.tres") as PropData
	check(source != null and source.local_flow_valid(), "電話亭水流來源與承接面有效")
	if source == null:
		return
	var prop := PropNode.new()
	prop.setup(source, Vector2(80, 80), true)
	runner.add_child(prop)
	var flow: Node = prop.get_node("LocalWaterFlow")
	check(flow != null and flow._materials.size() == 2, "base 與 glow 各一局部材質，不新增貼圖粒子")
	check((prop.get_child(0) as Sprite2D).flip_h and prop._glow_sprite.flip_h, "base 與 glow 同步鏡像，shader 沿來源 UV 選區")
	prop.scale = Vector2(2, 2)
	check(prop.steam_world_position().is_equal_approx(prop.to_global(Vector2(source.size.x - source.steam_offset.x, source.steam_offset.y))), "噴口座標支援鏡像與父縮放")
	# Headless suite cameras vary after other suites. Isolate the pause clock
	# from asynchronous visibility notifications; real visibility is exercised
	# by the chapter rendering probe and its ten zone transitions.
	for child in prop.get_children():
		if child is VisibleOnScreenNotifier2D:
			child.queue_free()
	await _motion_process_frames(2)
	flow.on_screen = true
	await _motion_process_frames(3)
	var clock: float = flow.clock
	runner.get_tree().paused = true
	await _motion_process_frames(3)
	check(is_equal_approx(flow.clock, clock), "真 SceneTree 暫停停止水流時鐘")
	runner.get_tree().paused = false
	flow.on_screen = true
	await _motion_process_frames(3)
	print("BG25_TEST_RESUME before=%f after=%f" % [clock, flow.clock])
	check(flow.clock > clock, "恢復後水流繼續")
	flow.on_screen = false
	clock = flow.clock
	await _motion_process_frames(3)
	check(is_equal_approx(flow.clock, clock), "離開視野停止局部時計")
	var weak: WeakRef = weakref(flow)
	prop.queue_free()
	await _motion_process_frames(2)
	check(weak.get_ref() == null, "切區釋放局部元件與材質")
	var bad := source.duplicate() as PropData
	bad.flow_region = Rect2(-1, 0, 1, 1)
	check(not bad.local_flow_valid() and not bad.validate().is_empty(), "損毀 UV 被驗證攔下")
	var fallback := PropNode.new()
	fallback.setup(bad, Vector2.ZERO)
	runner.add_child(fallback)
	check(not fallback.has_node("LocalWaterFlow"), "無效區域退回靜態原圖")
	fallback.queue_free()
	await _motion_process_frames(2)


func _motion_process_frames(count: int) -> void:
	for frame in count:
		await runner.get_tree().process_frame


func _test_kettle_steam_anchor() -> void:
	var data := load("res://data/environment/scene_props/pawnshop_kitchen/pawnshop_kitchen__kettle_stove.tres") as PropData
	check(data.steam and data.steam_offset.is_equal_approx(Vector2(1.5, 7.5)), "壺嘴蒸汽從左側真出氣口開始")
	check(data.steam_spread_valid() and is_equal_approx(data.steam_spread, 0.25), "小壺嘴不沿用排水孔的寬散布")
	for mirrored in [false, true]:
		var prop := PropNode.new()
		prop.setup(data, Vector2(120, 60), mirrored)
		prop.scale = Vector2(1.5, 2)
		runner.add_child(prop)
		var x: float = data.size.x - 1.5 if mirrored else 1.5
		check(prop.steam_world_position().is_equal_approx(prop.to_global(Vector2(x, 7.5))), "壺嘴接點與鏡像縮放本體相同")
		check(is_equal_approx(prop._steam_spread, 0.25), "壺嘴實體採用局部半徑")
		prop.queue_free()
	await _motion_process_frames(2)
	var bad := data.duplicate() as PropData
	bad.steam_spread = NAN
	check(not bad.steam_spread_valid() and not bad.validate().is_empty(), "損毀散布資料被驗證攔下")
	var fallback := PropNode.new()
	fallback.setup(bad, Vector2.ZERO)
	runner.add_child(fallback)
	check(is_equal_approx(fallback._steam_spread, 2.0), "非法散布退回既有預設")
	fallback.queue_free()
	await _motion_process_frames(2)


## 角色腳下的接觸陰影（BG-29）：落在實際的支撐面上；離地越高越小；太高或腳下沒有地就不畫；
## 站在邊緣時不懸空；上層有地板時不穿到下一層。
func _test_contact_shadow() -> void:
	var world := Node2D.new()
	runner.add_child(world)
	world.position = Vector2(-4000.0, -4000.0)
	var upper := _shadow_floor(world, Rect2(0.0, 100.0, 200.0, 16.0))
	var lower := _shadow_floor(world, Rect2(0.0, 300.0, 400.0, 16.0))
	var body := Node2D.new()
	world.add_child(body)
	body.position = Vector2(100.0, 100.0)
	var shadow := ContactShadow.attach(body, 12.0)
	await physics_frames(3)
	var grounded := shadow.world_rect()
	check(shadow.is_cast() and absf(grounded.position.y - (world.position.y + 100.0 - ContactShadow.SURFACE_LIP)) < 0.5,
			"contact shadow lies on the floor under the feet")
	check(grounded.size.x > 20.0 and grounded.size.y <= ContactShadow.MAX_HEIGHT, "grounded shadow spans the footprint and stays on the floor face")
	body.position = Vector2(100.0, 40.0)
	await physics_frames(3)
	var raised := shadow.world_rect()
	check(shadow.is_cast() and raised.size.x < grounded.size.x - 2.0 and is_equal_approx(raised.position.y, grounded.position.y),
			"jumping keeps the shadow on the same floor but smaller")
	body.position = Vector2(100.0, 100.0 - ContactShadow.MAX_DROP - 20.0)
	await physics_frames(3)
	check(not shadow.is_cast(), "no shadow when the floor is farther than the maximum drop")
	body.position = Vector2(198.0, 100.0)
	await physics_frames(3)
	var edge := shadow.world_rect()
	check(shadow.is_cast() and edge.end.x <= world.position.x + 200.0 + 4.0 and edge.size.x < grounded.size.x - 4.0,
			"standing on a ledge keeps the shadow on the ledge instead of hanging in the air")
	check(absf(edge.position.y - grounded.position.y) < 0.5, "a shadow on the upper floor does not fall through to the floor below")
	body.position = Vector2(300.0, 290.0)
	await physics_frames(3)
	check(shadow.is_cast() and absf(shadow.world_rect().position.y - (world.position.y + 300.0 - ContactShadow.SURFACE_LIP)) < 0.5,
			"the shadow follows the character onto the lower floor")
	body.position = Vector2(600.0, 100.0)
	await physics_frames(3)
	check(not shadow.is_cast(), "no shadow over a pit")
	upper.queue_free()
	lower.queue_free()
	world.queue_free()


func _shadow_floor(parent: Node2D, rect: Rect2) -> StaticBody2D:
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = Layers.WORLD
	floor_body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var node := CollisionShape2D.new()
	node.shape = shape
	node.position = rect.get_center()
	floor_body.add_child(node)
	parent.add_child(floor_body)
	return floor_body


## 關卡固定物件的貼圖（BG-21）：七張都讀得到、依世界尺寸縮放或平鋪；缺圖時回傳 null 讓物件退回簡單畫法。
func _test_fixture_art() -> void:
	FixtureArt.clear_cache()
	for id: StringName in [&"door_steel", &"ladder_segment", &"hint_sign", &"switch_box_on", &"switch_box_off", &"breakable_wall", &"gate_shutter"]:
		check(FixtureArt.texture(id) != null, "fixture texture loads: " + String(id))
	var holder := Node2D.new()
	runner.add_child(holder)
	var door := FixtureArt.attach(holder, &"door_steel", Vector2(-14.0, -48.0), Vector2(28.0, 48.0))
	check(door != null and door.show_behind_parent and (door.texture.get_size() * door.scale).is_equal_approx(Vector2(28.0, 48.0)),
			"a fixture sprite is scaled to its world size and sits behind its owner")
	var ladder := FixtureArt.attach(holder, &"ladder_segment", Vector2(-10.0, -152.0), Vector2(20.0, 152.0), true)
	check(ladder != null and ladder.region_enabled and ladder.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED
			and (ladder.region_rect.size * ladder.scale).is_equal_approx(Vector2(20.0, 152.0)), "a tiled fixture repeats at its native density")
	FixtureArt.resize(ladder, Vector2(20.0, 40.0), true)
	check((ladder.region_rect.size * ladder.scale).is_equal_approx(Vector2(20.0, 40.0)), "a tiled fixture can be resized")
	check(FixtureArt.attach(holder, &"test_missing_prop_fixture", Vector2.ZERO, Vector2(8.0, 8.0)) == null,
			"a missing fixture texture returns null instead of breaking the level")
	holder.queue_free()
	FixtureArt.clear_cache()


## 滴水（BG-25）：出水口在承接面上方才有效；水滴由上往下、越落越快，落到水面後濺開再等下一滴；
## 暫停時停住；資料不對就保留靜態圖。
func _test_local_drip() -> void:
	var bucket := load("res://data/environment/scene_props/pawnshop_front/pawnshop_front__leak_bucket.tres") as PropData
	check(bucket != null and bucket.has_drip() and bucket.drip_valid(), "the leak bucket declares a valid drip")
	var barrel := load("res://data/environment/scene_props/rooftop/rooftop__rain_collecting_barrel.tres") as PropData
	check(barrel != null and barrel.has_local_flow() and barrel.local_flow_valid() and not barrel.ripple,
			"the rain barrel uses a local water column instead of rippling the whole image")
	var bad := PropData.new()
	bad.size = Vector2(20, 40)
	bad.drip_period = 1.5
	bad.drip_from = Vector2(0.5, 0.8)
	bad.drip_to = Vector2(0.5, 0.2)
	check(not bad.drip_valid(), "a drip whose mouth is below its surface is rejected")
	bad.drip_from = Vector2(0.5, 0.1)
	bad.drip_to = Vector2(0.5, 0.9)
	bad.drip_period = 0.2
	check(not bad.drip_valid(), "a drip faster than one drop cycle is rejected")
	var node := PropNode.new()
	node.setup(bucket, Vector2(-5000.0, -5000.0))
	runner.add_child(node)
	var drip := node.get_node_or_null("LocalDrip") as LocalDrip
	check(drip != null, "the bucket gets a drip component")
	if drip != null:
		var from := bucket.drip_from * bucket.size
		var to := bucket.drip_to * bucket.size
		drip.clock = 0.0
		check(drip.stage() == &"fall" and drip.drop_position().is_equal_approx(from), "a drop starts at the pipe mouth")
		drip.clock = LocalDrip.FALL_TIME * 0.5
		var half := drip.drop_position()
		check(half.y > from.y and half.y < (from.y + to.y) * 0.5, "the drop accelerates: halfway in time is less than halfway down")
		drip.clock = LocalDrip.FALL_TIME + 0.01
		check(drip.stage() == &"splash" and drip.drop_position().is_equal_approx(to), "the drop splashes on the water surface")
		drip.clock = LocalDrip.FALL_TIME + LocalDrip.SPLASH_TIME + 0.05
		check(drip.stage() == &"wait", "then it waits for the next drop")
		# 不在畫面內就不走時間；進畫面後才走，暫停時停住。
		drip.on_screen = false
		var parked := drip.clock
		await frames(3)
		check(is_equal_approx(drip.clock, parked), "an off-screen drip does not advance")
		drip.on_screen = true
		await frames(3)
		check(not is_equal_approx(drip.clock, parked), "an on-screen drip advances")
		runner.get_tree().paused = true
		var frozen := drip.clock
		await frames(3)
		check(is_equal_approx(drip.clock, frozen), "the drip stops while the game is paused")
		runner.get_tree().paused = false
	node.queue_free()
	var broken := PropNode.new()
	var broken_data := bucket.duplicate() as PropData
	broken_data.drip_to = Vector2(0.5, 0.1)
	broken.setup(broken_data, Vector2(-5000.0, -5000.0))
	runner.add_child(broken)
	check(broken.get_node_or_null("LocalDrip") == null, "invalid drip data keeps the static image")
	broken.queue_free()


## 場景燈具（BG-36）：款式資料、依周圍環境挑款、每一盞燈都有支撐、缺資料時退回安全預設。
func _test_lamp_fixtures() -> void:
	var problems := LampFixtures.problems()
	check(problems.is_empty(), "燈具款式資料有效：%s" % ", ".join(problems))
	var ids := LampFixtures.ids()
	check(ids.size() >= 10, "至少有十款燈具（%d）" % ids.size())
	var mounts := {}
	for id: StringName in ids:
		mounts[LampFixtures.fixture(id)["mount"]] = true
		var prop := LampFixtures.prop(id)
		check(prop != null and prop.has_glow and prop.size.y >= 6.0 and prop.size.y <= 64.0,
				"燈具 %s 有圖、有發光部位，高度在合理範圍" % id)
	check(mounts.size() == LampFixtures.MOUNTS.size(), "四種安裝方式都有燈具（%d）" % mounts.size())
	# 挑款：只挑周圍裝得上的；相鄰的燈輪流換款；指定的都裝不上就用備用款；什麼支撐都沒有就不給燈具。
	var wanted := PackedStringArray(["tube_batten", "highbay_pendant", "bulkhead_wall"])
	var only_wall := {&"ceiling": false, &"wall": true, &"pole": false, &"ground": false}
	var only_ceiling := {&"ceiling": true, &"wall": false, &"pole": false, &"ground": false}
	check(LampFixtures.pick(wanted, only_wall, 0, 0) == &"bulkhead_wall", "只有牆的地方挑壁掛的款式")
	check(LampFixtures.pick(wanted, only_ceiling, 0, 0) != LampFixtures.pick(wanted, only_ceiling, 1, 0), "相鄰兩盞燈用不同款")
	check(LampFixtures.pick(wanted, only_ceiling, 3, 5) == LampFixtures.pick(wanted, only_ceiling, 3, 5), "同一盞燈每次挑到同一款")
	var only_pole := {&"ceiling": false, &"wall": false, &"pole": true, &"ground": false}
	var ceiling_only_kinds := PackedStringArray(["tube_batten", "led_panel"])
	check(LampFixtures.fixture(LampFixtures.pick(ceiling_only_kinds, only_pole, 0, 0)).get("mount") == &"pole", "指定的款式都裝不上時改用立桿的備用款")
	# 可以掛在桿子上的款式：沒有天花板也沒有牆時改掛在桿子上，周圍有原本的支撐時用原本的。
	var lantern := LampFixtures.fixture(&"led_lantern")
	check(LampFixtures.mount_for(lantern, only_pole) == &"pole" and LampFixtures.mount_for(lantern, only_ceiling) == &"ceiling",
			"燈籠沒有天花板時掛在桿子上，有天花板時吊在天花板")
	check(LampFixtures.mount_for(LampFixtures.fixture(&"tube_batten"), only_pole) == &"", "日光燈不能掛在桿子上")
	check(LampFixtures.pick(PackedStringArray(["led_lantern", "neon_tube_bracket"]), only_pole, 0, 0)
			!= LampFixtures.pick(PackedStringArray(["led_lantern", "neon_tube_bracket"]), only_pole, 1, 0), "戶外相鄰兩盞桿子上的燈用不同款")
	var hung := Lamp.new()
	hung.floor_y = 200.0
	hung.use_fixture(&"led_lantern", only_pole)
	check(hung.mount() == &"pole" and hung.is_supported() and not is_zero_approx(hung.support_offset_x()), "掛在桿子上的燈籠有桿子接到地面，桿子在燈的旁邊")
	hung.settle(func(_x: float) -> float: return INF)
	check(not hung.is_supported(), "桿子兩側都沒有地面時回報沒有支撐")
	hung.free()
	var on_wall := Lamp.new()
	on_wall.use_fixture(&"bulkhead_wall")
	check(not on_wall.is_supported(), "壁掛的燈背後沒有牆時回報沒有支撐")
	on_wall.free()
	check(LampFixtures.pick(wanted, {}, 0, 0) == &"", "沒有任何支撐時不給燈具")
	# 不存在的款式：燈照樣亮，只是沒有燈具圖。
	var bare := Lamp.new()
	bare.use_fixture(&"test_missing_prop_lamp")
	runner.get_tree().root.add_child(bare)
	await frames(1)
	check(bare.fixture_id == &"" and bare._light != null and bare._art == null, "不存在的燈具款式退回只有光的安全預設")
	bare.queue_free()
	# 停電：燈具的發光部位跟著熄滅、本體變暗；復電後恢復。
	var powered := Lamp.new()
	powered.ceiling_y = -40.0
	powered.use_fixture(&"highbay_pendant")
	runner.get_tree().root.add_child(powered)
	await frames(2)
	var lit_glow := powered._glow != null and powered._glow.visible
	# 光跟著燈具走：顏色以燈具為主（工礦吊燈是暖色，不是區段預設的青色），光池是區段基準乘上燈具的比例。
	var pendant := LampFixtures.fixture(&"highbay_pendant")
	check(powered.light_color.r > powered.light_color.b and is_equal_approx(powered.light_radius, powered.radius * float(pendant["radius"]))
			and is_equal_approx(powered._light.energy, powered.energy * float(pendant["energy"])), "光的顏色、光池與亮度跟著燈具走")
	LightKit.lamp_power = 0.0
	await frames(2)
	check(lit_glow and not powered._glow.visible and powered._art.self_modulate.r < 0.99, "停電時燈具的發光部位熄滅、本體變暗")
	LightKit.lamp_power = 1.0
	await frames(2)
	check(powered._glow.visible, "復電後燈具的發光部位恢復")
	powered.queue_free()
	# 每份光影設定的燈風格只用存在的款式。
	for file in DirAccess.get_files_at("res://data/lighting"):
		if file.ends_with(".tres"):
			var profile := load("res://data/lighting/" + file) as LightingProfile
			if profile != null and profile.lamp_style != null:
				check(profile.lamp_style.validate().is_empty() and profile.lamp_style.fixtures.size() >= 2,
						"%s 的燈風格至少兩款燈具而且都存在" % file)
	# 第一章每一區：每一盞燈都有燈具與支撐；有兩盞以上的區域至少兩款。
	for file in DirAccess.get_files_at("res://data/levels"):
		if not file.begins_with("ch1_") or not file.ends_with(".tres"):
			continue
		var level := await start_level(load("res://data/levels/" + file) as LevelData)
		var kinds := {}
		var lamps := 0
		var loose := PackedStringArray()
		var tallest := 0.0
		var soft := true
		for node: Node in level.find_children("*", "Node2D", true, false):
			var lamp := node as Lamp
			if lamp == null:
				continue
			lamps += 1
			kinds[lamp.fixture_id] = true
			if lamp.fixture_id == &"" or not lamp.is_supported():
				loose.append("(%d, %d)" % [int(lamp.position.x / 16.0), int(lamp.position.y / 16.0)])
			# 桿子不能太高：約 4 公尺（主角身高的兩倍多），不是三倍高的電線桿。
			if lamp.mount() == &"pole" or lamp.mount() == &"ground":
				tallest = maxf(tallest, lamp.support_floor_y - lamp.position.y)
			var lamp_shaft := lamp._shaft
			soft = soft and (lamp_shaft == null or not lamp_shaft.crisp)
		check(loose.is_empty(), "%s 的每一盞燈都有燈具與支撐（共 %d 盞；沒有的在 %s）" % [file, lamps, ", ".join(loose)])
		check(lamps < 2 or kinds.size() >= 2, "%s 的燈至少兩款（%d 盞、%d 款）" % [file, lamps, kinds.size()])
		check(tallest <= Level.LAMP_POLE_MAX, "%s 的燈桿不超過 %d 像素（最高 %d）" % [file, int(Level.LAMP_POLE_MAX), int(tallest)])
		check(soft, "%s 場景燈的光錐是柔邊" % file)
		await end_level(level)


## 閃爍的燈（BG-35）：三種狀態、供電狀況、光敏安全（一秒內亮暗變化不超過 3 次）、「減少閃光」、電流聲。
func _test_lamp_flicker() -> void:
	check(LampFlicker.problems().is_empty(), "燈的閃法資料有效：%s" % ", ".join(LampFlicker.problems()))
	check(LampFlicker.change_limit() <= LampFlicker.MAX_CHANGES_PER_SECOND and LampFlicker.MAX_CHANGES_PER_SECOND == 3, "亮暗變化的上限是每秒 3 次")
	check(LampFlicker.states().has(&"loose") and LampFlicker.states().has(&"dying"), "有接觸不良與快壞了兩種會閃的狀態")
	for state: StringName in LampFlicker.states():
		check(LampFlicker.pattern_count(state) > 0, "狀態 %s 有閃法" % state)
		for index in LampFlicker.pattern_count(state):
			check(LampFlicker.worst_window(LampFlicker.pattern(state, index)) <= 3, "狀態 %s 的第 %d 條閃法一秒內亮暗變化不超過 3 次" % [state, index])
	check(LampFlicker.worst_window(LampFlicker._parse_pattern("amamamamamamamamamam")) > 3, "每秒閃五次的閃法會被檢查擋下")
	check(LampFlicker._parse_pattern("mmM1").is_empty(), "不是小寫字母的閃法不採用")
	check(LampFlicker.darkest(&"dying") < 0.2 and LampFlicker.buzz(&"dying") > 0.0 and is_zero_approx(LampFlicker.buzz(&"loose")), "快壞的燈多半是暗的而且有電流聲，接觸不良的沒有")
	# 供電狀況：電力不足的區域大部分的燈會閃；穩定的區域與不認得的供電狀況都不閃。
	var counts := {}
	for ordinal in 10:
		var state := LampFlicker.state_for(&"low", ordinal)
		counts[state] = int(counts.get(state, 0)) + 1
	check(int(counts.get(&"loose", 0)) + int(counts.get(&"dying", 0)) > 5 and counts.has(&"loose") and counts.has(&"dying"),
			"電力不足的區域大部分的燈接觸不良或快壞了（%s）" % str(counts))
	check(LampFlicker.state_for(&"stable", 3) == LampFlicker.STABLE and LampFlicker.state_for(&"test_missing_prop_supply", 0) == LampFlicker.STABLE,
			"穩定的區域與不認得的供電狀況都不閃")
	var worn := LampStyle.new()
	worn.flicker_chance = 0.05
	var steady := LampStyle.new()
	steady.flicker_chance = 0.01
	var forced := LampStyle.new()
	forced.supply = &"low"
	check(worn.supply_id() == &"worn" and steady.supply_id() == LampFlicker.STABLE and forced.supply_id() == &"low", "供電狀況可以指定，沒指定時依老舊程度決定")
	forced.supply = &"test_missing_prop_supply"
	check(not forced.validate().is_empty(), "燈風格用了不存在的供電狀況會被資料檢查抓到")

	# 同一盞燈每次進關卡的閃法相同；不同的燈不一定相同。
	var first := await _flicker_lamp(&"loose", 4242)
	var again := await _flicker_lamp(&"loose", 4242)
	check(first.flicker_state == &"loose" and first._pattern == again._pattern and first._pattern_offset == again._pattern_offset, "同一盞燈每次進關卡的閃法相同")
	again.queue_free()
	var reduce_before := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(false)
	await frames(1)
	var run := _simulate_lamp(first, 20.0)
	check(run["worst"] <= 3 and run["worst"] >= 1 and run["low"] < 0.6 and run["high"] > 0.95,
			"接觸不良的燈會暗下來再亮回去，一秒內亮暗變化不超過 3 次（最多 %d 次，%.2f～%.2f）" % [run["worst"], run["low"], run["high"]])
	check(run["glow_follows"] and run["shaft_follows"], "燈閃的時候，光錐與燈具的發光部位跟著一起變化")
	var dying := await _flicker_lamp(&"dying", 99)
	run = _simulate_lamp(dying, 20.0)
	check(run["worst"] <= 3 and run["dark_share"] > 0.6 and run["high"] > 0.6,
			"快壞的燈多半是暗的、偶爾亮起來，一秒內亮暗變化不超過 3 次（最多 %d 次，暗的時間占 %.0f%%）" % [run["worst"], run["dark_share"] * 100.0])
	check(dying.buzz_level() > 0.0 and is_zero_approx(first.buzz_level()), "快壞的燈有電流聲，接觸不良的沒有")
	# 火花：只有快壞的燈有，從暗的突然亮起來那一下才掉；沒有火花在飛的時候不處理。
	check(dying._sparks != null and first._sparks == null and dying._spark_count > 0 and not dying._sparks.is_processing() == not dying._sparks.is_active(),
			"快壞的燈亮起來時掉火花（20 秒內 %d 次），接觸不良的燈沒有" % dying._spark_count)
	check(is_equal_approx(LampBuzz.nearness(0.0), 1.0) and LampBuzz.nearness(LampBuzz.RANGE * 0.5) < 0.3
			and is_zero_approx(LampBuzz.nearness(LampBuzz.RANGE)) and is_zero_approx(LampBuzz.nearness(LampBuzz.RANGE * 3.0)),
			"電流聲離燈越遠越小，超過範圍聽不到")
	# 幾乎全暗的時候不投影（省成本、不佔投影名額），亮回來的那一格就恢復。
	Lamp.flicker_hold = 0.0
	_simulate_lamp(dying, 0.5)
	var dark_shadow := dying._light.shadow_enabled or bool(dying._light.get_meta(LightKit.META_WANTS_SHADOW, false))
	Lamp.flicker_hold = 1.0
	_simulate_lamp(dying, 0.5)
	Lamp.flicker_hold = -1.0
	check(not dark_shadow and dying._light.shadow_enabled and bool(dying._light.get_meta(LightKit.META_WANTS_SHADOW, false)),
			"快壞的燈暗著的時候不投影，亮起來時影子跟著回來")
	# 「減少閃光」：改成緩慢的明暗起伏，沒有突然的變化。
	Settings.set_reduce_flashes(true)
	await frames(1)
	var sparks_before := dying._spark_count
	_simulate_lamp(dying, 0.5)  # 切換設定的那一下先走完
	_simulate_lamp(first, 0.5)
	run = _simulate_lamp(dying, 20.0)
	check(run["worst"] <= 1 and run["max_step"] < 0.03 and run["high"] - run["low"] > 0.1,
			"減少閃光打開時快壞的燈改成緩慢起伏（一秒內最多 %d 次明顯變化、相鄰兩格最多差 %.3f）" % [run["worst"], run["max_step"]])
	run = _simulate_lamp(first, 20.0)
	check(run["worst"] <= 1 and run["max_step"] < 0.03, "減少閃光打開時接觸不良的燈也改成緩慢起伏")
	check(dying._spark_count == sparks_before, "減少閃光打開時不掉火花")
	Settings.set_reduce_flashes(reduce_before)
	await frames(1)
	# 量測用的固定亮度：停在最暗的那一刻。
	Lamp.flicker_hold = 0.0
	run = _simulate_lamp(dying, 1.0)
	Lamp.flicker_hold = -1.0
	check(run["high_end"] < 0.2, "量測時可以把會閃的燈固定在最暗的那一刻")
	# 停電時沒有電流聲；穩定的燈與會脈動的警示燈不閃。
	LightKit.lamp_power = 0.0
	dying._process(0.016)
	check(is_zero_approx(dying.buzz_level()), "停電時快壞的燈沒有電流聲")
	LightKit.lamp_power = 1.0
	var stable := await _flicker_lamp(LampFlicker.STABLE, 7)
	run = _simulate_lamp(stable, 5.0)
	check(run["worst"] == 0 and is_equal_approx(run["low"], 1.0), "穩定的燈不受影響")
	var beacon := Lamp.new()
	beacon.pulse_hz = 0.5
	beacon.use_flicker(&"dying", 5)
	check(beacon.flicker_state == LampFlicker.STABLE, "會脈動的警示燈不再疊上閃爍")
	beacon.free()
	for lamp: Lamp in [first, dying, stable]:
		lamp.queue_free()

	# 第一章：倉庫與倉庫深處電力不足，大部分亮著的燈會閃，而且有電流聲；街道與安全區維持穩定。
	for file: String in ["ch1_warehouse.tres", "ch1_vault.tres", "ch1_street.tres", "ch1_pawnshop.tres", "ch1_lounge.tres",
			"ch1_rooftop.tres", "ch1_booth_alley.tres", "ch1_stall.tres", "ch1_pawnshop_dawn.tres"]:
		var level := await start_level(load("res://data/levels/" + file) as LevelData)
		var lit := 0
		var unstable := 0
		for node: Node in level.find_children("*", "Node2D", true, false):
			var lamp := node as Lamp
			if lamp != null and not lamp.dead:
				lit += 1
				unstable += int(lamp.flicker_state != LampFlicker.STABLE)
		var buzz := level.find_child("LampBuzz", true, false) as LampBuzz
		if file in ["ch1_warehouse.tres", "ch1_vault.tres"]:
			check(lit >= 2 and unstable * 2 > lit, "%s 電力不足：亮著的 %d 盞燈裡有 %d 盞會閃" % [file, lit, unstable])
			check(buzz != null and buzz._player != null, "%s 有快壞的燈的電流聲" % file)
		else:
			check(unstable == 0 and buzz == null, "%s 的燈維持穩定（%d 盞裡 %d 盞會閃）" % [file, lit, unstable])
		await end_level(level)


## 一盞指定狀態的燈（吊在天花板的工礦吊燈），已加入場景、停掉自動更新，由測試手動推進。
func _flicker_lamp(state: StringName, seed_value: int) -> Lamp:
	var lamp := Lamp.new()
	lamp.ceiling_y = -40.0
	lamp.floor_y = 120.0
	lamp.use_fixture(&"highbay_pendant")
	lamp.use_flicker(state, seed_value)
	runner.get_tree().root.add_child(lamp)
	await frames(1)
	lamp.set_process(false)
	return lamp


## 手動推進一盞燈 seconds 秒（每秒 60 格）。回傳：worst＝任何一秒內亮度明顯變化的最多次數（從上一個轉折點往反方向走了門檻以上才算一次）、
## low／high＝最暗與最亮的比例、high_end＝最後一格的比例、max_step＝相鄰兩格最大的變化、dark_share＝比例低於 0.3 的時間占比、
## glow_follows／shaft_follows＝燈具的發光部位與光錐有沒有跟著亮度走。
func _simulate_lamp(lamp: Lamp, seconds: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var threshold := LampFlicker.change_threshold()
	var value := lamp._light.energy / lamp.light_energy
	var ref := value
	var dir := 0
	var events: Array[float] = []
	var low := value
	var high := value
	var max_step := 0.0
	var dark := 0
	var glow_follows := true
	var shaft_follows := true
	var total := int(seconds / dt)
	for frame in total:
		var previous := value
		lamp._process(dt)
		value = lamp._light.energy / lamp.light_energy
		low = minf(low, value)
		high = maxf(high, value)
		max_step = maxf(max_step, absf(value - previous))
		dark += int(value < 0.3)
		glow_follows = glow_follows and lamp._glow != null and lamp._glow.visible == (value > 0.01)
		shaft_follows = shaft_follows and is_equal_approx(lamp._shaft.intensity, clampf(value, 0.0, 1.5))
		if dir == 0:
			if absf(value - ref) >= threshold:
				dir = 1 if value > ref else -1
				ref = value
				events.append(float(frame) * dt)
		elif (value - ref) * float(dir) > 0.0:
			ref = value
		elif absf(value - ref) >= threshold:
			dir = -dir
			ref = value
			events.append(float(frame) * dt)
	var worst := 0
	var start := 0
	for last in events.size():
		while events[last] - events[start] > 1.0:
			start += 1
		worst = maxi(worst, last - start + 1)
	return {"worst": worst, "low": low, "high": high, "high_end": value, "max_step": max_step, "dark_share": float(dark) / float(total),
		"glow_follows": glow_follows, "shaft_follows": shaft_follows}


## 牆上的影子（BG-34）：角色與離牆站著的擺設依光源在背牆上投影；低品質關閉；不累積資源。
func _test_wall_shadows() -> void:
	check(LightQuality.SETTINGS[LightQuality.Tier.LOW]["wall_shadow_lights"] == 0, "光影品質低不在牆上投影（只留腳下的接觸陰影）")
	check(LightQuality.SETTINGS[LightQuality.Tier.MEDIUM]["wall_shadow_lights"] > 0
			and LightQuality.SETTINGS[LightQuality.Tier.HIGH]["wall_shadow_lights"] >= LightQuality.SETTINGS[LightQuality.Tier.MEDIUM]["wall_shadow_lights"]
			and LightQuality.SETTINGS[LightQuality.Tier.HIGH]["wall_shadow_lights"] <= WallShadows.MAX_LIGHTS, "中、高品質投影的燈數在上限內")
	var saved_quality := Settings.get_light_quality()
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	var level := await start_level(load("res://data/levels/ch1_warehouse.tres") as LevelData)
	var shadows := level.find_child("WallShadows", true, false) as WallShadows
	check(shadows != null and shadows.is_enabled() and shadows.visible, "有背牆的關卡在高品質下有牆上的影子")
	if shadows == null:
		Settings.set_light_quality(saved_quality)
		await end_level(level)
		return
	check(shadows.z_index > WorldLayers.BACK_WALL and shadows.z_index < WorldLayers.PROPS and shadows.z_index < WorldLayers.CHARACTER_MIN_Z,
			"影子畫在背牆之上、擺設與角色之下（不會蓋住角色、子彈與介面）")
	check(level.player.is_in_group(WallShadows.CASTER_GROUP), "主角會在牆上投影")
	var enemies := runner.get_tree().get_nodes_in_group(&"enemies")
	# 有腳下接觸陰影的敵人（站在地上的）都會在牆上投影；飛行與固定在牆上的敵人沒有接觸陰影，也不投影。
	var grounded := 0
	var all_cast := true
	for node: Node in enemies:
		var has_contact := node.find_child("ContactShadow", false, false) != null
		grounded += int(has_contact)
		all_cast = all_cast and node.is_in_group(WallShadows.CASTER_GROUP) == has_contact
	check(grounded > 0 and all_cast, "站在地上的敵人會在牆上投影（%d 個裡有 %d 個）" % [enemies.size(), grounded])
	# 輪廓圖只看得到會投影的東西：主角的零件在投影用的顯示層上，接觸陰影、場景燈與背牆不在。
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	var parts := level.player.find_children("*", "Sprite2D", true, false)
	var flagged := not parts.is_empty()
	for part: Node in parts:
		flagged = flagged and ((part as CanvasItem).visibility_layer & WallShadows.CASTER_LAYER) != 0
	check(flagged and (level.player.visibility_layer & WallShadows.CASTER_LAYER) != 0, "主角的零件（%d 個）會畫進輪廓圖" % parts.size())
	var contact := level.player.find_child("ContactShadow", true, false) as CanvasItem
	check(contact != null and (contact.visibility_layer & WallShadows.CASTER_LAYER) == 0, "腳下的接觸陰影不會被當成身體投到牆上")
	var stray := 0
	for node: Node in level.find_children("*", "Node2D", true, false):
		if (node is Lamp or node is BackWall) and ((node as CanvasItem).visibility_layer & WallShadows.CASTER_LAYER) != 0:
			stray += 1
	check(stray == 0, "場景燈與背牆不會畫進輪廓圖")
	check(shadows.active_lights() <= LightQuality.wall_shadow_lights(), "投影的燈不超過品質上限（%d 盞）" % shadows.active_lights())
	var silhouette := shadows.silhouette()
	check(silhouette != null and silhouette.get_size().x > 0.0 and silhouette.get_size().x <= runner.get_viewport().size.x * WallShadows.RESOLUTION + 1.0,
			"輪廓圖是低解析度的")
	# 燈熄滅（停電）：熄滅的燈不再投影。
	var lit_before := shadows.active_lights()
	LightKit.lamp_power = 0.0
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	var dark_lamp_casting := false
	for light: PointLight2D in shadows._chosen:
		if light != null and is_instance_valid(light) and light.get_parent() is Lamp and not light.enabled and shadows.active_lights() >= lit_before and lit_before > 0:
			dark_lamp_casting = true
	check(shadows.active_lights() <= lit_before and not dark_lamp_casting, "燈熄滅後不再投影（%d → %d 盞）" % [lit_before, shadows.active_lights()])
	LightKit.lamp_power = 1.0
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	# 任何登記在場景裡的光（敵人身上的燈、擺設的燈）都會讓角色投影：在主角旁邊放一盞很亮的，它會被選進投影的燈。
	var carried := LightKit.create_point_light(Color(1.0, 0.4, 0.3), 160.0, 3.0)
	level._world.add_child(carried)
	carried.global_position = level.player.global_position + Vector2(40.0, -30.0)
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	check(shadows._chosen.has(carried), "敵人或擺設身上的光也會讓角色在牆上投影")
	carried.enabled = false
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	check(not shadows._chosen.has(carried), "那盞光關掉之後不再投影")
	carried.queue_free()
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	# 離牆站著的擺設會投影，其他擺設不會。
	var casting_props := 0
	var wrong_props := 0
	for node: Node in level.find_children("*", "Node2D", true, false):
		var prop := node as PropNode
		if prop != null and prop.data != null:
			casting_props += int(prop.is_in_group(WallShadows.CASTER_GROUP))
			wrong_props += int(prop.is_in_group(WallShadows.CASTER_GROUP) != (prop.data.wall_shadow and prop.data.light_radius <= 0.0))
	check(casting_props > 0 and wrong_props == 0, "標了會投影的擺設在牆上有影子（%d 件），其他擺設與自己會發光的擺設沒有" % casting_props)
	# 暫停：不畫影子，輪廓圖也不更新。
	shadows.suspended = true
	await frames(WallShadows.REDRAW_EVERY + 1)
	check(not shadows.visible and not shadows.is_processing() and shadows._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"暫停時不畫影子、輪廓圖不更新")
	shadows.suspended = false
	check(shadows.visible and shadows.is_processing(), "恢復後繼續投影")
	# 光影品質低：整個關掉，輪廓圖放掉。
	Settings.set_light_quality(LightQuality.Tier.LOW)
	await frames(3)
	check(not shadows.is_enabled() and not shadows.visible and shadows.find_child("Silhouettes", false, false) == null, "光影品質低時牆上沒有影子，輪廓圖也放掉")
	check(contact.is_inside_tree(), "光影品質低時腳下的接觸陰影還在")
	Settings.set_light_quality(LightQuality.Tier.MEDIUM)
	await frames(int(WallShadows.RESCAN * 60.0) + 30)
	check(shadows.is_enabled() and shadows.active_lights() <= LightQuality.wall_shadow_lights(), "光影品質中重新開啟，投影的燈數依中品質的上限")
	Settings.set_light_quality(saved_quality)
	await end_level(level)
	# 沒有背牆：不建立輪廓圖、不處理。
	var bare := WallShadows.new()
	bare.setup([] as Array[Rect2])
	runner.get_tree().root.add_child(bare)
	await frames(2)
	check(not bare.is_enabled() and not bare.visible and not bare.is_processing(), "沒有背牆的地方不投影")
	bare.queue_free()
	# 反覆進出關卡：節點數不累積。
	var counts: Array[int] = []
	for round_index in 4:
		var again := await start_level(load("res://data/levels/ch1_warehouse.tres") as LevelData)
		await frames(20)
		await end_level(again)
		await frames(4)
		counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	check(counts[3] <= counts[1], "反覆進出關卡後節點數不累積（%s）" % str(counts))
