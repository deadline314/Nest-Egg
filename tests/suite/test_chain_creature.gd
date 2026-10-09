class_name ChainCreatureSuite
extends EnemySuiteBase
## 觸手與蠕行生物（NE-98）：姿勢與網格數學、落腳步行（交替、釘住、不浮空）、斷肢與核心露出、骨頭判定，
## 以及打撈臂、纏絲、浮標蟲、雲蛇四種敵人的資料、招式流程與擊敗。

const SALVAGE_PATH := "res://data/enemies/salvage_arm.tres"
const TANGLE_PATH := "res://data/enemies/tangle_wire.tres"
const BUOY_PATH := "res://data/enemies/buoy_worm.tres"
const SMALL_PATH := "res://data/enemies/buoy_worm_small.tres"
const SERPENT_PATH := "res://data/enemies/cloud_serpent.tres"
const CHAIN_IDS: Array[String] = ["salvage_arm", "tangle_wire", "buoy_worm"]
const DT := 1.0 / 60.0


func run() -> void:
	_test_pose_math()
	_test_mesh_topology()
	_test_worm_belly_and_neck()
	_test_data()
	await _test_gait()
	await _test_severing()
	_test_bad_data_is_safe()
	await _test_salvage_arm()
	await _test_tangle_wire()
	await _test_buoy_worm()
	await _test_cloud_serpent()
	await check_defeatable_on_every_difficulty([SALVAGE_PATH, TANGLE_PATH, BUOY_PATH, SMALL_PATH])


func _test_pose_math() -> void:
	for ratio: float in [0.5, 0.7, 0.85, 0.95]:
		var seg := 4.0
		var n := 9
		var chord := Vector2(0.3, 1.0).normalized() * seg * float(n) * ratio
		var rotations := ChainPose.arc(chord, seg, n, Vector2(1, -1))
		check(ChainPose.tip_of(rotations, seg).distance_to(chord) < 0.35, "the arc reaches the foot at %.0f%% of the full length" % (ratio * 100.0))
	var straight := ChainPose.arc(Vector2(0, 100), 4.0, 8, Vector2.RIGHT)
	check(ChainPose.tip_of(straight, 4.0).distance_to(Vector2(0, 32)) < 0.01, "a chord longer than the chain gives a straight chain pointing at the target")
	var left := ChainPose.tip_of(ChainPose.arc(Vector2(0, 20), 4.0, 8, Vector2.LEFT), 4.0)
	check(left.distance_to(Vector2(0, 20)) < 0.3, "bending the other way still reaches the foot")
	var mid_a := _midpoint(ChainPose.arc(Vector2(0, 20), 4.0, 8, Vector2.LEFT), 4.0)
	var mid_b := _midpoint(ChainPose.arc(Vector2(0, 20), 4.0, 8, Vector2.RIGHT), 4.0)
	check(mid_a.x < -1.0 and mid_b.x > 1.0, "the knee bulges toward the requested side (%.1f, %.1f)" % [mid_a.x, mid_b.x])


func _midpoint(rotations: PackedFloat32Array, seg_len: float) -> Vector2:
	var half := PackedFloat32Array()
	for i in rotations.size() / 2:
		half.append(rotations[i])
	return ChainPose.tip_of(half, seg_len)


func _test_mesh_topology() -> void:
	for segments in [2, 3, 10, 24]:
		var topology := ChainMesh.topology(segments)
		var weights: Array[PackedFloat32Array] = topology["weights"]
		var vertex_count := ChainMesh.rows_for(segments) * ChainMesh.COLUMNS
		var worst := 0.0
		for v in vertex_count:
			var sum := 0.0
			for w in weights:
				sum += w[v]
			worst = maxf(worst, absf(sum - 1.0))
		check(worst < 0.0001, "every vertex of a %d-bone chain has weights summing to 1" % segments)
		check(topology == ChainMesh.topology(segments), "the topology of %d bones is cached" % segments)
	var plain := ChainMesh.build_geometry(Vector2(16, 64), 4, 4.0, 5.0, Vector2.ZERO, 0.0, false)
	var flipped := ChainMesh.build_geometry(Vector2(16, 64), 4, 4.0, 5.0, Vector2.ZERO, 0.0, true)
	check((plain["uvs"] as PackedVector2Array)[0].x == 0.0 and (flipped["uvs"] as PackedVector2Array)[0].x == 16.0, "mirroring flips the texture, not the shape")


