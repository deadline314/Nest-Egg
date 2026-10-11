class_name ThrowablesSuite
extends EnemySuiteBase
## 可撿取投擲物與油桶（NE-254）：資料、真正的按鍵撿起／丟出／放下、命中敵人、落地、油桶的引信與連鎖、
## 高低地形（丟上單向平台、撞牆不穿過）、與衝刺／射擊不互相卡住、重進區域不累積、第一章的擺放。
## 場地見 EnemySuiteBase：地面第 20 列、牆在欄 30～31、單向平台欄 50～56（第 16 列）。

const DIR := "res://data/throwables"
const CRATE := "res://data/throwables/crate_small.tres"
const BARREL := "res://data/throwables/fuel_barrel.tres"
const PIPE := "res://data/throwables/pipe.tres"


func run() -> void:
	_test_data()
	await _test_pick_throw_hit()
	await _test_miss_lands_and_rests()
	await _test_barrel_fuse_and_chain()
	await _test_thrown_barrel_explodes_on_contact()
	await _test_terrain()
	await _test_no_input_conflicts()
	await _test_chapter_one_placement()


func _test_data() -> void:
	var cards := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/codex/defeat_cards.json"))
	for card: Dictionary in (parsed as Dictionary).get("cards", []):
		cards[str(card.get("id", ""))] = true
	var files := DirAccess.get_files_at(DIR)
	check(files.size() >= 4, "there are several kinds of throwable (%d)" % files.size())
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var data := load(DIR.path_join(file)) as ThrowableData
		check(data != null and data.validate().is_empty(), "%s is valid: %s" % [file, data.validate() if data != null else "not ThrowableData"])
		if data != null and data.is_explosive():
			check(cards.has(String(data.source_id)), "%s's explosion has a defeat card (%s)" % [file, data.source_id])
	var light := load(CRATE) as ThrowableData
	var heavy := load(BARREL) as ThrowableData
	check(light.throw_speed > heavy.throw_speed and light.gravity < heavy.gravity and light.carry_speed_scale > heavy.carry_speed_scale,
			"weight matters: the barrel flies slower, drops faster and slows the carrier")


func _place(path: String, x_tile: float, y := FLOOR_Y) -> Throwable:
	var item := Throwable.new()
	item.configure(load(path) as ThrowableData)
	item.position = Vector2(x_tile * 16.0, y)
	level._entities.add_child(item)
	return item


func _press(action: StringName) -> void:
	Input.action_press(action)
	await physics_frames(1)
	Input.action_release(action)
	await physics_frames(1)


## 用手把右搖桿瞄準（無頭環境讀不到有效的滑鼠位置）。
func _aim(direction: Vector2) -> void:
	AimInput.set_virtual_gamepad(level.player, true)
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
	await physics_frames(3)


func _release_aim() -> void:
	for action: StringName in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		Input.action_release(action)
	AimInput.set_virtual_gamepad(level.player, false)


func _pick_up(item: Throwable) -> bool:
	await _press(&"interact")
	for i in 40:
		if level.player.carry.phase == PlayerCarry.Phase.HOLDING:
			break
		await physics_frames(1)
	return level.player.carry.is_holding() and level.player.carry.held == item


