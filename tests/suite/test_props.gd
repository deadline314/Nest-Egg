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
const SUSPENDED_PATH := "res://data/props/suspended_crate.tres"
const SUSPENDED_MAP := "res://tests/fixtures/suspended_map.json"
const VALVE_PATH := "res://data/props/steam_valve.tres"
const VALVE_MAP := "res://tests/fixtures/steam_valve_map.json"
const LAMP_MAP := "res://tests/fixtures/shootable_lamp_map.json"
const CABLE_PATH := "res://data/props/live_cable.tres"
const CABLE_MAP := "res://tests/fixtures/live_cable_map.json"
const CONVEYOR_PATH := "res://data/props/conveyor.tres"
const CONVEYOR_MAP := "res://tests/fixtures/conveyor_map.json"
const RADIO_PATH := "res://data/props/decoy_radio.tres"
const RADIO_MAP := "res://tests/fixtures/decoy_radio_map.json"
const WALKWAY_PATH := "res://data/props/crumbling_walkway.tres"
const WALKWAY_MAP := "res://tests/fixtures/crumbling_walkway_map.json"
const HIDING_PATH := "res://data/props/hiding_spot.tres"
const HIDING_MAP := "res://tests/fixtures/hiding_spot_map.json"


func run() -> void:
	_test_data()
	_test_mechanism_translations()
	await _test_fixture_states()
	await _test_breakables()
	await _test_barrel_explosion()
	await _test_switch_and_gate()
	await _test_lift()
	await _test_power_and_lighting()
	await _test_checkpoint_restore()
	await _test_suspended_load()
	await _test_steam_valve()
	await _test_shootable_lamp()
	await _test_live_cable()
	await _test_conveyor()
	await _test_decoy_radio()
	await _test_crumbling_walkway()
	await _test_hiding_spot()
	_test_mechanic_placements()
	await _test_hazard_avoidance()
	await _test_steam_blocks_sight()
	await _test_area_challenge()
	await _test_unseen_challenge()
	await _test_crate_cover()
	await _test_timed_challenge()


func _test_mechanism_translations() -> void:
	var legacy := MechanismData.new()
	legacy.hint = "舊提示"
	check(legacy.hint_for("ja") == "舊提示" and legacy.start_text_for("en").is_empty(),
		"legacy hints fall back to source and silent events stay silent")
	legacy.localized_hints["en"] = "Fallback"
	check(legacy.hint_for("ja") == "Fallback" and legacy.hint_for("zh") == "舊提示",
		"an absent Japanese translation falls back to English while Chinese uses its source")
	var warehouse := load("res://data/props/ch1_enc_warehouse_walkway.tres") as MechanismData
	check(warehouse.start_text_for("en").begins_with("Guards") and warehouse.clear_text_for("ja") == "通路はひとまず安全だ。",
		"warehouse encounter has localized warnings and clear messages")


## Formal views follow real health/power/motion; presentation cannot change collision or restoration.
func _test_fixture_states() -> void:
	for look: int in FixtureArt.BREAKABLE_BODIES:
		var id := FixtureArt.breakable_body(look)
		check(FixtureArt.missing_parts(FixtureArt.body_parts(id)).is_empty(), "all destructible states are packaged: %s" % id)
	for kind: int in FixtureArt.MECHANISM_PARTS:
		check(FixtureArt.missing_parts(FixtureArt.MECHANISM_PARTS[kind]).is_empty(), "all mechanism parts are packaged: %s" % kind)
	check(FixtureArt.missing_parts([&"test_missing_prop_fixture"]) == PackedStringArray([FixtureArt.FOLDER + "test_missing_prop_fixture.png"]),
		"the audit retains an exact missing path instead of declaring every fixture complete")
	var level := await start_level(level_data())
	var crate := _find_at(level, Breakable, 10) as Breakable
	check(crate._body_art != null and (crate._body_art.texture.get_size() * crate._body_art.scale).is_equal_approx(crate.size_px),
		"crate art matches its original collision size")
	var shape := crate._shape_node.shape as RectangleShape2D
	var original_size := shape.size
	_hit(crate, 1)
	check(crate._body_art.texture == FixtureArt.texture(&"breakable_crate_damaged") and shape.size == original_size,
		"real damage switches art without changing collision")
	_hit(crate, 99)
	await frames(3)
	var rubble := crate.get_parent().get_node_or_null("FixtureRubble") as Sprite2D
	check(rubble != null and rubble.texture == FixtureArt.texture(&"breakable_crate_broken") and crate.is_broken,
		"real destruction displays bounded rubble while the original object stays broken")
	var restored := Breakable.new()
	restored.configure(crate.data, Vector2i(100, 20), 16)
	crate.get_parent().add_child(restored)
	var children_before := restored.get_parent().get_child_count()
	restored.restore_state(true)
	await frames(2)
	check(restored.is_broken and not restored.visible and restored.get_parent().get_child_count() == children_before,
		"checkpoint restoration does not emit debris or replay rewards")
	var glass_image := FixtureArt.texture(&"breakable_glass").get_image()
	if glass_image.is_compressed():
		glass_image.decompress()
	var alpha := glass_image.get_pixel(glass_image.get_width() / 2, glass_image.get_height() / 2).a
	check(alpha > 0.0 and alpha < 0.5, "the glass pane remains genuinely translucent")
	var lift := _find_all(level, Lift)[0] as Lift
	check(lift._art != null and (lift._art.texture.get_size() * lift._art.scale).is_equal_approx(Vector2(lift._width, Lift.PLATFORM_THICKNESS)),
		"the lift deck aligns with the standable surface")
	var rail_origin := lift._rails.global_position
	lift._enabled = true
	lift._wait_left = 0.0
	await frames(12)
	check(lift.position.y < lift._start_y and lift._rails.global_position == rail_origin
		and lift._rails._left != null and lift._rails._right != null,
		"the textured platform moves along stationary textured rails")
	var power := _find_all(level, PowerSwitch)[0] as PowerSwitch
	check(power._art_off.visible and not power._art_on.visible and power._art_off.texture == FixtureArt.texture(&"power_switch_off"),
		"power has its own mounted artwork and a visible initial state")
	power.toggle()
	check(power.active and power._art_on.visible and not power._art_off.visible and power._status_color() == Palette.DANGER,
		"real power cutoff changes lever and lamp immediately")
	power.restore_state(false)
	check(not power.active and power._art_off.visible and not power._art_on.visible, "restoring power also restores the visible lever")
	var body := Throwable.new()
	body.configure(load("res://data/throwables/fuel_barrel.tres"))
	level._entities.add_child(body)
	check(body._body_art != null and body._body_art.texture == FixtureArt.texture(&"breakable_barrel"),
		"throwable fuel uses the same drum identity without changing its rules")
	var hit := DamageInfo.create(body.data.max_health, Combat.Team.PLAYER, &"test")
	hit.ignore_invulnerability = true
	body.hurtbox.receive(hit)
	check(body.is_fuse_lit() and body._body_art.texture == FixtureArt.texture(&"breakable_barrel_damaged"),
		"a real hit starts the original fuse and damaged appearance")
	var flashes_before := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(true)
	var fuse_before := body._fuse_left
	check(is_equal_approx(body.fuse_light_energy(), 2.0) and is_equal_approx(body._fuse_left, fuse_before),
		"reduced flashes gives a steady warning without advancing or disabling the fuse")
	Settings.set_reduce_flashes(flashes_before)
	# Missing cached art takes the same safe branch used after a loader refusal.
	var original := FixtureArt.texture(&"breakable_crate")
	FixtureArt._cache[&"breakable_crate"] = null
	var fallback := Breakable.new()
	fallback.configure(crate.data, Vector2i(101, 20), 16)
	level._entities.add_child(fallback)
	check(fallback._body_art == null and fallback.health != null and not fallback.is_broken,
		"a texture refusal keeps the original functional simple body")
	FixtureArt._cache[&"breakable_crate"] = original
	await runner.get_tree().create_timer(0.8).timeout
	check(not is_instance_valid(rubble), "rubble is released after its short presentation lifetime")
	await end_level(level)


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
	var previous_language := Story.language
	Story.language = "en"
	var level := await start_level(level_data())
	var power_switch := _find_at(level, PowerSwitch, 56) as PowerSwitch
	var fence := _find_all(level, LaserFence)[0] as LaserFence
	var lift := _find_at(level, Lift, 50) as Lift
	var grid: PowerGrid = level._power_grid
	check(power_switch != null and fence != null and grid != null, "power switch, fence and grid exist")
	if power_switch == null or fence == null or grid == null:
		await end_level(level)
		Story.language = previous_language
		return
	var notices: Array[String] = []
	var record := func(text: String) -> void: notices.append(text)
	EventBus.toast_requested.connect(record)
	var using_gamepad := InputBindings.using_gamepad
	var device_before := InputBindings.active_device
	InputBindings._set_device(false, -1)
	check(power_switch._prompt._display_text.begins_with(InputBindings.primary_label(&"interact") + " Cut power"),
		"powered switch uses the localized action and the keyboard binding")
	InputBindings._set_device(true, 0)
	check(power_switch._prompt._display_text.begins_with(InputBindings.primary_label(&"interact") + " Cut power"),
		"the visible power prompt refreshes when the active device changes")
	InputBindings._set_device(using_gamepad, device_before)
	check(grid.has_zone(power_switch.data.channel), "power switch registers its zone")
	check(PowerGrid.is_powered(fence), "fence is powered at the start")
	level.player.global_position = power_switch.global_position + Vector2(0, -2)
	await frames(6)
	await runner._press_action(&"interact")
	await frames(6)
	check(not grid.is_zone_powered(power_switch.data.channel), "interact cuts the power")
	check(power_switch._prompt.text.begins_with("{interact} Restore power") and notices.has("Power cut. Lights and security are offline."),
		"after the interaction the hover offers restoration and the toast reports the outage")
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
	check(power_switch._prompt.text.begins_with("{interact} Cut power") and notices.has("Power restored."),
		"restoring power changes the hover back and reports the restoration")
	var before_restore := notices.size()
	power_switch.restore_state(true)
	check(power_switch._prompt.text.begins_with("{interact} Restore power") and notices.size() == before_restore,
		"checkpoint restoration refreshes the resulting hover silently")
	EventBus.toast_requested.disconnect(record)
	await end_level(level)
	Story.language = previous_language


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