func _test_data() -> void:
	check_enemy_data([SALVAGE_PATH, TANGLE_PATH, BUOY_PATH, SMALL_PATH, SERPENT_PATH],
			[&"salvage_slam", &"tangle_lash", &"buoy_spit", &"salvage_contact", &"cloud_serpent_contact"])
	for id in CHAIN_IDS:
		var creature := ChainCreature.new()
		runner.get_tree().root.add_child(creature)
		check(creature.setup(id), "%s builds" % id)
		var data := RigLibrary.load_json(ChainCreature.PATH % id)
		check(creature.tentacle_count() == (data["tentacles"] as Array).size(), "%s has every tentacle of its data" % id)
		for state: String in (data["states"] as Dictionary).keys():
			for i in 40:
				creature.animate(DT, StringName(state))
			var finite := true
			for t in creature.tentacle_count():
				var tip := creature.tip_of(t)
				finite = finite and is_finite(tip.x) and is_finite(tip.y)
			check(finite, "%s in state %s has finite tentacle tips" % [id, state])
		creature.queue_free()
	var worm := WormCreature.new()
	runner.get_tree().root.add_child(worm)
	check(worm.setup("cloud_serpent"), "cloud_serpent builds")
	var worm_data := RigLibrary.load_json(WormCreature.PATH % "cloud_serpent")
	for state: String in (worm_data["states"] as Dictionary).keys():
		for i in 40:
			worm.global_position += Vector2(1.5, 0)
			worm.animate(DT, StringName(state))
		check(is_finite(worm.joint_position(worm.joint_count() - 1).x), "the serpent in state %s has finite joints" % state)
	worm.queue_free()
	# 不共用動畫：每個敵人用自己的美術與狀態表，專屬特效也各一份
	var skins := {}
	for path in [SALVAGE_PATH, TANGLE_PATH, BUOY_PATH, SERPENT_PATH]:
		var skin := (load(path) as EnemyData).creature_skin
		check(not skins.has(skin), "each creature has its own motion data: %s" % skin)
		skins[skin] = true
	for id in ["salvage_arm", "tangle_wire", "buoy_worm", "buoy_worm_small", "cloud_serpent"]:
		check(ResourceLoader.exists(EnemyVfx.PATH % id), "%s has its own effects file" % id)


