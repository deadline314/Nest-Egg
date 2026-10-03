class_name PropsSuite
extends TestSuite
## 可破壞物與環境機關（NE-30）：破壞與掉落、油桶爆炸、開關與閘門、升降梯、電力與熄燈、檢查點還原。

## 地圖與字元對照也給截圖工具使用（tools/screenshot.gd 的 props 情境）。
const MAP_PATH := "res://tests/fixtures/props_map.json"
const CRATE_PATH := "res://data/props/crate.tres"
const BARREL_PATH := "res://data/props/barrel.tres"
const GLASS_PATH := "res://data/props/glass_wall.tres"
const LIFT_PATH := "res://data/props/lift.tres"
const GATE_PATH := "res://data/props/gate_a.tres"
const SWITCH_PATH := "res://data/props/switch_a.tres"
const POWER_PATH := "res://data/props/power_switch.tres"
const GRUNT_PATH := "res://data/enemies/grunt.tres"


func run() -> void:
	_test_data()
	await _test_breakables()
	await _test_barrel_explosion()
	await _test_switch_and_gate()
	await _test_lift()
	await _test_power_and_lighting()
	await _test_checkpoint_restore()


## 測試用關卡：地圖在 tests/fixtures/props_map.json，字元對照見 _legend()。
static func level_data() -> LevelData:
	var data := LevelData.new()
	data.id = &"props_test"
	data.layout_path = MAP_PATH
	data.legend = _legend()
	return data


static func _legend() -> Dictionary[String, Resource]:
	return {
		"a": load(CRATE_PATH), "b": load(BARREL_PATH), "g": load(GRUNT_PATH), "w": load(GLASS_PATH),
		"s": load(SWITCH_PATH), "G": load(GATE_PATH), "L": load(LIFT_PATH), "p": load(POWER_PATH),
	}


func _find_all(level: Level, type: Script) -> Array[Node]:
	var result: Array[Node] = []
	_collect(level, type, result)
	return result


func _collect(node: Node, type: Script, result: Array[Node]) -> void:
	for child in node.get_children():
		if child.get_script() == type:
			result.append(child)
		_collect(child, type, result)


func _find_at(level: Level, type: Script, column: int) -> Node:
	for node in _find_all(level, type):
		if node.cell.x == column:
			return node
	return null


func _hit(target: Breakable, amount: int, source := Combat.Team.PLAYER) -> void:
	var info := DamageInfo.create(amount, source, &"test")
	info.ignore_invulnerability = true
	target.hit_by_projectile(info)


func _test_data() -> void:
	for path in [CRATE_PATH, BARREL_PATH, GLASS_PATH]:
		var item := load(path) as BreakableData
		check(item != null, "breakable loads: %s" % path)
		if item != null:
			check(item.validate().is_empty(), "breakable valid: %s %s" % [path, item.validate()])
			check(not item.hint.is_empty(), "breakable has a hint: %s" % path)
	for path in [LIFT_PATH, GATE_PATH, SWITCH_PATH, POWER_PATH]:
		var mechanism := load(path) as MechanismData
		check(mechanism != null, "mechanism loads: %s" % path)
		if mechanism != null:
			check(mechanism.validate().is_empty(), "mechanism valid: %s %s" % [path, mechanism.validate()])
			check(not mechanism.hint.is_empty(), "mechanism has a hint: %s" % path)
	check((load(GATE_PATH) as MechanismData).channel == (load(SWITCH_PATH) as MechanismData).channel, "switch and gate share a channel")
	check(DefeatCodex.has_card(&"explosive_barrel"), "codex has the explosive barrel card")
	# 資料驗證會抓到壞資料。
	var bad := BreakableData.new()
	bad.max_health = 0
	bad.drop_chance = 0.5
	check(bad.validate().size() >= 2, "invalid breakable data is reported")
	var bad_switch := MechanismData.new()
	bad_switch.kind = MechanismData.Kind.SWITCH
	check(not bad_switch.validate().is_empty(), "switch without channel is reported")


