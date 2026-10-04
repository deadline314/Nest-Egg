class_name ExoticEnemiesSuite
extends EnemySuiteBase
## 飛行、攀附、軌道、懸浮與群體的新敵人（NE-99）：井道蝙蝠機（拍翼隨速度、俯衝、撞牆暈眩）、攀牆者（貼附幾何、撲出、落在任何表面）、
## 吊軌砲（沿軌道換位、慣性）、雲母（脈動漂浮、放電）、蜂群（群集、1 點生命、同屏多隻的效能）。

const BAT_PATH := "res://data/enemies/shaft_bat.tres"
const GECKO_PATH := "res://data/enemies/wall_gecko.tres"
const RAIL_PATH := "res://data/enemies/rail_cannon.tres"
const JELLY_PATH := "res://data/enemies/cloud_jelly.tres"
const BEE_PATH := "res://data/enemies/swarm_bee.tres"
const ALL: Array[String] = [BAT_PATH, GECKO_PATH, RAIL_PATH, JELLY_PATH, BEE_PATH]
const DT := 1.0 / 60.0
## 這道牆（欄 30～31、高 7 格）左側面的 x 與頂面的 y。
const WALL_LEFT_X := 30.0 * 16.0
const WALL_TOP_Y := (20.0 - 7.0) * 16.0
const SWARM_SIZE := 24
## 24 隻蜂群集轉向每影格的腳本時間上限（毫秒）；抓的是 O(n²) 之類的退化。
const SWARM_FRAME_BUDGET_MS := 3.0


func run() -> void:
	_test_data()
	_test_flap_follows_speed()
	await _test_surface_walker()
	await _test_bat()
	await _test_gecko()
	await _test_rail_cannon()
	await _test_jelly()
	await _test_swarm()
	await check_defeatable_on_every_difficulty(ALL)


func _test_data() -> void:
	check_enemy_data(ALL, [&"shaft_bat_contact", &"wall_gecko_contact", &"rail_cannon_shot", &"rail_cannon_contact", &"cloud_jelly_contact", &"swarm_bee_contact"])
	var skins := {}
	for path in ALL:
		var data := load(path) as EnemyData
		check(not skins.has(data.creature_skin) and not data.creature_skin.is_empty(), "%s has its own art and motion data" % data.id)
		skins[data.creature_skin] = true
		check(ResourceLoader.exists(EnemyVfx.PATH % data.id), "%s has its own effects file" % data.id)
		check(data.telegraph_time >= 0.45, "%s gives a readable warning (%.2f s)" % [data.id, data.telegraph_time])
	for id in ["shaft_bat", "wall_gecko", "rail_cannon", "swarm_bee"]:
		var creature := PartCreature.new()
		runner.get_tree().root.add_child(creature)
		check(creature.setup(id), "%s builds" % id)
		var states: Array = (RigLibrary.load_json(PartCreature.PATH % id)["states"] as Dictionary).keys()
		for state: String in states:
			for i in 30:
				creature.animate(DT, StringName(state), Vector2(60, 0), 1, 0.0)
			var finite := true
			for part_name in creature.part_names():
				var p := creature.joint_of(part_name).global_position
				finite = finite and is_finite(p.x) and is_finite(p.y)
			check(finite, "%s in state %s has finite parts" % [id, state])
		creature.queue_free()
	var jelly := ChainCreature.new()
	runner.get_tree().root.add_child(jelly)
	check(jelly.setup("cloud_jelly") and jelly.tentacle_count() == 6, "the jelly builds with six tentacles")
	for state: String in (RigLibrary.load_json(ChainCreature.PATH % "cloud_jelly")["states"] as Dictionary).keys():
		for i in 30:
			jelly.animate(DT, StringName(state))
	jelly.queue_free()