## 撿起（動作、舉在頭上、拋物線預覽）→ 往準星丟 → 打中敵人：傷害、擊退、命中回饋；木箱撞到就碎。
func _test_pick_throw_hit() -> void:
	await open_level(10.0)
	var player := level.player
	var crate := _place(CRATE, 11.0)
	var grunt := spawn(GRUNT_PATH, 22.0)
	grunt.set_physics_process(false)
	await physics_frames(3)
	check(player.carry.nearest_pickable() == crate, "the crate at the player's feet can be picked up")
	await _press(&"interact")
	check(player.carry.phase == PlayerCarry.Phase.LIFTING and player.carry.pose() == PlayerCarry.POSE_LIFT, "pressing interact starts the lift pose")
	for i in 40:
		if player.carry.phase == PlayerCarry.Phase.HOLDING:
			break
		await physics_frames(1)
	check(player.carry.is_holding() and player.carry.held == crate, "after the lift the crate is held")
	check(crate.global_position.y < player.global_position.y - 40.0, "it is carried overhead (%.0f above the feet)" % (player.global_position.y - crate.global_position.y))
	await _aim(Vector2(1, -0.12).normalized())
	await physics_frames(2)
	check(player.carry._preview.size() > 3 and player.carry._preview_land != Vector2.INF, "holding shows the throw arc and landing point")
	var ammo := player.loadout.mag_in(player.loadout.active_slot)
	var before := grunt.health.current
	await _press(&"shoot")
	check(player.carry.pose() == PlayerCarry.POSE_THROW and crate.state == Throwable.State.FLYING, "shoot throws it with the throw pose")
	check(player.loadout.mag_in(player.loadout.active_slot) == ammo, "throwing does not fire the gun")
	for i in 90:
		if not is_instance_valid(crate):
			break
		await physics_frames(1)
	check(grunt.health.current < before, "the thrown crate hurts the enemy (%d -> %d)" % [before, grunt.health.current])
	check(not is_instance_valid(crate), "a crate breaks when it hits")
	_release_aim()
	await end_level(level)


## 丟空：落地彈一下後躺好，還能再撿；不會卡進地面。
func _test_miss_lands_and_rests() -> void:
	await open_level(10.0)
	var pipe := _place(PIPE, 11.0)
	await physics_frames(3)
	await _pick_up(pipe)
	await _aim(Vector2(1, -0.5).normalized())
	await _press(&"shoot")
	for i in 240:
		if pipe.state == Throwable.State.REST and pipe.is_on_floor():
			break
		await physics_frames(1)
	await physics_frames(10)
	check(pipe.state == Throwable.State.REST and absf(pipe.global_position.y - FLOOR_Y) < 2.0, "a missed throw lands on the floor and rests (y %.1f)" % pipe.global_position.y)
	check(pipe.global_position.x > 12.0 * 16.0, "it flew forward (x %.0f)" % pipe.global_position.x)
	level.player.global_position.x = pipe.global_position.x
	await physics_frames(2)
	check(level.player.carry.nearest_pickable() == pipe, "it can be picked up again")
	_release_aim()
	await end_level(level)


## 油桶被子彈打壞：先燒引信（有預兆、不會立刻炸），再爆炸傷到敵人與附近的玩家；旁邊的油桶被炸到也會點燃、晚一點才爆。
func _test_barrel_fuse_and_chain() -> void:
	await open_level(10.0)
	var player := level.player
	var first := _place(BARREL, 40.0)
	var second := _place(BARREL, 42.5)
	var grunt := spawn(GRUNT_PATH, 41.0)
	grunt.set_physics_process(false)
	place_player(44.0)
	player.set_physics_process(false)
	for i in 300:  # 等開場的無敵時間過去
		if not player.health.is_invulnerable():
			break
		await physics_frames(1)
	var grunt_before := grunt.health.current
	var player_before := player.health.current
	var order: Array[String] = []
	first.finished.connect(func(_t: Throwable) -> void: order.append("first"))
	second.finished.connect(func(_t: Throwable) -> void: order.append("second"))
	for i in 2:
		shoot_from(first.world_center() + Vector2(-60, 0), Vector2.RIGHT)
		await physics_frames(6)
	check(first.is_fuse_lit() and is_instance_valid(first), "a shot barrel lights its fuse instead of blowing up at once")
	for i in 120:
		if order.size() >= 2:
			break
		await physics_frames(1)
	check(order == ["first", "second"], "the blast sets off the neighbour after its own fuse: %s" % [order])
	await physics_frames(4)  # 爆炸在下一個物理影格才結算傷害
	check(grunt.health.current < grunt_before, "the blast hurts the enemy")
	check(player.health.current < player_before, "the blast hurts a player standing too close")
	player.set_physics_process(true)
	await end_level(level)