## 吊掛貨箱（NE-397）：吊著時不擋路、打到就砸下來傷害底下的敵人、不傷玩家也不卡住玩家、落地後是掩體、狀態跟著檢查點、資料有檢查。
func _test_suspended_load() -> void:
	var load_data := load(SUSPENDED_PATH) as SuspendedLoadData
	check(load_data != null and load_data.validate().is_empty(), "the suspended crate data is valid: %s" % [load_data.validate() if load_data != null else ["missing"]])
	if load_data == null:
		return
	check(load_data.hint_for("en").begins_with("Shoot") and not load_data.hint_for("ja").is_empty() and load_data.hint_for("zh") == load_data.hint,
			"the hint is available in all three languages")
	var bad := SuspendedLoadData.new()
	bad.hang_tiles = 2
	bad.hint = "只有中文"
	check(bad.validate().size() >= 3, "a load that hangs too low or lacks translations is reported")

	var data := LevelData.new()
	data.id = &"suspended_test"
	data.layout_path = SUSPENDED_MAP
	data.legend = {"Q": load_data, "g": load(GRUNT_PATH)}
	var level := await start_level(data)
	var loads := _find_all(level, SuspendedLoad)
	check(loads.size() == 1, "the map character spawns one suspended crate")
	if loads.is_empty():
		await end_level(level)
		return
	var crate := loads[0] as SuspendedLoad
	var tile := 16.0
	check(crate.is_hanging() and is_equal_approx(crate.drop_height(), load_data.hang_tiles * tile), "it starts hanging %d tiles above the floor" % load_data.hang_tiles)
	check(crate._shape_node.disabled and crate.hurtbox.enabled, "while hanging it blocks nothing but can be shot")
	check(is_equal_approx(crate._anchor_height, 11.0 * tile), "the chain reaches the ceiling above it (%.0f px)" % crate._anchor_height)
	check(crate.capture_state() == false and crate.state_key() == "suspended@14,19", "a hanging crate saves as not fallen")
	var enemy: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		enemy = node as Enemy
	check(enemy != null, "an enemy stands beside the landing spot")
	if enemy == null:
		await end_level(level)
		return
	enemy.set_physics_process(false)
	enemy.set_process(false)
	var enemy_health := enemy.health.current
	var player := level.player
	player.set_physics_process(false)
	player.global_position = crate.global_position + Vector2(-3.0, 0.0)  # 玩家站在正下方（略偏左，會被推向沒有敵人的那一側）
	var player_health := player.health.current
	# 敵方的子彈打不動它。
	crate.hurtbox.receive(DamageInfo.create(3, Combat.Team.ENEMY, &"test_enemy_shot"))
	check(crate.is_hanging(), "enemy fire does not release the crate")
	crate.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	check(crate.state == SuspendedLoad.State.FALLING and not crate.hurtbox.enabled, "a player hit releases the chain")
	for i in 180:
		if crate.state == SuspendedLoad.State.LANDED:
			break
		await physics_frames(1)
	await physics_frames(3)
	check(crate.state == SuspendedLoad.State.LANDED and is_zero_approx(crate.drop_height()), "the crate falls to the floor")
	check(not crate._shape_node.disabled, "once landed it is solid cover")
	check(not is_instance_valid(enemy) or enemy.health.current <= enemy_health - mini(load_data.drop_damage, enemy_health),
			"the enemy below takes the drop damage")
	check(player.health.current == player_health, "the player is never hurt by a crate they dropped (%d -> %d)" % [player_health, player.health.current])
	check(absf(player.global_position.x - crate.global_position.x) >= crate.size_px.x * 0.5 + SuspendedLoad.SHOVE_MARGIN - 0.5,
			"a player standing underneath is pushed clear instead of being trapped inside")
	check(crate.capture_state() == true, "a fallen crate saves as fallen")
	crate.release()
	check(crate.state == SuspendedLoad.State.LANDED, "a landed crate cannot be released again")
	await end_level(level)

	var restored_level := await start_level(data)
	var again := _find_all(restored_level, SuspendedLoad)
	if not again.is_empty():
		var restored := again[0] as SuspendedLoad
		var survivor_health := -1
		for node in runner.get_tree().get_nodes_in_group(&"enemies"):
			(node as Enemy).set_physics_process(false)
			survivor_health = (node as Enemy).health.current
		restored.restore_state(true)
		await physics_frames(3)
		check(restored.state == SuspendedLoad.State.LANDED and not restored._shape_node.disabled, "restoring a checkpoint puts the fallen crate back on the floor")
		for node in runner.get_tree().get_nodes_in_group(&"enemies"):
			check((node as Enemy).health.current == survivor_health, "restoring does not replay the drop damage")
	await end_level(restored_level)


## 蒸汽閥（NE-398）：射中閥門噴出蒸汽牆，牆在時雙方子彈都打不穿、角色走得過去；時間到散掉、冷卻後才能再用；敵人打不開；資料有檢查。
func _test_steam_valve() -> void:
	var valve_data := load(VALVE_PATH) as SteamValveData
	check(valve_data != null and valve_data.validate().is_empty(), "the steam valve data is valid: %s" % [valve_data.validate() if valve_data != null else ["missing"]])
	if valve_data == null:
		return
	check(not valve_data.hint_for("en").is_empty() and not valve_data.hint_for("ja").is_empty(), "the valve hint is available in all three languages")
	var bad := SteamValveData.new()
	bad.texture = "res://art/environment/test_missing_prop_valve.png"
	bad.screen_seconds = NAN
	bad.hint = "只有中文"
	check(bad.validate().size() >= 3, "a valve with missing art, broken timing or missing translations is reported")

	var data := LevelData.new()
	data.id = &"steam_valve_test"
	data.layout_path = VALVE_MAP
	data.legend = {"V": valve_data}
	var level := await start_level(data)
	var valves := _find_all(level, SteamValve)
	check(valves.size() == 1, "the map character spawns one steam valve")
	if valves.is_empty():
		await end_level(level)
		return
	var valve := valves[0] as SteamValve
	check(valve.is_ready_to_vent() and not valve._screen.is_blocking(), "the valve starts ready with no steam")
	valve.hurtbox.receive(DamageInfo.create(2, Combat.Team.ENEMY, &"test_enemy_shot"))
	check(valve.is_ready_to_vent(), "enemy fire cannot open the valve")
	valve.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	await physics_frames(2)
	check(valve.is_venting() and valve._screen.is_blocking(), "a player hit opens the valve and raises the steam screen")
	check(valve.health.current == valve.health.max_health, "the valve itself is never worn down")
	var rect := valve.screen_rect()
	check(rect.position.x > valve.global_position.x and rect.size.y >= 48.0, "the screen stands beside the valve, tall enough to cover a standing body")

	# 子彈從兩邊打進蒸汽都會被吃掉；穿牆的子彈不受影響。
	var spec := load("res://data/projectiles/collector_shot.tres") as ProjectileSpec if ResourceLoader.exists("res://data/projectiles/collector_shot.tres") else null
	if spec == null:
		for file in DirAccess.get_files_at("res://data/projectiles"):
			var candidate := load("res://data/projectiles".path_join(file)) as ProjectileSpec
			if candidate != null and not candidate.passes_walls and candidate.gravity == 0.0:
				spec = candidate
				break
	check(spec != null, "a straight bullet spec exists for the screen check")
	if spec != null:
		var middle := rect.get_center()
		for team: Combat.Team in [Combat.Team.PLAYER, Combat.Team.ENEMY]:
			var bullet := ProjectilePool.spawn(spec, middle + Vector2(-60.0, 0.0), Vector2.RIGHT, team) as Projectile
			var crossed := false
			for i in 30:
				await physics_frames(1)
				if not bullet.active:
					break
				crossed = crossed or bullet.global_position.x > rect.end.x + 2.0
			check(not crossed and not bullet.active, "a %s bullet stops inside the steam" % ("player" if team == Combat.Team.PLAYER else "enemy"))
	# 角色穿得過去：蒸汽不在角色會撞到的層。
	check((valve._screen.collision_layer & (Layers.SOLID | Layers.PLAYER | Layers.ENEMY)) == 0 and level.player.collision_mask & Layers.SCREEN == 0,
			"bodies walk straight through the steam")

	valve.vent()
	check(valve.is_venting(), "hitting the valve again while venting changes nothing")
	await runner.get_tree().create_timer(valve_data.screen_seconds + 0.2).timeout
	await physics_frames(2)
	check(valve.state == SteamValve.State.COOLING and not valve._screen.is_blocking() and is_zero_approx(valve.screen_opacity()),
			"the steam clears after its time and the valve cools down")
	check(not valve.vent(), "a cooling valve cannot be opened")
	await runner.get_tree().create_timer(valve_data.cooldown_seconds + 0.2).timeout
	check(valve.is_ready_to_vent() and not valve.is_processing(), "after cooling the valve is ready again and idle")
	await end_level(level)