func _test_breakables() -> void:
	var level := await start_level(level_data())
	var crate := _find_at(level, Breakable, 10) as Breakable
	check(crate != null, "crate spawned from the map")
	if crate == null:
		await end_level(level)
		return
	var wall := _find_at(level, Breakable, 30) as Breakable
	check(wall != null and wall.size_px.y > crate.size_px.y, "glass wall is taller than a crate")
	check((crate.collision_layer & Layers.WORLD) != 0 and not crate._shape_node.disabled, "crate blocks movement")
	# 敵方傷害打不壞（箱子是掩體）；玩家傷害逐步破壞。
	_hit(crate, 1, Combat.Team.ENEMY)
	check(crate.health.current == crate.data.max_health, "enemy attacks do not damage crates")
	_hit(crate, 1)
	check(crate.health.current == crate.data.max_health - 1 and not crate.is_broken, "player hit damages the crate")
	var broke: Array[Breakable] = []
	crate.broken.connect(func(b: Breakable) -> void: broke.append(b))
	_hit(crate, 99)
	await frames(3)
	check(crate.is_broken and broke.size() == 1, "crate breaks and reports once")
	check(crate._shape_node.disabled and not crate.visible, "broken crate stops blocking and hides")
	_hit(crate, 99)
	await frames(2)
	check(broke.size() == 1, "a broken crate cannot break twice")
	# 玩家的子彈能打壞玻璃牆；敵人的子彈被擋下（掩體）。
	var spec := load("res://data/projectiles/pistol_shot.tres") as ProjectileSpec
	var before := wall.health.current
	ProjectilePool.spawn(spec, wall.world_center() + Vector2(-40, 0), Vector2.RIGHT, Combat.Team.PLAYER)
	await frames(12)
	check(wall.health.current < before, "a player bullet damages the glass wall")
	var enemy_spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	var wall_health := wall.health.current
	ProjectilePool.spawn(enemy_spec, wall.world_center() + Vector2(-40, 0), Vector2.RIGHT, Combat.Team.ENEMY)
	await frames(12)
	check(wall.health.current == wall_health, "enemy bullets are stopped without damaging the wall")
	# 掉落只由位置決定：同一個箱子每次掉一樣的東西。
	var roll_a := crate.roll_drop()
	var roll_b := crate.roll_drop()
	check(roll_a["resource"] == roll_b["resource"] and roll_a["health"] == roll_b["health"], "drops are deterministic per position")
	await end_level(level)


func _test_barrel_explosion() -> void:
	var level := await start_level(level_data())
	var player := level.player
	var barrel := _find_at(level, Breakable, 20) as Breakable
	var grunt: Enemy = null
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		grunt = node as Enemy
	check(barrel != null and grunt != null, "barrel and grunt spawned")
	if barrel == null or grunt == null:
		await end_level(level)
		return
	# 把玩家放在爆炸範圍外，先確認敵人受傷、玩家不受傷。
	player.global_position = Vector2(8 * 16, 19 * 16)
	var grunt_before := grunt.health.current
	var player_before := player.health.current
	_hit(barrel, 99)
	await frames(40)
	check(barrel.is_broken, "barrel breaks")
	check(grunt.health.current < grunt_before or grunt.health.is_dead, "barrel explosion hurts nearby enemies")
	check(player.health.current == player_before, "player outside the blast is unharmed")
	await end_level(level)

	# 玩家站在旁邊會被炸傷，死因是油桶。
	level = await start_level(level_data())
	player = level.player
	barrel = _find_at(level, Breakable, 20) as Breakable
	player.global_position = barrel.global_position + Vector2(-20, 0)
	var before := player.health.current
	_hit(barrel, 99)
	await frames(40)
	check(player.health.current < before or player.is_dead(), "barrel explosion hurts the player standing next to it")
	await end_level(level)


func _test_switch_and_gate() -> void:
	var level := await start_level(level_data())
	var channel_switch := _find_at(level, ChannelSwitch, 36) as ChannelSwitch
	var gate := _find_at(level, Gate, 40) as Gate
	check(channel_switch != null and gate != null, "switch and gate spawned")
	if channel_switch == null or gate == null:
		await end_level(level)
		return
	check(not gate.is_open and not gate._shape_node.disabled, "gate starts closed and solid")
	level.player.global_position = channel_switch.global_position + Vector2(0, -2)
	await frames(6)
	check(channel_switch._player_in_range, "player in range of the switch")
	await runner._press_action(&"interact")
	await frames(4)
	check(channel_switch.active and gate.is_open, "interact flips the switch and opens its gate")
	await frames(3)
	check(gate._shape_node.disabled, "open gate stops blocking")
	await runner._press_action(&"interact")
	await frames(4)
	check(channel_switch._cooldown >= 0.0, "switch has a toggle cooldown")
	await end_level(level)


