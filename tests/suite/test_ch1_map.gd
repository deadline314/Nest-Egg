class_name Chapter1MapSuite
extends TestSuite
## 第一章（傘）的地圖（ST-6）：八個區域都能解析、出入口互相對得上、從當舖走得到每一個區域、敵人名單與分佈、
## 道具只有該放的、新遊戲從當舖開始、依序走過每個出入口時玩家出現在對應的位置、世界在區域之間保留。

const IDS: Array[String] = ["pawnshop", "rooftop", "street", "booth_alley", "warehouse", "lounge", "stall", "pawnshop_dawn"]
const ROSTER: Array[StringName] = [&"sweeper", &"collector_gunner", &"collector_brute", &"drone", &"watchdog", &"ch1_inspector"]
const DESIGN_PATH := "res://data/levels/ch1_design.json"
## 遭遇總數與鎖場、迷你頭目的下限（design/13-story-v2/CH01_PACING_V2.md）。
const MIN_ENCOUNTERS := 22
const MAX_ENCOUNTERS := 26
const MIN_LOCKED := 4
const NEW_KIND_GAP := 12.0
const FIRST_ENEMY_DISTANCE := 18
const ALLOWED_WEAPONS: Array[StringName] = [&"melee_dagger"]
## 每個區域的出生地（P）腳底座標用格子表示，走查時用它檢查玩家站得穩。
const TILE := 16.0

var _layouts: Dictionary[String, LevelLayout] = {}
var _datas: Dictionary[String, LevelData] = {}


static func path_of(id: String) -> String:
	return "res://data/levels/ch1_%s.tres" % id


func run() -> void:
	_load_all()
	_test_data()
	_test_props()
	_test_portals()
	_test_roster()
	_test_encounters()
	_test_items()
	_test_entry_point()
	_test_story_hooks()
	_test_prefetch()
	_test_staging()
	await _test_story_flags()
	await _test_scenes_play_through()
	await _test_every_area_builds()
	await _test_locked_encounters_play_through()
	await _test_walkthrough()
	await _test_state_across_areas()


func _load_all() -> void:
	for id in IDS:
		var data := load(path_of(id)) as LevelData
		check(data != null, "chapter 1 area loads: %s" % id)
		if data == null:
			continue
		_datas[id] = data
		_layouts[id] = LevelBuilder.parse(data)


# ---------------------------------------------------------------------------
# 資料
# ---------------------------------------------------------------------------

func _test_data() -> void:
	for id in _datas:
		var data := _datas[id]
		var layout := _layouts[id]
		check(layout.is_valid() and layout.warnings.is_empty(), "%s parses without warnings %s" % [id, layout.warnings])
		check(layout.height == 24 and data.height == 24, "%s is 24 tiles tall like the other levels" % id)
		check(data.persistent_world, "%s keeps the world between areas" % id)
		check(str(data.id) == "ch1_%s" % id, "%s has a matching level id (%s)" % [id, data.id])
		check(data.validate_lighting().is_empty(), "%s lighting is valid %s" % [id, data.validate_lighting()])
		check(data.environment != null and data.environment.validate().is_empty(), "%s environment is valid %s" % [id, data.environment.validate() if data.environment != null else "missing"])
		check(not data.lighting_zones.is_empty(), "%s has a lighting zone" % id)
		check(data.show_chapter_card == (id == "pawnshop"), "only the first area shows the chapter card (%s)" % id)
		for resource in data.legend.values():
			if resource is EnemyData:
				check((resource as EnemyData).validate().is_empty(), "%s: enemy data valid %s" % [id, resource.id])
			elif resource is MechanismData:
				check((resource as MechanismData).validate().is_empty(), "%s: mechanism data valid %s" % [id, resource.id])
			elif resource is PortalData:
				check((resource as PortalData).validate().is_empty(), "%s: portal data valid %s" % [id, (resource as PortalData).validate()])
	check(_datas["pawnshop_dawn"].complete_after_intro and not _datas["pawnshop"].complete_after_intro, "only the dawn pawnshop ends the chapter after its intro")
	check(_datas["pawnshop_dawn"].layout_path == _datas["pawnshop"].layout_path, "the dawn pawnshop reuses the pawnshop map")
	check(_datas["pawnshop_dawn"].lighting_zones[0].profile != _datas["pawnshop"].lighting_zones[0].profile, "the dawn pawnshop has its own lighting")
	check(Story.chapter_ids().has(_datas["pawnshop"].chapter), "the chapter exists in the story data (%s)" % _datas["pawnshop"].chapter)