## 可以射暗的燈（NE-399）：只有標記的區域可以射；射暗後燈下變暗，沒察覺的敵人看不遠、察覺後照常；敵人打不到燈；狀態跟著檢查點。
func _test_shootable_lamp() -> void:
	var plain := LevelData.new()
	plain.id = &"lamp_plain_test"
	plain.layout_path = LAMP_MAP
	plain.legend = {"g": load(GRUNT_PATH)}
	var plain_level := await start_level(plain)
	var plain_lamps := _find_all(plain_level, Lamp)
	check(plain_lamps.size() == 1 and not (plain_lamps[0] as Lamp).shootable and (plain_lamps[0] as Lamp)._hurtbox == null
			and not (plain_lamps[0] as Lamp).is_in_group(WorldState.GROUP), "areas that do not opt in keep ordinary lamps")
	await end_level(plain_level)

	var data := LevelData.new()
	data.id = &"lamp_shoot_test"
	data.layout_path = LAMP_MAP
	data.legend = {"g": load(GRUNT_PATH)}
	data.shootable_lamps = true
	var level := await start_level(data)
	var lamps := _find_all(level, Lamp)
	check(lamps.size() == 1, "the test map has one lamp")
	if lamps.is_empty():
		await end_level(level)
		return
	var lamp := lamps[0] as Lamp
	check(lamp.shootable and lamp._hurtbox != null and lamp._prompt != null, "lamps in an opted-in area can be shot and explain how")
	var under := Vector2(lamp.global_position.x, lamp.floor_y - 2.0)
	check(not Lamp.in_shot_out_dark(under), "nothing is dark before a lamp is shot out")
	var enemy: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		enemy = node as Enemy
	check(enemy != null, "an enemy watches the lamp-lit floor")
	if enemy == null:
		await end_level(level)
		return
	enemy.set_physics_process(false)
	var player := level.player
	player.set_physics_process(false)
	var reach := absf(enemy.global_position.x - under.x) + 4.0
	player.global_position = under
	check(enemy._can_see_target(reach), "an unaware enemy sees the player standing in the light")
	lamp._hurtbox.receive(DamageInfo.create(1, Combat.Team.ENEMY, &"test_enemy_shot"))
	check(not lamp.shot_out, "enemy fire cannot shoot out a lamp")
	lamp._hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	await physics_frames(2)
	check(lamp.shot_out and not lamp._light.enabled and not lamp.is_processing(), "a player hit shoots the lamp out")
	check(is_zero_approx(lamp.light_at(under)), "a shot-out lamp lights nothing")
	check(Lamp.in_shot_out_dark(under), "the floor under it is now dark")
	check(not Lamp.in_shot_out_dark(under + Vector2(lamp.light_radius, 0.0)), "the dark area ends near the lamp's old light")
	check(not enemy._can_see_target(reach), "an unaware enemy cannot see the player hiding in the new dark at the same distance")
	check(enemy._can_see_target(reach * Lamp.DARK_SIGHT_SCALE * 0.8) or enemy.global_position.distance_to(under) > reach * Lamp.DARK_SIGHT_SCALE,
			"close up the enemy still sees the player")
	enemy.raise_alert(under, 3.0)
	check(enemy._can_see_target(reach), "an alerted enemy sees into the dark as usual")
	check(lamp.capture_state() == true, "a shot-out lamp saves as shot out")
	lamp.shoot_out(true)
	check(lamp.shot_out, "shooting an already dark lamp changes nothing")
	await end_level(level)
	check(not Lamp.in_shot_out_dark(under), "leaving the area clears the dark list")

	var restored_level := await start_level(data)
	var again := _find_all(restored_level, Lamp)
	if not again.is_empty():
		var restored := again[0] as Lamp
		restored.restore_state(true)
		check(restored.shot_out and not restored._light.enabled, "restoring a checkpoint keeps the lamp dark")
	await end_level(restored_level)


## 斷電纜（NE-400）：射斷後預警、通電；水裡的敵人與玩家都會觸電、格擋擋不住、跳起來不會；時間到就停、只能用一次；敵人打不斷；有敗北卡片。
func _test_live_cable() -> void:
	var cable_data := load(CABLE_PATH) as LiveCableData
	check(cable_data != null and cable_data.validate().is_empty(), "the live cable data is valid: %s" % [cable_data.validate() if cable_data != null else ["missing"]])
	if cable_data == null:
		return
	check(not cable_data.hint_for("en").is_empty() and not cable_data.hint_for("ja").is_empty(), "the cable hint is available in all three languages")
	var cards: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/codex/defeat_cards.json"))
	var has_card := false
	for card: Dictionary in cards.get("cards", []):
		has_card = has_card or card.get("id") == String(cable_data.source_id)
	check(has_card, "dying to the shock has its own defeat card")
	var bad := LiveCableData.new()
	bad.live_seconds = NAN
	bad.source_id = &""
	check(bad.validate().size() >= 2, "broken timing or a missing death cause is reported")

	var data := LevelData.new()
	data.id = &"live_cable_test"
	data.layout_path = CABLE_MAP
	data.legend = {"K": cable_data, "g": load(GRUNT_PATH)}
	var level := await start_level(data)
	var cables := _find_all(level, LiveCable)
	check(cables.size() == 1, "the map character spawns one live cable")
	if cables.is_empty():
		await end_level(level)
		return
	var cable := cables[0] as LiveCable
	check(cable.state == LiveCable.State.HANGING and not cable.is_live(), "the cable starts hanging and the water is safe")
	var enemy: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		enemy = node as Enemy
	check(enemy != null and cable.shock_rect().has_point(enemy.global_position + Vector2(0.0, -1.0)), "an enemy stands in the puddle")
	if enemy == null:
		await end_level(level)
		return
	enemy.set_physics_process(false)
	var player := level.player
	player.set_physics_process(false)
	player.global_position = cable.global_position + Vector2(-20.0, 0.0)  # 玩家也站在水裡
	player.health.setup(20, 0.0)
	var enemy_before := enemy.health.current
	cable.hurtbox.receive(DamageInfo.create(1, Combat.Team.ENEMY, &"test_enemy_shot"))
	check(cable.state == LiveCable.State.HANGING, "enemy fire cannot cut the cable")
	cable.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	check(cable.state == LiveCable.State.WARNING and not cable._hit_players.active, "a player hit cuts the cable and the water warns before going live")
	await runner.get_tree().create_timer(cable_data.warning_seconds + 0.25).timeout
	await physics_frames(3)
	check(cable.is_live(), "after the warning the water is live")
	check(not is_instance_valid(enemy) or enemy.health.current < enemy_before, "the enemy standing in the water is shocked")
	check(player.health.current < 20, "the player standing in the water is shocked too")
	# 跳起來（腳離開水面）就不會觸電。
	player.global_position = cable.global_position + Vector2(-20.0, -LiveCable.SHOCK_HEIGHT - 10.0)
	# 等觸電範圍真的不再和玩家重疊才開始量（負載高時，前幾格還在水裡的重疊會晚幾格才消失）。
	for i in 12:
		await physics_frames(1)
		if not cable._hit_players.overlaps_area(player.hurtbox):
			break
	await physics_frames(1)
	player.health.setup(20, 0.0)
	await physics_frames(4)
	check(player.health.current == 20, "a player in the air above the water is not shocked")
	check(cable._hit_players.bypass_guard and cable._hit_enemies.bypass_guard, "guarding cannot block the current")
	await runner.get_tree().create_timer(cable_data.live_seconds + 0.2).timeout
	await physics_frames(2)
	check(cable.state == LiveCable.State.SPENT and not cable._hit_players.active and not cable._hit_enemies.active, "the current stops after its time")
	player.health.setup(20, 0.0)
	player.global_position = cable.global_position
	await physics_frames(4)
	check(player.health.current == 20, "the spent puddle is just water")
	check(not cable.cut(), "a spent cable cannot be cut again")
	await end_level(level)


