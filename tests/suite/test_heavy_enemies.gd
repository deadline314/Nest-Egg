class_name HeavyEnemiesSuite
extends EnemySuiteBase
## 重裝型敵人（NE-47）：火焰兵（點火預熱、噴射範圍與持續時間、背後燃料罐爆炸）
## 與重裝機槍手（槍管加速、停步掃射、過熱空檔、正面裝甲、爆炸無視裝甲）。

const FLAMER_PATH := "res://data/enemies/flamer.tres"
const GUNNER_PATH := "res://data/enemies/heavy_gunner.tres"
const WARDEN_PATH := "res://data/enemies/warden.tres"
const WATCHDOG_PATH := "res://data/enemies/watchdog.tres"
const PISTOL_SHOT_PATH := "res://data/projectiles/pistol_shot.tres"


func run() -> void:
	_test_data()
	_test_level_placement()
	await _test_flamer_attack()
	await _test_flamer_range_and_interrupt()
	await _test_flamer_tank()
	await _test_flamer_tank_shots()
	await _test_gunner_sequence()
	await _test_gunner_armor()
	await _test_warden_core_cannon()
	await _test_warden_core_origin()
	await _test_visible_heads_are_hittable()
	await _test_watchdog_head_shot()
	await _test_core_hit_along_path()
	await _test_hit_feedback_at_contact()
	await _test_platform_strike_contact()
	await _test_path_resolution_contract()
	await _test_watchdog_head_in_warehouse()
	await _test_codex_unlocks()
	await check_defeatable_on_every_difficulty([FLAMER_PATH, GUNNER_PATH])


func _test_data() -> void:
	check_enemy_data([FLAMER_PATH, GUNNER_PATH], [&"flamer_burn", &"flamer_contact", &"flamer_tank_blast", &"heavy_gunner_shot", &"heavy_gunner_contact"])
	var gunner := load(GUNNER_PATH) as EnemyData
	var flamer := load(FLAMER_PATH) as EnemyData
	check(gunner.telegraph_time >= 0.8, "the gunner's barrel spin-up is a long windup")
	check(gunner.max_health > load(GRUNT_PATH).max_health * 2, "the heavy gunner is much tougher than a trooper")
	check(flamer.ability_damage >= 1 and flamer.projectile != null and flamer.projectile.explosion_radius > 0.0, "the flamer's fuel tank has durability and a blast")
	check(flamer.projectile.explosion_damage >= flamer.max_health * 0.5, "the fuel tank blast takes at least half of the flamer's health")


## 配置：第二章升降井（70～139）、夾層區後段（180～214）與電力室（215～274）。
func _test_level_placement() -> void:
	check_level_placement({
		"res://data/levels/level_02.tres": [[&"flamer", 70, 140], [&"flamer", 325, 385], [&"heavy_gunner", 180, 215], [&"heavy_gunner", 325, 385]],
	})


## 點火預熱（預兆、火舌逐漸變長）→ 噴射（範圍、持續時間）→ 收火，期間站在火裡會受傷。
func _test_flamer_attack() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	place_player(40.0 - 3.0)
	level.player.health.setup(50, 0.0)
	var before := level.player.health.current
	var ignited := await wait_state(flamer, &"ignite", 60 * 3)
	check(ignited, "the flamer ignites when the player is within reach")
	check(flamer.is_telegraphing(), "igniting is a telegraph")
	check(not flamer._flame_box.active, "no flame damage during the warm-up")
	await physics_frames(20)
	var early_length := flamer.flame_length
	var burning := await wait_state(flamer, &"burn", 60 * 3)
	check(burning, "the flame jets after the warm-up")
	check(flamer._flame_box.active and early_length < flamer.data.attack_range * 0.5, "the flame grows during the warm-up (%.0f) and is live while burning" % early_length)
	for i in 240:
		if flamer.fsm.time_in_state >= 0.4:
			break
		await physics_frames(1)
	check(absf(flamer.flame_length - flamer.data.attack_range) < 1.0, "the flame reaches its full length (%.1f)" % flamer.flame_length)
	check(flamer._flame_light.enabled, "the flame lights its surroundings")
	check(level.player.health.current < before, "standing in the flame hurts")
	var burn_seconds := 0.0
	for i in 60 * 6:
		if not flamer.fsm.is_in(&"burn"):
			break
		burn_seconds = flamer.fsm.time_in_state
		await physics_frames(1)
	check(flamer.fsm.is_in(&"recover") and not flamer._flame_box.active, "the flame goes out after its duration")
	check(absf(burn_seconds - flamer.data.ability_time) < 0.15, "the burn lasts the configured time (%.2f s of %.1f)" % [burn_seconds, flamer.data.ability_time])
	var back := await wait_state(flamer, &"patrol", 60 * 3)
	check(back and flamer._cooldown > 0.0, "the flamer has a cooldown after burning")
	flamer.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 火焰有固定射程：遠一點的玩家不會受傷；暈眩（完美格擋）會中斷噴射。
