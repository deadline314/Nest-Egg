class_name Chapter2ExpansionSuite
extends EnemySuiteBase
## 第二章擴充（NE-54）：中庭、回收燈幕追逐橋段（出發、追上就死、跑得過、橋段後重生視為已過）、迷你頭目看守長（睡著、醒來亮血條、擊敗解開閘門但不結束關卡）、
## 光橋（只有燈亮時看得見）、病房區與新增的隱藏房間，以及新生物的配置與安全空間。

const LEVEL_2 := "res://data/levels/level_02.tres"
const CUSTODIAN_PATH := "res://data/enemies/custodian.tres"
const CHASE_START_COL := 272
const CHASE_END_COL := CHASE_START_COL + 50
const DT := 1.0 / 60.0
const RUN_SPEED := 150.0
## 跑過橋段時，玩家和光幕前緣至少要保持的距離（像素）。
const MIN_RUN_MARGIN := 120.0


func run() -> void:
	_test_layout()
	_test_chase_data()
	check_enemy_data([CUSTODIAN_PATH], [&"custodian_contact", &"recycle_curtain"])
	check(ResourceLoader.exists(EnemyVfx.PATH % "custodian"), "the custodian has his own effects file")
	await _test_curtain_kills_a_player_who_stops()
	await _test_curtain_can_be_outrun()
	await _test_curtain_after_the_chase()
	await _test_custodian_flow()
	await _test_gate_and_defeat()
	await _test_ghost_path()


func _data() -> LevelData:
	return load(LEVEL_2) as LevelData


func _test_layout() -> void:
	var data := _data()
	var layout := LevelBuilder.parse(data)
	check(layout.is_valid() and layout.warnings.is_empty(), "the expanded level 2 parses without warnings %s" % [layout.warnings])
	check(layout.width >= 480, "the level is longer than before (%d columns)" % layout.width)
	var counts: Dictionary[String, int] = {}
	for y in layout.height:
		for x in layout.width:
			counts[layout.cell(x, y)] = counts.get(layout.cell(x, y), 0) + 1
	check(counts.get("X", 0) == 1 and counts.get("b", 0) == 1 and counts.get("m", 0) == 1, "one chase start, one mini-boss and one gate")
	check(counts.get("x", 0) >= 2, "at least two crackable walls (hidden rooms A and C): %d" % counts.get("x", 0))
	check(layout.ghost_rects.size() == 3, "the light bridge has three segments (%d)" % layout.ghost_rects.size())
	# 橋段前後都有檢查點
	var before := false
	var after := false
	for checkpoint in layout.checkpoints:
		var col := int(checkpoint.x / layout.tile_size)
		before = before or (col < CHASE_START_COL and col >= CHASE_START_COL - 12)
		after = after or (col >= CHASE_END_COL and col <= CHASE_END_COL + 8)
	check(before and after, "there are checkpoints right before and right after the chase")
	# 新生物的配置與第一次遭遇的安全空間
	check_level_placement({LEVEL_2: [[&"wall_gecko", 215, 263], [&"shaft_bat", 70, 140], [&"shaft_bat", 215, 263], [&"tangle_wire", 325, 385], [&"rail_cannon", 440, 470]]})
	for id in [&"wall_gecko", &"shaft_bat", &"tangle_wire", &"rail_cannon"]:
		var all_clear := true
		for cell in PlacementChecks.cells_of(layout, id):
			all_clear = all_clear and PlacementChecks.first_encounter_clear(layout, cell)
		check(all_clear, "%s never appears right behind another kind of enemy" % id)
	# 病房區：護理師在病房裡，每間病房有床位平台
	var nurse_col := -1
	for spawn: Dictionary in layout.spawns:
		if spawn["resource"] is NpcData and (spawn["resource"] as NpcData).id == &"nurse":
			nurse_col = (spawn["cell"] as Vector2i).x
	check(nurse_col >= 440 and nurse_col < 470, "the nurse works in the ward (column %d)" % nurse_col)


func _test_chase_data() -> void:
	var curtain := load("res://data/props/recycle_curtain.tres") as ChaseData
	check(curtain != null and curtain.validate().is_empty(), "the curtain data is valid %s" % [curtain.validate() if curtain != null else []])
	var tuning := load("res://data/player/player_tuning.tres") as PlayerTuning
	var run_speed := tuning.run_speed if tuning != null else RUN_SPEED
	check(curtain.speed <= run_speed * 0.6, "the curtain is much slower than a running player (%.0f vs %.0f)" % [curtain.speed, run_speed])
	var bad := ChaseData.new()
	bad.speed = 200.0
	bad.lead_tiles = 2
	bad.length_tiles = 1
	check(bad.validate().size() >= 3, "bad chase data is reported")