## 輸送帶（NE-401）：站在上面的人被帶走、撞牆不穿；射馬達反轉、有冷卻、敵人打不轉；方向跟著檢查點。
func _test_conveyor() -> void:
	var belt_data := load(CONVEYOR_PATH) as ConveyorData
	check(belt_data != null and belt_data.validate().is_empty(), "the conveyor data is valid: %s" % [belt_data.validate() if belt_data != null else ["missing"]])
	if belt_data == null:
		return
	check(not belt_data.hint_for("en").is_empty() and not belt_data.hint_for("ja").is_empty(), "the conveyor hint is available in all three languages")
	var bad := ConveyorData.new()
	bad.speed = 0.0
	bad.hint = "x"
	check(bad.validate().size() >= 2, "a stopped belt or a missing translation is reported")

	var data := LevelData.new()
	data.id = &"conveyor_test"
	data.layout_path = CONVEYOR_MAP
	data.legend = {"K": belt_data}
	var level := await start_level(data)
	var belts := _find_all(level, Conveyor)
	check(belts.size() == 1, "the map character spawns one conveyor")
	if belts.is_empty():
		await end_level(level)
		return
	var belt := belts[0] as Conveyor
	var rect := belt.belt_rect()
	check(is_equal_approx(rect.position.x, 5.0 * 16.0) and is_equal_approx(rect.size.x, belt_data.length_tiles * 16.0), "the belt starts at the left edge of its cell and spans its length: %s" % rect)
	var player := level.player
	var start_x := rect.position.x + rect.size.x * 0.5
	player.global_position = Vector2(start_x, rect.end.y)
	await physics_frames(30)
	check(player.global_position.x < start_x - 8.0, "a player standing on the belt is carried along its direction: %.1f -> %.1f" % [start_x, player.global_position.x])
	belt.hurtbox.receive(DamageInfo.create(1, Combat.Team.ENEMY, &"test_enemy_shot"))
	check(not belt.is_reversed(), "enemy fire cannot reverse the belt")
	belt.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	check(belt.is_reversed() and belt.speed > 0.0, "hitting the motor reverses the belt")
	check(not belt.reverse(), "the motor has a cooldown so a burst does not flip it back")
	var mid_x := player.global_position.x
	await physics_frames(30)
	check(player.global_position.x > mid_x + 8.0, "after reversing the player is carried the other way")
	# 帶子只在腳底踩在帶面上時才推：被推到端點就停下來，不會一路推出去。
	belt.restore_state(false)
	check(not belt.is_reversed() and belt.speed < 0.0, "the direction is restored from a checkpoint")
	check(belt.capture_state() == false and belt.state_key().begins_with("conveyor@"), "the direction is saved under a stable key")
	player.global_position = Vector2(rect.position.x + 2.0, rect.end.y)
	await physics_frames(90)
	check(player.global_position.x > rect.position.x - 4.0 and player.global_position.x <= rect.position.x + 1.0, "the belt stops carrying at its end: %.1f" % player.global_position.x)
	# 跳起來（不在地面上）就不會被帶走。
	player.global_position = Vector2(start_x, rect.end.y - 40.0)
	player.velocity = Vector2.ZERO
	var air_x := player.global_position.x
	await physics_frames(3)
	check(absf(player.global_position.x - air_x) < 1.0, "a player in the air is not carried")
	await end_level(level)


## 會塌的走道：站上去的那一片抖一下就掉、一路跑過去就不會掉；敵人站上去也一樣；空出來之後補回（有人在上方時先不補）；
## 重來（檢查點重建）時一律完整；「減少介面動態」時不抖但照樣會塌。
func _test_crumbling_walkway() -> void:
	var walkway_data := load(WALKWAY_PATH) as CrumblingWalkwayData
	check(walkway_data != null and walkway_data.validate().is_empty(), "the crumbling walkway data is valid: %s" % [walkway_data.validate() if walkway_data != null else ["missing"]])
	if walkway_data == null:
		return
	check(not walkway_data.hint_for("en").is_empty() and not walkway_data.hint_for("ja").is_empty(), "the walkway hint is available in all three languages")
	var bad := CrumblingWalkwayData.new()
	bad.length_tiles = 1
	bad.warn_seconds = NAN
	bad.hint = "x"
	check(bad.validate().size() >= 3, "a too-short walkway, broken timing or a missing translation is reported: %s" % [bad.validate()])
	check(walkway_data.segment_count() == ceili(float(walkway_data.length_tiles) / float(walkway_data.segment_tiles)), "the walkway is split into pieces of the given length")

	var data := LevelData.new()
	data.id = &"crumbling_walkway_test"
	data.layout_path = WALKWAY_MAP
	data.legend = {"K": walkway_data}
	var level := await start_level(data)
	var walkways := _find_all(level, CrumblingWalkway)
	check(walkways.size() == 1, "the map character spawns one crumbling walkway")
	if walkways.is_empty():
		await end_level(level)
		return
	var walkway := walkways[0] as CrumblingWalkway
	var player := level.player
	player.health.setup(999, 0.0)
	var first := walkway.segment_rect(0)
	check(is_equal_approx(first.position.x, 10.0 * 16.0) and is_equal_approx(walkway.deck_top(), 15.0 * 16.0), "the deck starts at the left edge of its cell, level with the top of that cell: %s" % first)
	var top := walkway.deck_top()

	# 站著不動：那一片先預警（還站得住），過了預警時間掉下去，人跟著掉。
	var stand := walkway.segment_rect(3)
	player.global_position = Vector2(stand.get_center().x, top)
	player.velocity = Vector2.ZERO
	await physics_frames(6)
	check(walkway.segment_state(3) == CrumblingWalkway.Piece.WARNING and absf(player.global_position.y - top) < 2.0, "the piece under a standing player warns first and still holds: state %d, feet %.1f" % [walkway.segment_state(3), player.global_position.y])
	check(walkway.segment_state(2) == CrumblingWalkway.Piece.INTACT and walkway.segment_state(4) == CrumblingWalkway.Piece.INTACT, "only the piece being stood on crumbles")
	await physics_frames(int(walkway_data.warn_seconds * 60.0) + 20)
	check(walkway.segment_state(3) == CrumblingWalkway.Piece.FALLEN, "the piece falls after the warning time")
	check(player.global_position.y > top + 24.0, "a player who stays still falls with it: feet %.1f, deck %.1f" % [player.global_position.y, top])

	# 補回：上方有人時先不補，人離開才補；補回後又站得住。
	player.set_physics_process(false)
	player.global_position = Vector2(stand.get_center().x, top - 20.0)
	await physics_frames(int(walkway_data.respawn_seconds * 60.0) + 20)
	check(walkway.segment_state(3) == CrumblingWalkway.Piece.FALLEN, "a fallen piece does not return while someone is right above it")
	player.global_position = Vector2(stand.get_center().x, top + 60.0)
	await physics_frames(30)
	check(walkway.is_solid(3), "the piece returns once the space above it is clear")
	await physics_frames(int(CrumblingWalkway.RETURN_SECONDS * 60.0) + 4)
	check(walkway.segment_state(3) == CrumblingWalkway.Piece.INTACT, "the returned piece is whole again")
	player.set_physics_process(true)

	# 一路往右跑：從左邊的平台跑到右邊的平台，不會掉下去；走過的片在身後一片片塌掉。
	player.global_position = Vector2(4.0 * 16.0, top)
	player.velocity = Vector2.ZERO
	await physics_frames(4)
	var fell := [0]
	walkway.segment_fell.connect(func(_index: int) -> void: fell[0] += 1)
	Input.action_press(&"move_right")
	var lowest := top
	var frames_left := 320
	while frames_left > 0 and player.global_position.x < 26.0 * 16.0:
		await physics_frames(1)
		lowest = maxf(lowest, player.global_position.y)
		frames_left -= 1
	Input.action_release(&"move_right")
	check(player.global_position.x >= 26.0 * 16.0 and lowest < top + 3.0, "running straight across reaches the far side without falling: x %.1f, lowest feet %.1f" % [player.global_position.x, lowest])
	var warned := 0
	for i in walkway.segment_count():
		warned += 1 if walkway.segment_state(i) != CrumblingWalkway.Piece.INTACT else 0
	await physics_frames(int(walkway_data.warn_seconds * 60.0) + 10)
	check(warned >= walkway.segment_count() - 1 and fell[0] >= walkway.segment_count() - 1, "the pieces crumble behind the runner (%d warned, %d fell of %d)" % [warned, fell[0], walkway.segment_count()])

	# 敵人站上去也會塌，敵人跟著掉下去。
	await physics_frames(int((walkway_data.respawn_seconds + CrumblingWalkway.RETURN_SECONDS) * 60.0) + 30)
	player.set_physics_process(false)
	player.global_position = Vector2(36.0 * 16.0, top - 200.0)  # 敵人看不到
	var enemy := level._spawn_reinforcement(load(GRUNT_PATH) as EnemyData, Vector2(walkway.segment_rect(5).get_center().x, top))
	var enemy_piece := walkway.segment_at(enemy.global_position.x) if enemy != null else -1
	var enemy_lowest := top
	for i in int(walkway_data.warn_seconds * 60.0) + 60:
		await physics_frames(1)
		if enemy != null and is_instance_valid(enemy):
			enemy_lowest = maxf(enemy_lowest, enemy.global_position.y)
	check(enemy != null and enemy_piece >= 0 and walkway.segment_state(enemy_piece) == CrumblingWalkway.Piece.FALLEN, "an enemy standing on the walkway makes it crumble too")
	check(enemy_lowest > top + 24.0, "the enemy falls with the piece: lowest feet %.1f, deck %.1f, now %s" % [enemy_lowest, top, enemy.global_position if enemy != null and is_instance_valid(enemy) else "gone"])
	player.set_physics_process(true)

	# 「減少介面動態」：不抖，但照樣預警、照樣塌。
	var old_motion := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	await physics_frames(int((walkway_data.respawn_seconds + CrumblingWalkway.RETURN_SECONDS) * 60.0) + 30)
	var still_piece := walkway.segment_rect(1)
	player.global_position = Vector2(still_piece.get_center().x, top)
	player.velocity = Vector2.ZERO
	var max_shake := 0.0
	for i in 12:
		await physics_frames(1)
		max_shake = maxf(max_shake, absf(walkway.shake_offset(1)))
	check(walkway.segment_state(1) == CrumblingWalkway.Piece.WARNING and max_shake == 0.0, "with reduced motion the warning piece does not shake but still warns")
	await physics_frames(int(walkway_data.warn_seconds * 60.0) + 10)
	check(walkway.segment_state(1) == CrumblingWalkway.Piece.FALLEN, "with reduced motion the piece still falls")
	Settings.set_reduce_ui_motion(old_motion)
	check(not walkway.is_in_group(WorldState.GROUP), "the walkway is not part of the checkpoint snapshot")

	# 從檢查點重來：關卡重建，走道一律是完整的（存檔來回）。
	GameState.set_checkpoint(Vector2(4.0 * 16.0, top), {}, {})
	await end_level(level)
	level = await spawn_level(data)
	walkway = _find_all(level, CrumblingWalkway)[0] as CrumblingWalkway
	var whole := true
	for i in walkway.segment_count():
		whole = whole and walkway.segment_state(i) == CrumblingWalkway.Piece.INTACT and walkway.is_solid(i)
	check(whole, "after respawning from a checkpoint every piece is back")
	check(absf(level.player.global_position.x - 4.0 * 16.0) < 2.0, "the player respawns at the checkpoint on the near side")
	await end_level(level)
	GameState.clear_checkpoint()