func _test_flamer_range_and_interrupt() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	place_player(40.0 - 11.0)
	level.player.health.setup(50, 0.0)
	var before := level.player.health.current
	flamer.fsm.transition(&"ignite")
	await wait_state(flamer, &"burn", 60 * 3)
	for i in 50:
		await physics_frames(1)
		place_player(40.0 - 11.0)
	check(level.player.health.current == before, "a player beyond the flame's reach is not hurt (11 tiles away)")
	# 暈眩中斷：噴射中被格擋。
	flamer.fsm.transition(&"burn")
	flamer.stun(0.5)
	await physics_frames(2)
	check(flamer.fsm.is_in(&"recover") and not flamer._flame_box.active, "a stun cuts the flame off")
	flamer.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 監管者的核心砲（NE-89 專屬骨頭範例）：第二階段才會用；預兆時胸甲（掛在專屬骨頭 core_plate 上）掀開，
## 發射從專屬骨頭 core_port 出去，發射後核心部位判定外露時雙倍、收起來回到一般。原有招式不受影響。
func _test_warden_core_cannon() -> void:
	await open_level(10.0)
	var warden := spawn(WARDEN_PATH, 30.0)
	place_player(24.0)
	await physics_frames(3)
	var rig := warden.rig
	check(rig != null and rig.has_bone(&"core_plate") and rig.has_bone(&"core_port"), "the warden rig declares its dedicated bones")
	check(rig.parent_of(&"core_plate") == &"chest" and rig.parent_of(&"core_port") == &"chest", "the dedicated bones hang off the chest")
	var plate_sprite := rig.bone(&"core_plate").get_node_or_null("armor_chest")
	check(plate_sprite != null, "the chest plate is mounted on the dedicated plate bone")
	var core_part: Hurtbox = null
	for part in warden.hurtbox.parts:
		if part.part_id == &"core":
			core_part = part
	check(core_part != null and core_part.damage_scale == 1.0, "the core hurt part exists and counts as normal while closed")
	var phase_one_moves := {}
	for i in 40:
		phase_one_moves[warden.call(&"_choose_attack")] = true
	check(not phase_one_moves.has(&"core_windup"), "phase one never uses the core cannon")
	warden.set("_phase", 2)
	var moves := {}
	for i in 80:
		moves[warden.call(&"_choose_attack")] = true
		warden.set("_last_attack", &"")
	check(moves.has(&"core_windup") and moves.has(&"burst_windup") and moves.has(&"leap_windup"), "phase two adds the core cannon to the old moves")
	var rest_angle := rig.bone(&"core_plate").rotation
	warden.fsm.transition(&"core_windup")
	await physics_frames(20)
	check(absf(rig.bone(&"core_plate").rotation - rest_angle) > 0.3, "the plate swings open while the cannon charges (%.2f)" % rig.bone(&"core_plate").rotation)
	var port_world := rig.bone(&"core_port").global_position
	check(warden._core_point().distance_to(warden.to_local(port_world)) < 0.01, "the glow ring and the aim line sit on the core port bone")
	var before := ProjectilePool.active_count()
	var fired := await wait_state(warden, &"core_recover", 90)
	check(fired, "the charge ends in the recover state")
	await physics_frames(1)
	check(ProjectilePool.active_count() >= before + 3, "the cannon fires its volley (%d -> %d)" % [before, ProjectilePool.active_count()])
	check(core_part.damage_scale == 2.0, "the core takes double damage while exposed")
	var exposed := await wait_state(warden, &"idle", 150)
	check(exposed and core_part.damage_scale == 1.0, "the core closes again afterwards")
	await physics_frames(60)
	await end_level(level)


func _test_warden_core_origin() -> void:
	await open_level(10.0)
	var warden := spawn(WARDEN_PATH, 40.0)
	await physics_frames(3)
	warden.set_physics_process(false)
	level.player.set_physics_process(false)
	var original_rig := warden.rig
	for use_rig: bool in [true, false]:
		warden.rig = original_rig if use_rig else null
		for face: int in [-1, 1]:
			for configuration: Vector2 in [Vector2(1, 0), Vector2(1.3, 0), Vector2(1, .35), Vector2(1.3, -.35)]:
				warden.scale = Vector2.ONE * configuration.x
				warden.rotation = configuration.y
				warden.facing = face
				level.player.global_position = warden.global_position + Vector2(face * 150.0, 0)
				if use_rig:
					warden._rig_input.facing = face
					warden._rig_input.aim_dir = Vector2(face, 0)
					warden.rig.animate(1.0 / 60.0, warden._rig_input)
				ProjectilePool.clear_in_radius(warden.global_position, 10000.0, Combat.Team.ENEMY)
				warden.fsm.transition(&"core_windup")
				warden._telegraph_left = 0.0
				var expected := original_rig.bone(&"core_port").global_position if use_rig else warden.to_global(Vector2(0, -warden.data.body_size.y * .62))
				warden.call(&"_core_windup_tick", 0.0)
				var count := 0
				var worst := 0.0
				for child: Node in ProjectilePool.container().get_children():
					if child is Projectile and child.active and child.team == Combat.Team.ENEMY:
						count += 1
						worst = maxf(worst, child.global_position.distance_to(expected))
				check(count == 3 and warden.fsm.is_in(&"core_recover"), "core cannon fires three real projectiles before recovering")
				check(warden.facing == face and worst < .001, "core world origin rig=%s face=%d scale=%.1f rotation=%.2f gap=%.6f" % [use_rig, face, configuration.x, configuration.y, worst])
	warden.rig = original_rig
	await end_level(level)


