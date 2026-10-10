class_name Chapter2Suite
extends TestSuite
## 第二章關卡（NE-27）：資料與地圖結構、區段光影、檢查點、機關與收集品的擺放、安全示範、
## 從第一章銜接進來（成長與裝備帶過來）、三種難度都能打完頭目進入結算。

const LEVEL_1 := "res://data/levels/level_01.tres"
const LEVEL_2 := "res://data/levels/level_02.tres"
## 第一次出現時必須有「安全示範」的物件字元（附近 DEMO_RADIUS 內不能有敵人）。
const DEMO_CHARS := ["a", "o", "w", "u", "y", "h", "p", "f"]
const DEMO_RADIUS := 9.0
## 第二章要用到的新內容。
const NEW_ENEMY_CHARS := ["k", "s", "M", "E", "Y"]


func run() -> void:
	_test_data()
	_test_layout()
	await _test_checkpoints()
	await _test_required_route()
	await _test_campaign_flow()
	await _test_difficulties()


func _data() -> LevelData:
	return load(LEVEL_2) as LevelData


func _test_data() -> void:
	var data := _data()
	check(data != null and data.chapter == &"chapter_02", "level 2 loads and belongs to chapter 2")
	check(data.validate_lighting().is_empty(), "level 2 lighting valid: %s" % [data.validate_lighting()])
	var profiles: Dictionary[StringName, bool] = {}
	for zone in data.lighting_zones:
		profiles[zone.profile.id] = true
	check(data.lighting_zones.size() >= 5 and profiles.size() == data.lighting_zones.size(), "at least five zones, each with its own lighting (%d)" % data.lighting_zones.size())
	check(data.boss_lighting != null and not profiles.has(data.boss_lighting.id), "the boss fight has its own lighting")
	for scene_id in [data.intro_scene, data.boss_scene, data.outro_scene]:
		check(Story.has_scene(scene_id), "level 2 scene exists: %s" % scene_id)
	for scene_id in data.story_triggers:
		check(Story.has_scene(StringName(scene_id)), "level 2 trigger scene exists: %s" % scene_id)
	check(not Story.chapter_info(data.chapter).is_empty(), "level 2 has its chapter card data")
	check(not data.rain, "level 2 is sealed (no rain)")
	check((load(LEVEL_1) as LevelData).next_level == LEVEL_2 and data.next_level.is_empty(), "level 1 leads into level 2, level 2 ends the campaign")
	for ch in data.legend:
		check(data.legend[ch] != null, "level 2 legend entry has a resource: %s" % ch)
	for hint in data.hints:
		check(not str(hint).is_empty(), "level 2 hint is not empty")