## 可躲藏的位置：蹲在簾子後面，還沒進入戰鬥的敵人看不到（從面前走過去也一樣）；站起來或蹲在簾子外面就看得到；
## 已經在戰鬥的敵人照常看得到。沒有狀態要存，重建關卡後不留下舊的登記。
func _test_hiding_spot() -> void:
	var spot_data := load(HIDING_PATH) as HidingSpotData
	check(spot_data != null and spot_data.validate().is_empty(), "the hiding spot data is valid: %s" % [spot_data.validate() if spot_data != null else ["missing"]])
	if spot_data == null:
		return
	check(not spot_data.hint_for("en").is_empty() and not spot_data.hint_for("ja").is_empty(), "the hiding spot hint is available in all three languages")
	var bad := HidingSpotData.new()
	bad.width_tiles = 1
	bad.height_tiles = 9
	bad.hint = "x"
	check(bad.validate().size() >= 3, "a too-narrow or too-tall spot, or a missing translation, is reported: %s" % [bad.validate()])

	var data := LevelData.new()
	data.id = &"hiding_spot_test"
	data.layout_path = HIDING_MAP
	data.legend = {"K": spot_data}
	var level := await start_level(data)
	var spots := _find_all(level, HidingSpot)
	check(spots.size() == 1 and HidingSpot._spots.size() == 1, "the map character spawns one hiding spot and registers it once")
	if spots.is_empty():
		await end_level(level)
		return
	var spot := spots[0] as HidingSpot
	var player := level.player
	player.health.setup(999, 0.0)
	var floor_y := spot.global_position.y
	var inside_x := spot.global_position.x + spot.width * 0.5
	check(is_equal_approx(spot.global_position.x, 20.0 * 16.0), "the alcove starts at the left edge of its cell: %.1f" % spot.global_position.x)

	# 站在簾子裡：還藏不住。蹲下：藏好了。
	player.global_position = Vector2(inside_x, floor_y)
	player.velocity = Vector2.ZERO
	await physics_frames(4)
	check(not HidingSpot.conceals(player), "standing inside the alcove does not hide the player")
	Input.action_press(&"move_down")
	await physics_frames(4)
	check(player.is_crouching and HidingSpot.conceals(player) and spot.is_hiding_player(), "crouching behind the curtain hides the player")

	# 還沒發現玩家的敵人從面前走過去：看不到、不進入戰鬥。
	var enemy := level._spawn_reinforcement(load(GRUNT_PATH) as EnemyData, Vector2(inside_x + 90.0, floor_y))
	if enemy == null:
		check(false, "the hiding fixture spawns a patrolling enemy")
		Input.action_release(&"move_down")
		await end_level(level)
		return
	enemy.facing = -1
	enemy.fsm.transition(&"patrol")
	await physics_frames(2)
	check(not enemy._can_see_target(enemy.data.detect_range), "a relaxed enemy facing the curtain cannot see the crouching player")
	var passed := false
	var engaged := false
	for i in 240:
		await physics_frames(1)
		engaged = engaged or enemy.is_engaged()
		passed = passed or enemy.global_position.x < inside_x - 24.0
	check(passed and not engaged and player.health.current == 999 and player.is_crouching, "a patrolling enemy walks right past (and through) the hidden player without noticing or bumping into him (passed %s, engaged %s, health %d)" % [passed, engaged, player.health.current])

	# 站起來就看得到。
	Input.action_release(&"move_down")
	enemy.global_position = Vector2(inside_x + 60.0, floor_y)
	enemy.facing = -1
	await physics_frames(4)
	check(not HidingSpot.conceals(player) and enemy._can_see_target(enemy.data.detect_range), "standing up in the alcove makes the player visible again")

	# 蹲在簾子外面：藏不住。
	enemy.fsm.transition(&"patrol")
	player.global_position = Vector2(spot.global_position.x - 40.0, floor_y)
	Input.action_press(&"move_down")
	await physics_frames(4)
	check(player.is_crouching and not HidingSpot.conceals(player), "crouching outside the curtain does not hide the player")

	# 巡邏的看守（back_sight_scale < 1）背後只看得到近處：跟在後面一段距離不會被發現；太近或面對面就看得到。
	# 一般敵人（預設 1）前後一樣。
	Input.action_release(&"move_down")
	await physics_frames(3)
	var reach := enemy.data.detect_range
	check(is_equal_approx(enemy.data.back_sight_scale, 1.0), "ordinary enemies see the same distance behind them by default")
	enemy.facing = 1
	enemy.global_position = Vector2(player.global_position.x + reach * 0.6, floor_y)
	check(enemy._can_see_target(reach), "an ordinary enemy still notices a player behind it")
	var watcher := level._spawn_reinforcement(load("res://data/enemies/ch2_escort.tres") as EnemyData, Vector2(inside_x + 400.0, floor_y))
	if watcher != null:
		var watch_reach := watcher.data.detect_range
		check(watcher.data.back_sight_scale < 1.0, "the loading-bay escorts are back-blind watchers (%.2f)" % watcher.data.back_sight_scale)
		watcher.facing = 1
		watcher.global_position = Vector2(player.global_position.x + watch_reach * 0.6, floor_y)
		check(not watcher._can_see_target(watch_reach), "a patrolling watcher does not notice a player well behind its back")
		watcher.global_position = Vector2(player.global_position.x + watch_reach * watcher.data.back_sight_scale * 0.5, floor_y)
		check(watcher._can_see_target(watch_reach), "a patrolling watcher still notices a player right behind it")
		watcher.facing = -1
		watcher.global_position = Vector2(player.global_position.x + watch_reach * 0.6, floor_y)
		check(watcher._can_see_target(watch_reach), "facing the player, the watcher sees the same distance")
		watcher.queue_free()
	else:
		check(false, "the watcher enemy spawns")
	Input.action_press(&"move_down")
	await physics_frames(3)

	# 已經在戰鬥（被警報引來）的敵人照常看得到。
	player.global_position = Vector2(inside_x, floor_y)
	await physics_frames(4)
	enemy.global_position = Vector2(inside_x + 60.0, floor_y)
	enemy.raise_alert(player.global_position, 3.0)
	check(HidingSpot.conceals(player) and enemy.is_engaged() and enemy._can_see_target(enemy.data.detect_range), "an enemy already in the fight still sees the player behind the curtain")
	Input.action_release(&"move_down")

	# 「減少介面動態」：人穿過簾子時條簾不晃。
	enemy.queue_free()
	var old_motion := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	player.global_position = Vector2(spot.global_position.x - 20.0, floor_y)
	Input.action_press(&"move_right")
	var max_drift := 0.0
	for i in 30:
		await physics_frames(1)
		max_drift = maxf(max_drift, absf(spot.strip_offset(3)))
	Input.action_release(&"move_right")
	check(max_drift == 0.0, "with reduced motion the strip curtain does not sway")
	Settings.set_reduce_ui_motion(old_motion)
	player.global_position = Vector2(spot.global_position.x - 20.0, floor_y)
	Input.action_press(&"move_right")
	max_drift = 0.0
	for i in 30:
		await physics_frames(1)
		max_drift = maxf(max_drift, absf(spot.strip_offset(3)))
	Input.action_release(&"move_right")
	check(max_drift > 0.2, "walking through the curtain makes the strips sway (%.2f px)" % max_drift)

	# 從檢查點重來：關卡重建，舊的登記被清掉、新的一處登記一次，玩家站著就沒有藏著。
	GameState.set_checkpoint(Vector2(3.5 * 16.0, floor_y), {}, {})
	await end_level(level)
	check(HidingSpot._spots.is_empty(), "leaving the level clears the hiding spot registry")
	level = await spawn_level(data)
	check(HidingSpot._spots.size() == 1 and not HidingSpot.conceals(level.player), "after respawning there is exactly one hiding spot and the player starts out in the open")
	await end_level(level)
	GameState.clear_checkpoint()