## 燃料罐：打中兩次爆炸；爆炸傷到敵人（含背著它的火焰兵與旁邊的保全）與玩家，並讓火焰兵暈眩。
func _test_flamer_tank() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	var neighbor := spawn(GRUNT_PATH, 42.0)
	neighbor.set_physics_process(false)
	flamer.set_physics_process(false)
	place_player(37.0)
	await physics_frames(3)
	check(flamer.has_tank(), "the flamer carries a fuel tank")
	var tank_behind := flamer.tank.global_position.x > flamer.global_position.x if flamer.facing < 0 else flamer.tank.global_position.x < flamer.global_position.x
	check(tank_behind, "the tank sits on the flamer's back")
	var flamer_before := flamer.health.current
	var neighbor_before := neighbor.health.current
	var player_before := level.player.health.current
	flamer.tank.hurtbox.receive(hit(1))
	check(not flamer.tank.is_exploded, "one hit does not set off the tank")
	flamer.tank.hurtbox.receive(hit(1))
	check(flamer.tank.is_exploded, "enough hits set off the tank")
	flamer.set_physics_process(true)
	await physics_frames(40)
	check(flamer.health.current < flamer_before, "the blast hurts the flamer wearing the tank (%d -> %d)" % [flamer_before, flamer.health.current])
	check(neighbor.health.current < neighbor_before, "the blast hurts a nearby enemy")
	check(level.player.health.current < player_before, "the blast hurts a nearby player too")
	check(flamer.is_dying() or flamer.is_stunned() or flamer.fsm.is_in(&"recover"), "the blast staggers the flamer")
	check(not flamer.has_tank(), "the tank is gone after exploding")
	await physics_frames(120)
	await end_level(level)


## 子彈打到哪裡：從前面打中身體、從背後打中燃料罐。
func _test_flamer_tank_shots() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 50.0) as Flamer
	flamer.set_physics_process(false)
	flamer.facing = -1
	flamer.tank.follow(-1, Flamer.TANK_OFFSET)
	place_player(5.0)
	await physics_frames(3)
	var body_before := flamer.health.current
	var tank_before := flamer.tank.health.current
	var y := FLOOR_Y - 28.0
	# 從前面（左邊）朝右射：打中身體。
	shoot_from(Vector2(44.0 * 16.0, y), Vector2.RIGHT)
	await physics_frames(40)
	check(flamer.health.current < body_before and flamer.tank.health.current == tank_before, "a shot from the front hits the flamer, not the tank")
	body_before = flamer.health.current
	# 從背後（右邊）朝左射：先打中燃料罐。
	shoot_from(Vector2(56.0 * 16.0, y), Vector2.LEFT)
	await physics_frames(40)
	check(flamer.tank.health.current < tank_before and flamer.health.current == body_before, "a shot from behind hits the fuel tank first")
	flamer.set_physics_process(true)
	flamer.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 重裝機槍手：旋轉加速（長前搖、預兆）→ 停步掃射（射速由慢到快）→ 過熱空檔（裝甲打開、受傷加成）。
func _test_gunner_sequence() -> void:
	await open_level(10.0)
	var gunner := spawn(GUNNER_PATH, 27.0) as HeavyGunner
	place_player(10.0)
	level.player.health.setup(200, 0.0)
	var before := level.player.health.current
	var winding := await wait_state(gunner, &"spin_up", 60 * 4)
	check(winding and gunner.is_telegraphing(), "the gunner winds up its barrel with a telegraph")
	var last_spin := 0.0
	var spin_rises := true
	var windup_frames := 0
	for i in 600:
		await physics_frames(1)
		if not gunner.fsm.is_in(&"spin_up"):
			break
		windup_frames += 1
		spin_rises = spin_rises and gunner.spin() >= last_spin - 0.001
		last_spin = gunner.spin()
		check(absf(gunner.velocity.x) < 0.1, "the gunner stands still while winding up")
	var windup_seconds := windup_frames / 60.0
	check(spin_rises and last_spin > 0.8, "the barrel spins faster and faster (%.2f)" % last_spin)
	check(windup_seconds >= gunner.data.telegraph_time * 0.8, "the windup is long (%.2f s)" % windup_seconds)
	check(gunner.fsm.is_in(&"fire"), "the gunner fires after the windup")
	var half := int(gunner.data.ability_time * 60.0 * 0.5)
	await physics_frames(half)
	var first_half := gunner.shots_fired
	check(absf(gunner.velocity.x) < 0.1, "the gunner stands still while firing")
	await wait_state(gunner, &"vent", 60 * 4)
	var second_half := gunner.shots_fired - first_half
	check(first_half >= 3 and second_half > first_half, "the fire rate climbs during the burst (%d then %d shots)" % [first_half, second_half])
	check(level.player.health.current < before, "a player standing in the line of fire is hit")
	check(gunner.is_armor_open() and is_equal_approx(gunner.hurtbox.damage_scale, HeavyGunner.VENT_DAMAGE_SCALE), "the armor opens and damage is boosted while venting")
	check(gunner.heat() > 0.5, "the barrel is hot when the burst ends (%.2f)" % gunner.heat())
	await physics_frames(60)
	check(gunner.heat() < 0.9, "the barrel cools during the vent")
	var back := await wait_state(gunner, &"patrol", 60 * 4)
	check(back and not gunner.is_armor_open() and is_equal_approx(gunner.hurtbox.damage_scale, 1.0), "the armor closes again after the vent")
	check(gunner._cooldown > 0.0, "the gunner rests between bursts")
	gunner.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 正面裝甲：擋下正面的一般攻擊；背後與過熱空檔打得進去；爆炸與終結技無視裝甲。