## 丟出的油桶撞到敵人立刻爆炸。
func _test_thrown_barrel_explodes_on_contact() -> void:
	await open_level(10.0)
	var barrel := _place(BARREL, 11.0)
	var grunt := spawn(GRUNT_PATH, 18.0)
	grunt.set_physics_process(false)
	await physics_frames(3)
	await _pick_up(barrel)
	check(level.player.carry.speed_scale() < 0.7, "a heavy barrel slows the carrier")
	await _aim(Vector2(1, -0.25).normalized())
	var before := grunt.health.current
	var blasts_before: Vector2 = Fx.get("_last_blast_position")
	await _press(&"shoot")
	var blast_at := Vector2.INF
	for i in 120:
		if not is_instance_valid(barrel):
			break
		blast_at = barrel.world_center()
		await physics_frames(1)
	await physics_frames(4)
	check(not is_instance_valid(barrel) and grunt.health.current < before, "a thrown barrel explodes on the enemy (%d -> %d)" % [before, grunt.health.current])
	# 爆炸畫面走全遊戲共用的火球（NE-95），不是油桶自己的一套。
	var blast: Vector2 = Fx.get("_last_blast_position")
	check(blast != blasts_before and blast.distance_to(blast_at) < 24.0, "the barrel blast is drawn by the shared fireball at the barrel (%s, barrel %s)" % [blast, blast_at])
	_release_aim()
	await end_level(level)


## 高低地形：往斜上丟能落到單向平台上；往牆丟不會穿過去；往下丟落在腳邊的地上。
func _test_terrain() -> void:
	await open_level(46.0)
	var player := level.player
	var crate := _place(PIPE, 46.0)
	await physics_frames(3)
	await _pick_up(crate)
	await _aim(Vector2(0.55, -1.0).normalized())
	await _press(&"shoot")
	for i in 240:
		if crate.state == Throwable.State.REST and crate.is_on_floor():
			break
		await physics_frames(1)
	await physics_frames(10)
	var on_platform := absf(crate.global_position.y - 16.0 * 16.0) < 2.0 and crate.global_position.x > 50.0 * 16.0 and crate.global_position.x < 57.0 * 16.0
	check(on_platform, "an upward throw lands on the one-way platform above (%s)" % crate.global_position)
	place_player(34.0)
	var wall := _place(PIPE, 34.0)
	await physics_frames(3)
	await _pick_up(wall)
	await _aim(Vector2(-1, -0.05).normalized())
	await _press(&"shoot")
	for i in 180:
		if wall.state == Throwable.State.REST:
			break
		await physics_frames(1)
	await physics_frames(10)
	check(wall.global_position.x > 32.0 * 16.0 - 1.0, "a throw into the wall does not pass through it (x %.0f)" % wall.global_position.x)
	check(wall.state == Throwable.State.REST and absf(wall.global_position.y - FLOOR_Y) < 2.0, "it drops to the floor in front of the wall")
	# 從高處平台（欄 62～65，第 12 列）往下丟：落到下面的地上。
	place_player(63.5, 12.0 * 16.0)
	var chunk := _place(PIPE, 63.5, 12.0 * 16.0)
	await physics_frames(5)
	await _pick_up(chunk)
	await _aim(Vector2(0.6, 0.8).normalized())
	await _press(&"shoot")
	for i in 240:
		if chunk.state == Throwable.State.REST and chunk.is_on_floor():
			break
		await physics_frames(1)
	await physics_frames(10)
	check(absf(chunk.global_position.y - FLOOR_Y) < 2.0 and chunk.global_position.x > 65.0 * 16.0, "a downward throw from the high ledge lands on the floor below (%s)" % chunk.global_position)
	_release_aim()
	player.velocity = Vector2.ZERO
	await end_level(level)