## 誘餌收音機（NE-404）：射中才播、敵人打不開；範圍內沒發現玩家的敵人走過去盯著看、看不到背後；被打就醒；播完就壞。
func _test_decoy_radio() -> void:
	var radio_data := load(RADIO_PATH) as DecoyRadioData
	check(radio_data != null and radio_data.validate().is_empty(), "the decoy radio data is valid: %s" % [radio_data.validate() if radio_data != null else ["missing"]])
	if radio_data == null:
		return
	check(not radio_data.hint_for("en").is_empty() and not radio_data.hint_for("ja").is_empty(), "the radio hint is available in all three languages")
	var bad := DecoyRadioData.new()
	bad.play_seconds = NAN
	bad.hint = "x"
	check(bad.validate().size() >= 2, "broken timing or a missing translation is reported")

	var data := LevelData.new()
	data.id = &"decoy_radio_test"
	data.legend = {"K": radio_data, "g": load(GRUNT_PATH)}
	data.layout_path = RADIO_MAP
	var level := await start_level(data)
	var radios := _find_all(level, DecoyRadio)
	check(radios.size() == 1, "the map character spawns one decoy radio")
	var enemy: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		enemy = node as Enemy
	if radios.is_empty() or enemy == null:
		await end_level(level)
		return
	var radio := radios[0] as DecoyRadio
	var player := level.player
	player.set_physics_process(false)
	player.global_position = enemy.global_position + Vector2(0.0, -400.0)  # 遠在上方，敵人看不到
	enemy.fsm.transition(&"patrol")  # 開場時可能已經瞄過玩家；讓它回到還沒發現的狀態
	await physics_frames(2)
	check(not enemy.is_engaged(), "the enemy starts unaware")
	radio.hurtbox.receive(DamageInfo.create(1, Combat.Team.ENEMY, &"test_enemy_shot"))
	check(not radio.is_playing(), "enemy fire does not start the radio")
	radio.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	check(radio.is_playing(), "a player hit starts the radio")
	await frames(3)
	check(enemy.is_lured(), "an unaware enemy in range is drawn to the radio")
	var start_gap := absf(radio.global_position.x - enemy.global_position.x)
	await runner.get_tree().create_timer(1.5).timeout
	var gap := absf(radio.global_position.x - enemy.global_position.x)
	check(gap < start_gap - 20.0, "the lured enemy walks toward the radio: %.0f -> %.0f px" % [start_gap, gap])
	var front := 1 if radio.global_position.x > enemy.global_position.x else -1
	check(enemy.facing == front, "the lured enemy faces the radio")
	# 背後的人看不到，面前的看得到（看到之後就不再被吸引）。
	player.global_position = enemy.global_position + Vector2(-front * 40.0, 0.0)
	check(not enemy._can_see_target(400.0), "a lured enemy cannot see the player right behind it")
	check(enemy.is_lured(), "standing behind does not break the lure")
	enemy.health.damaged.emit(DamageInfo.create(1, Combat.Team.PLAYER, &"test_poke"))
	check(not enemy.is_lured(), "getting hit snaps the enemy out of it")
	player.global_position = enemy.global_position + Vector2(0.0, -400.0)
	check(enemy.lure_to(radio.global_position, 2.0), "a relaxed enemy can be lured again while the radio plays")
	player.global_position = enemy.global_position + Vector2(front * 300.0, 0.0)
	check(not enemy._can_see_target(400.0) and enemy.is_lured(), "a distracted enemy only sees half as far in front")
	player.global_position = enemy.global_position + Vector2(front * 40.0, 0.0)
	check(enemy._can_see_target(400.0) and not enemy.is_lured(), "a player close in front is seen and ends the lure")
	await runner.get_tree().create_timer(radio_data.play_seconds).timeout
	check(radio.state == DecoyRadio.State.SPENT and not radio.play(), "the radio breaks after playing and cannot be used again")
	await end_level(level)


## 環境機關擺進各章（NE-405 起）：每一處都在預期的區域與格子，資源路徑正確；新章節的擺放加在 EXPECTED。
func _test_mechanic_placements() -> void:
	const EXPECTED := [
		# [區域, 機關資源, 地圖格]
		["res://data/levels/ch2_loading.tres", "res://data/props/suspended_crate.tres", Vector2i(73, 35)],
		["res://data/levels/ch2_market_gate.tres", "res://data/props/live_cable.tres", Vector2i(40, 35)],
		["res://data/levels/ch2_market_gate.tres", "res://data/props/live_cable.tres", Vector2i(65, 35)],
		["res://data/levels/ch3_pump.tres", "res://data/props/decoy_radio.tres", Vector2i(37, 35)],
		["res://data/levels/ch3_mezzanine.tres", "res://data/props/decoy_radio.tres", Vector2i(61, 35)],
		["res://data/levels/ch3_mezzanine.tres", "res://data/props/live_cable.tres", Vector2i(63, 35)],
		["res://data/levels/ch4_factory_relay.tres", "res://data/props/conveyor.tres", Vector2i(13, 19)],
		["res://data/levels/ch4_factory_relay.tres", "res://data/props/live_cable.tres", Vector2i(32, 19)],
		["res://data/levels/ch1_rooftop.tres", "res://data/props/crumbling_walkway.tres", Vector2i(16, 44)],
		["res://data/levels/ch2_loading.tres", "res://data/props/hiding_spot.tres", Vector2i(7, 35)],
	]
	for entry: Array in EXPECTED:
		var level := load(entry[0]) as LevelData
		var found := false
		if level != null:
			for spawn: Dictionary in LevelBuilder.parse(level).spawns:
				var res: Resource = spawn["resource"]
				found = found or (res.resource_path == entry[1] and spawn["cell"] == entry[2])
		check(found, "%s has %s at %s" % [entry[0].get_file(), entry[1].get_file(), entry[2]])
	# 第四章中繼區的組合（NE-407）：輸送帶反轉後把人送到馬達那一端，那一端要落在電纜積水裡。
	var belt := load(CONVEYOR_PATH) as ConveyorData
	var cable := load(CABLE_PATH) as LiveCableData
	var belt_end := (13.0 + belt.length_tiles) * 16.0
	var puddle_center := (32.0 + 0.5) * 16.0
	check(absf(belt_end - puddle_center) < cable.water_width * 0.5 - 8.0, "the reversed belt delivers riders into the relay puddle: end %.0f, puddle %.0f±%.0f" % [belt_end, puddle_center, cable.water_width * 0.5])


## 敵人避開通電的積水（NE-408）：預警與通電期間巡邏的敵人走到水邊就回頭、不會踩進去；水用完之後範圍撤掉。
func _test_hazard_avoidance() -> void:
	check(not HazardZones.blocks(Vector2(123.0, 456.0)), "no hazard zones are registered outside a live puddle")
	var data := LevelData.new()
	data.id = &"hazard_avoidance_test"
	data.layout_path = CABLE_MAP
	data.legend = {"K": load(CABLE_PATH), "g": load(GRUNT_PATH)}
	var level := await start_level(data)
	var cables := _find_all(level, LiveCable)
	var enemy: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		enemy = node as Enemy
	if cables.is_empty() or enemy == null:
		check(false, "the hazard fixture has a cable and an enemy")
		await end_level(level)
		return
	var cable := cables[0] as LiveCable
	var player := level.player
	player.set_physics_process(false)
	player.global_position = cable.global_position + Vector2(0.0, -400.0)  # 敵人看不到
	var rect := cable.shock_rect()
	enemy.global_position = Vector2(rect.end.x + 40.0, cable.global_position.y)
	enemy.facing = -1  # 往水的方向巡邏
	enemy.fsm.transition(&"patrol")
	cable.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	check(HazardZones.blocks(cable.global_position + Vector2(0.0, -1.0)), "a cut cable marks its puddle as dangerous from the warning on")
	var stepped_in := false
	var turned := false
	var health_before := enemy.health.current
	var timer := runner.get_tree().create_timer(2.5)
	while timer.time_left > 0.0:
		await physics_frames(1)
		if not is_instance_valid(enemy):
			break
		stepped_in = stepped_in or rect.has_point(enemy.global_position + Vector2(0.0, -1.0))
		turned = turned or enemy.facing == 1
	check(not stepped_in, "a patrolling enemy does not walk into the live puddle")
	check(turned, "the patrolling enemy turns back at the water's edge")
	check(is_instance_valid(enemy) and enemy.health.current == health_before, "the enemy that stayed out of the water is never shocked")
	await runner.get_tree().create_timer(LiveCable.ARC_EVERY + (load(CABLE_PATH) as LiveCableData).live_seconds).timeout
	check(cable.state == LiveCable.State.SPENT and not HazardZones.blocks(cable.global_position + Vector2(0.0, -1.0)), "the spent puddle is no longer marked dangerous")
	await end_level(level)
	check(not HazardZones.blocks(cable.global_position if is_instance_valid(cable) else Vector2.ZERO), "leaving the level clears the hazard zones")