func _test_gunner_armor() -> void:
	await open_level(10.0)
	var gunner := spawn(GUNNER_PATH, 40.0) as HeavyGunner
	gunner.set_physics_process(false)
	gunner.facing = -1
	place_player(20.0)
	await physics_frames(2)
	var front := gunner.global_position + Vector2(-30, -20)
	var back := gunner.global_position + Vector2(30, -20)
	var before := gunner.health.current
	check(gunner.hurtbox.receive(hit(1, false, front)) == Hurtbox.Result.BLOCKED and gunner.health.current == before, "the front armor blocks an ordinary hit")
	check(gunner.hurtbox.receive(hit(1, false, back)) == Hurtbox.Result.DAMAGED and gunner.health.current == before - 1, "the back is not armored")
	before = gunner.health.current
	check(gunner.hurtbox.receive(hit(1, true, front)) == Hurtbox.Result.DAMAGED and gunner.health.current == before - 1, "explosions ignore the armor")
	before = gunner.health.current
	gunner.fsm.transition(&"vent")
	check(gunner.hurtbox.receive(hit(2, false, front)) == Hurtbox.Result.DAMAGED and gunner.health.current == before - 3, "venting opens the armor and boosts damage (2 -> 3)")
	# 暈眩（完美格擋）會中斷掃射並進入過熱空檔。
	gunner.fsm.transition(&"fire")
	gunner.stun(0.5)
	await physics_frames(2)
	check(gunner.fsm.is_in(&"vent"), "a stun cuts the burst short")
	gunner.set_physics_process(true)
	gunner.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 被每種敵人擊敗一次：死因對應的敗北圖鑑卡片會解鎖（火焰、燃料罐爆炸、機槍子彈）。
func _test_codex_unlocks() -> void:
	# 火焰：站在火裡直到倒下。
	await open_level(10.0)
	level.player.health.setup(1, 0.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	place_player(37.0)
	await expect_codex_unlock(&"flamer_burn", "the flamer's fire", 60 * 8)
	flamer.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)
	# 燃料罐爆炸：貼著火焰兵打爆燃料罐。
	await open_level(10.0)
	flamer = spawn(FLAMER_PATH, 40.0) as Flamer
	flamer.set_physics_process(false)
	level.player.health.setup(1, 0.0)
	place_player(41.0)
	flamer.tank.hurtbox.receive(hit(5))
	await expect_codex_unlock(&"flamer_tank_blast", "the fuel tank blast", 60 * 3)
	await physics_frames(120)
	await end_level(level)
	# 機槍子彈：站著挨掃射。
	await open_level(10.0)
	level.player.health.setup(1, 0.0)
	var gunner := spawn(GUNNER_PATH, 27.0) as HeavyGunner
	await expect_codex_unlock(&"heavy_gunner_shot", "the heavy gunner's bullets", 60 * 8)
	gunner.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)


# ---------------------------------------------------------------------------
# 命中部位與畫面一致（NE-252 看門狗頭部、NE-248 外露核心）
# ---------------------------------------------------------------------------

## 畫面上零件的世界外框（Sprite2D 或關節網格）。
static func _visual_rect(node: CanvasItem) -> Rect2:
	var local := Rect2()
	if node is Sprite2D:
		local = (node as Sprite2D).get_rect()
	elif node is Polygon2D and not (node as Polygon2D).polygon.is_empty():
		var points := (node as Polygon2D).polygon
		local = Rect2(points[0], Vector2.ZERO)
		for point in points:
			local = local.expand(point)
	else:
		return Rect2()
	var xf := (node as Node2D).global_transform
	var a := xf * local.position
	var b := xf * local.end
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


static func _head_center(enemy: Enemy) -> Vector2:
	if enemy.rig == null:
		# 零件式外觀：頭零件關節底下的第一張圖。
		var joint := enemy.creature.joint_of("head") if enemy.creature != null else null
		for child: Node in (joint.get_children() if joint != null else []):
			if child is Sprite2D:
				return _visual_rect(child as CanvasItem).get_center()
		return Vector2.INF
	for node: Node in enemy.rig.find_children("head", "CanvasItem", true, false):
		if not (node is Bone2D):
			var rect := _visual_rect(node as CanvasItem)
			if rect.has_area():
				return rect.get_center()
	return Vector2.INF