## The pale underside must follow the head on both sides, including its first frame.
## The leading body cross-section must overlap opaque neck pixels, not meet a cut edge.
func _test_worm_belly_and_neck() -> void:
	var head_image := (load("res://art/creatures/cloud_serpent/head.png") as Texture2D).get_image()
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2(1, 0.4).normalized(), Vector2(-1, 0.4).normalized()]:
		var worm := WormCreature.new()
		runner.get_tree().root.add_child(worm)
		check(worm.setup("cloud_serpent"), "the serpent neck fixture builds")
		worm.global_position = Vector2(160, 100)
		worm.reset_trail(direction)
		for sample: int in [1, 119]:
			for frame in sample:
				worm.animate(DT, &"idle")
			var body := worm.get_node("Body") as Polygon2D
			var head := worm.get_node("Head") as Sprite2D
			var belly := Vector2.ZERO
			var back := Vector2.ZERO
			if body.uv[0].y > body.uv[1].y:
				belly = body.polygon[0]
				back = body.polygon[1]
			else:
				belly = body.polygon[1]
				back = body.polygon[0]
			var underside_agrees := (belly - back).dot(head.global_transform.y) > 0.0
			for row in range(1, body.polygon.size() / 2):
				var first := row * 2
				var row_belly := body.polygon[first] if body.uv[first].y > body.uv[first + 1].y else body.polygon[first + 1]
				var row_back := body.polygon[first + 1] if body.uv[first].y > body.uv[first + 1].y else body.polygon[first]
				underside_agrees = underside_agrees and (row_belly - row_back).dot(head.global_transform.y) > 0.0
			check(underside_agrees,
					"body UV underside agrees with head underside for %s at frame %d" % [direction, sample])
			var neck_covered := true
			for step in 9:
				var world := body.polygon[0].lerp(body.polygon[1], float(step) / 8.0)
				var pixel := head.to_local(world) - head.offset
				var inside := pixel.x >= 1.0 and pixel.x < head_image.get_width() - 1 and pixel.y >= 0 and pixel.y < head_image.get_height()
				neck_covered = neck_covered and inside
				if inside:
					neck_covered = neck_covered and head_image.get_pixel(int(pixel.x), int(pixel.y)).a >= 0.5
			check(neck_covered, "the whole body end overlaps opaque head pixels for %s at frame %d" % [direction, sample])
			check(worm.joint_position(0).distance_to(worm.joint_position(19)) > 85.0,
					"the neck repair keeps the complete twenty-joint trail")
		worm.free()
	var turning := WormCreature.new()
	runner.get_tree().root.add_child(turning)
	turning.setup("cloud_serpent")
	turning.reset_trail(Vector2.RIGHT)
	var belly_down := true
	var previous_uv := PackedVector2Array()
	var largest_visible_uv_step := 0.0
	var tail_belly_down := true
	var previous_head_mirrored := false
	var opposing_tail_samples := 0
	for frame in 480:
		turning.global_position += Vector2.from_angle(float(frame) * TAU / 240.0) * 1.2
		turning.animate(DT, &"erupt")
		belly_down = belly_down and (turning.get_node("Head") as Sprite2D).global_transform.y.y >= -0.00001
		var mesh := turning.get_node("Body") as Polygon2D
		if not previous_uv.is_empty():
			# Row zero is covered by the opaque head; every exposed row must roll gradually.
			for index in range(2, mesh.uv.size()):
				largest_visible_uv_step = maxf(largest_visible_uv_step, absf(mesh.uv[index].y - previous_uv[index].y))
		previous_uv = mesh.uv.duplicate()
		var last := mesh.polygon.size() - 2
		var tail_direction := ((mesh.polygon[last - 2] + mesh.polygon[last - 1]) - (mesh.polygon[last] + mesh.polygon[last + 1])).normalized()
		var head_mirrored := (turning.get_node("Head") as Sprite2D).scale.y < 0.0
		if head_mirrored != previous_head_mirrored and absf(tail_direction.x) > 0.5 and (tail_direction.x < 0.0) != head_mirrored:
			opposing_tail_samples += 1
			var lower := mesh.polygon[last] if mesh.uv[last].y > mesh.uv[last + 1].y else mesh.polygon[last + 1]
			var upper := mesh.polygon[last + 1] if mesh.uv[last].y > mesh.uv[last + 1].y else mesh.polygon[last]
			tail_belly_down = tail_belly_down and lower.y > upper.y
		previous_head_mirrored = head_mirrored
	check(belly_down, "the head underside stays on the lower side throughout two full turns")
	check(largest_visible_uv_step <= 4.0001, "a head direction change cannot instantly flip the exposed body texture (largest UV step %.2f)" % largest_visible_uv_step)
	check(tail_belly_down, "the far tail underside follows its own direction while the head turns the other way")
	check(opposing_tail_samples > 0, "the turn fixture actually includes a head flip with a tail still pointing the other way")
	print("WORM_TURN_METRICS max_visible_uv_step=", largest_visible_uv_step, " opposing_tail_samples=", opposing_tail_samples)
	turning.free()


