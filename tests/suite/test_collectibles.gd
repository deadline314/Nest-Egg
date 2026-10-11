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
	_test_item_custody()
	_test_custody_validation()
	_test_custody_bounded_input()
	await _test_custody_lifecycle()
	_test_world_item_assets()
	await _test_pickup_and_progress()
	await _test_persistence()
	await _test_hidden_room()
	await _test_inventory_page()


func _test_item_custody() -> void:
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	var observations: Array[Dictionary] = []
	var on_save := func() -> void: observations.append(StoryItems.snapshot())
	var acquired_states: Array[bool] = []
	var transferred_states: Array[bool] = []
	var on_acquired := func(item: StoryItemData) -> void:
		acquired_states.append(StoryItems.owns(item.id) and StoryItems.holds(item.id) and StoryItems.is_new(item.id) and not StoryItems.was_transferred(item.id))
	var on_transferred := func(item: StoryItemData) -> void:
		transferred_states.append(StoryItems.owns(item.id) and not StoryItems.holds(item.id) and StoryItems.was_transferred(item.id))
	GameState.run_save_requested.connect(on_save)
	StoryItems.acquired.connect(on_acquired)
	StoryItems.transferred.connect(on_transferred)
	var credits := Progression.credits
	check(StoryItems.acquire(&"ch1_data_disk", false), "custody: real disk first acquisition succeeds")
	check(acquired_states == [true] and observations.size() == 1 and observations[0]["held"].has(&"ch1_data_disk"), "custody: acquire callbacks and save observe complete state")
	check(StoryItems.transfer(&"ch1_data_disk"), "custody: held disk transfers once")
	check(transferred_states == [true] and observations.size() == 2 and not observations[1]["held"].has(&"ch1_data_disk") and observations[1]["transferred"].has(&"ch1_data_disk"), "custody: transfer callbacks and save observe complete state")
	var after := StoryItems.snapshot()
	check(not StoryItems.transfer(&"ch1_data_disk") and not StoryItems.transfer(HIDDEN_ITEM) and not StoryItems.transfer(&"unknown_item"), "custody: replay, unheld and unknown transfers fail")
	check(not StoryItems.acquire(&"ch1_data_disk", false), "custody: acquired history prevents recreating transferred disk")
	StoryItems._grant(StoryItemData.Trigger.RUN_START, &"", false)
	check(StoryItems.snapshot() == after and observations.size() == 2 and transferred_states.size() == 1 and Progression.credits == credits, "custody: failed transfer and automatic replay have zero mutation, save or currency reward")
	check(StoryItems.owned_items().has(StoryItems.find(&"ch1_data_disk")), "custody: transferred disk remains in acquired inventory directory")
	StoryItems.transfer(&"nest_egg_chip")
	var before_grant := StoryItems.snapshot()
	var saves_before := observations.size()
	StoryItems._grant(StoryItemData.Trigger.RUN_START, &"", false)
	check(StoryItems.snapshot() == before_grant and observations.size() == saves_before and not StoryItems.holds(&"nest_egg_chip"), "custody: automatic RUN_START cannot recreate its own transferred original")
	StoryItems._on_scene_finished(&"cut_c1_shop")
	check(StoryItems.holds(&"old_k_order"), "custody: real scene grant creates held item on first completion")
	StoryItems.transfer(&"old_k_order")
	before_grant = StoryItems.snapshot()
	saves_before = observations.size()
	StoryItems._on_scene_finished(&"cut_c1_shop")
	check(StoryItems.snapshot() == before_grant and observations.size() == saves_before and not StoryItems.holds(&"old_k_order"), "custody: repeated scene completion cannot recreate its transferred grant")
	StoryItems.acquire(OPEN_ITEM, false)
	var collected := StoryItems.collected_count(&"chapter_02")
	check(StoryItems.transfer(OPEN_ITEM) and StoryItems.collected_count(&"chapter_02") == collected and StoryItems.is_new(OPEN_ITEM), "custody: transfer preserves collectible history and unread status")
	StoryItems.mark_seen(OPEN_ITEM)
	check(not StoryItems.is_new(OPEN_ITEM) and StoryItems.owns(OPEN_ITEM) and not StoryItems.holds(OPEN_ITEM), "custody: reading transferred entry only clears NEW")
	var exported := StoryItems.snapshot()
	var wire: Dictionary = JSON.parse_string(JSON.stringify(exported))
	check(StoryItems.restore({"owned": [], "unseen": []}), "custody: valid empty legacy restore succeeds")
	check(StoryItems.restore(wire) and StoryItems.snapshot() == exported, "custody: true JSON roundtrip restores transferred disk without resurrection")
	wire["held"].append("ch1_data_disk")
	exported["owned"].clear()
	check(not StoryItems.holds(&"ch1_data_disk") and StoryItems.owns(&"ch1_data_disk"), "custody: export and restored input have no mutable alias")
	GameState.run_save_requested.disconnect(on_save)
	StoryItems.acquired.disconnect(on_acquired)
	StoryItems.transferred.disconnect(on_transferred)


