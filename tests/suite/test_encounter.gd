class_name EncounterSuite
extends EnemySuiteBase
## 鎖場遭遇（ST-11）：走進範圍鎖上競技場閘門、成員與增援全部倒下才打開、完成後不再觸發、
## 成員已死時不鎖人、逾時強制解鎖、競技場閘門不存進世界狀態（重生時是打開的）、資料檢查。

const GRUNT := "res://data/enemies/sweeper.tres"


func run() -> void:
	_test_data_rules()
	await _test_free_encounter()
	await preload("res://tests/helpers/encounter_resume_checks.gd").run(self)
	await preload("res://tests/helpers/encounter_restore_guard_checks.gd").run(self)
	await _test_special_entry_inset()
	await _test_special_boss_boundary()
	await _test_lock_and_clear()
	await _test_reinforcements()
	await _test_empty_zone_does_not_lock()
	await _test_timeout_unlocks()
	await _test_arena_gate_is_not_persisted()
	GameState.start_new_run(GameState.difficulties[1])


func _encounter(channel := &"test_arena", reinforcements: Array[EnemyData] = [], max_lock := 90.0, locked := true) -> MechanismData:
	var data := MechanismData.new()
	data.id = &"test_encounter"
	data.kind = MechanismData.Kind.ENCOUNTER
	data.channel = channel
	data.size_tiles = Vector2i(20, 8)
	data.reinforcements = reinforcements
	data.max_lock_seconds = max_lock
	data.lock_combat_area = locked
	data.clear_text = "通道打開了"
	return data


func _arena_gate(channel := &"test_arena", locked := true) -> MechanismData:
	var data := MechanismData.new()
	data.id = &"test_arena_gate"
	data.kind = MechanismData.Kind.GATE
	data.channel = channel
	data.size_tiles = Vector2i(1, 8)
	data.arena_gate = true
	data.lock_combat_area = locked
	return data


## 在場地放一個鎖場：範圍中心在 center_tile，左右各一道競技場閘門。
func _setup(center_tile: float, data: MechanismData) -> Dictionary:
	var zone := EncounterZone.new()
	zone.configure(data, Vector2i(int(center_tile), 20), 16)
	zone.position = Vector2(center_tile * 16.0, FLOOR_Y)
	zone.spawner = level._spawn_reinforcement
	level._entities.add_child(zone)
	var gates: Array[Gate] = []
	for offset in [-11.0, 11.0]:
		var gate := Gate.new()
		gate.configure(_arena_gate(data.channel, data.lock_combat_area), Vector2i(int(center_tile + offset), 20), 16)
		gate.position = Vector2((center_tile + offset) * 16.0, FLOOR_Y)
		level._entities.add_child(gate)
		gates.append(gate)
	await physics_frames(2)
	return {"zone": zone, "gates": gates}


func _all_closed(gates: Array) -> bool:
	return gates.all(func(g: Gate) -> bool: return not g.is_open)


func _all_open(gates: Array) -> bool:
	return gates.all(func(g: Gate) -> bool: return g.is_open)


func _test_data_rules() -> void:
	check(not MechanismData.new().lock_combat_area and not LevelData.new().lock_boss_arena, "new encounter and boss areas default to free movement")
	check(_encounter().validate().is_empty(), "a valid encounter has no problems")
	var no_channel := _encounter(&"")
	check(not no_channel.validate().is_empty(), "an encounter needs a channel")
	var tiny := _encounter()
	tiny.size_tiles = Vector2i(3, 2)
	check(not tiny.validate().is_empty(), "a tiny zone is reported")
	var quick := _encounter(&"x", [], 3.0)
	check(not quick.validate().is_empty(), "a lock shorter than ten seconds is reported")
	var holes := _encounter()
	holes.reinforcements = [null]
	check(not holes.validate().is_empty(), "an empty reinforcement slot is reported")
	for path in ["res://data/props/ch1_arena_street_blockade.tres", "res://data/props/ch1_arena_street_plaza.tres", "res://data/props/ch1_arena_warehouse_vault.tres", "res://data/props/ch1_arena_warehouse_walkway.tres"]:
		var gate_data := load(path) as MechanismData
		check(gate_data != null and gate_data.arena_gate and not gate_data.lock_combat_area, "authored ordinary combat gate is disabled: %s" % path)