## 落腳步行：走路時腳交替離地，釘住的腳在世界座標不動，腳都落在地面上，身體隨斷肢變低。
func _test_gait() -> void:
	await open_level(10.0)
	var creature := ChainCreature.new()
	level.add_child(creature)
	creature.position = Vector2(100.0, FLOOR_Y)
	check(creature.setup("salvage_arm"), "the walker builds")
	for i in 20:
		creature.animate(DT, &"idle")
	var legs := creature.tentacle_count()
	var planted_before: Array[Vector2] = []
	for i in legs:
		planted_before.append(creature.foot_of(i))
	check(planted_before[0].y == FLOOR_Y and planted_before[3].y == FLOOR_Y, "the feet start on the ground")
	var landed: Array[int] = []
	creature.foot_planted.connect(func(i: int, _at: Vector2) -> void: landed.append(i))
	var max_airborne := 0
	var overlap_groups := 0
	var slipped := 0.0
	var previous: Array[Vector2] = planted_before.duplicate()
	for frame in 240:
		creature.position.x += 40.0 * DT
		creature.animate(DT, &"walk", Vector2(40.0, 0.0))
		var airborne := 0
		var groups := {}
		for i in legs:
			var foot := creature.foot_of(i)
			if creature.is_stepping(i):
				airborne += 1
				groups[i % 2] = true
			else:
				slipped = maxf(slipped, foot.distance_to(previous[i]) if previous[i].y == foot.y and not is_equal_approx(previous[i].x, foot.x) and foot.distance_to(previous[i]) < 0.001 else 0.0)
			previous[i] = foot
		max_airborne = maxi(max_airborne, airborne)
		if groups.size() > 1:
			overlap_groups += 1
	check(landed.size() >= 8, "walking for 4 seconds plants the feet many times (%d)" % landed.size())
	check(max_airborne <= legs - 1 and max_airborne >= 1, "some feet are always on the ground while others step (%d in the air at most)" % max_airborne)
	check(overlap_groups <= 60, "the two groups of legs take turns (%d overlapping frames)" % overlap_groups)
	for i in legs:
		if not creature.is_stepping(i):
			check(absf(creature.foot_of(i).y - FLOOR_Y) < 0.5, "planted foot %d is on the ground" % i)
	for i in 60:
		creature.animate(DT, &"idle")
	var rig := creature.get_node("Rig") as Node2D
	var stance_full: float = rig.position.y
	creature.sever(0)
	creature.sever(1)
	creature.sever(2)
	for i in 120:
		creature.animate(DT, &"idle")
	check(rig.position.y > stance_full + 1.5, "the body sinks as legs are lost (%.1f -> %.1f)" % [stance_full, rig.position.y])
	check(creature.speed_scale() < 0.8, "fewer legs means slower walking (%.2f)" % creature.speed_scale())
	creature.queue_free()
	await physics_frames(2)
	await end_level(level)


## 斷肢：每條有自己的生命，打斷後整條飛出；全部斷光露出核心且只通知一次。
func _test_severing() -> void:
	await open_level(10.0)
	var creature := ChainCreature.new()
	level.add_child(creature)
	creature.position = Vector2(100.0, FLOOR_Y)
	creature.setup("salvage_arm")
	var severed: Array[int] = []
	var exposed: Array[bool] = []
	creature.tentacle_severed.connect(func(i: int) -> void: severed.append(i))
	creature.core_exposed.connect(func() -> void: exposed.append(true))
	for i in 10:
		creature.animate(DT, &"idle")
	check(creature.life_of(2) == 3 and not creature.damage_tentacle(2, 2), "two points of damage do not sever a three-life tentacle")
	check(creature.life_of(2) == 1 and creature.is_alive(2), "the tentacle keeps its remaining life")
	check(creature.damage_tentacle(2, 1, Vector2.RIGHT) and not creature.is_alive(2), "the killing blow severs it")
	check(not creature.damage_tentacle(2, 5) and severed == [2], "a severed tentacle cannot be hurt again and is announced once")
	await physics_frames(3)
	check(level.find_children("*", "RigDebris", true, false).size() >= 1, "the severed tentacle flies off as a pooled piece")
	for i in creature.tentacle_count():
		creature.sever(i)
	check(creature.alive_tentacles() == 0 and creature.is_exposed() and exposed.size() == 1, "all tentacles gone exposes the core exactly once")
	check(creature.tip_of(2) == Vector2.INF and creature.capsule_of(2).is_empty(), "a severed tentacle has no hit points")
	for i in 20:
		creature.animate(DT, &"walk", Vector2(30, 0))
	check(true, "an exposed creature keeps animating")
	creature.queue_free()
	await physics_frames(2)
	await end_level(level)


func _test_bad_data_is_safe() -> void:
	var creature := ChainCreature.new()
	runner.get_tree().root.add_child(creature)
	check(not creature.setup("no_such_creature"), "a missing creature file is rejected without a crash")
	creature.animate(DT, &"idle")
	check(creature.alive_tentacles() == 0 and creature.tip_of(0) == Vector2.INF and creature.life_of(5) == 0, "queries on an empty creature are safe")
	creature.queue_free()
	var worm := WormCreature.new()
	runner.get_tree().root.add_child(worm)
	check(not worm.setup("no_such_creature"), "a missing worm file is rejected without a crash")
	worm.animate(DT, &"idle")
	worm.queue_free()


func _player_hit_count(damage_seen: Array) -> int:
	return damage_seen.size()