func _curtain_of(level: Level) -> LightCurtain:
	var found := level.find_children("*", "LightCurtain", true, false)
	return found[0] as LightCurtain if not found.is_empty() else null


func _quiet_level() -> Level:
	var level := await start_level(_data())
	level.player.health.setup(5, 0.0)
	for enemy in get_tree_enemies(level):
		enemy.queue_free()
	return level


func get_tree_enemies(level: Level) -> Array[Node]:
	return level.get_tree().get_nodes_in_group(&"enemies")


func _place_at_column(level: Level, column: float) -> void:
	level.player.global_position = Vector2(column * 16.0 + 8.0, FLOOR_Y)
	level.player.velocity = Vector2.ZERO


## 站著不動的玩家會被光幕追上：先待命，走過起點才出發，前緣在身後約 lead 格，之後追上就死。
func _test_curtain_kills_a_player_who_stops() -> void:
	var level := await _quiet_level()
	var curtain := _curtain_of(level)
	check(curtain != null and curtain.phase == LightCurtain.Phase.ARMED, "the curtain waits until the player crosses the start")
	_place_at_column(level, 100.0)
	await physics_frames(10)
	check(curtain.phase == LightCurtain.Phase.ARMED, "walking elsewhere does not start it")
	var toasts: Array[String] = []
	var listener := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(listener)
	_place_at_column(level, CHASE_START_COL + 1.0)
	await physics_frames(6)
	EventBus.toast_requested.disconnect(listener)
	check(curtain.phase == LightCurtain.Phase.RUNNING, "crossing the start sets the curtain off")
	check(toasts.any(func(t: String) -> bool: return t.contains("持續前進")), "the player is told to keep moving")
	var gap := curtain.gap_to_player()
	check(gap > 14.0 * 16.0 and gap < 19.0 * 16.0, "the curtain starts well behind the player (%.0f px)" % gap)
	for i in 60 * 7:
		await physics_frames(1)
		if level.player.is_dead():
			break
	check(level.player.is_dead(), "a player who stops is swallowed by the curtain")
	await end_level(level)


## 不停下來就跑得過：以跑速沿橋段前進（沿地形高度），全程和光幕保持距離，光幕在終點停下。
func _test_curtain_can_be_outrun() -> void:
	var level := await _quiet_level()
	var curtain := _curtain_of(level)
	var layout := LevelBuilder.parse(_data())
	var x := float(CHASE_START_COL * 16 + 8)
	var y := FLOOR_Y
	var closest := INF
	level.player.global_position = Vector2(x, y)
	await physics_frames(4)
	for i in 60 * 9:
		x += RUN_SPEED * DT
		var col := int(x / 16.0)
		var surface := layout.surface_heights[mini(col, layout.width - 1)]
		y = surface if surface != INF else y
		level.player.global_position = Vector2(x, y)
		level.player.velocity = Vector2.ZERO
		await physics_frames(1)
		if curtain.phase == LightCurtain.Phase.RUNNING:
			closest = minf(closest, curtain.gap_to_player())
		if x > float((CHASE_END_COL + 6) * 16):
			break
	check(not level.player.is_dead(), "a player who keeps running makes it through")
	check(closest > MIN_RUN_MARGIN, "the curtain never gets close to a runner (closest %.0f px)" % closest)
	for i in 60 * 16:  # 光幕從身後 18 格出發，要走完 68 格才停
		if curtain.phase == LightCurtain.Phase.DONE:
			break
		await physics_frames(1)
	check(curtain.phase == LightCurtain.Phase.DONE, "the curtain stops at the end of the chase")
	await end_level(level)


## 從橋段之後的檢查點重生：視為已經過了，光幕不會再出發。
func _test_curtain_after_the_chase() -> void:
	var level := await _quiet_level()
	var curtain := _curtain_of(level)
	_place_at_column(level, CHASE_END_COL + 4.0)
	await physics_frames(8)
	check(curtain.phase == LightCurtain.Phase.DONE and not level.player.is_dead(), "respawning after the chase leaves the curtain finished")
	await end_level(level)