func _test_free_encounter() -> void:
	var previous_gamepad := AimInput.using_gamepad
	var previous_direction := AimInput._last_stick_dir
	var previous_msec := AimInput._last_stick_msec
	await open_level(4.0)
	var first := spawn(GRUNT, 14.0)
	var second := spawn(GRUNT, 18.0)
	first.set_physics_process(false)
	second.set_physics_process(false)
	var set_up := await _setup(16.0, _encounter(&"free_encounter", [], 10.0, false))
	var zone: EncounterZone = set_up["zone"]
	var gates: Array = set_up["gates"]
	check(_all_open(gates) and not gates[0].visible and not gates[1].visible, "ordinary combat gates have no visible panel")
	check(gates[0].collision_layer == 0 and gates[1].collision_layer == 0, "ordinary combat gates have no world collision")
	AimInput.using_gamepad = true
	AimInput.restore_direction(Vector2.LEFT)
	Input.action_press(&"move_right")
	await physics_frames(60)
	Input.action_release(&"move_right")
	check(level.player.global_position.x > gates[0].global_position.x + 24.0 and zone.state == &"active", "real movement crosses the former entry gate and starts combat")
	Input.action_press(&"move_left")
	await physics_frames(60)
	Input.action_release(&"move_left")
	check(level.player.global_position.x < gates[0].global_position.x - 12.0 and zone.state == &"active", "the player can physically leave while both members remain alive")
	zone._lock_time = 100.0
	await physics_frames(20)
	check(zone.state == &"active" and zone.capture_state() == false, "a free encounter never awards completion from an old lock timeout")
	first.health.take_damage(lethal())
	second.health.take_damage(lethal())
	await physics_frames(60)
	check(zone.state == &"cleared" and zone.capture_state() == true and _all_open(gates), "actual member deaths complete and persist the free encounter")
	await end_level(level)
	AimInput.using_gamepad = previous_gamepad
	AimInput._last_stick_dir = previous_direction
	AimInput._last_stick_msec = previous_msec
	check(AimInput.using_gamepad == previous_gamepad and AimInput._last_stick_dir == previous_direction and AimInput._last_stick_msec == previous_msec, "free encounter restores aim source direction and timestamp")


func _test_special_entry_inset() -> void:
	await open_level(4.0)
	var enemy := spawn(GRUNT, 16.0)
	enemy.set_physics_process(false)
	var set_up := await _setup(16.0, _encounter())
	var zone: EncounterZone = set_up["zone"]
	place_player(6.0)
	await physics_frames(6)
	check(zone.state == &"idle" and _all_open(set_up["gates"]), "a special arena does not close at its outer boundary")
	place_player(8.5)
	await physics_frames(6)
	check(zone.state == &"active" and _all_closed(set_up["gates"]), "only entering the inset safe range closes an explicitly authored special arena")
	await end_level(level)


func _test_special_boss_boundary() -> void:
	var special := (load("res://data/levels/level_01.tres") as LevelData).duplicate() as LevelData
	special.lock_boss_arena = true
	special.intro_scene = &""
	var arena := await start_level(special)
	var initial_children := arena._world.get_child_count()
	arena._lock_boss_arena()
	await physics_frames(2)
	check(arena._world.get_child_count() == initial_children + 2 and arena.camera.limit_left == int(arena._layout.arena_x), "an explicit special boss arena still creates its boundary and camera lock")
	await end_level(arena)


func _test_lock_and_clear() -> void:
	await open_level(4.0)
	var enemies: Array[Enemy] = [spawn(GRUNT, 28.0), spawn(GRUNT, 32.0)]
	var set_up := await _setup(30.0, _encounter())
	var zone: EncounterZone = set_up["zone"]
	var gates: Array = set_up["gates"]
	check(_all_open(gates) and zone.state == &"idle", "before the player arrives: gates open, zone idle")
	place_player(30.0)
	await physics_frames(6)
	check(zone.state == &"active", "walking in starts the encounter")
	check(_all_closed(gates), "both arena gates close")
	check(zone.living_members() == 2, "the two enemies inside are the members")
	enemies[0].health.take_damage(lethal())
	await physics_frames(40)
	check(_all_closed(gates), "one member left: still locked")
	enemies[1].health.take_damage(lethal())
	await physics_frames(60)
	check(zone.state == &"cleared" and _all_open(gates), "the last member falls: the gates open")
	place_player(8.0)
	await physics_frames(2)
	place_player(30.0)
	await physics_frames(6)
	check(zone.state == &"cleared" and _all_open(gates), "a cleared encounter never locks again")
	check(zone.capture_state() == true, "the cleared state is saved with the world")
	await end_level(level)