## 打撈臂：逼近 → 掃地（預兆、貼地橫掃）→ 砸地（預告圈、衝擊）；打斷觸手；全斷後核心露出傷害加倍。
func _test_salvage_arm() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var arm := spawn(SALVAGE_PATH, 40.0) as ChainEnemy
	place_player(40.0 - 2.0)
	check(arm.chain != null and arm.chain.tentacle_count() == 6, "the salvage arm has six tentacles")
	check(arm.hurtbox.parts.size() >= 6, "each tentacle has its own simple hurtbox")
	var sweep_seen := await wait_state(arm, &"sweep_windup", 60 * 6)
	check(sweep_seen and arm.is_telegraphing(), "the arm winds up a sweep with a telegraph")
	check(arm.data.telegraph_time >= 0.6, "the sweep telegraph is long enough to read")
	var free_arms := 0
	for i in 6:
		if arm.chain.get("_chains")[i]["free"]:
			free_arms += 1
	check(free_arms == 2, "two front legs are released from walking for the attack")
	var before := level.player.health.current
	check(await wait_state(arm, &"sweep", 60 * 3), "the windup becomes a sweep")
	check(arm._strike.active and arm._strike.point_count() > 0, "the sweep's hit circles follow the tentacle bones")
	for i in 60 * 2:
		if arm.fsm.is_in(&"recover"):
			break
		await physics_frames(1)
	check(level.player.health.current < before, "standing under the sweep hurts")
	check(not arm._strike.active, "the hit circles are gone after the sweep")
	# 砸地：預告圈固定在落點，離開就不會受傷
	level.player.health.setup(999, 0.0)
	place_player(40.0 - 4.0)
	arm._use_slam_next = true
	arm._cooldown = 0.0
	check(await wait_state(arm, &"slam_windup", 60 * 6), "the arm winds up a slam")
	for i in 60 * 2:
		if arm._telegraph_left < 0.2:
			break
		await physics_frames(1)
	var locked: Vector2 = arm._slam_point
	place_player(40.0 + 6.0)
	for i in 60 * 3:
		if arm.fsm.is_in(&"slam"):
			break
		await physics_frames(1)
	check(arm.fsm.is_in(&"slam") or arm.fsm.is_in(&"recover"), "the slam follows its windup")
	check(locked.distance_to(arm._slam_point) < 1.0, "the slam target is locked in before the hit and stays put when the player moves")
	await physics_frames(60)
	# 打斷觸手：打中觸手的受擊框扣那條的生命
	var part := arm.hurtbox.parts[0]
	var index := int(String(part.part_id).trim_prefix("tentacle_"))
	var health_before := arm.health.current
	var life_before := arm.chain.life_of(index)
	level.player.health.setup(999, 0.0)
	part.receive(hit(1, true))
	check(arm.chain.life_of(index) < life_before, "hitting a tentacle hurts that tentacle (%d -> %d)" % [life_before, arm.chain.life_of(index)])
	check(arm.health.current > health_before - 2, "the armored hull takes reduced damage through the tentacle")
	for i in arm.chain.tentacle_count():
		arm.chain.sever(i)
	await physics_frames(2)
	check(arm.chain.is_exposed() and absf(arm.hurtbox.damage_scale - 2.0) < 0.01, "with every tentacle severed the core takes double damage")
	check(arm.hurtbox.parts.any(func(p: Hurtbox) -> bool: return p.part_id == &"core"), "the exposed core is a weak point")
	check(arm.is_stunned(), "exposing the core staggers the arm")
	check(arm._move_speed() < arm.data.move_speed * 0.5, "an armless arm crawls")
	await end_level(level)


## 纏絲：藏著 → 抖動冒火花（預兆）→ 伸出鞭打 → 縮回；縮著時觸手打不到；觸手全斷就報銷。
func _test_tangle_wire() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var wire := spawn(TANGLE_PATH, 40.0, FLOOR_Y - 20.0) as ChainEnemy
	place_player(40.0 - 3.0)
	check(wire.fsm.is_in(&"hidden") or wire.fsm.is_in(&"warn"), "the nest starts hidden")
	check(not wire._tentacles_hittable() or not wire.fsm.is_in(&"hidden"), "tentacles cannot be hit while retracted")
	check(await wait_state(wire, &"warn", 60 * 4), "the nest warns when the player comes close")
	check(wire.is_telegraphing() and wire.data.telegraph_time >= 0.8, "the warning is a long telegraph")
	var before := level.player.health.current
	check(await wait_state(wire, &"lash", 60 * 3), "the warning becomes a lash")
	check(wire._tentacles_hittable(), "tentacles can be hit when extended")
	for i in 60:
		await physics_frames(1)
	check(level.player.health.current < before, "the lash hurts a player in reach")
	check(await wait_state(wire, &"retract", 60 * 3), "the nest retracts after the lash")
	check(await wait_state(wire, &"hidden", 60 * 2), "and hides again")
	for i in wire.chain.tentacle_count():
		wire.chain.sever(i)
	await physics_frames(2)
	check(wire.is_dying(), "cutting every cable destroys the nest")
	await end_level(level)