## 拍翼頻率隨飛行速度增加：同樣的狀態，飛得快的一秒內翅膀轉動的總量更大。
func _test_flap_follows_speed() -> void:
	var totals: Array[float] = []
	for speed in [0.0, 150.0]:
		var creature := PartCreature.new()
		runner.get_tree().root.add_child(creature)
		creature.setup("shaft_bat")
		for i in 40:
			creature.animate(DT, &"hover", Vector2(speed, 0), 1, 0.0)
		var wing := creature.joint_of("wing_near")
		var previous := wing.rotation
		var total := 0.0
		for i in 60:
			creature.animate(DT, &"hover", Vector2(speed, 0), 1, 0.0)
			total += absf(wing.rotation - previous)
			previous = wing.rotation
		totals.append(total)
		creature.queue_free()
	check(totals[1] > totals[0] * 1.2, "the bat flaps faster when it flies faster (%.1f vs %.1f rad per second)" % [totals[1], totals[0]])


## 貼附幾何：地面向右爬 → 撞到牆轉上牆 → 爬到牆頂繞過凸角回到頂面。
func _test_surface_walker() -> void:
	await open_level(10.0)
	var space := level.get_world_2d().direct_space_state
	var walker := SurfaceWalker.new()
	walker.radius = 5.0
	var start := Vector2(26.0 * 16.0, FLOOR_Y - walker.radius)
	var found := walker.attach(space, start + Vector2(0, -2))
	check(not found.is_empty() and (found["normal"] as Vector2) == Vector2.UP, "a body just above the floor attaches to the floor")
	var position := found["position"] as Vector2
	check(absf(position.y - (FLOOR_Y - walker.radius)) < 0.6, "attached at the body radius above the floor (%.1f)" % position.y)
	for i in 400:
		position = walker.advance(space, position, 2.0)
		if walker.normal != Vector2.UP:
			break
	check(walker.normal == Vector2.LEFT, "walking into the wall turns onto the wall face (normal %s)" % walker.normal)
	check(absf(position.x - (WALL_LEFT_X - walker.radius)) < 1.0, "stuck to the wall's face (x %.1f)" % position.x)
	for i in 400:
		position = walker.advance(space, position, 2.0)
		if walker.normal != Vector2.LEFT:
			break
	check(walker.normal == Vector2.UP, "climbing over the top edge turns back onto the top (normal %s)" % walker.normal)
	check(absf(position.y - (WALL_TOP_Y - walker.radius)) < 1.5, "walks on top of the wall (y %.1f)" % position.y)
	check(walker.angle() == 0.0 and absf(SurfaceWalker.new().angle()) < 0.001, "an upright body has no rotation")
	var ceiling := SurfaceWalker.new()
	ceiling.normal = Vector2.DOWN
	check(absf(absf(ceiling.angle()) - PI) < 0.001, "a ceiling walker is upside down")
	check(walker.land(space, Vector2(20.0 * 16.0, FLOOR_Y - 60.0), Vector2(20.0 * 16.0, FLOOR_Y + 10.0))["normal"] == Vector2.UP, "landing from the air finds the floor")
	check(walker.land(space, Vector2(20.0 * 16.0, FLOOR_Y - 60.0), Vector2(20.0 * 16.0, FLOOR_Y - 40.0)).is_empty(), "no hit means still flying")
	await end_level(level)


## 蝙蝠機：待機 → 盤旋 → 預兆 → 俯衝；撞牆暈眩後爬升。
func _test_bat() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var bat := spawn(BAT_PATH, 14.0, FLOOR_Y - 120.0) as Enemy
	place_player(12.0)
	check(bat.fsm.is_in(&"idle"), "the bat hangs until it notices the player")
	check(await wait_state(bat, &"hover", 60 * 3), "the bat circles once it notices the player")
	check(await wait_state(bat, &"lock", 60 * 8), "the bat winds up a dive")
	check(bat.is_telegraphing() and bat.data.telegraph_time >= 0.5, "the dive has a telegraph")
	var before := level.player.health.current
	check(await wait_state(bat, &"dive", 60 * 2), "the bat dives after the warning")
	for i in 90:
		await physics_frames(1)
		if not bat.fsm.is_in(&"dive"):
			break
	check(bat.fsm.is_in(&"glide") or bat.fsm.is_in(&"dizzy") or bat.fsm.is_in(&"climb"), "the dive ends in a glide or a dizzy crash")
	# 暈眩：翼不規則抽動、之後爬升
	bat.fsm.transition(&"dizzy")
	await physics_frames(5)
	check(bat._creature_state() == &"dizzy", "a crashed bat shows the dizzy animation")
	check(await wait_state(bat, &"climb", 60 * 3), "a dizzy bat recovers and climbs")
	check(level.player.health.current <= before, "the bat never heals the player")
	await end_level(level)