func _test_custody_validation() -> void:
	var legacy := {"owned": [&"ch1_data_disk", OPEN_ITEM], "unseen": [OPEN_ITEM]}
	check(StoryItems.restore(legacy) and StoryItems.holds(&"ch1_data_disk") and not StoryItems.was_transferred(&"ch1_data_disk"), "custody: complete legacy maps history to held")
	StoryItems.transfer(&"ch1_data_disk")
	# 正式劇本裡交出資料盤的場景同時寫下交出旗標（data/save/required_items.json）；夾具照真實結果寫，存檔才不自相矛盾。
	GameState.set_flag(&"ch1_disk_delivered")
	var good := StoryItems.snapshot()
	var valid_run := RunSnapshot.capture("res://data/levels/ch1_pawnshop.tres", {"health": 4, "position": [100, 160], "world": {}, "loadout": {}})
	var malformed: Array = [null, {}, {"owned": [], "unseen": null}]
	for key in ["custody_version", "held", "transferred", "owned", "unseen"]:
		var missing := good.duplicate(true)
		missing.erase(key)
		malformed.append(missing)
		var explicit_null := good.duplicate(true)
		explicit_null[key] = null
		malformed.append(explicit_null)
	for version: Variant in [2, "1", 1.5, true]:
		var bad_version := good.duplicate(true)
		bad_version["custody_version"] = version
		malformed.append(bad_version)
	for key in ["owned", "unseen", "held", "transferred"]:
		var unknown := good.duplicate(true)
		unknown[key].append("unknown_item")
		malformed.append(unknown)
		var duplicate := good.duplicate(true)
		duplicate[key] = [OPEN_ITEM, OPEN_ITEM]
		malformed.append(duplicate)
		var invalid_type := good.duplicate(true)
		invalid_type[key] = [5]
		malformed.append(invalid_type)
		var too_many := good.duplicate(true)
		too_many[key] = []
		too_many[key].resize(StoryItems.catalog().size() + 1)
		malformed.append(too_many)
	var overlap := good.duplicate(true)
	overlap["held"].append(&"ch1_data_disk")
	malformed.append(overlap)
	var orphan := good.duplicate(true)
	orphan["held"].append(HIDDEN_ITEM)
	malformed.append(orphan)
	var unaccounted := good.duplicate(true)
	unaccounted["transferred"].clear()
	malformed.append(unaccounted)
	var unseen_orphan := good.duplicate(true)
	unseen_orphan["unseen"].append(HIDDEN_ITEM)
	malformed.append(unseen_orphan)
	var legacy_bad := legacy.duplicate(true)
	legacy_bad["owned"].append(&"unknown_item")
	malformed.append(legacy_bad)
	for i in malformed.size():
		var candidate: Variant = malformed[i]
		var before_candidate: Variant = candidate.duplicate(true) if candidate is Dictionary else candidate
		var prepared := StoryItems.prepare_snapshot(candidate, "custody_fixture/items")
		check(prepared.has("error") and prepared["error"].begins_with("custody_fixture/items"), "custody: malformed %d has exact component diagnostic" % i)
		check(not StoryItems.restore(candidate, "custody_fixture/items") and StoryItems.snapshot() == good, "custody: malformed %d direct restore retains entire live state" % i)
		check(candidate == before_candidate, "custody: malformed %d input remains unchanged" % i)
		var run := valid_run.duplicate(true)
		run["story"]["items"] = candidate
		var before_run := run.duplicate(true)
		check(RunSnapshot.prepare(run).has("error") and run == before_run and StoryItems.snapshot() == good, "custody: malformed %d rejects whole-run without partial state or source repair" % i)
	var legacy_run := valid_run.duplicate(true)
	legacy_run["story"]["items"] = legacy
	# 舊格式的資料盤還在手上，交出旗標也照當時的真實狀態（尚未交出）。
	legacy_run["story"]["flags"]["ch1_disk_delivered"] = false
	var migrated := RunSnapshot.prepare(legacy_run)
	check(migrated.has("data") and migrated["data"]["story"]["items"]["held"].size() == 2 and not legacy_run["story"]["items"].has("held"), "custody: run prepare normalizes legacy in detached result only")
	var path := "user://st3_custody_suite.json"
	var store := RunSaveStore.new(path)
	store.validator = RunSnapshot.prepare
	check(store.write(valid_run, true), "custody: valid transferred whole-run writes to private fixture slot")
	var original := FileAccess.get_file_as_string(path)
	var rejected := valid_run.duplicate(true)
	rejected["story"]["items"]["held"] = null
	check(not store.write(rejected) and FileAccess.get_file_as_string(path) == original, "custody: failed whole-run write preserves original transferred save")
	check(store.read()["story"]["items"]["transferred"].has(&"ch1_data_disk") or store.read()["story"]["items"]["transferred"].has("ch1_data_disk"), "custody: private disk roundtrip preserves actual transfer")
	var future := valid_run.duplicate(true)
	future["story"]["items"]["custody_version"] = 2
	var future_prepared := RunSnapshot.prepare(future)
	check(future_prepared.has("error") and future_prepared.get("unknown_version", false), "custody: future version remains an unsupported format rather than corrupt legacy")
	var future_bytes := RunSaveCodec.encode(future)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(future_bytes)
	file.close()
	check(store.read().is_empty() and store.unknown_version and FileAccess.get_file_as_string(path) == future_bytes, "custody: future primary cannot downgrade to otherwise valid old backup")
	check(not store.write(valid_run) and FileAccess.get_file_as_string(path) == future_bytes, "custody: normal save cannot overwrite future custody primary")
	for suffix in ["", ".bak", ".tmp", ".freshbak", ".newrun", ".newrun.previous", ".previous", ".previous.bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _test_custody_bounded_input() -> void:
	var good := StoryItems.snapshot()
	var long_id := good.duplicate(true)
	long_id["held"] = ["x".repeat(RunSaveCodec.MAX_TEXT + 1)]
	var deep := good.duplicate(true)
	var nested: Array = []
	var cursor: Array = nested
	for i in RunSaveCodec.MAX_DEPTH + 1:
		var next: Array = []
		cursor.append(next)
		cursor = next
	deep["extra"] = nested
	var cyclic := good.duplicate(true)
	var cycle: Array = []
	cycle.append(cycle)
	cyclic["extra"] = cycle
	# 這些資料先驗再用；不能為了測拒絕先 deep copy 或 JSON.stringify 循環輸入。
	for input: Dictionary in [long_id, deep, cyclic]:
		var prepared := StoryItems.prepare_snapshot(input, "custody_fixture/items")
		check(prepared.has("error") and prepared["error"].length() <= RunSaveCodec.MAX_DIAGNOSTIC_PATH, "custody: long id, deep extra or cycle receives one bounded rejection")
		check(not StoryItems.restore(input, "custody_fixture/items") and StoryItems.snapshot() == good, "custody: bounded rejection occurs before interning or replacing live items")
	check(long_id["held"][0].length() == RunSaveCodec.MAX_TEXT + 1 and cycle.size() == 1, "custody: bounded validator leaves rejected source untouched")
	cycle.clear()


func _test_custody_lifecycle() -> void:
	var level := await start_level(level_data())
	StoryItems.acquire(OPEN_ITEM, false)
	StoryItems.acquire(&"ch1_data_disk", false)
	GameState.set_checkpoint(level.player.global_position, level.player.loadout.snapshot(), {}, Progression.snapshot())
	var entry := RunSnapshot.capture("res://data/levels/ch1_pawnshop.tres", {"health": 4, "position": [100, 160], "world": {}, "loadout": {}})
	StoryItems.transfer(&"ch1_data_disk")
	GameState.deaths += 1
	RunSnapshot.rollback_presentation(entry)
	check(StoryItems.holds(&"ch1_data_disk") and not StoryItems.was_transferred(&"ch1_data_disk") and GameState.deaths == entry["state"]["deaths"] + 1, "custody: cancelling unfinished segment restores entry custody and keeps live death")
	StoryItems.transfer(&"ch1_data_disk")
	StoryItems.transfer(OPEN_ITEM)
	var delivered := StoryItems.snapshot()
	GameState.clear_checkpoint()
	GameState.register_death()
	check(StoryItems.snapshot() == delivered, "custody: checkpoint reset and death keep acquired and transferred state")
	var next_segment := RunSnapshot.capture("res://data/levels/ch1_pawnshop.tres", {"health": 4, "position": [100, 160], "world": {}, "loadout": {}})
	StoryItems.acquire(HIDDEN_ITEM, false)
	RunSnapshot.rollback_presentation(next_segment)
	check(StoryItems.snapshot() == delivered and not StoryItems.owns(HIDDEN_ITEM), "custody: cancellation of later segment keeps earlier committed transfer and removes only provisional acquisition")
	await end_level(level)
	level = await spawn_level(level_data())
	check(StoryItems.owns(OPEN_ITEM) and not StoryItems.holds(OPEN_ITEM) and _find_pickup(level, OPEN_ITEM) == null and not StoryItems.holds(&"ch1_data_disk"), "custody: rebuilding after death cannot respawn transferred collectibles or disk")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
	check(not StoryItems.owns(&"ch1_data_disk") and not StoryItems.holds(&"ch1_data_disk") and not StoryItems.was_transferred(&"ch1_data_disk") and StoryItems.holds(&"nest_egg_chip") and not StoryItems.was_transferred(&"nest_egg_chip"), "custody: new run clears history and transfer before granting RUN_START items")


func _test_world_item_assets() -> void:
	# A generated sprite must actually be reachable from the pickup, not only exist on disk.
	for file in DirAccess.get_files_at("res://data/weapons"):
		if not file.ends_with(".tres"):
			continue
		var weapon := load("res://data/weapons/" + file) as WeaponData
		var pickup := WeaponPickup.new()
		pickup.configure(weapon)
		check(pickup.has_method("world_icon_key"), "%s exposes its actual world sprite key" % weapon.id)
		if pickup.has_method("world_icon_key"):
			var key: String = pickup.call("world_icon_key")
			check(not ItemIcons.world(key).is_empty(), "%s has a real world sprite (%s)" % [weapon.id, key])
		pickup.free()
	for file in DirAccess.get_files_at("res://data/weapons/melee"):
		if not file.ends_with(".tres"):
			continue
		var weapon := load("res://data/weapons/melee/" + file) as WeaponData
		check(not ItemIcons.world(str(weapon.id)).is_empty(), "%s world silhouette has dedicated art" % weapon.id)
	for key in ["repair_pack", "document", "recording"]:
		check(not ItemIcons.world(key).is_empty(), "%s geometric placeholder has replacement world art" % key)
	check(ItemIcons.world("ne225_absent_resource").is_empty(), "missing world art keeps the geometric fallback")


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
	check(per_chapter.get(&"chapter_01", 0) == 5 and per_chapter.get(&"chapter_02", 0) == 7 and per_chapter.get(&"ch1_kasa", 0) == 5, "fixed collectible counts per chapter %s" % per_chapter)
	check(StoryItems.collectible_total(&"chapter_02") == 7 and StoryItems.collectible_total(&"nope") == 0, "collectible_total counts per chapter")
	check(StoryItems.collectible_chapters().size() == 3, "three chapters have collectibles")
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
	check(page.tab_tooltip().contains("2／17"), "tab tooltip shows overall progress: %s" % page.tab_tooltip())
	check(not by_id.has(&"doc_nest_log"), "uncollected documents are not listed")
	page.free()