## 地圖上的擺設（場景專屬物件）都找得到資料，而且落在地表上。
func _test_props() -> void:
	for id in _datas:
		var data := _datas[id]
		var layout := _layouts[id]
		var dirs := data.environment.prop_dirs()
		for entry in data.load_props():
			var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
			check(prop != null, "%s: prop exists %s" % [id, entry["id"]])
			if prop == null:
				continue
			var placed := PropPlacement.resolve(entry, prop, layout)
			check(not placed.is_empty(), "%s: prop %s has ground under it (column %d)" % [id, entry["id"], int(entry["x"])])
			if not placed.is_empty():
				var rect: Rect2 = placed["rect"]
				check(rect.position.x >= 0.0 and rect.end.x <= layout.pixel_size().x, "%s: prop %s stays inside the map" % [id, entry["id"]])


# ---------------------------------------------------------------------------
# 出入口
# ---------------------------------------------------------------------------

func _portals_of(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spawn in _layouts[id].spawns:
		if spawn["resource"] is PortalData:
			result.append(spawn)
	return result


func _area_id_of_path(path: String) -> String:
	for id in IDS:
		if path_of(id) == path:
			return id
	return ""


func _test_portals() -> void:
	var all_ids: Dictionary[StringName, String] = {}
	var edges: Dictionary[String, Array] = {}
	for id in IDS:
		edges[id] = []
	var locked := 0
	for id in IDS:
		if id == "pawnshop_dawn":
			continue  # 與當舖同一張地圖，出入口相同
		for spawn in _portals_of(id):
			var portal := spawn["resource"] as PortalData
			var cell: Vector2i = spawn["cell"]
			check(not all_ids.has(portal.id), "portal id is unique in the chapter: %s" % portal.id)
			all_ids[portal.id] = id
			var layout := _layouts[id]
			check(layout.cell(cell.x, cell.y + 1) == "#" or layout.cell(cell.x, cell.y + 1) == "=", "%s: portal %s stands on the ground" % [id, portal.id])
			if portal.style == "ladder":
				# 室內的梯子要一路通到天花板（頭上沒有天花板的屋頂梯子不檢查）。
				var free_rows := 0
				var y := cell.y
				while y >= 0 and layout.cell(cell.x, y) != "#":
					free_rows += 1
					y -= 1
				if y >= 0:
					check(float(portal.height) >= 0.8 * float(free_rows * layout.tile_size), "%s: the ladder %s reaches the ceiling (%d of %d px)" % [id, portal.id, portal.height, free_rows * layout.tile_size])
			if portal.is_locked_door():
				locked += 1
				check(not portal.locked_text.is_empty(), "%s: a locked door says why (%s)" % [id, portal.id])
				continue
			var target_id := _area_id_of_path(portal.target_level)
			check(target_id != "", "%s: portal %s leads to a chapter 1 area (%s)" % [id, portal.id, portal.target_level])
			if target_id == "":
				continue
			edges[id].append(target_id)
			if portal.target_portal != &"":
				var found := false
				for other in _portals_of(target_id):
					if (other["resource"] as PortalData).id == portal.target_portal:
						found = true
				check(found, "%s: portal %s arrives at an existing portal (%s in %s)" % [id, portal.id, portal.target_portal, target_id])
	check(locked == 2, "two locked doors: the basement and the market road (%d)" % locked)
	# 從當舖出發，沿著出入口走得到每一個區域。
	var seen: Dictionary[String, bool] = {"pawnshop": true}
	var queue: Array[String] = ["pawnshop"]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for target: String in edges[current]:
			if not seen.has(target):
				seen[target] = true
				queue.append(target)
	for id in IDS:
		check(seen.has(id), "%s can be reached from the pawnshop by walking through portals" % id)
	# 單向：從倉庫去復原館之後，復原館沒有回倉庫的門。
	check(not edges["lounge"].has("warehouse"), "the upper walkway is one way")
	check(edges["warehouse"].has("lounge") and edges["lounge"].has("stall") and edges["stall"].has("pawnshop_dawn"), "the chapter ends warehouse, lounge, stall, home")


# ---------------------------------------------------------------------------
# 敵人與道具
# ---------------------------------------------------------------------------

func _enemy_spawns(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spawn in _layouts[id].spawns:
		if spawn["resource"] is EnemyData:
			result.append(spawn)
	return result


func _design() -> Dictionary:
	var json := load(DESIGN_PATH) as JSON
	return (json.data as Dictionary)["areas"] if json != null and typeof(json.data) == TYPE_DICTIONARY else {}


## 設計資料裡某個區域所有遭遇的成員總數（＝擺在地圖上的敵人數）。
func _design_members(id: String) -> int:
	var members := 0
	for encounter: Dictionary in _design()[id]["encounters"]:
		members += (encounter["members"] as Array).size()
	return members


func _test_roster() -> void:
	var kinds: Dictionary[StringName, int] = {}
	var placed: Dictionary[String, int] = {}
	for id in IDS:
		if id == "pawnshop_dawn":
			continue
		for spawn in _enemy_spawns(id):
			var enemy := spawn["resource"] as EnemyData
			kinds[enemy.id] = kinds.get(enemy.id, 0) + 1
			placed[id] = placed.get(id, 0) + 1
	check(kinds.size() == ROSTER.size(), "the chapter uses exactly six kinds of enemy (%s)" % [kinds.keys()])
	for id in ROSTER:
		check(kinds.has(id), "the roster enemy appears on the map: %s" % id)
	check(kinds.get(&"watchdog", 0) == 1, "one watchdog (mini-boss A)")
	check(kinds.get(&"ch1_inspector", 0) == 2, "two inspectors (the mini-bosses of the blockade and the vault)")
	# 擺在地圖上的敵人數＝設計資料裡各場遭遇的成員總數（設計資料由產生器輸出，兩邊一致才算數）。
	var design := _design()
	for id in design:
		var members := 0
		for encounter: Dictionary in design[id]["encounters"]:
			members += (encounter["members"] as Array).size()
		check(placed.get(id, 0) == members, "%s: enemies on the map match the encounter table (%d vs %d)" % [id, placed.get(id, 0), members])
	for id in ["pawnshop", "rooftop", "booth_alley", "lounge", "stall"]:
		check(_enemy_spawns(id).is_empty(), "%s is a safe area without enemies" % id)
	# 每一個出入口進來，最近的敵人都在 18 格以外；出生點也一樣。
	for id in _datas:
		var layout := _layouts[id]
		var entries: Array[float] = [layout.player_start.x / TILE]
		for pos in layout.checkpoints:
			entries.append(pos.x / TILE)
		for spawn in _portals_of(id):
			if not (spawn["resource"] as PortalData).is_locked_door():
				entries.append(float((spawn["cell"] as Vector2i).x) + 0.5)
		for spawn in _enemy_spawns(id):
			var x := float((spawn["cell"] as Vector2i).x) + 0.5
			for entry in entries:
				check(absf(x - entry) >= FIRST_ENEMY_DISTANCE, "%s: enemy at column %d is %d+ tiles from the entrance at %d" % [id, int(x), FIRST_ENEMY_DISTANCE, int(entry)])
	# 新種類出現的間隔：依路線（街道、倉庫）第一次遇到的種類，同一個區域裡相隔至少 20 格。
	var seen_kinds: Dictionary[StringName, bool] = {}
	for id in ["street", "warehouse"]:
		var first_x: Dictionary[StringName, float] = {}
		for spawn in _enemy_spawns(id):
			var enemy_id := (spawn["resource"] as EnemyData).id
			if seen_kinds.has(enemy_id):
				continue
			var x := float((spawn["cell"] as Vector2i).x)
			first_x[enemy_id] = minf(first_x.get(enemy_id, INF), x)
		var xs: Array = first_x.values()
		xs.sort()
		for i in range(1, xs.size()):
			check(float(xs[i]) - float(xs[i - 1]) >= NEW_KIND_GAP, "%s: new enemy kinds are introduced at least %d tiles apart (%s)" % [id, int(NEW_KIND_GAP), xs])
		for enemy_id in first_x:
			seen_kinds[enemy_id] = true
	# 示範段落：街道第一名敵人之前沒有任何敵人。
	var street_enemies := _enemy_spawns("street")
	var first_cell := 9999
	for spawn in street_enemies:
		first_cell = mini(first_cell, (spawn["cell"] as Vector2i).x)
	check(first_cell >= 49, "the street's tutorial fights start after column 49 (%d)" % first_cell)
	# 難度曲線：街道上第一種是清掃兵（遠程、單發），收帳人槍手、打手、無人機與督察依序加入。
	street_enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["cell"] as Vector2i).x < (b["cell"] as Vector2i).x)
	var introduced: Array[StringName] = []
	for spawn in street_enemies:
		var enemy_id := (spawn["resource"] as EnemyData).id
		if not introduced.has(enemy_id):
			introduced.append(enemy_id)
	check(introduced == [&"sweeper", &"collector_gunner", &"drone", &"collector_brute", &"ch1_inspector"], "the street introduces: sweeper, gunner, drone, brute, inspector (%s)" % [introduced])