## 攀牆者：貼地爬行 → 發現玩家蹲伏 → 撲出 → 落在表面上貼住 → 硬直 → 繼續巡邏。
func _test_gecko() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var gecko := spawn(GECKO_PATH, 44.0, FLOOR_Y - 5.0) as Enemy
	place_player(40.0)
	await physics_frames(10)
	check(gecko._surface.normal == Vector2.UP and absf(gecko.global_position.y - (FLOOR_Y - 5.0)) < 1.5, "the gecko lies on the floor")
	check(await wait_state(gecko, &"windup", 60 * 4), "the gecko crouches when it sees the player")
	check(gecko.is_telegraphing() and gecko.data.telegraph_time >= 0.5, "the crouch is a telegraph")
	var before := level.player.health.current
	check(await wait_state(gecko, &"leap", 60 * 2), "then leaps")
	check(not gecko._attached, "it is airborne during the leap")
	check(await wait_state(gecko, &"land", 60 * 3), "it lands on a surface")
	check(gecko._attached, "and sticks to whatever it landed on")
	check(await wait_state(gecko, &"patrol", 60 * 3), "after the recovery it crawls again")
	# 倒掛在天花板：身體整個轉過來，判定框跟著表面
	gecko.fsm.transition(&"land")  # 停在原地的狀態，不讓巡邏改掉測試設定的表面
	gecko._surface.normal = Vector2.DOWN
	gecko._attached = true
	await physics_frames(3)
	check(absf(absf(gecko.creature.extra_rotation) - PI) < 0.01, "on a ceiling the whole body is upside down")
	gecko._surface.normal = Vector2.LEFT
	await physics_frames(3)
	var box := gecko.hurtbox._shape_node.shape as RectangleShape2D
	check(box.size.y > box.size.x, "on a wall the hit box turns upright (%s)" % box.size)
	check(level.player.health.current <= before, "the gecko never heals the player")
	await end_level(level)


## 吊軌砲：追蹤 → 鎖定 → 開火 → 沿軌道滑到新位置（有慣性，不超出軌道，高度不變）。
func _test_rail_cannon() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var cannon := spawn(RAIL_PATH, 40.0, FLOOR_Y - 60.0) as Enemy
	var home_x := cannon.global_position.x
	var home_y := cannon.global_position.y
	place_player(34.0)
	check(await wait_state(cannon, &"track", 60 * 4), "the cannon tracks the player")
	check(await wait_state(cannon, &"lock", 60 * 3), "then locks on")
	check(await wait_state(cannon, &"slide", 60 * 3), "after firing it slides to a new spot")
	var start_x := cannon.global_position.x
	var peak_accel := 0.0
	var last_v := cannon.velocity.x
	for i in 60 * 4:
		await physics_frames(1)
		peak_accel = maxf(peak_accel, absf(cannon.velocity.x - last_v) / DT)
		last_v = cannon.velocity.x
		check(absf(cannon.global_position.x - home_x) <= cannon.data.ability_radius + 1.0, "the cannon stays on its rail")
		if cannon.fsm.is_in(&"idle"):
			break
	check(cannon.fsm.is_in(&"idle"), "the cannon settles into its new spot")
	check(absf(cannon.global_position.x - start_x) > cannon.data.ability_radius * 0.4, "it moved a good way along the rail (%.0f px)" % absf(cannon.global_position.x - start_x))
	check(peak_accel < 400.0, "the slide accelerates smoothly (%.0f px/s²)" % peak_accel)
	check(is_equal_approx(cannon.global_position.y, home_y), "the cannon stays at its rail height")
	await end_level(level)