## 浮標蟲：發現 → 逼近 → 鼓起（預兆）→ 噴酸液；被擊敗分裂成兩隻小的，小的不再分裂。
func _test_buoy_worm() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var worm := spawn(BUOY_PATH, 38.0) as ChainEnemy
	place_player(38.0 - 6.0)
	check(worm.chain != null and worm.chain.tentacle_count() == 6, "the buoy worm has six short legs")
	check(await wait_state(worm, &"swell", 60 * 6), "the worm swells before spitting")
	check(worm.is_telegraphing() and worm.data.telegraph_time >= 0.5, "the swelling is a telegraph")
	var spat := false
	for i in 90:
		await physics_frames(1)
		if not runner.get_tree().get_nodes_in_group(&"projectiles").is_empty() or worm.fsm.is_in(&"spit") or worm.fsm.is_in(&"recover"):
			spat = true
			break
	check(spat, "the worm spits after swelling")
	var before := runner.get_tree().get_nodes_in_group(&"enemies").size()
	worm.hurtbox.receive(lethal())
	await physics_frames(3)
	var small: Array = []
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		if (node as Enemy).data.id == &"buoy_worm_small":
			small.append(node)
	check(small.size() == 2, "a defeated buoy worm splits into two small ones (%d)" % small.size())
	check(runner.get_tree().get_nodes_in_group(&"enemies").size() >= before + 1, "the pieces join the fight")
	(small[0] as Enemy).hurtbox.receive(lethal())
	await physics_frames(3)
	var count_small := 0
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		if (node as Enemy).data.id == &"buoy_worm_small" and not (node as Enemy).is_dying():
			count_small += 1
	check(count_small == 1, "small worms do not split again")
	await end_level(level)


## 雲蛇：地底潛行 → 地面隆起（預兆）→ 躍出（可被打、頭兩倍）→ 落回地裡（打不到）。
func _test_cloud_serpent() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	var serpent := spawn(SERPENT_PATH, 36.0, FLOOR_Y + 16.0) as Enemy
	place_player(36.0 - 6.0)
	check(not serpent.hurtbox.enabled, "the serpent cannot be hit while underground")
	check(await wait_state(serpent, &"rumble", 60 * 5), "the ground bulges before the serpent erupts")
	check(serpent.is_telegraphing() and serpent.data.telegraph_time >= 0.8, "the bulge is a long telegraph")
	check(not serpent.hurtbox.enabled, "still underground during the warning")
	check(await wait_state(serpent, &"erupt", 60 * 3), "the serpent erupts")
	await physics_frames(2)
	check(serpent.hurtbox.enabled and serpent.global_position.y < FLOOR_Y, "in the air the serpent can be hit")
	check(serpent.hurtbox.parts.any(func(p: Hurtbox) -> bool: return p.part_id == &"head" and p.damage_scale >= 2.0), "its head is a double-damage weak point")
	serpent.hurtbox.receive(lethal())
	await physics_frames(1)
	check(serpent.is_dying(), "an erupted serpent can be defeated")
	await end_level(level)
	await open_level(10.0)
	serpent = spawn(SERPENT_PATH, 36.0, FLOOR_Y + 16.0) as Enemy
	place_player(36.0 - 6.0)
	serpent.hurtbox.receive(lethal())
	check(not serpent.is_dying(), "attacks pass over a serpent that is underground")
	check(await wait_state(serpent, &"erupt", 60 * 8), "the serpent erupts again")
	check(await wait_state(serpent, &"dive", 60 * 3), "it dives back into the ground")
	check(await wait_state(serpent, &"lurk", 60 * 3), "and goes back to lurking")
	await physics_frames(2)
	check(not serpent.hurtbox.enabled, "underground again, it cannot be hit")
	await end_level(level)