## 鎖場遭遇（ST-11）：總數與鎖場數、閘門成對且頻道對得上、範圍在地圖內且不重疊、鎖場範圍內的敵人數與設計資料一致、
## 成員與增援不超過同屏上限；戰鬥區都有迴圈、獎勵、秘密、地標與垂直空間的說明。
func _test_encounters() -> void:
	var design := _design()
	check(not design.is_empty(), "the design data exists (%s)" % DESIGN_PATH)
	var total := 0
	var locked := 0
	for id in design:
		for encounter: Dictionary in design[id]["encounters"]:
			total += 1
			locked += 1 if bool(encounter["lock"]) else 0
	check(total >= MIN_ENCOUNTERS and total <= MAX_ENCOUNTERS, "%d to %d encounters in the chapter (%d)" % [MIN_ENCOUNTERS, MAX_ENCOUNTERS, total])
	check(locked >= MIN_LOCKED, "at least %d locked encounters (%d)" % [MIN_LOCKED, locked])
	var zone_count := 0
	for id in IDS:
		if id == "pawnshop_dawn":
			continue
		var layout := _layouts[id]
		var zones: Array[Dictionary] = []
		var gate_cells: Dictionary[StringName, Array] = {}
		for spawn in layout.spawns:
			var res: Resource = spawn["resource"]
			if not (res is MechanismData):
				continue
			var mechanism := res as MechanismData
			if mechanism.kind == MechanismData.Kind.ENCOUNTER:
				zones.append(spawn)
			elif mechanism.kind == MechanismData.Kind.GATE and mechanism.arena_gate:
				if not gate_cells.has(mechanism.channel):
					gate_cells[mechanism.channel] = []
				gate_cells[mechanism.channel].append((spawn["cell"] as Vector2i).x)
		zone_count += zones.size()
		var ranges: Array[Vector2i] = []
		for spawn in zones:
			var zone := spawn["resource"] as MechanismData
			var center := (spawn["cell"] as Vector2i).x
			var left := center - zone.size_tiles.x / 2
			var right := center + zone.size_tiles.x / 2
			check(left >= 1 and right <= layout.width - 2, "%s: the locked zone %s stays inside the map (%d..%d)" % [id, zone.id, left, right])
			var gates: Array = gate_cells.get(zone.channel, [])
			gates.sort()
			check(gates.size() == 2 and gates[0] == left and gates[1] == right, "%s: %s has one arena gate at each end (%s vs %d..%d)" % [id, zone.id, gates, left, right])
			for other in ranges:
				check(right < other.x or left > other.y, "%s: locked zones do not overlap (%s)" % [id, zone.id])
			ranges.append(Vector2i(left, right))
			var inside := 0
			for enemy_spawn in _enemy_spawns(id):
				var x := (enemy_spawn["cell"] as Vector2i).x
				inside += 1 if x >= left and x <= right else 0
			check(inside >= 1 and inside <= 4, "%s: %s has one to four members inside (%d)" % [id, zone.id, inside])
			check(inside + zone.reinforcements.size() <= 6, "%s: %s keeps at most six enemies alive at once (%d + %d)" % [id, zone.id, inside, zone.reinforcements.size()])
	var locked_in_design := 0
	for id in design:
		for encounter: Dictionary in design[id]["encounters"]:
			locked_in_design += 1 if bool(encounter["lock"]) else 0
	check(zone_count == locked_in_design, "every locked encounter in the design is on a map (%d vs %d)" % [zone_count, locked_in_design])
	for id in design:
		if not bool(design[id]["combat"]):
			continue
		for key in ["loop", "reward", "secret", "landmark", "vertical"]:
			check(not str((design[id]["features"] as Dictionary).get(key, "")).is_empty(), "%s: the combat area documents its %s" % [id, key])