## 讓敵人面向 side（-1 左、1 右）後凍住，部位判定停在當下的骨頭位置。
func _freeze_facing(enemy: Enemy, side: int) -> void:
	place_player(enemy.global_position.x / 16.0 + side * 8.0)
	enemy.facing = side
	enemy._rig_input.facing = side
	enemy._rig_input.aim_dir = Vector2(side, 0)
	if enemy.rig != null:
		enemy.rig.animate(1.0 / 60.0, enemy._rig_input)
	enemy._drive_creature(1.0 / 60.0)
	enemy._update_hurt_parts()
	enemy.set_physics_process(false)
	await physics_frames(2)


## 一發真實子彈（物件池、掃掠碰撞）從 origin 打向 target，回傳這個敵人收到的每次命中：
## 受傷 [部位, 傷害, 弱點]；被裝甲擋下 [&"blocked", 部位, 0, false]。
func _shot(enemy: Enemy, origin: Vector2, target: Vector2) -> Array:
	var hits: Array = []
	var record := func(info: DamageInfo) -> void: hits.append([info.part, info.amount, info.weak_hit])
	enemy.health.damaged.connect(record)
	var boxes: Array[Hurtbox] = [enemy.hurtbox]
	boxes.append_array(enemy.hurtbox.parts)
	var blocked: Array[Callable] = []
	for box in boxes:
		var on_block := func(_info: DamageInfo) -> void: hits.append([&"blocked", box.part_id, 0, false])
		box.hit_blocked.connect(on_block)
		blocked.append(on_block)
	ProjectilePool.spawn(load(PISTOL_SHOT_PATH) as ProjectileSpec, origin, (target - origin).normalized(), Combat.Team.PLAYER)
	await physics_frames(25)
	enemy.health.damaged.disconnect(record)
	for i in boxes.size():
		boxes[i].hit_blocked.disconnect(blocked[i])
	return hits


## 看門狗抬頭準備吠叫（頭部感測器打開）並停在這個姿勢。
func _open_watchdog_head(dog: PatternBoss) -> void:
	dog.set("_move_id", &"bark")
	dog.fsm.transition(&"windup")
	dog.set("_telegraph_left", 99.0)
	dog.call(&"_refresh_parts")
	await physics_frames(2)


## 所有骨架與零件式敵人：畫面上的頭（零件中心）都落在整體或部位受擊框內，兩個面向都一樣；不能有「看得到打不到」的頭。
func _test_visible_heads_are_hittable() -> void:
	await open_level(10.0)
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data == null or (data.rig_skin.is_empty() and data.creature_skin.is_empty()):
			continue
		var enemy := spawn("res://data/enemies/" + file, 40.0)
		await physics_frames(2)
		if enemy.anchor_node(&"head") == null:
			enemy.queue_free()
			continue
		for side: int in [-1, 1]:
			await _freeze_facing(enemy, side)
			var head := _head_center(enemy)
			var covered := enemy.hurtbox.contains_point(head)
			for part in enemy.hurtbox.parts:
				covered = covered or (part.enabled and part.contains_point(head))
			check(head != Vector2.INF and covered, "%s's visible head is inside a hurt box (facing %d, head %s)" % [data.id, side, head])
		enemy.queue_free()
		await physics_frames(2)
	await end_level(level)


## 看門狗：瞄準畫面上的頭開槍，算頭部命中（部位倍率、弱點回饋），左右兩邊、兩個面向都一樣；
## 真正的玩家手槍（_try_fire）斜向上射頭也一樣；射身體仍是一般命中。
func _test_watchdog_head_shot() -> void:
	await open_level(10.0)
	var dog := spawn(WATCHDOG_PATH, 45.0)
	await physics_frames(2)
	var base_damage := (load(PISTOL_SHOT_PATH) as ProjectileSpec).damage
	# 平常頭部感測器有裝甲：打到算頭部、被擋下彈開；抬頭吠叫時打開，算頭部弱點命中。兩個面向、前後兩側都一樣。
	# 從正面水平射；從背後要從高處往下射，越過背上的砲塔（水平從背後射，砲塔先擋住是正確的遮擋）。
	for side: int in [-1, 1]:
		for from: int in [-1, 1]:
			await _freeze_facing(dog, side)
			var head := _head_center(dog)
			var lift := 0.0 if from == side else -70.0
			var hits := await _shot(dog, head + Vector2(from * 140.0, lift), head)
			check(hits.size() == 1 and hits[0][0] == &"blocked" and hits[0][1] == &"head",
					"a shot at the watchdog's drawn head registers on the armoured head (facing %d, from %d): %s" % [side, from, hits])
			await _open_watchdog_head(dog as PatternBoss)
			head = _head_center(dog)
			hits = await _shot(dog, head + Vector2(from * 140.0, lift), head)
			check(hits.size() == 1 and hits[0][0] == &"head" and hits[0][2] and hits[0][1] > roundi(base_damage),
					"while it raises its head to bark, a head shot is a weak hit (facing %d, from %d): %s" % [side, from, hits])
			dog.fsm.transition(&"idle")
			dog.call(&"_refresh_parts")
			dog.health.setup(dog.data.max_health, 0.0)
	# 各招式的預兆與每個階段：頭的部位判定跟著畫面上的頭走。
	dog.set_physics_process(true)
	for phase: int in dog.pattern.phases.size():
		dog.call(&"_apply_phase", phase, false)
		for move: StringName in dog.pattern.phases[phase]["moves"]:
			dog.set("_move_id", move)
			dog.fsm.transition(&"windup")
			await physics_frames(12)
			var drawn := _head_center(dog)
			var head_box: Hurtbox = null
			for part in dog.hurtbox.parts:
				if part.part_id == &"head":
					head_box = part
			check(head_box != null and head_box.contains_point(drawn), "the head box follows the drawn head while winding up %s (phase %d)" % [move, phase + 1])
	dog.call(&"_apply_phase", 0, false)
	await _freeze_facing(dog, -1)
	var body := dog.hurtbox.center() + Vector2(0, 12)
	var body_hits := await _shot(dog, body + Vector2(-140, 0), body)
	check(body_hits.size() == 1 and body_hits[0][0] == &"blocked" and body_hits[0][1] == &"", "the armoured body deflects a body shot: %s" % [body_hits])
	# 真正的玩家：站在牠前方的地上，斜向上瞄準抬起的頭開一槍（從背後打，背上的砲塔會先擋住，那是正確的遮擋）。
	await _freeze_facing(dog, -1)
	await _open_watchdog_head(dog as PatternBoss)
	var player := level.player
	place_player(dog.global_position.x / 16.0 - 9.0)
	player.set_physics_process(false)
	await physics_frames(2)
	var head := _head_center(dog)
	await _settle_player_aim(player, head)
	var hits: Array = []
	var record := func(info: DamageInfo) -> void: hits.append([info.part, info.weak_hit])
	dog.health.damaged.connect(record)
	player._try_fire()
	await physics_frames(25)
	dog.health.damaged.disconnect(record)
	check(hits.size() == 1 and hits[0][0] == &"head" and hits[0][1], "the real player pistol aimed at the raised head scores a head hit: %s" % [hits])
	player.set_physics_process(true)
	await end_level(level)


