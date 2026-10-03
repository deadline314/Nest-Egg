extends Node
## 開發工具：自動擷取遊戲畫面（檢查美術、光影、UI 排版用）。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑/資料夾 [--scenario=名稱]
## 情境：all（預設）、settings、mouse_aim、block、story、story_ch2、collectibles、progression、supply、props、new_enemies、dynamic_hud、weapons、reload、consumables、story_items、inventory、lighting、postfx、brightness、quality、combat_light、normals
## 需要可渲染的環境（有 GPU 或軟體 Vulkan / OpenGL）。

const LEVEL_PATH := "res://data/levels/level_01.tres"

var _out_dir := "user://screenshots"
var _scenario := "all"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--scenario="):
			_scenario = arg.trim_prefix("--scenario=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	# 劇情演出會暫停遊戲並蓋住畫面；只有 story 情境需要拍到演出。
	Story.auto_skip = _scenario != "story" and _scenario != "story_ch2"
	if _scenario == "settings":
		await _run_settings()
		get_tree().quit()
		return
	if _scenario == "story":
		await _run_story()
		get_tree().quit()
		return
	if _scenario == "story_ch2":
		await _run_story_ch2()
		get_tree().quit()
		return
	if _scenario == "new_enemies":
		await _run_new_enemies()
		get_tree().quit()
		return
	if _scenario == "supply":
		await _run_supply()
		get_tree().quit()
		return
	if _scenario == "progression":
		await _run_progression()
		get_tree().quit()
		return
	if _scenario == "collectibles":
		await _run_collectibles()
		get_tree().quit()
		return
	if _scenario == "props":
		await _run_props()
		get_tree().quit()
		return
	if _scenario == "block":
		await _run_block()
		get_tree().quit()
		return
	if _scenario == "normals":
		await _run_normals()
		get_tree().quit()
		return
	if _scenario == "combat_light":
		await _run_combat_light()
		get_tree().quit()
		return
	if _scenario == "quality":
		await _run_quality()
		get_tree().quit()
		return
	if _scenario == "brightness":
		await _run_brightness()
		get_tree().quit()
		return
	if _scenario == "postfx":
		await _run_postfx()
		get_tree().quit()
		return
	if _scenario == "lighting":
		await _run_lighting()
		get_tree().quit()
		return
	if _scenario == "inventory":
		await _run_inventory()
		get_tree().quit()
		return
	if _scenario == "story_items":
		await _run_story_items()
		get_tree().quit()
		return
	if _scenario == "consumables":
		await _run_consumables()
		get_tree().quit()
		return
	if _scenario == "reload":
		await _run_reload()
		get_tree().quit()
		return
	if _scenario == "weapons":
		await _run_weapons()
		get_tree().quit()
		return
	if _scenario == "dynamic_hud":
		await _run_dynamic_hud()
		get_tree().quit()
		return
	if _scenario == "mouse_aim":
		await _run_mouse_aim()
		get_tree().quit()
		return
	var menu := MainMenu.new()
	add_child(menu)
	await _settle(30)
	_capture("01_main_menu")
	menu.queue_free()

	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	await _shoot_at(player, Vector2(250, 240), 25)
	_capture("02_rooftop")
	await _shoot_at(player, Vector2(1480, 320), 40)
	_capture("03_neon_market")
	await _shoot_at(player, Vector2(2780, 320), 20)
	_capture("04_freight_yard")
	await _shoot_at(player, Vector2(4180, 320), 20)
	_capture("05_facility")
	player.global_position = Vector2(5040, 300)
	await _wait(2.5)
	Input.action_press(&"shoot")
	await _settle(25)
	_capture("06_boss")
	Input.action_release(&"shoot")
	var info := DamageInfo.create(999, Combat.Team.ENEMY, &"boss_fan")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	await _wait(1.8)
	_capture("07_death_card")
	get_tree().quit()


## 劇情：開場過場、章節標題、通訊、頭目登場、結尾、章節結束。
func _run_story() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _wait(1.0)
	for i in 2:
		Story._layer.advance()
		Story._layer.advance()
	await _wait(0.8)
	_capture("story_prologue")
	Story.skip_cinematic()
	await _wait(1.2)
	_capture("story_chapter_title")
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(level._layout.story_triggers[4]["x"] + 30.0, 320)
	level_camera_snap()
	await _wait(1.6)
	_capture("story_radio")
	player.global_position = Vector2(level._layout.arena_x + 80.0, 300)
	await _wait(2.0)
	Story._layer.advance()
	await _wait(0.6)
	_capture("story_boss_intro")
	Story.skip_cinematic()
	await _wait(1.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.is_boss:
			var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
			lethal.ignore_invulnerability = true
			lethal.bypass_guard = true
			enemy.health.take_damage(lethal)
	await _wait(4.6)
	for i in 4:
		Story._layer.advance()
		Story._layer.advance()
	await _wait(1.0)
	_capture("story_epilogue")
	Story.skip_cinematic()
	await _wait(1.5)
	_capture("story_chapter_end")


## 第二章劇情：在第一章場景上播放第二章的過場與章節卡，檢查講者、頭像與文字。
func _run_story_ch2() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _wait(0.5)
	Story.skip_cinematic()
	for id in [&"prologue"]:
		Story._seen[id] = true
	await _wait(0.5)
	Story.play(&"c2_prologue")
	await _wait(0.5)
	for i in 2:
		Story._layer.advance()
		Story._layer.advance()
	await _wait(0.8)
	_capture("story2_prologue")
	Story.skip_cinematic()
	await _wait(0.5)
	Story.play(&"c2_boss_intro")
	await _wait(0.5)
	for i in 2:
		Story._layer.advance()
		Story._layer.advance()
	await _wait(0.8)
	_capture("story2_boss_intro")
	Story.skip_cinematic()
	await _wait(0.5)
	Story.play(&"c2_radio_voice")
	await _wait(2.0)
	_capture("story2_voice")
	var info := Story.chapter_info(&"chapter_02")
	_show_chapter_card(level, str(info["title"]), str(info["subtitle"]))
	await _wait(1.6)
	_capture("story2_chapter_title")


func _show_chapter_card(level: Level, title: String, subtitle: String) -> void:
	level._show_chapter_card(title, subtitle, false)


## 義體能力與補給點：背包義體頁、補給點貨架、電磁脈衝與超頻的畫面。
func _run_supply() -> void:
	var data := NewEnemiesSuite.arena_data()
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load("res://data/lighting/facility.tres")
	data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	var floor_y := 20 * 16.0
	player.global_position = Vector2(12 * 16.0, floor_y)
	level_camera_snap()
	Progression.add_credits(420)
	var station := ShopStation.new()
	station.configure(load("res://data/shops/supply.tres"), Vector2i(14, 19))
	station.position = Vector2(14 * 16.0 + 8.0, floor_y)
	level._entities.add_child(station)
	await _wait(1.0)
	_capture("supply_station")
	station._open()
	await _wait(0.9)
	_capture("supply_shop")
	station._screen.close()
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	inventory.select_tab(inventory.page_index(CyberPage))
	await _wait(0.9)
	_capture("supply_cyber_locked")
	inventory._pages[inventory.page_index(CyberPage)].activate()
	await _wait(0.6)
	_capture("supply_cyber_unlocked")
	inventory.close()
	await _wait(0.3)
	# 電磁脈衝：三隻敵人在身邊。
	for x in [18.0, 21.0]:
		var enemy := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
		enemy.position = Vector2(x * 16.0, floor_y)
		level._entities.add_child(enemy)
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	ProjectilePool.spawn(spec, player.global_position + Vector2(70, -24), Vector2.LEFT, Combat.Team.ENEMY)
	await _wait(0.4)
	player.cyber.charge = 100.0
	player.cyber.try_activate()
	await _wait(0.18)
	_capture("supply_emp")
	await _wait(1.0)
	_capture("supply_emp_stunned")


## 成長系統：HUD 的信用點、背包改裝頁（金額不足、買得起、買完後）。
func _run_progression() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	player.global_position = Vector2(14 * 16.0, 14 * 16.0)
	level_camera_snap()
	player.loadout.equip(load("res://data/weapons/rifle.tres"))
	Progression.add_credits(85)
	await _wait(1.0)
	_capture("progress_hud")
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	var tab := inventory.page_index(UpgradesPage)
	inventory.select_tab(tab)
	await _wait(0.9)
	_capture("progress_upgrades_poor")
	Progression.add_credits(400)
	inventory._pages[tab].refresh()
	await _wait(0.5)
	_capture("progress_upgrades_rich")
	inventory._pages[tab].activate()
	await _wait(0.6)
	_capture("progress_upgrades_bought")
	inventory.close()


## 背景故事收集：第一章的裂縫牆與隱藏房間、撿取提示、背包裡閱讀文件與收集進度。
func _run_collectibles() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var floor_y := 20 * 16.0
	player.global_position = Vector2(30 * 16.0, floor_y)
	level_camera_snap()
	await _wait(1.2)
	_capture("collect_wall")
	var wall: Breakable = null
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Breakable and (node as Breakable).data.look == BreakableData.Look.WALL:
			wall = node
			break
		stack.append_array(node.get_children())
	wall.hit_by_projectile(DamageInfo.create(99, Combat.Team.PLAYER, &"shot"))
	await _wait(0.8)
	_capture("collect_room_open")
	player.global_position = Vector2(35.0 * 16.0, floor_y)
	level_camera_snap()
	Input.action_press(&"move_right")
	await _wait(0.8)
	Input.action_release(&"move_right")
	_capture("collect_pickup_toast")
	StoryItems.acquire(&"doc_sky_flyer", false)
	StoryItems.acquire(&"doc_cargo_manifest", false)
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	var story_tab := inventory.page_index(StoryItemsPage)
	inventory.select_tab(story_tab)
	await _wait(0.9)
	inventory._pages[story_tab]._select(inventory._pages[story_tab]._entries.size() - 1)
	await _wait(0.6)
	_capture("collect_inventory")
	inventory.close()


## 第二章新敵人：切割者的蓄力與撲擊、迷彩獵手（暗處隱形／燈下現形）、維修機的光束與護盾、精銳保全。
func _run_new_enemies() -> void:
	var data := NewEnemiesSuite.arena_data()
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load("res://data/lighting/facility.tres")
	data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	var floor_y := 20 * 16.0
	player.global_position = Vector2(12 * 16.0, floor_y)
	level_camera_snap()
	var slasher := _spawn_enemy(level, "res://data/enemies/slasher.tres", 22.0)
	while not slasher.fsm.is_in(&"windup"):
		await _wait(0.05)
	await _wait(0.3)
	_capture("enemies2_slasher_windup")
	while not slasher.fsm.is_in(&"leap"):
		await _wait(0.03)
	await _wait(0.12)
	_capture("enemies2_slasher_leap")
	slasher.queue_free()
	# 兩隻迷彩獵手：右邊那隻站在燈下現形，左邊那隻在暗處隱形。
	var hidden := _spawn_enemy(level, "res://data/enemies/stalker.tres", 16.5)
	var lit := _spawn_enemy(level, "res://data/enemies/stalker.tres", 24.0)
	for e in [hidden, lit]:
		e.set_physics_process(false)
	var lamp := LightKit.create_point_light(Color(1.0, 0.85, 0.6), 110.0, 1.6, false)
	lamp.global_position = lit.global_position + Vector2(0, -40)
	level.add_child(lamp)
	player.global_position = Vector2(8 * 16.0, floor_y)
	level_camera_snap()
	for step in 40:
		await _wait(0.05)
		hidden._update_visibility(0.05)
		lit._update_visibility(0.05)
		hidden.queue_redraw()
		lit.queue_redraw()
	_capture("enemies2_stalker_cloak")
	hidden.queue_free()
	lit.queue_free()
	lamp.queue_free()
	# 維修機替保全加護盾。
	var grunt := _spawn_enemy(level, "res://data/enemies/grunt.tres", 26.0)
	var elite := _spawn_enemy(level, "res://data/enemies/elite_grunt.tres", 30.0)
	var drone := _spawn_enemy(level, "res://data/enemies/repair_drone.tres", 28.0)
	drone.position.y = floor_y - 70.0
	player.global_position = Vector2(14 * 16.0, floor_y)
	level_camera_snap()
	for e in [grunt, elite]:
		e.set_physics_process(false)
	while not drone.fsm.is_in(&"channel"):
		await _wait(0.05)
		grunt.queue_redraw()
		elite.queue_redraw()
	await _wait(0.5)
	_capture("enemies2_repair_beam")
	while grunt.shield == 0 and elite.shield == 0:
		await _wait(0.05)
	for i in 6:
		await _wait(0.1)
		grunt.queue_redraw()
		elite.queue_redraw()
	_capture("enemies2_shielded")


func _spawn_enemy(level: Level, path: String, x_tile: float) -> Enemy:
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(x_tile * 16.0, 20 * 16.0)
	level._entities.add_child(enemy)
	return enemy


## 可破壞物與環境機關：用測試地圖（tests/fixtures/props_map.json）拍破壞、爆炸、閘門、升降梯與斷電。
func _run_props() -> void:
	var data := PropsSuite.level_data()
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load("res://data/lighting/facility.tres")
	data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	var feet := 19 * 16.0
	player.global_position = Vector2(12 * 16.0, feet)
	level_camera_snap()
	await _wait(1.5)
	_capture("props_overview")
	# 玻璃牆：連打幾槍。
	var wall := _prop_at(level, Breakable, 30)
	var barrel := _prop_at(level, Breakable, 20)
	var info := DamageInfo.create(2, Combat.Team.PLAYER, &"shot")
	wall.hit_by_projectile(info)
	await _wait(0.4)
	_capture("props_glass_cracked")
	wall.hit_by_projectile(DamageInfo.create(9, Combat.Team.PLAYER, &"shot"))
	await _wait(0.25)
	_capture("props_glass_broken")
	# 油桶：爆炸瞬間。
	player.global_position = Vector2(14 * 16.0, feet)
	level_camera_snap()
	barrel.hit_by_projectile(DamageInfo.create(9, Combat.Team.PLAYER, &"shot"))
	await _wait(0.34)
	_capture("props_barrel_blast")
	await _wait(1.0)
	# 開關與閘門。
	var channel_switch := _prop_at(level, ChannelSwitch, 36)
	player.global_position = Vector2(36 * 16.0, feet)
	level_camera_snap()
	await _wait(1.0)
	_capture("props_gate_closed")
	channel_switch.toggle()
	await _wait(1.2)
	_capture("props_gate_open")
	# 升降梯：站上去。
	var lift := _prop_at(level, Lift, 50)
	player.global_position = lift.global_position + Vector2(0, -2)
	level_camera_snap()
	await _wait(2.6)
	_capture("props_lift")
	# 電力開關：斷電。
	var power_switch := _prop_at(level, PowerSwitch, 56)
	player.global_position = Vector2(55 * 16.0, feet)
	level_camera_snap()
	await _wait(1.0)
	_capture("props_power_on")
	power_switch.toggle()
	await _wait(2.5)
	_capture("props_power_cut")


func _prop_at(level: Level, type: Script, column: int) -> Node:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_script() == type and node.get("cell") != null and (node.get("cell") as Vector2i).x == column:
			return node
		stack.append_array(node.get_children())
	return null


## 格擋：舉盾、完美格擋反彈、護盾能量條。
func _run_block() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(340, 320)
	# 清掉場上敵人，只留一個標靶，讓畫面只呈現格擋本身。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	var dummy_data := load("res://data/enemies/grunt.tres") as EnemyData
	var dummy := dummy_data.behavior.new() as Enemy
	dummy.configure(dummy_data)
	dummy.position = player.global_position + Vector2(150, 0)
	player.get_parent().add_child(dummy)
	dummy.set_physics_process(false)
	level_camera_snap()
	await _settle(10)
	var screen := get_viewport().get_canvas_transform() * (player.global_position + Vector2(90, -16))
	Input.warp_mouse(screen * (Vector2(get_window().size) / get_viewport().get_visible_rect().size))
	await _settle(4)
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	# 先擋一發消耗能量，再在完美格擋時間窗內反彈一發。
	Input.action_press(&"block")
	await _wait(0.3)
	ProjectilePool.spawn(spec, player.aim_origin() + Vector2(16, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _wait(0.2)
	Input.action_release(&"block")
	await _settle(2)
	Input.action_press(&"block")
	ProjectilePool.spawn(spec, player.aim_origin() + Vector2(14, -1), Vector2.LEFT, Combat.Team.ENEMY)
	await _settle(3)
	_capture("block_parry")
	await _wait(0.12)
	_capture("block_reflect")
	Input.action_release(&"block")


## 法線貼圖：凜旁邊放一盞暖色燈，對照高品質（法線貼圖＋輪廓光）與低品質（平面貼圖）。
func _run_normals() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(20 * layout.tile_size + 8.0, layout.surface_heights[20] - 2.0)
	level_camera_snap()
	Input.action_press(&"aim_right")
	var torch := LightKit.create_point_light(Color(1.0, 0.62, 0.3), 170.0, 1.8, false, false)
	torch.global_position = player.global_position + Vector2(-70, -40)
	level.add_child(torch)
	await _wait(4.6)
	_capture("normals_high")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	await _wait(0.5)
	_capture("normals_low")
	Settings.set_light_quality(LightQuality.DEFAULT_TIER)
	Input.action_release(&"aim_right")


## 戰鬥光影：爆炸閃光、閃電、低血量暗角、敵人攻擊預兆的紅光。
func _run_combat_light() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(30 * layout.tile_size + 8.0, layout.surface_heights[30] - 2.0)
	level_camera_snap()
	Input.action_press(&"aim_right")
	await _wait(4.6)
	_capture("combat_calm")
	Fx.explosion(player.global_position + Vector2(130, -10), 44.0, 0, Combat.Team.ENEMY, &"test")
	await _wait(0.06)
	_capture("combat_explosion")
	await _wait(0.8)
	level._lighting._lightning_gap = 0.0
	level._lighting.strike()
	await _wait(0.05)
	_capture("combat_lightning")
	await _wait(1.5)
	var dummy_data := load("res://data/enemies/grunt.tres") as EnemyData
	var dummy := dummy_data.behavior.new() as Enemy
	dummy.configure(dummy_data)
	dummy.position = player.global_position + Vector2(140, 0)
	player.get_parent().add_child(dummy)
	await _settle(4)
	dummy._start_telegraph(2.0)
	await _wait(0.35)
	_capture("combat_telegraph")
	dummy.queue_free()
	EventBus.player_health_changed.emit(1, 6)
	await _wait(1.4)
	_capture("combat_low_health")
	EventBus.player_health_changed.emit(6, 6)
	Input.action_release(&"aim_right")


## 光影品質：霓虹市集在高／低品質的對照、停電時場景燈熄滅，以及設定畫面的光影品質選項。
func _run_quality() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(115 * layout.tile_size + 8.0, layout.surface_heights[115] - 2.0)
	level_camera_snap()
	Input.action_press(&"aim_right")
	await _wait(4.6)
	_capture("quality_high")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	await _wait(0.5)
	_capture("quality_low")
	Settings.set_light_quality(LightQuality.DEFAULT_TIER)
	await _wait(0.3)
	# 停電：供電下降，各盞燈依序熄滅。
	EventBus.lighting_override_requested.emit(&"blackout", load("res://data/lighting/blackout.tres"), 2.0)
	await _wait(0.9)
	_capture("quality_power_down")
	await _wait(1.6)
	_capture("quality_blackout")
	EventBus.lighting_override_cleared.emit(&"blackout", 0.5)
	Input.action_release(&"aim_right")
	var settings := SettingsScreen.new()
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	layer.add_child(settings)
	settings._tabs.current_tab = 2
	await _settle(10)
	_capture("quality_settings")


## 亮度設定：停電走廊在亮度 0%、50%（設計值）、100% 的對照，以及設定畫面的亮度滑桿。
func _run_brightness() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(275 * layout.tile_size + 8.0, layout.checkpoints[3].y - 2.0)
	level_camera_snap()
	Input.action_press(&"aim_right")
	await _wait(4.6)
	for value in [0.0, 0.5, 1.0]:
		Settings.set_brightness(value)
		await _wait(0.4)
		_capture("brightness_%d" % int(value * 100.0))
	Settings.set_brightness(Settings.BRIGHTNESS_DEFAULT)
	Input.action_release(&"aim_right")
	var settings := SettingsScreen.new()
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	layer.add_child(settings)
	settings._tabs.current_tab = 2
	await _settle(10)
	_capture("brightness_settings")


## 後製：同一個畫面開啟與關閉後製的對照，以及暫停選單（介面不受後製影響）。
func _run_postfx() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(115 * layout.tile_size + 8.0, layout.surface_heights[115] - 2.0)
	level_camera_snap()
	Input.action_press(&"aim_right")
	await _wait(4.6)
	_capture("postfx_on")
	level._post.visible = false
	await _settle(4)
	_capture("postfx_off")
	level._post.visible = true
	level._pause_menu.open()
	await _wait(0.4)
	_capture("postfx_menu")
	level._pause_menu.close()
	Input.action_release(&"aim_right")


## 光影：第一章五個區段各一張（環境光、光池、霧、背景），以及停電覆蓋。
func _run_lighting() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	# 直接傳送會連續觸發沿路的通訊，先標記為看過。
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	# 每個區段取中段的一欄，站在該欄的地面上。
	var layout: LevelLayout = level._layout
	var spots := {}
	for entry in [["rooftop", 30], ["market", 115], ["freight", 200], ["facility", 252], ["corridor", 275], ["hangar", 330]]:
		var tile: int = entry[1]
		spots[entry[0]] = Vector2(tile * layout.tile_size + 8.0, layout.surface_heights[tile] - 2.0)
	# 設施入口是室內，最上面的「地面」是天花板，改用檢查點的高度。
	for name in ["facility", "corridor", "hangar"]:
		spots[name].y = layout.checkpoints[3].y - 2.0
	Input.action_press(&"aim_right")
	for zone in spots:
		player.global_position = spots[zone]
		level_camera_snap()
		await _wait(4.6 if zone == "rooftop" else 1.4)
		_capture("lighting_" + zone)
		if zone == "market":
			# 停電事件：暫時覆蓋成幾乎全黑，再淡回區段光影。
			EventBus.lighting_override_requested.emit(&"blackout", load("res://data/lighting/blackout.tres"), 0.3)
			await _wait(1.0)
			_capture("lighting_blackout")
			EventBus.lighting_override_cleared.emit(&"blackout", 0.3)
			await _wait(0.6)
	Input.action_release(&"aim_right")


## 背包：武器與彈藥、消耗品（使用醫療針）、劇情道具（NEW）、角色狀態，以及開啟動畫的中途畫面。
func _run_inventory() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	player.global_position = Vector2(330, 320)
	level_camera_snap()
	for path in ["res://data/weapons/smg.tres", "res://data/weapons/spread.tres", "res://data/weapons/laser.tres"]:
		player.loadout.equip(load(path))
	player.loadout.select(1)
	for i in 14:
		player.loadout.consume_ammo()
	player.loadout.select(0)
	player.consumables.add(ConsumableBag.find(&"med_injector"))
	player.consumables.add(ConsumableBag.find(&"med_injector"))
	var info := DamageInfo.create(3, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	GameState.kills = 17
	GameState.finishers = 3
	GameState.run_time = 312.4
	await _wait(0.5)
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	await _wait(0.07)
	_capture("inventory_opening")
	await _wait(0.8)
	inventory._pages[0]._select(1)
	await _wait(0.5)
	_capture("inventory_weapons")
	var consumables_tab := inventory.page_index(ConsumablesPage)
	inventory.select_tab(consumables_tab)
	await _wait(0.6)
	_capture("inventory_consumables")
	inventory._pages[consumables_tab].activate()
	await _wait(0.2)
	_capture("inventory_use")
	inventory.select_tab(inventory.page_index(StoryItemsPage))
	await _wait(0.6)
	_capture("inventory_story")
	inventory.select_tab(inventory.page_index(StatusPage))
	await _wait(0.9)
	_capture("inventory_status")
	inventory.close()


## 劇情道具：開場過場結束後取得委託單的提示、擊敗頭目取得資料碎片的提示、四個道具圖示。
func _run_story_items() -> void:
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _wait(1.0)
	Story.skip_cinematic()
	await _wait(0.9)
	_capture("story_items_order")
	var player := level.player
	player.health.setup(999, 0.0)
	# 直接傳送到戰場會連續觸發沿路的通訊，先標記為看過，避免通訊框蓋住提示。
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	player.global_position = Vector2(level._layout.arena_x + 80.0, 300)
	await _wait(2.0)
	Story.skip_cinematic()
	await _wait(1.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.is_boss:
			var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
			lethal.ignore_invulnerability = true
			lethal.bypass_guard = true
			enemy.health.take_damage(lethal)
	# 等頭目倒下、取得資料碎片後，拍下提示。
	for i in 120:
		if StoryItems.owns(&"nest07_shard"):
			break
		await _wait(0.1)
	await _wait(0.4)
	_capture("story_items_shard")
	level.queue_free()
	await _settle(2)
	await _capture_item_sheet()


## 四個劇情道具圖示放大 4 倍排開（最近鄰），確認放大後依然銳利。
func _capture_item_sheet() -> void:
	var layer := CanvasLayer.new()
	var root := UiKit.full_rect_root(layer)
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BG_FAR
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 90)
	row.add_theme_constant_override(&"separation", 24)
	root.add_child(row)
	for item in StoryItems.catalog():
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(112, 0)
		row.add_child(column)
		var icon := TextureRect.new()
		icon.texture = ItemIcons.item(item.icon)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(ItemIcons.ICON_SIZE * 4)
		column.add_child(icon)
		column.add_child(UiKit.label(item.display_name, 11, item.color, HORIZONTAL_ALIGNMENT_CENTER))
	await _settle(4)
	_capture("story_items_icons")
	layer.queue_free()


## 消耗品：屋頂上的醫療針與拾取提示、撿起後的 HUD 數量、受傷後快速使用。
func _run_consumables() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	Input.action_press(&"aim_right")
	player.global_position = Vector2(760, 240)
	level_camera_snap()
	await _wait(4.5)
	_capture("consumables_pickup")
	player.global_position = Vector2(808, 240)
	await _wait(0.6)
	player.consumables.add(ConsumableBag.find(&"shield_cell"))
	var info := DamageInfo.create(3, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	await _wait(0.8)
	player.use_consumable(&"med_injector")
	await _wait(0.12)
	_capture("consumables_use")
	Input.action_release(&"aim_right")


## 換彈：手槍彈匣偏低的換彈提示、打空後自動換彈（槍口壓低、彈藥環顯示進度）。
func _run_reload() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(330, 320)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level_camera_snap()
	Input.action_press(&"aim_right")
	await _wait(4.5)
	for i in 10:
		player.loadout.consume_ammo()
	await _wait(0.3)
	_capture("reload_low")
	player.loadout.consume_ammo()
	player.loadout.consume_ammo()
	await _wait(0.45)
	_capture("reload_progress")
	Input.action_release(&"aim_right")


## 武器陣容：每把玩家武器各開火一段時間，拼成一張 4×2 的總覽圖。
func _run_weapons() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(330, 320)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level_camera_snap()
	Input.action_press(&"aim_right")
	# 等章節標題淡出。
	await _wait(4.5)
	var ids := ["pistol", "smg", "rifle", "spread", "launcher", "laser", "railgun"]
	var sheet := Image.create(1280, 360, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in ids.size():
		player.loadout.equip(load("res://data/weapons/%s.tres" % ids[i]))
		await _settle(4)
		Input.action_press(&"shoot")
		await _wait(0.35)
		var shot := get_viewport().get_texture().get_image()
		Input.action_release(&"shoot")
		shot.convert(Image.FORMAT_RGBA8)
		# 以角色為中心裁一塊，縮成 1/4 格。
		var center := get_viewport().get_canvas_transform() * (player.global_position + Vector2(70, -26))
		var scale := float(shot.get_width()) / get_viewport().get_visible_rect().size.x
		var crop := Rect2i(Vector2i((center * scale) - Vector2(240, 135)), Vector2i(480, 270)).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		var tile := shot.get_region(crop)
		tile.resize(320, 180)
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i((i % 4) * 320, (i / 4) * 180))
		await _wait(0.4)
	Input.action_release(&"aim_right")
	var path := _out_dir.path_join("weapons_roster.png")
	print("saved %s (%s)" % [path, error_string(sheet.save_png(path))])


## 動態 HUD：受傷彈出（殘影碎裂）、低血量常駐、破防、彈藥環低彈藥。
func _run_dynamic_hud() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.global_position = Vector2(330, 320)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level_camera_snap()
	# 用右搖桿瞄準，不受系統滑鼠位置影響。
	Input.action_press(&"aim_right")
	await _wait(3.5)
	_capture("dynamic_hud_idle")
	var info := DamageInfo.create(2, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	await _wait(0.12)
	_capture("dynamic_hud_hit")
	await _wait(0.6)
	player.health.take_damage(info)
	player.loadout.equip(load("res://data/weapons/spread.tres"))
	Input.action_press(&"shoot")
	await _wait(1.6)
	Input.action_release(&"shoot")
	await _wait(0.6)
	_capture("dynamic_hud_low")
	Input.action_press(&"block")
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	await _wait(0.3)
	player.guard = 1.0
	ProjectilePool.spawn(spec, player.aim_origin() + Vector2(16, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _wait(0.25)
	_capture("dynamic_hud_break")
	Input.action_release(&"block")
	Input.action_release(&"aim_right")


## 滑鼠瞄準：準星、擴散、命中標記、武器欄。
func _run_mouse_aim() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for path in ["res://data/weapons/spread.tres", "res://data/weapons/laser.tres"]:
		player.loadout.equip(load(path))
	player.loadout.select(0)
	player.global_position = Vector2(330, 320)
	level_camera_snap()
	await _settle(10)
	# 準星放在角色右上方（敵人方向），按住射擊。
	var screen := get_viewport().get_canvas_transform() * (player.global_position + Vector2(110, -40))
	Input.warp_mouse(screen * (Vector2(get_window().size) / get_viewport().get_visible_rect().size))
	await _settle(4)
	Input.action_press(&"shoot")
	await _settle(14)
	_capture("mouse_aim_firing")
	Input.action_release(&"shoot")
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var settings := SettingsScreen.new()
	layer.add_child(settings)
	settings._tabs.current_tab = 1
	await _settle(10)
	_capture("mouse_bindings")


func _run_settings() -> void:
	var settings := SettingsScreen.new()
	add_child(settings)
	await _settle(20)
	_capture("settings_audio")
	settings._tabs.current_tab = 1
	await _settle(10)
	settings._begin_capture(&"jump", 1)
	await _settle(10)
	_capture("settings_bindings")
	settings._cancel_capture()
	settings.queue_free()


func _shoot_at(player: Player, position: Vector2, frames: int) -> void:
	player.global_position = position
	level_camera_snap()
	await _settle(15)
	Input.action_press(&"shoot")
	Input.action_press(&"move_right")
	await _settle(frames)
	Input.action_release(&"move_right")


func level_camera_snap() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var camera := get_viewport().get_camera_2d() as LevelCamera
		if camera != null:
			camera.snap_to_target()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(file_name + ".png")
	var err := image.save_png(path)
	print("saved %s (%s) fps=%d" % [path, error_string(err), Engine.get_frames_per_second()])