func _test_layout() -> void:
	var data := _data()
	var layout := LevelBuilder.parse(data)
	check(layout.is_valid() and layout.warnings.is_empty(), "level 2 parses without warnings %s" % [layout.warnings])
	check(layout.checkpoints.size() >= 4, "at least four checkpoints (%d)" % layout.checkpoints.size())
	for checkpoint in layout.checkpoints:
		var cell_below := layout.cell(int(checkpoint.x / layout.tile_size), int(checkpoint.y / layout.tile_size))
		check(cell_below == "#", "checkpoint stands on solid ground: %s" % checkpoint)
	check(layout.story_triggers.size() == data.story_triggers.size(), "every & trigger is mapped to a scene")
	check(not layout.boss_spawn.is_empty() and layout.arena_x > 0.0, "level 2 has a boss and an arena")
	check(layout.boss_spawn["position"].x > layout.arena_x, "the boss spawns inside the arena")
	# 內容盤點：用到新敵人、每種機關與可破壞物、六件收集品各一次、補給點、信用點。
	var counts: Dictionary[String, int] = {}
	var first_x: Dictionary[String, float] = {}
	var enemy_xs: Array[float] = []
	for y in layout.height:
		for x in layout.width:
			var c := layout.cell(x, y)
			if data.legend.has(c):
				counts[c] = counts.get(c, 0) + 1
				if not first_x.has(c) or x < first_x[c]:
					first_x[c] = float(x)
				if data.legend[c] is EnemyData:
					enemy_xs.append(float(x))
	for c in NEW_ENEMY_CHARS:
		check(counts.get(c, 0) >= 1, "level 2 uses the new enemy: %s" % c)
	for c in ["a", "o", "w", "x", "u", "f", "h", "y", "j", "l", "p", "z", "q"]:
		check(counts.get(c, 0) >= 1, "level 2 places %s" % c)
	var collectibles := 0
	for c in data.legend:
		if data.legend[c] is StoryItemData and (data.legend[c] as StoryItemData).chapter == &"chapter_02":
			check(counts.get(c, 0) == 1, "collectible placed exactly once: %s" % c)
			collectibles += counts.get(c, 0)
	# 場景人物給的收集品不在地圖上，算進同一份總數。
	for c in data.legend:
		if data.legend[c] is NpcData:
			for talk in (data.legend[c] as NpcData).talks:
				if talk.story_item != null and talk.story_item.chapter == &"chapter_02":
					collectibles += 1
	check(collectibles == StoryItems.collectible_total(&"chapter_02"), "every chapter 2 collectible is in the level or given by a person (%d)" % collectibles)
	# 安全示範：每種機關第一次出現的地方，附近沒有敵人。
	for c in DEMO_CHARS:
		var x: float = first_x.get(c, -1.0)
		check(x >= 0.0, "demo object exists: %s" % c)
		var crowded := enemy_xs.any(func(ex: float) -> bool: return absf(ex - x) <= DEMO_RADIUS)
		check(not crowded, "the first %s appears with no enemies within %d tiles" % [c, int(DEMO_RADIUS)])
	# 閘門與開關成對（同頻道），電力開關有對應的受電物件（雷射柵欄）。
	check(layout.laser_rects.size() >= 2, "level 2 has powered laser fences")
	var channels: Dictionary[StringName, int] = {}
	for c in ["h", "y", "j", "l"]:
		channels[(data.legend[c] as MechanismData).channel] = channels.get((data.legend[c] as MechanismData).channel, 0) + 1
	check(channels.size() == 2 and channels.values().all(func(n: int) -> bool: return n == 2), "gates and switches are paired by channel %s" % [channels])
	check(layout.health_pickups.size() >= 2, "level 2 has health pickups")


func _test_checkpoints() -> void:
	var data := _data()
	var layout := LevelBuilder.parse(data)
	var level := await start_level(data)
	level.player.health.setup(9999, 0.0)
	for enemy in get_tree_enemies(level):
		enemy.queue_free()  # 撥號要一秒多，敵人會走過來把玩家撞開，這個測試只看電話亭
	for checkpoint in layout.checkpoints:
		level.player.global_position = checkpoint + Vector2(0, -2)
		level.player.velocity = Vector2.ZERO
		await frames(20)
		check(level.player.is_on_floor() and absf(level.player.global_position.y - checkpoint.y) < 4.0, "player stands at checkpoint %s" % checkpoint)
		check(not GameState.has_checkpoint, "just walking past does not record the phone booth %s" % checkpoint)
		var booth := _booth_at(level, checkpoint)
		check(booth != null and booth.start_call(level.player), "dialing at the booth works %s" % checkpoint)
		await frames(90)
		check(GameState.has_checkpoint and GameState.checkpoint_position.distance_to(checkpoint) < 4.0, "dialing records the checkpoint %s" % checkpoint)
		GameState.clear_checkpoint()
	await end_level(level)
	GameState.clear_checkpoint()


func get_tree_enemies(level: Level) -> Array[Node]:
	return level.get_tree().get_nodes_in_group(&"enemies")


func _booth_at(level: Level, at: Vector2) -> Checkpoint:
	for node in level.find_children("*", "Checkpoint", true, false):
		if (node as Checkpoint).global_position.distance_to(at) < 4.0:
			return node as Checkpoint
	return null