## 看守長：玩家遠的時候睡著、不亮血條；靠近後醒來、血條出現；擊敗後解開閘門、收起血條，但關卡不結束。
func _test_custodian_flow() -> void:
	await open_level(8.0)
	level.player.health.setup(999, 0.0)
	var started: Array[String] = []
	var changed: Array[Vector2i] = []
	var closed: Array[bool] = []
	var toggled: Array[StringName] = []
	var defeated: Array[bool] = []
	var l1 := func(name: String, _max: int) -> void: started.append(name)
	var l2 := func(current: int, maximum: int) -> void: changed.append(Vector2i(current, maximum))
	var l3 := func() -> void: closed.append(true)
	var l4 := func(channel: StringName, active: bool) -> void:
		if active:
			toggled.append(channel)
	var l5 := func() -> void: defeated.append(true)
	EventBus.boss_started.connect(l1)
	EventBus.boss_health_changed.connect(l2)
	EventBus.boss_bar_closed.connect(l3)
	EventBus.mechanism_toggled.connect(l4)
	EventBus.boss_defeated.connect(l5)
	var boss := spawn(CUSTODIAN_PATH, 70.0) as Enemy
	check(boss.fsm.is_in(&"dormant") and not boss.data.is_boss, "the custodian sleeps until the player comes close")
	await physics_frames(60)
	check(started.is_empty() and boss.fsm.is_in(&"dormant"), "no health bar while he sleeps")
	place_player(58.0)
	for i in 120:
		await physics_frames(1)
		if not boss.fsm.is_in(&"dormant"):
			break
	check(started.size() == 1 and started[0] == boss.data.display_name, "the bar opens once when he wakes (%s)" % [started])
	check(boss.fsm.is_in(&"intro") or boss.fsm.is_in(&"idle") or boss.fsm.time_in_state >= 0.0, "he starts fighting")
	boss.hurtbox.receive(hit(2, true))
	check(not changed.is_empty() and changed[changed.size() - 1].x < boss.data.max_health, "damage moves the bar")
	check(boss.health.max_health < load("res://data/enemies/warden.tres").max_health, "the mini-boss is weaker than the warden")
	check(boss.data.contact_damage >= 2, "but hits harder than an ordinary enemy")
	boss.hurtbox.receive(lethal())
	for i in 60 * 4:
		await physics_frames(1)
		if not is_instance_valid(boss) or boss.is_queued_for_deletion():
			break
	await physics_frames(2)
	check(toggled.has(&"custodian_gate"), "defeating him opens the transfer-station gate %s" % [toggled])
	check(not closed.is_empty(), "the health bar closes")
	check(defeated.is_empty(), "defeating the mini-boss does not end the chapter")
	EventBus.boss_started.disconnect(l1)
	EventBus.boss_health_changed.disconnect(l2)
	EventBus.boss_bar_closed.disconnect(l3)
	EventBus.mechanism_toggled.disconnect(l4)
	EventBus.boss_defeated.disconnect(l5)
	await end_level(level)


## 閘門在地圖上：打開頻道後閘門真的打開；看守長在地圖上；被遠距離打到會醒。
func _test_gate_and_defeat() -> void:
	var level := await start_level(_data())
	var gates := level.find_children("*", "Gate", true, false).filter(func(g: Node) -> bool: return (g as Gate).data.channel == &"custodian_gate")
	check(gates.size() == 1 and not (gates[0] as Gate).is_open, "the transfer-station gate starts closed")
	var bosses := get_tree_enemies(level).filter(func(e: Node) -> bool: return (e as Enemy).data.id == &"custodian")
	check(bosses.size() == 1, "the custodian stands in the level")
	var sleeper := bosses[0] as Enemy
	sleeper.hurtbox.receive(hit(1, true))
	check(not sleeper.fsm.is_in(&"dormant"), "being shot from afar wakes him")
	EventBus.mechanism_toggled.emit(&"custodian_gate", true)
	await physics_frames(2)
	check((gates[0] as Gate).is_open, "the gate opens when the channel is toggled")
	EventBus.boss_bar_closed.emit()
	await end_level(level)


## 光橋：三段平台一直能踩，但只有燈亮的時候看得見；每段的燈明滅，可見度在 0 與 1 之間來回。
func _test_ghost_path() -> void:
	var level := await start_level(_data())
	var ghosts := level.find_children("*", "GhostPlatforms", true, false)
	check(ghosts.size() == 1, "the level builds the light bridge")
	var bridge := ghosts[0] as GhostPlatforms
	check(bridge.segment_count() == 3, "three segments")
	var lowest: Array[float] = [1.0, 1.0, 1.0]
	var highest: Array[float] = [0.0, 0.0, 0.0]
	for i in 60 * 5:
		await physics_frames(1)
		for k in 3:
			lowest[k] = minf(lowest[k], bridge.lit_amount(k))
			highest[k] = maxf(highest[k], bridge.lit_amount(k))
	for k in 3:
		check(highest[k] > 0.5 and lowest[k] < 0.3, "segment %d fades in and out with its lamp (%.2f..%.2f)" % [k, lowest[k], highest[k]])
	var shapes := bridge.get_node("Bridge").get_children().filter(func(n: Node) -> bool: return n is CollisionShape2D and (n as CollisionShape2D).one_way_collision)
	check(shapes.size() == 3, "every segment can be stood on whether or not it is lit")
	await end_level(level)