## 蒸汽擋住敵人的視線（NE-409）：隔著蒸汽看不到玩家、不會開槍，但會往玩家那一頭推進；蒸汽散了就照常看得到。
func _test_steam_blocks_sight() -> void:
	var data := LevelData.new()
	data.id = &"steam_sight_test"
	data.layout_path = VALVE_MAP
	data.legend = {"V": load(VALVE_PATH)}
	var level := await start_level(data)
	var valves := _find_all(level, SteamValve)
	if valves.is_empty():
		check(false, "the steam sight fixture has a valve")
		await end_level(level)
		return
	var valve := valves[0] as SteamValve
	var enemy := level._create_enemy(load(GRUNT_PATH) as EnemyData)
	var rect := valve.screen_rect()
	enemy.position = Vector2(rect.end.x + 90.0, valve.global_position.y)
	level._entities.add_child(enemy)
	var player := level.player
	player.set_physics_process(false)
	player.global_position = Vector2(rect.position.x - 60.0, valve.global_position.y)
	await physics_frames(2)
	enemy.set_physics_process(false)  # 只看視線判斷，先不讓它自己動
	check(enemy._can_see_target(400.0), "with no steam the enemy sees the player across the valve")
	valve.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	await physics_frames(3)
	check(valve._screen.is_blocking(), "the steam screen is up")
	check(not enemy._can_see_target(400.0), "the enemy cannot see the player through the steam")
	check(enemy.is_alerted(), "losing sight to steam sends the enemy toward the player's side")
	var start_x := enemy.global_position.x
	enemy.fsm.transition(&"patrol")
	enemy.set_physics_process(true)
	await runner.get_tree().create_timer(1.0).timeout
	check(is_instance_valid(enemy) and enemy.global_position.x < start_x - 10.0, "the enemy pushes toward the player instead of standing still: %.0f -> %.0f" % [start_x, enemy.global_position.x if is_instance_valid(enemy) else -1.0])
	await end_level(level)


## 區域可選小挑戰（NE-410）：只有環境機關的擊倒算數；達成給一次信用點、不會重複；進度跟著檢查點狀態。
func _test_area_challenge() -> void:
	var gate := load("res://data/levels/ch2_market_gate.tres") as LevelData
	check(gate != null and gate.challenges.size() == 1 and gate.challenges[0].validate().is_empty(), "the market gate has one valid area challenge")
	if gate != null and not gate.challenges.is_empty():
		check(not gate.challenges[0].goal_for("en").is_empty() and not gate.challenges[0].goal_for("ja").is_empty(), "the challenge goal is available in all three languages")
	var bad := AreaChallengeData.new()
	check(bad.validate().size() >= 2, "a challenge without id, goal or translations is reported")

	var challenge_data := AreaChallengeData.new()
	challenge_data.id = &"test_environment"
	challenge_data.target = 1
	challenge_data.reward_credits = 25
	challenge_data.goal = "測試"
	challenge_data.localized_goals = {"en": "test", "ja": "テスト"}
	var data := LevelData.new()
	data.id = &"area_challenge_test"
	data.layout_path = CABLE_MAP
	data.legend = {"K": load(CABLE_PATH), "g": load(GRUNT_PATH)}
	data.challenges = [challenge_data]
	var level := await start_level(data)
	var challenges := runner.get_tree().get_nodes_in_group(AreaChallenge.GROUP)
	check(challenges.size() == 1, "the level spawns its area challenge")
	var cables := _find_all(level, LiveCable)
	var enemy: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		enemy = node as Enemy
	if challenges.is_empty() or cables.is_empty() or enemy == null:
		await end_level(level)
		return
	var challenge := challenges[0] as AreaChallenge
	var player := level.player
	player.set_physics_process(false)
	player.global_position = enemy.global_position + Vector2(0.0, -400.0)
	# 一般的擊倒不算。
	var other := level._create_enemy(load(GRUNT_PATH) as EnemyData)
	other.position = player.global_position + Vector2(200.0, 0.0)
	level._entities.add_child(other)
	await physics_frames(2)
	other.health.take_damage(DamageInfo.create(999, Combat.Team.PLAYER, &"test_gun"))
	await physics_frames(2)
	check(challenge.progress == 0 and not challenge.done, "an ordinary kill does not count toward the challenge")
	var credits_before := Progression.credits
	enemy.set_physics_process(false)
	enemy.health.setup(1, 0.0)
	(cables[0] as LiveCable).hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"test_player_shot"))
	await runner.get_tree().create_timer((load(CABLE_PATH) as LiveCableData).warning_seconds + 0.4).timeout
	check(challenge.done and challenge.progress == 1, "a kill by the electrified water completes the challenge")
	check(Progression.credits == credits_before + 25, "completing the challenge pays its reward once: %d -> %d" % [credits_before, Progression.credits])
	check(not challenge.add_progress(1) and Progression.credits == credits_before + 25, "a finished challenge does not pay again")
	var saved: Variant = challenge.capture_state()
	challenge.restore_state({"progress": 0, "done": false})
	check(not challenge.done, "restoring an earlier checkpoint rolls the challenge back")
	challenge.restore_state(saved)
	check(challenge.done and challenge.state_key() == "challenge@test_environment", "the challenge state round-trips under a stable key")
	# 存檔的世界狀態清理（RunSnapshot）要收得下挑戰的物件狀態，不能讓比較出錯（NE-414）。
	var cleaned := RunSnapshot._world(WorldState.capture(runner.get_tree()))
	check(cleaned.get("challenge@test_environment") == {"progress": 1, "done": true, "failed": false}, "the run save keeps the challenge state: %s" % [cleaned.get("challenge@test_environment")])
	var broken := RunSnapshot._world({"challenge@x": "bad", "gate@1,2": {"open": true}, "lamp@3,4": true})
	check(broken["challenge@x"] == {"progress": 0, "done": false, "failed": false} and broken["gate@1,2"] == false and broken["lamp@3,4"] == true, "a damaged world state falls back to safe defaults: %s" % broken)
	challenge.restore_state(cleaned["challenge@test_environment"])
	check(challenge.done, "a saved challenge state restores after the save round-trip")
	await end_level(level)


## 「不被發現」挑戰（NE-411）：走到終點前沒被發現就完成；終點附近的敵人一進入戰鬥就失敗、不給獎勵；失敗跟著檢查點重置。
func _test_unseen_challenge() -> void:
	var loading := load("res://data/levels/ch2_loading.tres") as LevelData
	check(loading != null and loading.challenges.size() == 1 and loading.challenges[0].kind == AreaChallengeData.Kind.UNSEEN_PASS and loading.challenges[0].validate().is_empty(), "the loading bay has a valid unseen-pass challenge")
	var no_finish := AreaChallengeData.new()
	no_finish.kind = AreaChallengeData.Kind.UNSEEN_PASS
	check("".join(no_finish.validate()).contains("終點"), "an unseen-pass challenge without a finish cell is reported")
	for spotted: bool in [false, true]:
		var challenge_data := AreaChallengeData.new()
		challenge_data.id = &"test_unseen"
		challenge_data.kind = AreaChallengeData.Kind.UNSEEN_PASS
		challenge_data.target = 1
		challenge_data.reward_credits = 30
		challenge_data.finish_cell_x = 20
		challenge_data.goal = "測試"
		challenge_data.localized_goals = {"en": "test", "ja": "テスト"}
		var data := LevelData.new()
		data.id = &"unseen_challenge_test"
		data.layout_path = CABLE_MAP
		data.legend = {"g": load(GRUNT_PATH)}
		data.challenges = [challenge_data]
		var level := await start_level(data)
		var challenge := runner.get_tree().get_nodes_in_group(AreaChallenge.GROUP)[0] as AreaChallenge
		var enemy: Enemy
		for node in runner.get_tree().get_nodes_in_group(&"enemies"):
			enemy = node as Enemy
		var player := level.player
		player.set_physics_process(false)
		var credits_before := Progression.credits
		player.global_position += Vector2(0.0, -200.0)
		if spotted:
			enemy.raise_alert(player.global_position, 3.0)
		await runner.get_tree().create_timer(AreaChallenge.WATCH_EVERY * 2.0).timeout
		# 終點在敵人頭上：玩家從上方越過，地面的敵人看不到（高度差超過視野）。
		player.global_position = Vector2(21.0 * 16.0, player.global_position.y - 200.0)
		await runner.get_tree().create_timer(AreaChallenge.WATCH_EVERY * 2.0).timeout
		if spotted:
			check(challenge.failed and not challenge.done and Progression.credits == credits_before, "being spotted fails the challenge and pays nothing")
			challenge.restore_state({"progress": 0, "done": false, "failed": false})
			check(not challenge.failed and challenge.is_physics_processing(), "an earlier checkpoint resets a failed challenge")
		else:
			check(challenge.done and Progression.credits == credits_before + 30, "reaching the finish unseen completes the challenge and pays once")
		await end_level(level)