## 必經路線真的走得通：搭 S1 的升降梯跳上平台；閘門不開過不去、打開後走得過。
func _test_required_route() -> void:
	var data := _data()
	var level := await start_level(data)
	var player := level.player
	player.health.setup(9999, 0.0)
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	# 升降梯：站上去，升到頂就往右跳上平台（平台頂面 y = 14 × 16）。
	var lift: Lift = null
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Lift and (node as Lift).data.id == &"lift":
			lift = node
		stack.append_array(node.get_children())
	check(lift != null, "the entry lift exists")
	player.global_position = lift.global_position + Vector2(0, -2)
	player.velocity = Vector2.ZERO
	var top := lift.global_position.y - lift.data.travel_tiles * 16.0
	for i in 600:
		await physics_frames(1)
		if lift.global_position.y <= top + 1.0:
			break
	check(lift.global_position.y <= top + 1.0, "the lift reaches the top")
	check(absf(player.global_position.x - lift.global_position.x) < 30.0, "the player rides the lift")
	# 按住跳躍鍵（放開太早只會跳一小段）並往右走。
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	var landed := false
	for i in 400:
		await physics_frames(1)
		if player.is_on_floor() and absf(player.global_position.y - 14.0 * 16.0) < 3.0 and player.global_position.x > 66.0 * 16.0:
			landed = true
			break
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	check(landed, "the player gets from the lift onto the plateau (x=%.0f y=%.0f)" % [player.global_position.x, player.global_position.y])
	# 閘門：先確認擋路，再打開。
	var gate: Gate = null
	var switch: ChannelSwitch = null
	stack = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Gate and (node as Gate).data.id == &"gate_a":
			gate = node
		elif node is ChannelSwitch and (node as ChannelSwitch).data.id == &"switch_a":
			switch = node
		stack.append_array(node.get_children())
	check(gate != null and switch != null, "the first gate and its switch exist")
	player.global_position = Vector2(86.0 * 16.0, 14.0 * 16.0 - 2.0)
	player.velocity = Vector2.ZERO
	await physics_frames(10)
	Input.action_press(&"move_right")
	await physics_frames(120)
	Input.action_release(&"move_right")
	check(player.global_position.x < gate.global_position.x, "a closed gate blocks the tunnel (x=%.0f)" % player.global_position.x)
	switch.toggle()
	await physics_frames(10)
	Input.action_press(&"move_right")
	await physics_frames(150)
	Input.action_release(&"move_right")
	check(player.global_position.x > gate.global_position.x + 32.0, "an open gate lets the player through (x=%.0f)" % player.global_position.x)
	await end_level(level)


