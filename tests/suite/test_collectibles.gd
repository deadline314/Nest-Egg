class_name CollectiblesSuite
extends TestSuite
## 背景故事收集與隱藏房間（NE-31）：文件與錄音的資料、收集進度、撿取與提示、背包閱讀、
## 跟著本輪進度保留、裂縫牆打開隱藏房間。

const MAP_PATH := "res://tests/fixtures/secret_map.json"
const WALL_PATH := "res://data/props/cracked_wall.tres"
const OPEN_ITEM := &"doc_shaft_memo"
const HIDDEN_ITEM := &"doc_nest_log"


func run() -> void:
	_test_data()
	await _test_pickup_and_progress()
	await _test_persistence()
	await _test_hidden_room()
	await _test_inventory_page()


static func level_data() -> LevelData:
	var data := LevelData.new()
	data.id = &"secret_test"
	data.layout_path = MAP_PATH
	data.legend = {
		"E": load("res://data/story_items/%s.tres" % OPEN_ITEM),
		"D": load("res://data/story_items/%s.tres" % HIDDEN_ITEM),
		"x": load(WALL_PATH),
	}
	return data


func _test_data() -> void:
	var per_chapter: Dictionary[StringName, int] = {}
	for item in StoryItems.catalog():
		if not item.is_collectible():
			continue
		check(item.validate().is_empty(), "collectible valid: %s %s" % [item.id, item.validate()])
		check(item.body.length() <= StoryItemData.MAX_BODY_LENGTH, "collectible text fits the inventory: %s" % item.id)
		check(Story.chapter_ids().has(item.chapter), "collectible chapter exists: %s -> %s" % [item.id, item.chapter])
		per_chapter[item.chapter] = per_chapter.get(item.chapter, 0) + 1
		if item.play_scene != &"":
			check(Story.has_scene(item.play_scene), "collectible scene exists: %s -> %s" % [item.id, item.play_scene])
	check(per_chapter.get(&"chapter_01", 0) == 5 and per_chapter.get(&"chapter_02", 0) == 7, "fixed collectible counts per chapter %s" % per_chapter)
	check(StoryItems.collectible_total(&"chapter_02") == 7 and StoryItems.collectible_total(&"nope") == 0, "collectible_total counts per chapter")
	check(StoryItems.collectible_chapters().size() == 2, "two chapters have collectibles")
	# 壞資料會被回報。
	var bad := StoryItemData.new()
	bad.id = &"bad_doc"
	bad.display_name = "壞文件"
	bad.description = "x"
	bad.category = StoryItemData.Category.DOCUMENT
	bad.trigger = StoryItemData.Trigger.RUN_START
	bad.body = "字".repeat(StoryItemData.MAX_BODY_LENGTH + 1)
	check(bad.validate().size() >= 3, "invalid collectible is reported (chapter, length, trigger)")
	var wall := load(WALL_PATH) as BreakableData
	check(wall != null and wall.validate().is_empty() and wall.look == BreakableData.Look.WALL, "cracked wall data valid")


func _find_pickup(level: Level, id: StringName) -> CollectiblePickup:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollectiblePickup and (node as CollectiblePickup).item.id == id:
			return node
		stack.append_array(node.get_children())
	return null


func _find_wall(level: Level) -> Breakable:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Breakable and (node as Breakable).data.look == BreakableData.Look.WALL:
			return node
		stack.append_array(node.get_children())
	return null


func _test_pickup_and_progress() -> void:
	var toasts: Array[String] = []
	var on_toast := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(on_toast)
	var level := await start_level(level_data())
	check(StoryItems.collected_count(&"chapter_02") == 0, "a new run starts with nothing collected")
	var pickup := _find_pickup(level, OPEN_ITEM)
	check(pickup != null, "collectible pickup spawned from the legend")
	level.player.global_position = pickup.global_position
	await frames(8)
	check(StoryItems.owns(OPEN_ITEM), "touching the pickup collects it")
	check(StoryItems.collected_count(&"chapter_02") == 1, "collection progress counts it")
	var message := ""
	for text in toasts:
		if text.contains("升降井維護備忘"):
			message = text
	check(message.contains("文件") and message.contains("1／7"), "pickup toast shows the chapter progress: %s" % message)
	check(StoryItems.is_new(OPEN_ITEM), "a new collectible is flagged NEW")
	EventBus.toast_requested.disconnect(on_toast)
	await end_level(level)


func _test_persistence() -> void:
	# 重新建立關卡（模擬死亡重來，不重置本輪）：已收集的不會再出現，進度保留。
	var level := await spawn_level(level_data())
	check(StoryItems.owns(OPEN_ITEM), "collection survives rebuilding the level")
	check(_find_pickup(level, OPEN_ITEM) == null, "a collected pickup does not respawn")
	check(_find_pickup(level, HIDDEN_ITEM) != null, "an uncollected pickup is still there")
	await end_level(level)
	# 新的一輪才重置。
	var fresh := await start_level(level_data())
	check(not StoryItems.owns(OPEN_ITEM) and _find_pickup(fresh, OPEN_ITEM) != null, "a new run resets the collection")
	await end_level(fresh)


func _test_hidden_room() -> void:
	var level := await start_level(level_data())
	var wall := _find_wall(level)
	check(wall != null and not wall.is_broken, "cracked wall seals the hidden room")
	var player := level.player
	player.health.setup(999, 0.0)
	# 牆還在：玩家走不進去。
	player.global_position = Vector2(28 * 16.0, 20 * 16.0)
	player.velocity = Vector2.ZERO
	Input.action_press(&"move_right")
	await physics_frames(90)
	Input.action_release(&"move_right")
	check(player.global_position.x < 31 * 16.0, "the intact wall blocks the way in")
	# 打破：入口打開，裡面的文件拿得到。
	var info := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	wall.hit_by_projectile(info)
	await physics_frames(10)
	check(wall.is_broken, "the cracked wall breaks")
	player.global_position = Vector2(30 * 16.0, 20 * 16.0)
	player.velocity = Vector2.ZERO
	Input.action_press(&"move_right")
	await physics_frames(150)
	Input.action_release(&"move_right")
	check(player.global_position.x > 34 * 16.0, "the broken wall opens the hidden room")
	check(StoryItems.owns(HIDDEN_ITEM), "the hidden document is collected inside the room")
	await end_level(level)


func _test_inventory_page() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	StoryItems.acquire(OPEN_ITEM, false)
	StoryItems.acquire(&"rec_wataru_1", false)
	var page := StoryItemsPage.new()
	var entries := page._build_entries()
	var by_id: Dictionary[StringName, InventoryEntry] = {}
	for entry in entries:
		by_id[entry.id] = entry
	check(by_id.has(OPEN_ITEM) and by_id.has(&"rec_wataru_1"), "inventory lists collected documents and recordings")
	var doc: InventoryEntry = by_id[OPEN_ITEM]
	check(doc.subtitle == "文件" and doc.detail_body == (load("res://data/story_items/%s.tres" % OPEN_ITEM) as StoryItemData).body, "document shows its full text")
	check(doc.detail_stats.size() == 1 and doc.detail_stats[0].contains("2／7"), "document shows the chapter collection progress: %s" % [doc.detail_stats])
	check((by_id[&"rec_wataru_1"] as InventoryEntry).subtitle == "錄音", "recording is labelled as a recording")
	check(page.tab_tooltip().contains("2／12"), "tab tooltip shows overall progress: %s" % page.tab_tooltip())
	check(not by_id.has(&"doc_nest_log"), "uncollected documents are not listed")
	page.free()