func _test_items() -> void:
	var med := 0
	var cell := 0
	var small := 0
	var large := 0
	var docs := 0
	var disk := 0
	var weapons := 0
	for id in IDS:
		if id == "pawnshop_dawn":
			continue
		for spawn in _layouts[id].spawns:
			var res: Resource = spawn["resource"]
			if res is ConsumableData:
				if (res as ConsumableData).id == &"med_injector":
					med += 1
				elif (res as ConsumableData).id == &"shield_cell":
					cell += 1
			elif res is CreditPileData:
				if (res as CreditPileData).value >= 40:
					large += 1
				else:
					small += 1
			elif res is StoryItemData:
				if (res as StoryItemData).is_collectible():
					docs += 1
					check((res as StoryItemData).chapter == _datas[id].chapter, "%s: the document belongs to this chapter (%s)" % [id, (res as StoryItemData).id])
				else:
					disk += 1
			elif res is WeaponData:
				weapons += 1
				check(ALLOWED_WEAPONS.has((res as WeaponData).id), "%s: only the dagger lies around in chapter 1 (%s)" % [id, (res as WeaponData).id])
	check(med >= 3 and med <= 6, "three to six med injectors (%d)" % med)
	check(cell == 1, "one shield cell (%d)" % cell)
	check(small >= 12 and small <= 30, "twelve to thirty small credit piles (%d)" % small)
	check(large >= 2 and large <= 5, "two to five large credit piles (%d)" % large)
	check(docs == 5, "five documents (%d)" % docs)
	check(disk == 1, "one key item: the data disk (%d)" % disk)
	check(weapons == 1, "one optional weapon: the dagger (%d)" % weapons)