## 第一章通關 → 第二章：成長（信用點、改裝）與裝備（武器、消耗品）帶進去；重試重載同一關。
func _test_campaign_flow() -> void:
	var previous_autosave := GameState.story_autosave
	var previous_run := RunSnapshot.capture(LEVEL_1, {})
	var previous_carried: Dictionary = GameState.get("_carried_loadout").duplicate(true)
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	var main: Node = load("res://game/main.gd").new()
	var campaign_slot := "user://test_campaign_run/slot.json"
	_cleanup_campaign_slot(campaign_slot)
	main.set("_run_store", RunSaveStore.new(campaign_slot))
	runner.get_tree().root.add_child(main)
	await frames(3)
	var level_1 := load(LEVEL_1) as LevelData
	main._level_path = LEVEL_1
	main._active_run = true
	main._load_level()
	await frames(6)
	var source := main._screen as Level
	check(source != null and source.data == level_1, "campaign fixture loads a real source Level before completion")
	if source == null:
		main.free()
		_cleanup_campaign_slot(campaign_slot)
		RunSnapshot.apply(previous_run)
		GameState.set("_carried_loadout", previous_carried)
		GameState.story_autosave = previous_autosave
		return
	# 第一章的成果：信用點、改裝、武器。
	Progression.add_credits(321)
	Progression.buy_upgrade(load("res://data/weapons/pistol.tres"), Progression.find_upgrade(&"quick_reload")) if Progression.credits >= 100 else null
	var loadout := source.player.loadout
	loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	GameState.carry_over({"weapons": loadout.snapshot()["weapons"], "mag": loadout.snapshot()["mag"], "reserve": loadout.snapshot()["reserve"], "active": 1, "version": Loadout.SNAPSHOT_VERSION})
	var credits := Progression.credits
	main._level_path = LEVEL_1
	main._on_level_completed(level_1)
	await frames(6)
	check(main._screen is Level and (main._screen as Level).data.id == &"level_02", "completing chapter 1 loads chapter 2")
	check(Progression.credits == credits and GameState.level_start_progress.get("credits") == credits, "credits carry over to chapter 2")
	var level := main._screen as Level
	check(level.player.loadout.find_slot(&"rifle") >= 0, "the weapons carry over to chapter 2")
	check(not GameState.has_checkpoint, "chapter 2 starts without a checkpoint")
	# 重試：重載同一關（第二章），不會退回第一章。
	level.retry_requested.emit()
	await frames(6)
	check(main._screen is Level and (main._screen as Level).data.id == &"level_02", "retry reloads chapter 2")
	# 第二章是最後一關：通關後進入結算畫面。
	main._on_level_completed(_data())
	await frames(4)
	check(main._screen is VictoryScreen, "completing the last chapter shows the victory screen")
	runner.get_tree().root.remove_child(main)
	main.free()
	await frames(2)
	_cleanup_campaign_slot(campaign_slot)
	RunSnapshot.apply(previous_run)
	GameState.set("_carried_loadout", previous_carried)
	GameState.story_autosave = previous_autosave


func _cleanup_campaign_slot(slot: String) -> void:
	# 只移除固定fixture槽的檔案，不碰正式整輪／故事檔。
	for suffix: String in ["", ".bak", ".tmp", ".invalid", ".previous", ".previous.bak", ".freshbak", ".newrun", ".newrun.tmp", ".newrun.previous", ".recover"]:
		if FileAccess.file_exists(slot + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(slot + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot.get_base_dir()))


## 三種難度都能打完第二章的頭目並接上結尾（頭目由測試直接擊倒，戰鬥本身由頭目套件測試）。
func _test_difficulties() -> void:
	var data := _data()
	var layout := LevelBuilder.parse(data)
	for difficulty_index in GameState.difficulties.size():
		var level := await start_level(data, difficulty_index)
		var free_camera_left := level.camera.limit_left
		var done := [false]
		level.completed.connect(func() -> void: done[0] = true)
		level.player.health.setup(999, 0.5)
		level.player.global_position = Vector2(layout.arena_x + 80.0, 300.0)
		var boss: Enemy = null
		for i in 300:
			await physics_frames(1)
			for node in runner.get_tree().get_nodes_in_group(&"enemies"):
				if node is Enemy and (node as Enemy).data.is_boss:
					boss = node
			if boss != null:
				break
		var difficulty := GameState.difficulties[difficulty_index]
		check(boss != null and boss.data.id == &"reclaimer", "%s: the reclaimer appears in the arena" % difficulty.id)
		check(level._lighting.has_override(&"boss") or level._lighting.has_override(&"boss"), "%s: the boss lighting is applied" % difficulty.id)
		check(not data.lock_boss_arena and level.camera.limit_left == free_camera_left, "%s: the ordinary boss encounter keeps the camera unlocked" % difficulty.id)
		if boss != null:
			await physics_frames(60)
			var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
			lethal.bypass_guard = true
			lethal.ignore_invulnerability = true
			boss.health.take_damage(lethal)
		for i in 900:
			await physics_frames(1)
			if done[0]:
				break
		check(done[0], "%s: chapter 2 completes after the boss" % difficulty.id)
		for id in [&"maintenance_pass", &"nest_roster", &"wataru_wristband"]:
			check(StoryItems.owns(id), "%s: story item granted: %s" % [difficulty.id, id])
		await end_level(level)