## 落地的貨箱當掩護（NE-415）：清掃兵跑到貨箱後面蹲下（身體判定剛好到箱頂、子彈打不到），冷卻好了站起來越過箱頂開槍；
## 玩家繞到同一側就離開掩體；貨箱被移除就不再登記。
func _test_crate_cover() -> void:
	CoverSpots.clear()
	var owner := RefCounted.new()
	CoverSpots.register(owner, Rect2(100, 68, 32, 32))  # 地面 y=100
	var spot := CoverSpots.spot_behind(Vector2(200, 100), 0.0, 150.0)
	check(spot.get("x") == 144.0 and spot.get("top") == 68.0, "the cover spot is on the far side of the crate from the threat: %s" % spot)
	check(CoverSpots.spot_behind(Vector2(200, 100), 300.0, 150.0).is_empty(), "no cover when the threat is on the same side")
	check(CoverSpots.spot_behind(Vector2(200, 100), 116.0, 150.0).is_empty(), "no cover when the threat stands over the crate")
	check(CoverSpots.spot_behind(Vector2(200, 60), 0.0, 150.0).is_empty(), "no cover on a different floor")
	check(CoverSpots.spot_behind(Vector2(400, 100), 0.0, 150.0).is_empty(), "no cover beyond reach")
	check(CoverSpots.spot_behind(Vector2(50, 100), 300.0, 150.0).get("x") == 88.0, "the spot flips with the threat side")
	CoverSpots.unregister(owner)
	check(CoverSpots.is_empty(), "unregistering removes the cover")

	var data := LevelData.new()
	data.id = &"crate_cover_test"
	data.layout_path = SUSPENDED_MAP
	data.legend = {"Q": load(SUSPENDED_PATH), "g": load(GRUNT_PATH)}
	var level := await start_level(data)
	var loads := _find_all(level, SuspendedLoad)
	var gunner: Enemy
	for node in runner.get_tree().get_nodes_in_group(&"enemies"):
		gunner = node as Enemy
	if loads.is_empty() or gunner == null:
		check(false, "the cover map has a crate and a gunner")
		await end_level(level)
		return
	var crate := loads[0] as SuspendedLoad
	var floor_y := crate.global_position.y
	var top := floor_y - crate.size_px.y
	var player := level.player
	player.set_physics_process(false)
	player.health.setup(999, 0.0)
	player.global_position = Vector2(crate.global_position.x - 180.0, floor_y)
	gunner.global_position = Vector2(crate.global_position.x + 90.0, floor_y)
	check(CoverSpots.is_empty(), "a hanging crate is not cover")
	crate.restore_state(true)
	check(not CoverSpots.is_empty(), "a landed crate registers as cover")
	gunner.raise_alert(player.global_position, 8.0)
	var ducked := false
	var peek_y := INF
	var back := false
	for i in 360:
		await runner.get_tree().physics_frame
		if gunner.fsm.is_in(&"cover") and gunner.get("_ducked") == true:
			if not ducked:
				ducked = true
				var edge := crate.global_position.x + crate.size_px.x * 0.5
				check(absf(gunner.global_position.x - edge - CoverSpots.SIDE_MARGIN) <= 6.0, "the gunner crouches right behind the crate (%.0f px from its edge)" % (gunner.global_position.x - edge))
				check(gunner.hurtbox._shape.size.y <= crate.size_px.y + 0.5, "crouched, its body reaches no higher than the crate top (%.0f px)" % gunner.hurtbox._shape.size.y)
			elif peek_y < INF:
				back = true
				break
		if gunner.fsm.is_in(&"aim"):
			peek_y = minf(peek_y, gunner.call("_peek_origin").y)
	check(ducked, "the gunner takes cover behind the landed crate")
	check(peek_y < top, "it rises and fires from above the crate top (%.0f < %.0f)" % [peek_y, top])
	check(back, "after firing it ducks behind the crate again")
	# 蹲著時，從玩家的高度打過去的子彈被貨箱擋下。
	var before := gunner.health.current
	var spec := (load(GRUNT_PATH) as EnemyData).projectile
	ProjectilePool.spawn(spec, player.global_position + Vector2(10.0, -20.0), Vector2.RIGHT, Combat.Team.PLAYER, 1.0)
	await physics_frames(30)
	check(gunner.health.current == before, "a shot at body height hits the crate, not the crouched gunner")
	# 玩家繞到同一側：不再算掩護，離開掩體。
	player.global_position = Vector2(gunner.global_position.x + 120.0, floor_y)
	await physics_frames(6)
	check(not gunner.fsm.is_in(&"cover") and gunner.get("_ducked") == false and is_equal_approx(gunner.hurtbox._shape.size.y, gunner.data.body_size.y),
			"flanked, it leaves cover and stands up (%s)" % gunner.fsm.current)
	crate.queue_free()
	await physics_frames(2)
	check(CoverSpots.is_empty(), "a removed crate no longer counts as cover")
	await end_level(level)


## 「限時抵達」挑戰（NE-418）：越過起點才開始倒數，頭頂出現倒數；時間內到終點就完成並給一次獎勵，時間到就失敗、不給獎勵；
## 回到檢查點就回到還沒開始。
func _test_timed_challenge() -> void:
	var relay := load("res://data/levels/ch4_factory_relay.tres") as LevelData
	check(relay != null and relay.challenges.size() == 1 and relay.challenges[0].kind == AreaChallengeData.Kind.TIMED_REACH and relay.challenges[0].validate().is_empty(),
			"the chapter 4 relay has a valid timed challenge")
	var backwards := AreaChallengeData.new()
	backwards.kind = AreaChallengeData.Kind.TIMED_REACH
	backwards.start_cell_x = 20
	backwards.finish_cell_x = 10
	check("".join(backwards.validate()).contains("起點"), "a timed challenge whose finish is not past its start is reported")
	for in_time: bool in [true, false]:
		var challenge_data := AreaChallengeData.new()
		challenge_data.id = &"test_timed"
		challenge_data.kind = AreaChallengeData.Kind.TIMED_REACH
		challenge_data.reward_credits = 20
		challenge_data.start_cell_x = 6
		challenge_data.finish_cell_x = 24
		challenge_data.time_limit = 5.0
		challenge_data.goal = "測試"
		challenge_data.localized_goals = {"en": "test", "ja": "テスト"}
		var data := LevelData.new()
		data.id = &"timed_challenge_test"
		data.layout_path = SUSPENDED_MAP
		data.challenges = [challenge_data]
		var level := await start_level(data)
		var challenge := runner.get_tree().get_nodes_in_group(AreaChallenge.GROUP)[0] as AreaChallenge
		var player := level.player
		player.set_physics_process(false)
		var credits_before := Progression.credits
		var y := player.global_position.y
		player.global_position = Vector2(3.0 * 16.0, y)
		await physics_frames(10)
		check(challenge.time_left < 0.0 and challenge._clock == null, "the clock does not run before the start line")
		player.global_position = Vector2(8.0 * 16.0, y)
		await physics_frames(3)
		check(challenge.time_left > 4.5 and challenge.time_left <= 5.0 and challenge._clock != null and challenge._clock.text.contains("5"),
				"crossing the start line starts the countdown above the player (%.2f s, %s)" % [challenge.time_left, challenge._clock.text if challenge._clock != null else "no clock"])
		if in_time:
			player.global_position = Vector2(25.0 * 16.0, y)
			await physics_frames(3)
			check(challenge.done and Progression.credits == credits_before + 20, "reaching the finish in time completes the challenge and pays once")
			await physics_frames(2)
			check(challenge._clock == null, "the clock is removed once the challenge is done")
		else:
			await runner.get_tree().create_timer(challenge_data.time_limit + 0.3).timeout
			player.global_position = Vector2(25.0 * 16.0, y)
			await physics_frames(3)
			check(challenge.failed and not challenge.done and Progression.credits == credits_before and challenge._clock == null,
					"running out of time fails the challenge, pays nothing and removes the clock")
			challenge.restore_state({"progress": 0, "done": false, "failed": false})
			check(not challenge.failed and challenge.time_left < 0.0 and challenge.is_physics_processing(), "an earlier checkpoint resets the timer to not started")
		await end_level(level)