func _test_entry_point() -> void:
	# 新遊戲從當舖開始（Main 的入口與第一個區域一致）。
	var main_script := load("res://game/main.gd") as GDScript
	check(main_script.source_code.contains(path_of("pawnshop")), "a new game starts at the pawnshop")


# ---------------------------------------------------------------------------
# 劇情接點
# ---------------------------------------------------------------------------

## 每個區域引用的場景都存在；出入口要求的旗標一定有某個場景會設定它。
func _test_story_hooks() -> void:
	var flags_set: Dictionary[StringName, bool] = {}
	for id in Story.scene_ids():
		var scene: Variant = Story._scenes[id]
		if typeof(scene) == TYPE_DICTIONARY:
			for flag: Variant in (scene as Dictionary).get("set_flags", []):
				flags_set[StringName(str(flag))] = true
	for id in _datas:
		var data := _datas[id]
		if data.intro_scene != &"":
			check(Story.has_scene(data.intro_scene), "%s: the intro scene exists (%s)" % [id, data.intro_scene])
		for scene in data.story_triggers:
			check(Story.has_scene(StringName(scene)), "%s: the trigger scene exists (%s)" % [id, scene])
		for channel in data.channel_scenes:
			check(Story.has_scene(data.channel_scenes[channel]), "%s: the scene for channel %s exists" % [id, channel])
		for resource in data.legend.values():
			if resource is PortalData and (resource as PortalData).requires_flag != &"":
				check(flags_set.has((resource as PortalData).requires_flag), "%s: some scene sets the flag that opens %s (%s)" % [id, (resource as PortalData).id, (resource as PortalData).requires_flag])
	check(str(Story.death_scene_entry(&"ch1_kasa", &"flood", 1).get("scene", "")) == "ch1_c09_wake", "the first death plays the recovery room scene (before the respawn)")
	check(Story.respawn_scene_ids(&"ch1_kasa", 0).is_empty(), "no death, no recovery scene")
	check(_datas["pawnshop"].intro_scene == &"ch1_c00_prologue" and Story._scenes["ch1_c00_prologue"].get("then") == "ch1_c01_shop", "the prologue leads into the shop scene")