## 先換成沒有隨機散佈的同一把手槍（這裡量的是命中判定，不是準度運氣）、轉身並瞄向 target，
## 等畫面上的骨架更新（槍口取自骨架）與換武器的動作結束，再用更新後的槍口重新瞄準一次。
func _settle_player_aim(player: Player, target: Vector2) -> void:
	var steady := (load("res://data/weapons/pistol.tres") as WeaponData).duplicate()
	steady.random_spread_degrees = 0.0
	player.loadout.reset(steady)
	player.aim_bloom = 0.0
	player.facing = 1 if target.x >= player.global_position.x else -1
	player.aim_dir = (target - player.aim_origin()).normalized()
	for i in 60:
		await frames(1)
		if player._fire_cooldown_left <= 0.0 and player._melee_cooldown_left <= 0.0 and not player.loadout.is_reloading() and i >= 3:
			break
	player.aim_dir = (target - player.muzzle_position()).normalized()


## 監管者的外露核心藏在身體框裡：子彈先碰到身體框，但彈道會穿過核心，就算核心命中（雙倍、弱點、只扣一次）。
## 偏離核心是一般命中；核心關閉不是弱點；牆與擋在前面的敵人照原規則先擋。
func _test_core_hit_along_path() -> void:
	await open_level(10.0)
	var warden := spawn(WARDEN_PATH, 45.0)
	await physics_frames(2)
	var base_damage := roundi((load(PISTOL_SHOT_PATH) as ProjectileSpec).damage)
	var core_part: Hurtbox = null
	for part in warden.hurtbox.parts:
		if part.part_id == &"core":
			core_part = part
	for side: int in [-1, 1]:
		for from: int in [-1, 1]:
			await _freeze_facing(warden, side)
			warden.call(&"_set_core_exposed", true)
			var core := core_part.center()
			var entry_gap := absf(core.x - (warden.hurtbox.center().x - from * warden.data.body_size.x * 0.5))
			var hits := await _shot(warden, core + Vector2(from * 160.0, 0), core)
			check(entry_gap > 10.0 and hits.size() == 1 and hits[0][0] == &"core" and hits[0][2] and hits[0][1] == base_damage * 2,
					"an exposed core behind the body edge (%.1f px in) is hit along the path (facing %d, from %d): %s" % [entry_gap, side, from, hits])
			var miss := core + Vector2(0, 22)
			hits = await _shot(warden, miss + Vector2(from * 160.0, 0), miss)
			check(hits.size() == 1 and hits[0][0] == &"" and not hits[0][2], "a body shot below the core stays ordinary: %s" % [hits])
			warden.call(&"_set_core_exposed", false)
			hits = await _shot(warden, core + Vector2(from * 160.0, 0), core)
			check(hits.size() == 1 and not hits[0][2] and hits[0][1] == base_damage, "a closed core is not a weak hit: %s" % [hits])
			warden.health.setup(warden.data.max_health, 0.0)
	# 擋在前面的另一個監管者先被打到，不會越過它選後面的核心。
	await _freeze_facing(warden, -1)
	warden.call(&"_set_core_exposed", true)
	var shield_body := spawn(WARDEN_PATH, 41.0)
	await physics_frames(2)
	shield_body.set_physics_process(false)
	var core := core_part.center()
	var front_hits := await _shot(shield_body, core + Vector2(-200, 0), core)
	check(front_hits.size() == 1, "the enemy in front takes the shot: %s" % [front_hits])
	shield_body.queue_free()
	await physics_frames(2)
	# 牆（欄 30～31，x 480～512）在前面：打不到核心。
	place_player(20.0)
	var wall_hits := await _shot(warden, Vector2(26 * 16.0, core.y), core)
	check(wall_hits.is_empty(), "a wall in front still stops the shot: %s" % [wall_hits])
	await end_level(level)