func _test_lift() -> void:
	var level := await start_level(level_data())
	var lift := _find_at(level, Lift, 50) as Lift
	check(lift != null, "lift spawned")
	if lift == null:
		await end_level(level)
		return
	var start_y := lift.position.y
	check((lift.collision_layer & Layers.PLATFORM) != 0, "lift is a one-way platform")
	await physics_frames(int((lift.data.wait_time + 0.6) * 60.0))
	check(lift.position.y < start_y, "lift rises after waiting")
	check(lift.position.y >= start_y - lift.data.travel_tiles * 16.0 - 0.5, "lift stays within its travel")
	await end_level(level)


func _test_power_and_lighting() -> void:
	var level := await start_level(level_data())
	var power_switch := _find_at(level, PowerSwitch, 56) as PowerSwitch
	var fence := _find_all(level, LaserFence)[0] as LaserFence
	var lift := _find_at(level, Lift, 50) as Lift
	var grid: PowerGrid = level._power_grid
	check(power_switch != null and fence != null and grid != null, "power switch, fence and grid exist")
	if power_switch == null or fence == null or grid == null:
		await end_level(level)
		return
	check(grid.has_zone(power_switch.data.channel), "power switch registers its zone")
	check(PowerGrid.is_powered(fence), "fence is powered at the start")
	level.player.global_position = power_switch.global_position + Vector2(0, -2)
	await frames(6)
	await runner._press_action(&"interact")
	await frames(6)
	check(not grid.is_zone_powered(power_switch.data.channel), "interact cuts the power")
	check(not PowerGrid.is_powered(fence) and not fence.is_on(), "cut power switches the laser fence off")
	check(not PowerGrid.is_powered(lift) or lift.global_position.x < 48 * 16.0, "lift in the cut zone loses power")
	check(level._lighting.has_override(&"power_%s" % power_switch.data.channel), "cut power darkens the area (lighting override)")
	# 重新啟動後恢復。
	await physics_frames(30)
	await runner._press_action(&"interact")
	await frames(6)
	check(grid.is_zone_powered(power_switch.data.channel), "interact restores the power")
	check(PowerGrid.is_powered(fence), "restored power turns the fence back on")
	await physics_frames(int((PowerGrid.BLACKOUT_FADE_OUT + 0.4) * 60.0))
	check(not level._lighting.has_override(&"power_%s" % power_switch.data.channel), "restored power clears the blackout")
	await end_level(level)


func _test_checkpoint_restore() -> void:
	var data := level_data()
	var level := await start_level(data)
	var crate := _find_at(level, Breakable, 10) as Breakable
	var channel_switch := _find_at(level, ChannelSwitch, 36) as ChannelSwitch
	var gate := _find_at(level, Gate, 40) as Gate
	var checkpoint: Checkpoint = null
	for node in _find_all(level, Checkpoint):
		checkpoint = node as Checkpoint
	check(checkpoint != null, "checkpoint exists in the props map")
	_hit(crate, 99)
	channel_switch.toggle()
	await frames(4)
	level.player.global_position = checkpoint.global_position
	await physics_frames(20)
	Input.action_press(&"interact")  # 電話亭要按互動鍵撥號
	await physics_frames(2)
	Input.action_release(&"interact")
	await physics_frames(110)
	check(GameState.has_checkpoint and GameState.checkpoint_world.size() >= 3, "checkpoint stores the world state (%d entries)" % GameState.checkpoint_world.size())
	check(GameState.checkpoint_world.get(crate.state_key()) == true, "snapshot records the broken crate")
	await end_level(level)

	# 重生（關卡重建）：箱子仍是破的、開關仍啟動、閘門仍打開。
	level = await spawn_level(data)
	crate = _find_at(level, Breakable, 10) as Breakable
	channel_switch = _find_at(level, ChannelSwitch, 36) as ChannelSwitch
	gate = _find_at(level, Gate, 40) as Gate
	check(crate.is_broken and not crate.visible, "broken crate stays broken after respawning")
	check(channel_switch.active and gate.is_open, "switch and gate state restored after respawning")
	var barrel := _find_at(level, Breakable, 20) as Breakable
	check(not barrel.is_broken, "untouched barrel is intact after respawning")
	# 沒有檢查點時（重新開始）全部回到初始狀態。
	await end_level(level)
	level = await start_level(data)
	crate = _find_at(level, Breakable, 10) as Breakable
	check(not crate.is_broken, "a fresh run starts with everything intact")
	await end_level(level)
	# 損毀的快照不會讓關卡崩潰：未知的 key 被忽略。
	GameState.set_checkpoint(Vector2(80, 300), {}, {"breakable@999,999": true, "gate@1,1": "garbage"})
	level = await spawn_level(data)
	check(is_instance_valid(level.player), "level builds even with a stale or garbage world snapshot")
	await end_level(level)
	GameState.clear_checkpoint()