## 構圖：第一章每個動畫過場的演員腳底都在對話框之上；檢查本身也要抓得到違規的演出。
func _test_staging() -> void:
	var bad := {"steps": [{"do": "scene", "id": "x", "pos": [320, 180], "zoom": 1.0}, {"do": "actor", "id": "a", "pos": [100, 300]}]}
	check(CutsceneChecker.staging_problems("test_bad_staging", bad).size() == 1, "an actor standing under the dialogue box is reported once")
	var moved := {"steps": [{"do": "scene", "id": "x", "pos": [320, 180], "zoom": 1.0}, {"do": "actor", "id": "a", "pos": [100, 240]}, {"do": "move", "id": "a", "to": [200, 330]}]}
	check(CutsceneChecker.staging_problems("test_bad_staging", moved).size() == 1, "walking down behind the dialogue box is reported")
	var zoomed := {"steps": [{"do": "scene", "id": "x", "pos": [320, 180], "zoom": 1.0}, {"do": "actor", "id": "a", "pos": [100, 240]}, {"do": "camera", "pos": [100, 240], "zoom": 2.5}, {"do": "remove", "id": "a"}]}
	check(CutsceneChecker.staging_problems("test_ok_staging", zoomed).is_empty(), "a camera that puts the feet at the middle of the screen is fine")
	var checked := 0
	for id in Story.scene_ids():
		var scene: Dictionary = Story._scenes[id]
		if not str(id).begins_with("ch1_") or str(scene.get("mode", "")) != "animated":
			continue
		checked += 1
		var problems := CutsceneChecker.staging_problems(str(id), scene)
		check(problems.is_empty(), "%s keeps the actors' feet above the dialogue box: %s" % [id, problems])
	check(checked >= 10, "the chapter's animated scenes were checked (%d)" % checked)


## 預載：區域與過場用到的貼圖路徑找得到、請求只發一次、缺檔不報錯。
func _test_prefetch() -> void:
	AssetPrefetch.clear()
	var street := _datas["street"]
	var paths := AssetPrefetch.level_texture_paths(street)
	check(paths.size() > 20, "the street lists its textures for prefetching (%d)" % paths.size())
	var props_ok := false
	for path in paths:
		if path.contains("harbor_street__") and not path.contains("_n.") and not path.contains("_glow."):
			props_ok = ResourceLoader.exists(path)
			break
	check(props_ok, "the listed prop textures exist")
	var stage_paths := AssetPrefetch.scene_texture_paths(&"ch1_c00_prologue")
	check(stage_paths.size() > 0 and stage_paths.has("res://art/environment/scenes/pawnshop_front.webp"), "a scene chain lists the stage art of every part (%d)" % stage_paths.size())
	var sent := AssetPrefetch.warm_neighbors(_datas["pawnshop"])
	check(sent > 0, "warming the neighbors of the pawnshop sends requests (%d)" % sent)
	check(AssetPrefetch.warm_neighbors(_datas["pawnshop"]) == 0, "the same request is not sent twice")
	check(AssetPrefetch.request(PackedStringArray(["res://art/no_such_prefetch_texture.png"])) == 0, "a missing texture is skipped without an error")
	check(AssetPrefetch.warm_level("res://data/levels/ch1_street.tres") >= 0, "an area can be warmed by its path")
	check(AssetPrefetch.warm_level("res://data/levels/no_such_level.tres") == 0 and AssetPrefetch.warm_level(null) == 0, "a missing path or nothing is skipped")


## 場景結束時設旗標：吃完晚飯才能上樓，聽完差事才能出門。
func _test_story_flags() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	check(not GameState.has_flag(&"ch1_dinner_done"), "no flags at the start of a run")
	Story.auto_skip = true
	Story.play(&"ch1_c02_dinner")
	await frames(6)
	check(GameState.has_flag(&"ch1_dinner_done"), "finishing the dinner sets its flag")
	check(not GameState.has_flag(&"ch1_heard_brief"), "the rooftop flag is still unset")
	Story.play(&"ch1_c03a_roof")
	await frames(10)
	check(GameState.has_flag(&"ch1_heard_brief"), "finishing the rooftop scene sets its flag (the first part chains into the second)")
	Story.reset_progress()