## 命中回饋放在實際碰到的地方（NE-268）：近戰的火花、閃光與傷害數字在受擊範圍內、揮擊的高度，不在敵人腳底；
## 子彈沿彈道選中身體深處的核心時，回饋在核心上，不停在身體邊緣。兩個面向都一樣。
func _test_hit_feedback_at_contact() -> void:
	await open_level(10.0)
	var flashes: Array[Vector2] = []
	var on_confirm := func(at: Vector2, _killed: bool) -> void: flashes.append(at)
	EventBus.hit_confirmed.connect(on_confirm)
	var player := level.player
	var standing_y := INF
	for side: int in [-1, 1]:
		var grunt := await _still_grunt(60.0)
		place_player(60.0 - side * 1.6)
		AimInput.set_virtual_gamepad(player, true)
		Input.action_press(&"aim_right" if side > 0 else &"aim_left")
		await physics_frames(8)
		flashes.clear()
		player._try_melee()
		await physics_frames(30)
		var feet := grunt.global_position
		var box := grunt.hurtbox
		check(flashes.size() == 1 and box.contains_point(flashes[0], 1.0) and flashes[0].y < feet.y - grunt.data.body_size.y * 0.4,
				"a melee hit flashes on the body at swing height, not at the feet (side %d, feet %s): %s" % [side, feet, flashes])
		standing_y = flashes[0].y if flashes.size() == 1 else standing_y
		Input.action_release(&"aim_right" if side > 0 else &"aim_left")
		AimInput.set_virtual_gamepad(player, false)
		grunt.queue_free()
		await physics_frames(2)
	# 跳起來砍：揮擊點跟著角色升高，回饋落在受擊範圍裡更高的位置（不會掉回腳底）。
	var tall := await _still_grunt(60.0)
	place_player(58.4)
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right")
	await physics_frames(8)
	Input.action_press(&"jump")
	await physics_frames(1)
	flashes.clear()
	player._try_melee()
	await physics_frames(20)
	Input.action_release(&"jump")
	check(flashes.size() == 1 and tall.hurtbox.contains_point(flashes[0], 1.0) and flashes[0].y < standing_y - 4.0,
			"a jumping slash flashes higher on the body than a standing one (%.1f vs %.1f): %s" % [flashes[0].y if flashes.size() == 1 else INF, standing_y, flashes])
	tall.queue_free()
	await physics_frames(30)
	# 一刀砍到兩個：各自的回饋在自己的受擊範圍裡。
	var near := await _still_grunt(60.0)
	var far := await _still_grunt(60.6)
	place_player(59.0)
	await physics_frames(8)
	flashes.clear()
	player._try_melee()
	await physics_frames(30)
	var own := flashes.size() == 2 and ((near.hurtbox.contains_point(flashes[0], 1.0) and far.hurtbox.contains_point(flashes[1], 1.0))
			or (near.hurtbox.contains_point(flashes[1], 1.0) and far.hurtbox.contains_point(flashes[0], 1.0)))
	check(own, "one slash through two targets flashes inside each target's own hurt box: %s" % [flashes])
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	near.queue_free()
	far.queue_free()
	await physics_frames(2)
	var warden := spawn(WARDEN_PATH, 45.0)
	await physics_frames(2)
	var core_part: Hurtbox = null
	for part in warden.hurtbox.parts:
		if part.part_id == &"core":
			core_part = part
	for from: int in [-1, 1]:
		await _freeze_facing(warden, -1)
		warden.call(&"_set_core_exposed", true)
		var core := core_part.center()
		flashes.clear()
		var hits := await _shot(warden, core + Vector2(from * 160.0, 0), core)
		check(hits.size() == 1 and hits[0][0] == &"core" and flashes.size() == 1 and core_part.contains_point(flashes[0], 1.5),
				"a shot that reaches the core along its path flashes on the core, not at the body edge (from %d): %s %s" % [from, hits, flashes])
		warden.health.setup(warden.data.max_health, 0.0)
	EventBus.hit_confirmed.disconnect(on_confirm)
	await end_level(level)