func _test_reinforcements() -> void:
	await open_level(4.0)
	var wave: Array[EnemyData] = [load(GRUNT) as EnemyData, load(GRUNT) as EnemyData]
	var set_up := await _setup(30.0, _encounter(&"test_arena", wave))
	var zone: EncounterZone = set_up["zone"]
	var first := spawn(GRUNT, 28.0)
	var second := spawn(GRUNT, 32.0)
	place_player(26.0)
	zone.begin()
	await physics_frames(20)
	check(zone.state == &"active" and zone.living_members() == 2, "two members at the start, no reinforcement yet (%d)" % zone.living_members())
	first.health.take_damage(lethal())
	await physics_frames(40)
	check(zone.state == &"active" and zone.living_members() == 2, "down to one member: a reinforcement joins from the edge (%d)" % zone.living_members())
	second.health.take_damage(lethal())
	var guard := 0
	while zone.state == &"active" and guard < 60 * 20:
		for node in get_tree_enemies():
			(node as Enemy).health.take_damage(lethal())
		await physics_frames(10)
		guard += 10
	check(zone.state == &"cleared" and _all_open(set_up["gates"]), "after every reinforcement falls the encounter ends")
	await end_level(level)


func get_tree_enemies() -> Array[Node]:
	var result: Array[Node] = []
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		if not (node as Enemy).is_dying():
			result.append(node)
	return result


func _test_empty_zone_does_not_lock() -> void:
	await open_level(4.0)
	var set_up := await _setup(30.0, _encounter())
	var zone: EncounterZone = set_up["zone"]
	place_player(30.0)
	await physics_frames(6)
	check(zone.state == &"cleared" and _all_open(set_up["gates"]), "an empty zone (members already dead) never locks the player in")
	await end_level(level)


func _test_timeout_unlocks() -> void:
	await open_level(4.0)
	var enemy := spawn(GRUNT, 30.0)
	enemy.set_physics_process(false)
	var data := _encounter(&"test_arena", [], 10.0)
	var set_up := await _setup(30.0, data)
	var zone: EncounterZone = set_up["zone"]
	zone.begin()
	await physics_frames(5)
	check(zone.state == &"active" and _all_closed(set_up["gates"]), "locked (%s, members %d)" % [zone.state, zone.living_members()])
	zone._lock_time = data.max_lock_seconds - 0.1
	await physics_frames(40)
	check(zone.state == &"cleared" and _all_open(set_up["gates"]), "the lock times out and releases the player (a stuck enemy cannot trap them)")
	await end_level(level)


func _test_arena_gate_is_not_persisted() -> void:
	await open_level(4.0)
	var gate := Gate.new()
	gate.configure(_arena_gate(), Vector2i(10, 20), 16)
	gate.position = Vector2(160.0, FLOOR_Y)
	level._entities.add_child(gate)
	await physics_frames(2)
	check(gate.is_open and not gate.is_in_group(WorldState.GROUP), "an arena gate starts open and is not saved with the world")
	var normal := MechanismData.new()
	normal.id = &"test_normal_gate"
	normal.kind = MechanismData.Kind.GATE
	normal.channel = &"test_normal"
	var plain := Gate.new()
	plain.configure(normal, Vector2i(12, 20), 16)
	plain.position = Vector2(192.0, FLOOR_Y)
	level._entities.add_child(plain)
	await physics_frames(2)
	check(not plain.is_open and plain.is_in_group(WorldState.GROUP), "an ordinary gate is unchanged: starts closed and is saved")
	EventBus.mechanism_toggled.emit(&"test_arena", true)
	check(not gate.is_open, "the arena gate closes when its channel starts")
	EventBus.mechanism_toggled.emit(&"test_arena", false)
	check(gate.is_open, "and opens when it ends")
	await end_level(level)