## 雲母：漂浮靠近 → 鐘罩收緊（預兆）→ 放電（觸鬚判定）→ 恢復；放電傷到下面的玩家。
func _test_jelly() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var jelly := spawn(JELLY_PATH, 40.0, FLOOR_Y - 70.0) as ChainEnemy
	place_player(40.0)
	check(await wait_state(jelly, &"drift", 60 * 3), "the jelly drifts toward the player")
	var moved := false
	var y0 := jelly.global_position.y
	for i in 120:
		await physics_frames(1)
		moved = moved or absf(jelly.global_position.y - y0) > 2.0 or absf(jelly.velocity.x) > 2.0
	check(moved, "the bell pulses and pushes the jelly around")
	check(await wait_state(jelly, &"charge", 60 * 8), "the bell tightens before it zaps")
	check(jelly.is_telegraphing() and jelly.data.telegraph_time >= 0.8, "the charge is a long telegraph")
	var before := level.player.health.current
	check(await wait_state(jelly, &"discharge", 60 * 3), "then it discharges")
	check(jelly._strike.active and jelly._strike.point_count() > 0, "the tentacles become hit circles")
	place_player(40.0)
	level.player.global_position.y = jelly.global_position.y + 28.0
	for i in 40:
		await physics_frames(1)
	check(level.player.health.current < before, "the zap hurts a player under the tentacles")
	check(await wait_state(jelly, &"recover", 60 * 3), "the jelly recovers afterwards")
	for i in jelly.chain.tentacle_count():
		jelly.chain.sever(i)
	await physics_frames(2)
	check(jelly.chain.is_exposed() and jelly.hurtbox.damage_scale > 1.0, "with every tentacle cut the bell takes extra damage")
	await end_level(level)


## 蜂群：1 點生命、群集（彼此不疊成一團）、同屏 24 隻的處理時間。
func _test_swarm() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var data := load(BEE_PATH) as EnemyData
	var bees := SwarmBee.spawn_swarm(level._entities, data, Vector2(36.0 * 16.0, FLOOR_Y - 60.0), SWARM_SIZE)
	place_player(36.0)
	check(bees.size() == SWARM_SIZE, "the swarm spawns %d bees" % SWARM_SIZE)
	await physics_frames(2)
	check(runner.get_tree().get_nodes_in_group(SwarmBee.GROUP).size() == SWARM_SIZE, "every bee joins the swarm group")
	# 群集移動的腳本成本：直接重複呼叫 24 隻蜂的轉向 120 次（一個影格 24 次），量每影格花多久。
	var started := Time.get_ticks_usec()
	for frame in 120:
		for bee in bees:
			(bee as SwarmBee)._steer(DT, 1.0)
	var swarm_ms := float(Time.get_ticks_usec() - started) / 120.0 / 1000.0
	print("[swarm] steering 24 bees costs %.3f ms per frame" % swarm_ms)
	check(swarm_ms < SWARM_FRAME_BUDGET_MS, "steering 24 bees costs %.2f ms per frame (budget %.0f)" % [swarm_ms, SWARM_FRAME_BUDGET_MS])
	for i in 120:
		await physics_frames(1)
	var clumped := 0
	var finite := true
	for i in bees.size():
		finite = finite and is_finite(bees[i].global_position.x) and is_finite(bees[i].global_position.y)
		for j in range(i + 1, bees.size()):
			if bees[i].global_position.distance_to(bees[j].global_position) < 2.5:
				clumped += 1
	check(finite, "no bee position is NaN")
	check(clumped <= 8, "the flock keeps its members apart (%d overlapping pairs)" % clumped)
	var stung := false
	for bee in bees:
		stung = stung or bee.fsm.is_in(&"buzz") or bee.fsm.is_in(&"sting") or bee.fsm.is_in(&"recover")
	check(stung, "some bees charge up to sting")
	check(data.max_health == 1, "a bee has a single hit point")
	var victim := bees[0]
	victim.hurtbox.receive(hit(1, true))
	check(victim.is_dying(), "one hit kills a bee")
	await end_level(level)