## 一個不動、不還手的保全（量命中位置用）。
## 從平台上往下打（NE-268）：站在比敵人高四格的平台上，用跟著準星的長柄往右下刺；回饋在敵人的受擊範圍裡、靠上半身
## （最靠近武器揮到的那一點），不在腳底。左右兩個面向都一樣。
func _test_platform_strike_contact() -> void:
	await open_level(10.0)
	var flashes: Array[Vector2] = []
	var on_confirm := func(at: Vector2, _killed: bool) -> void: flashes.append(at)
	EventBus.hit_confirmed.connect(on_confirm)
	var player := level.player
	player.loadout.equip(load("res://data/weapons/melee/melee_glaive.tres") as WeaponData)
	for side: int in [1, -1]:
		var grunt := await _still_grunt(53.0 + side * 2.3)
		place_player(53.0, 16 * 16.0)
		player._melee_cooldown_left = 0.0
		player._melee_combo_left = 0.0  # 兩個面向都從第一招（平刺）開始，不接上一個面向的連段
		AimInput.set_virtual_gamepad(player, true)
		var horizontal := &"aim_right" if side > 0 else &"aim_left"
		Input.action_press(horizontal)
		Input.action_press(&"aim_down")
		await physics_frames(10)
		flashes.clear()
		var standing := player.global_position.y
		player._try_melee()
		await physics_frames(30)
		var feet := grunt.global_position
		check(standing < feet.y - 32.0 and flashes.size() == 1 and grunt.hurtbox.contains_point(flashes[0], 1.0) and flashes[0].y < feet.y - grunt.data.body_size.y * 0.4,
				"a downward strike from a platform flashes on the upper body below, not at the feet (side %d, player feet %.0f, enemy feet %s): %s" % [side, standing, feet, flashes])
		Input.action_release(horizontal)
		Input.action_release(&"aim_down")
		AimInput.set_virtual_gamepad(player, false)
		grunt.queue_free()
		await physics_frames(20)
	EventBus.hit_confirmed.disconnect(on_confirm)
	await end_level(level)


func _still_grunt(x_tile: float) -> Enemy:
	var grunt := spawn("res://data/enemies/grunt.tres", x_tile)
	grunt.data = grunt.data.duplicate()
	grunt.data.detect_range = 0.0
	grunt.data.attack_range = 0.0
	await physics_frames(2)
	grunt.set_physics_process(false)
	return grunt


## 合約：接觸點已在部位裡就用它；路徑被擋住時維持整體；沒有方向時等同 resolve_at。
func _test_path_resolution_contract() -> void:
	await open_level(10.0)
	var warden := spawn(WARDEN_PATH, 45.0)
	await physics_frames(2)
	await _freeze_facing(warden, -1)
	warden.call(&"_set_core_exposed", true)
	var box := warden.hurtbox
	var core := Vector2.ZERO
	for part in box.parts:
		if part.part_id == &"core":
			core = part.center()
	var edge := Vector2(box.center().x - warden.data.body_size.x * 0.5 + 0.05, core.y)
	check(box.resolve_along(edge, Vector2.RIGHT).part_id == &"core", "the path from the body edge reaches the core")
	check(box.resolve_along(edge, Vector2.LEFT) == box, "a path leaving the body never selects the core")
	check(box.resolve_along(edge, Vector2.RIGHT, 3.0, func(_a: Vector2, _b: Vector2) -> bool: return true) == box, "a blocked path keeps the body hit")
	check(box.resolve_along(edge, Vector2.ZERO) == box.resolve_at(edge), "no direction falls back to the contact point")
	check(box.resolve_along(core, Vector2.LEFT).part_id == &"core", "a contact already inside the core uses it")
	await end_level(level)


## 正式的第一章碼頭倉庫：看門狗自然醒來後，真正的玩家手槍瞄準畫面上的頭開槍，算頭部命中（左右兩邊各一次）。
func _test_watchdog_head_in_warehouse() -> void:
	level = await start_level(load("res://data/levels/ch1_warehouse.tres") as LevelData)
	level.player.health.setup(999, 0.0)
	var dog: Enemy = null
	for node in level._entities.get_children():
		if node is Enemy and (node as Enemy).data.id == &"watchdog":
			dog = node
	check(dog != null, "the warehouse places the watchdog")
	if dog == null:
		await end_level(level)
		return
	var player := level.player
	for side: int in [-1, 1]:
		# 站得很近：牠的習慣是抬頭吠叫；預兆中頭部感測器打開，真正的手槍瞄準畫面上的頭開一槍。
		player.global_position = dog.global_position + Vector2(side * 40.0, 0.0)
		player.velocity = Vector2.ZERO
		var settled := false
		for frame in 600:
			await physics_frames(1)
			player.global_position.x = dog.global_position.x + side * 40.0
			if dog.fsm.is_in(&"windup") and (dog as PatternBoss).current_move() == &"bark" and (dog as PatternBoss).is_part_open(&"head"):
				settled = true
				break
		# 預兆中退開一步再瞄頭（太近時子彈的路徑會先穿過有裝甲的軀幹）。
		player.global_position.x = dog.global_position.x + side * 90.0
		await _settle_player_aim(player, _head_center(dog))
		var hits: Array = []
		var record := func(info: DamageInfo) -> void: hits.append([info.part, info.weak_hit])
		dog.health.damaged.connect(record)
		player._try_fire()
		await physics_frames(12)
		dog.health.damaged.disconnect(record)
		check(settled and hits.size() == 1 and hits[0][0] == &"head" and hits[0][1],
				"in the warehouse, the real pistol aimed at the barking watchdog's head scores a head hit (player side %d): %s" % [side, hits])
	await end_level(level)