## 每個動畫過場真的能從頭播到尾（時間加速）：舞台載得進來、演員建得出來、每個步驟都跑得完，沒有腳本錯誤。
func _test_scenes_play_through() -> void:
	var previous_auto := Story.auto_skip
	var previous_scale := Engine.time_scale
	Story.auto_skip = false
	Engine.time_scale = 40.0
	for id: String in Story.scene_ids():
		if not id.begins_with("ch1_") or str(Story._scenes[id].get("mode", "")) != "animated":
			continue
		if Story._scenes[id].has("then") and not id.ends_with("prologue") and not id.ends_with("c03a_roof"):
			continue
		var done := [false]
		var waiter := func() -> void:
			await Story.play_and_wait(StringName(id), false)
			done[0] = true
		waiter.call()
		var waited := 0
		while not done[0] and waited < 1500:
			await physics_frames(1)
			waited += 1
			_press_advance()
		check(done[0], "animated scene plays through to its end: %s (%d frames)" % [id, waited])
		check(not Story.is_cinematic_active(), "back in the game after %s" % id)
		Story.reset_progress()
	Engine.time_scale = previous_scale
	Story.auto_skip = previous_auto


## 模擬玩家按下推進：打字機演完、直接進下一句。
func _press_advance() -> void:
	var player: CutscenePlayer = Story._player
	if player == null or not player.is_running():
		return
	if player._dialogue.visible:
		player._dialogue.complete()
		player._advance_requested = true


# ---------------------------------------------------------------------------
# 建立與走查
# ---------------------------------------------------------------------------

func _test_every_area_builds() -> void:
	for id in IDS:
		var level := await start_level(_datas[id])
		check(is_instance_valid(level.player), "%s: the player spawns" % id)
		await physics_frames(20)
		check(level.player.is_on_floor(), "%s: the player stands on the ground at the start" % id)
		check(level.player.global_position.y < _layouts[id].pixel_size().y, "%s: the player did not fall out of the map" % id)
		await end_level(level)


## 依序走過 當舖 → 街道 → 電話亭巷 → 街道 → 倉庫 → 復原館 → 麵攤 → 天亮的當舖：每次玩家都出現在目標出入口，
## 沿途的狀態（走過的區域、旗標）保留，最後一個區域結束本章。
func _test_walkthrough() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	# 前兩個門要先看過劇情：晚飯之後才能上樓，屋頂的差事之後才能出門（場景結束時設旗標）。
	var locked_front := (load(path_of("pawnshop")) as LevelData).legend
	var stairs_flag := &""
	var front_flag := &""
	for resource in locked_front.values():
		if resource is PortalData and (resource as PortalData).id == &"pawn_stairs":
			stairs_flag = (resource as PortalData).requires_flag
		elif resource is PortalData and (resource as PortalData).id == &"pawn_front":
			front_flag = (resource as PortalData).requires_flag
	check(stairs_flag != &"" and front_flag != &"", "the stairs and the front door wait for the story (%s, %s)" % [stairs_flag, front_flag])
	var route: Array[Array] = [
		["pawnshop", &"pawn_front", "street"],
		["street", &"street_booth", "booth_alley"],
		["booth_alley", &"booth_street", "street"],
		["street", &"street_warehouse", "warehouse"],
		["warehouse", &"wh_upper", "lounge"],
		["lounge", &"lounge_exit", "stall"],
		["stall", &"stall_home", "pawnshop_dawn"],
	]
	var level := await spawn_level(_datas["pawnshop"])
	var front: Portal = level._portals.get(&"pawn_front")
	check(not front.try_use(), "the front door stays shut before the rooftop")
	check(Story.has_scene(&"ch1_c02_dinner") and Story.has_scene(&"ch1_c03b_roof"), "the dinner and the rooftop scenes exist")
	GameState.set_flag(front_flag)
	for step in route:
		check(str(level.data.id) == "ch1_%s" % step[0], "walking: now in %s" % step[0])
		var requested := [""]
		level.area_requested.connect(func(path: String) -> void: requested[0] = path)
		var portal: Portal = level._portals.get(step[1])
		check(portal != null, "walking: %s has portal %s" % [step[0], step[1]])
		if portal == null:
			break
		check(portal.try_use(), "walking: portal %s opens" % step[1])
		check(requested[0] == path_of(step[2]), "walking: %s leads to %s (%s)" % [step[1], step[2], requested[0]])
		var target_portal := GameState.pending_portal
		await end_level(level)
		level = await spawn_level(_datas[step[2]])
		if target_portal != &"":
			var arrival: Portal = level._portals.get(target_portal)
			check(arrival != null and level.player.global_position.distance_to(arrival.global_position) < 2.0, "walking: arrives at %s" % target_portal)
	# 最後一個區域：進場後結束本章。
	var done := [false]
	level.completed.connect(func() -> void: done[0] = true)
	# 章末卡停留幾秒才結束，所以多等一會兒。
	for i in 30:
		if done[0]:
			break
		await physics_frames(20)
	check(str(level.data.id) == "ch1_pawnshop_dawn" and done[0], "the dawn pawnshop ends the chapter after its intro")
	await end_level(level)