## 不互相卡住：拿著時射擊鍵只丟不開槍；衝刺會先放下再衝；放下後可以正常開槍；受傷會放下。
func _test_no_input_conflicts() -> void:
	await open_level(10.0)
	var player := level.player
	var crate := _place(CRATE, 11.0)
	await physics_frames(3)
	await _pick_up(crate)
	var x_before := player.global_position.x
	Input.action_press(&"move_right")
	await _press(&"dash")
	Input.action_release(&"move_right")
	await physics_frames(10)
	check(not player.carry.is_holding() and crate.state == Throwable.State.REST, "dashing puts the crate down")
	check(player.global_position.x > x_before + 20.0, "and the dash still happens (%.0f -> %.0f)" % [x_before, player.global_position.x])
	player.global_position.x = crate.global_position.x
	await physics_frames(20)
	await _pick_up(crate)
	await _press(&"interact")
	check(not player.carry.is_holding() and crate.state == Throwable.State.REST, "interact puts it down")
	await physics_frames(20)
	var ammo := player.loadout.mag_in(player.loadout.active_slot)
	await _press(&"shoot")
	check(player.loadout.mag_in(player.loadout.active_slot) == ammo - 1, "with empty hands the gun fires again")
	player.global_position.x = crate.global_position.x
	await physics_frames(20)
	await _pick_up(crate)
	player.health.grant_invulnerability(0.0)
	player.hurtbox.receive(hit_player())
	await physics_frames(2)
	check(not player.carry.is_holding(), "getting hit drops what you carry")
	await end_level(level)


func hit_player() -> DamageInfo:
	var info := DamageInfo.create(1, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info


## 第一章：至少兩個區域擺了可投擲物與油桶；離出入口夠遠（互動鍵不會撿錯）；數量在上限內；重進區域不累積。
func _test_chapter_one_placement() -> void:
	var areas_with_items := 0
	for path in ["res://data/levels/ch1_street.tres", "res://data/levels/ch1_warehouse.tres"]:
		var data := load(path) as LevelData
		var layout := LevelBuilder.parse(data)
		var items := 0
		var barrels := 0
		var portals: Array[float] = []
		for spawn in layout.spawns:
			if spawn["resource"] is PortalData:
				portals.append((spawn["position"] as Vector2).x)
		for spawn in layout.spawns:
			var res: Resource = spawn["resource"]
			if res is ThrowableData:
				items += 1
				barrels += 1 if (res as ThrowableData).is_explosive() else 0
				var x := (spawn["position"] as Vector2).x
				for portal_x in portals:
					check(absf(x - portal_x) > 48.0, "%s: throwable at x %.0f is clear of the doorway at %.0f" % [data.id, x, portal_x])
		check(items <= Level.MAX_THROWABLES, "%s stays under the throwable cap (%d)" % [data.id, items])
		if items > 0 and barrels > 0:
			areas_with_items += 1
	check(areas_with_items >= 2, "chapter 1 has throwables and barrels in at least two areas (%d)" % areas_with_items)
	# 地圖字元全章通用（由產生器 tools/level/build_ch1.py 登記）：同一個字元在每個區域都是同一種東西，投擲物不能借用別的字元。
	var meaning: Dictionary = {}
	for file in DirAccess.get_files_at("res://data/levels"):
		if not (file.begins_with("ch1_") and file.ends_with(".tres")):
			continue
		var area := load("res://data/levels/" + file) as LevelData
		for c: String in area.legend:
			var res: Resource = area.legend[c]
			if res == null or res.resource_path.is_empty() or res.resource_path.contains("::"):
				continue  # 出入口是各區域自己的內嵌資源，只比對共用的資源檔
			if not meaning.has(c):
				meaning[c] = res.resource_path
			check(meaning[c] == res.resource_path, "%s: map character '%s' means %s here but %s elsewhere" % [file, c, res.resource_path, meaning[c]])
	# 重進同一個區域：數量跟地圖一樣，不會越來越多。
	var warehouse := load("res://data/levels/ch1_warehouse.tres") as LevelData
	level = await start_level(warehouse)
	var first := runner.get_tree().get_nodes_in_group(Throwable.GROUP).size()
	await end_level(level)
	level = await spawn_level(warehouse)
	var second := runner.get_tree().get_nodes_in_group(Throwable.GROUP).size()
	check(first > 0 and first == second, "re-entering the warehouse places the same number of throwables (%d, %d)" % [first, second])
	await end_level(level)