## 每場鎖場都能真的打完：把玩家放進範圍 → 閘門關上 → 一直打倒範圍內的敵人（含增援）→ 閘門打開、不再鎖人。
func _test_locked_encounters_play_through() -> void:
	for id in ["street", "warehouse"]:
		GameState.start_new_run(GameState.difficulties[1])
		var level := await spawn_level(_datas[id])
		level.player.health.setup(9999, 0.0)
		var zones: Array[EncounterZone] = []
		for node in level._entities.get_children():
			if node is EncounterZone:
				zones.append(node)
		for zone in zones:
			var floor_y := zone.global_position.y
			level.player.global_position = zone.global_position + Vector2(0.0, -2.0)
			level.player.velocity = Vector2.ZERO
			await physics_frames(40)
			check(zone.state == &"active", "%s: %s starts when the player walks in (%s)" % [id, zone.data.id, zone.state])
			var gates := 0
			for node in level._entities.get_children():
				if node is Gate and (node as Gate).data.channel == zone.data.channel and not (node as Gate).is_open:
					gates += 1
			check(gates == 2, "%s: both arena gates of %s close (%d)" % [id, zone.data.id, gates])
			var guard := 0
			while zone.state == &"active" and guard < 60 * 25:
				for enemy in get_tree_enemies_of(level):
					if is_instance_valid(enemy) and not enemy.is_dying() and absf(enemy.global_position.x - zone.global_position.x) < zone.data.size_tiles.x * 8.0:
						var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
						lethal.ignore_invulnerability = true
						lethal.bypass_guard = true
						enemy.health.take_damage(lethal)
				level.player.global_position = Vector2(zone.global_position.x, floor_y - 2.0)
				await physics_frames(15)
				guard += 15
			check(zone.state == &"cleared", "%s: %s can be fought to the end (%d frames)" % [id, zone.data.id, guard])
			var closed := 0
			for node in level._entities.get_children():
				if node is Gate and (node as Gate).data.channel == zone.data.channel and not (node as Gate).is_open:
					closed += 1
			check(closed == 0, "%s: the arena gates of %s open again" % [id, zone.data.id])
		await end_level(level)


func get_tree_enemies_of(level: Level) -> Array[Node]:
	return level.get_tree().get_nodes_in_group(&"enemies")


## 在街道打倒一名清掃兵、撿起道具，離開再回來仍保留；死亡後回到最近的電話亭所在的區域。
func _test_state_across_areas() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var street := await spawn_level(_datas["street"])
	var before := _alive_enemies(street)
	var expected := _design_members("street")
	check(before == expected, "the street starts with its enemies (%d vs %d)" % [before, expected])
	var victim: Enemy = null
	for node in street.get_tree().get_nodes_in_group(&"enemies"):
		if street.is_ancestor_of(node) and (node as Enemy).data.id == &"sweeper":
			victim = node
			break
	check(victim != null, "found a sweeper to defeat")
	if victim != null:
		victim.health.take_damage(DamageInfo.create(9999, Combat.Team.PLAYER, &"test"))
	await frames(2)
	var portal: Portal = street._portals.get(&"street_booth")
	portal.try_use()
	await end_level(street)
	var booth := await spawn_level(_datas["booth_alley"])
	var phone: Checkpoint = null
	for node in booth._entities.get_children():
		if node is Checkpoint:
			phone = node
	check(phone != null, "the booth alley has a phone booth")
	if phone != null:
		GameState.set_checkpoint(phone.global_position, booth.player.checkpoint_snapshot())
		check(GameState.checkpoint_level_path == path_of("booth_alley"), "the phone booth remembers its area")
	await end_level(booth)
	GameState.pending_portal = &"street_booth"
	var again := await spawn_level(_datas["street"])
	check(_alive_enemies(again) == expected - 1, "a defeated sweeper does not come back (%d)" % _alive_enemies(again))
	await end_level(again)


func _alive_enemies(level: Level) -> int:
	var count := 0
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		if level.is_ancestor_of(node) and not (node as Enemy).is_dying():
			count += 1
	return count
