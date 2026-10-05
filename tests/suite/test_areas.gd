class_name AreasSuite
extends TestSuite
## 區域與出入口（ST-5）：出入口資料檢查、穿過出入口出現在對應位置、本輪世界狀態保留（敵人、拾取、頭目的傷）、
## 死亡扣信用點、檢查點記錄區域、進場後自動離開或結束、旗標、壞資料的容錯。舊式關卡的行為由既有測試負責。

const AREA_A := "res://tests/fixtures/areas/area_a.tres"
const AREA_B := "res://tests/fixtures/areas/area_b.tres"
const MAP_A := "res://tests/fixtures/areas/area_map_a.json"
const TILE := 16.0

var _requested := ""
var _toasts: Array[String] = []


func run() -> void:
	_test_portal_data()
	_test_flags()
	_test_fixture_parse()
	await _test_entry_and_walk()
	await _test_state_persistence()
	await _test_boss_damage_and_death()
	await _test_checkpoint_area()
	await _test_locked_and_flagged_doors()
	await _test_bad_data()
	await _test_after_intro()
	_test_legacy_levels_unchanged()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _load_area(path: String) -> LevelData:
	var data := load(path) as LevelData
	check(data != null, "area loads: %s" % path)
	return data


func _watch(level: Level) -> void:
	_requested = ""
	level.area_requested.connect(func(path: String) -> void: _requested = path)


func _on_toast(text: String) -> void:
	_toasts.append(text)


func _portal(level: Level, id: StringName) -> Portal:
	return level._portals.get(id)


func _x_of(column: int) -> float:
	return (float(column) + 0.5) * TILE


func _enemy_count(level: Level) -> int:
	var count := 0
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		if level.is_ancestor_of(node) and not (node as Enemy).is_dying():
			count += 1
	return count


func _kill_all_enemies(level: Level) -> void:
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		if level.is_ancestor_of(node):
			(node as Enemy).health.take_damage(DamageInfo.create(9999, Combat.Team.PLAYER, &"test"))


# ---------------------------------------------------------------------------
# 資料
# ---------------------------------------------------------------------------

func _test_portal_data() -> void:
	var portal := PortalData.new()
	portal.id = &"test_ok"
	portal.target_level = AREA_B
	check(portal.validate().is_empty(), "a portal with an existing target is valid: %s" % [portal.validate()])
	check(not portal.is_locked_door(), "a portal with a target is not a locked door")
	check(portal.default_prompt().contains("{interact}"), "the default prompt names the interact key")
	var locked := PortalData.new()
	locked.id = &"test_locked"
	check(locked.is_locked_door() and locked.validate().is_empty(), "a portal without a target is a locked door with its text")
	var bad := PortalData.new()
	bad.target_level = "res://tests/fixtures/areas/test_area_bad_nothing.tres"
	bad.width = 2
	bad.locked_text = ""
	check(bad.validate().size() >= 2, "a portal without id and with a missing target is reported: %s" % [bad.validate()])


func _test_flags() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	check(not GameState.has_flag(&"test_flag"), "a new run has no flags")
	GameState.set_flag(&"test_flag")
	check(GameState.has_flag(&"test_flag") and GameState.get_flag(&"test_flag") == true, "a flag can be set and read")
	GameState.set_flag(&"test_count", 3)
	check(GameState.get_flag(&"test_count") == 3, "a flag can hold a number")
	GameState.clear_flag(&"test_flag")
	check(not GameState.has_flag(&"test_flag"), "a flag can be cleared")
	check(not GameState.has_flag(&""), "an empty flag name is never set")
	GameState.start_new_run(GameState.difficulties[1])
	check(not GameState.has_flag(&"test_count"), "starting a new run clears the flags")
	check(GameState.area_states.is_empty(), "starting a new run clears the area states")


func _test_fixture_parse() -> void:
	for path in [AREA_A, AREA_B]:
		var data := _load_area(path)
		if data == null:
			continue
		var layout := LevelBuilder.parse(data)
		check(layout.is_valid() and layout.warnings.is_empty(), "%s parses without warnings %s" % [path, layout.warnings])
		var portals := 0
		for spawn in layout.spawns:
			if spawn["resource"] is PortalData:
				portals += 1
		check(portals >= 1, "%s has portals on the map (%d)" % [path, portals])


# ---------------------------------------------------------------------------
# 進出
# ---------------------------------------------------------------------------

func _test_entry_and_walk() -> void:
	var level := await start_level(_load_area(AREA_A))
	_watch(level)
	var east := _portal(level, &"a_east")
	check(east != null, "the walk portal is built on the map")
	check(level.player.global_position.distance_to(Vector2(_x_of(3), 20.0 * TILE)) < 2.0, "without a portal or checkpoint the player starts at P")
	level.player.global_position = east.global_position + Vector2(0, -2)
	await frames(8)
	check(_requested == AREA_B, "walking into the portal asks for the target area (%s)" % _requested)
	check(GameState.pending_portal == &"b_west", "the target portal is remembered for the next area")
	await end_level(level)

	# 下一個區域：玩家出現在目標出入口，而且不會馬上又彈回去。
	var level_b := await spawn_level(_load_area(AREA_B))
	_watch(level_b)
	var west := _portal(level_b, &"b_west")
	check(level_b.player.global_position.distance_to(west.global_position) < 2.0, "the player appears at the target portal")
	check(not west.is_armed(), "the arrival portal ignores the player until he leaves it")
	await frames(10)
	check(_requested == "", "arriving does not bounce the player straight back (%s)" % _requested)
	level_b.player.global_position = Vector2(_x_of(15), 20.0 * TILE)
	await frames(6)
	check(west.is_armed(), "the portal arms itself after the player walked away")
	check(GameState.pending_portal == &"", "the pending portal is consumed on arrival")
	await end_level(level_b)


# ---------------------------------------------------------------------------
# 世界狀態
# ---------------------------------------------------------------------------

func _test_state_persistence() -> void:
	var level := await start_level(_load_area(AREA_A))
	_watch(level)
	check(_enemy_count(level) == 1, "the area starts with its enemy")
	var player := level.player
	var meds_before := player.consumables.count(&"med_injector")
	player.global_position = Vector2(_x_of(30), 20.0 * TILE)
	await frames(10)
	check(player.consumables.count(&"med_injector") == meds_before + 1, "the med injector is picked up")
	_kill_all_enemies(level)
	await frames(2)
	level.player.global_position = _portal(level, &"a_east").global_position + Vector2(0, -2)
	await frames(8)
	check(_requested == AREA_B, "leaving through the portal")
	var state := GameState.area_state(&"test_area_a")
	check((state["consumed"] as Dictionary).size() == 2, "the killed enemy and the picked item are recorded (%s)" % [state["consumed"]])
	await end_level(level)

	GameState.pending_portal = &"a_east"
	var again := await spawn_level(_load_area(AREA_A))
	check(_enemy_count(again) == 0, "a killed enemy stays dead after coming back")
	var pickups := 0
	for node in again._entities.get_children():
		if node is ConsumablePickup:
			pickups += 1
	check(pickups == 0, "a picked item stays picked after coming back")
	await end_level(again)

	# 新的一輪：狀態清空，敵人回來。
	var fresh := await start_level(_load_area(AREA_A))
	check(_enemy_count(fresh) == 1, "a new run brings the enemy back")
	await end_level(fresh)


func _boss_area() -> LevelData:
	var data := _load_area(AREA_A).duplicate() as LevelData
	data.id = &"test_area_boss"
	var boss := load("res://data/enemies/grunt.tres").duplicate() as EnemyData
	boss.persists_damage = true
	boss.max_health = 20
	data.legend = data.legend.duplicate()
	data.legend["g"] = boss
	return data


func _test_boss_damage_and_death() -> void:
	var level := await start_level(_boss_area())
	_watch(level)
	var boss: Enemy = null
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		if level.is_ancestor_of(node):
			boss = node
	check(boss != null and boss.health.max_health == 20, "the persistent enemy is built")
	if boss == null:
		await end_level(level)
		return
	boss.health.current = 8
	level.player.global_position = _portal(level, &"a_east").global_position + Vector2(0, -2)
	await frames(8)
	var damage: Dictionary = GameState.area_state(&"test_area_boss")["damage"]
	check(damage.values() == [12], "the lost health is saved when leaving (%s)" % [damage])
	await end_level(level)

	GameState.pending_portal = &"a_east"
	var again := await spawn_level(_boss_area())
	var boss_again: Enemy = null
	for node in again.get_tree().get_nodes_in_group(&"enemies"):
		if again.is_ancestor_of(node):
			boss_again = node
	check(boss_again != null and boss_again.health.current == 8, "the enemy comes back with its wounds (%s)" % [boss_again.health.current if boss_again != null else -1])

	# 死亡：頭目回復已損血量的一部分，信用點扣掉一個比例。
	Progression.credits = 200
	again._apply_death_to_world()
	check(Progression.credits == 190, "death costs 5%% of the credits (%d)" % Progression.credits)
	damage = GameState.area_state(&"test_area_boss")["damage"]
	check(damage.values() == [8], "death heals 30%% of the lost health: 12 -> 8 (%s)" % [damage])
	Progression.credits = 0
	again._apply_death_to_world()
	check(Progression.credits == 0, "death with no credits costs nothing")
	await end_level(again)


func _test_checkpoint_area() -> void:
	var level := await start_level(_load_area(AREA_A))
	check(GameState.current_level_path == AREA_A, "the level records which area is being played")
	var spot := Vector2(_x_of(8), 20.0 * TILE)
	GameState.set_checkpoint(spot, level.player.checkpoint_snapshot())
	check(GameState.checkpoint_level_path == AREA_A, "a checkpoint remembers its area")
	check(GameState.checkpoint_applies(AREA_A) and not GameState.checkpoint_applies(AREA_B), "the checkpoint only applies to its own area")
	await end_level(level)

	var other := await spawn_level(_load_area(AREA_B))
	check(other.player.global_position.distance_to(Vector2(_x_of(3), 20.0 * TILE)) < 2.0, "another area ignores the checkpoint and uses its own start")
	await end_level(other)

	var back := await spawn_level(_load_area(AREA_A))
	check(back.player.global_position.distance_to(spot) < 2.0, "the checkpoint's area respawns the player at the checkpoint")
	await end_level(back)

	# 穿過出入口進來時，優先出現在出入口，而不是檢查點。
	GameState.pending_portal = &"a_east"
	var via_portal := await spawn_level(_load_area(AREA_A))
	check(via_portal.player.global_position.distance_to(_portal(via_portal, &"a_east").global_position) < 2.0, "entering through a portal beats the checkpoint")
	await end_level(via_portal)


# ---------------------------------------------------------------------------
# 鎖住的門與壞資料
# ---------------------------------------------------------------------------

func _test_locked_and_flagged_doors() -> void:
	var level := await start_level(_load_area(AREA_B))
	_watch(level)
	_toasts.clear()
	EventBus.toast_requested.connect(_on_toast)
	var locked := _portal(level, &"b_locked")
	check(locked.try_use() == false and _requested == "", "a door without a target never opens")
	check(_toasts.has("鎖住的測試門。"), "a locked door shows its text (%s)" % [_toasts])
	var flagged := _portal(level, &"b_flag")
	check(not flagged.is_open() and flagged.try_use() == false, "a door that needs a flag stays closed without it")
	GameState.set_flag(&"test_area_flag")
	check(flagged.is_open(), "the flag opens the door")
	check(flagged.try_use() and _requested == AREA_A, "an open door asks for its target area (%s)" % _requested)
	EventBus.toast_requested.disconnect(_on_toast)
	await end_level(level)


func _test_bad_data() -> void:
	var level := await start_level(_load_area(AREA_B))
	_watch(level)
	var missing := _portal(level, &"test_area_bad_missing")
	check(missing != null and missing.try_use(), "a portal with a missing target still reports use")
	check(_requested == "", "a missing target area is refused instead of crashing")
	check(not level._finished, "the level keeps running after a refused door")
	await end_level(level)

	# 目標區域裡沒有那個出入口：退回起點。
	GameState.pending_portal = &"test_area_bad_entry"
	var level_a := await spawn_level(_load_area(AREA_A))
	check(level_a.player.global_position.distance_to(Vector2(_x_of(3), 20.0 * TILE)) < 2.0, "an unknown entry portal falls back to the start")
	await end_level(level_a)


# ---------------------------------------------------------------------------
# 進場過場之後
# ---------------------------------------------------------------------------

func _test_after_intro() -> void:
	var leaving := _load_area(AREA_A).duplicate() as LevelData
	leaving.id = &"test_area_leaving"
	leaving.after_intro_portal = &"a_east"
	var level := Level.new()
	GameState.start_new_run(GameState.difficulties[1])
	_requested = ""
	level.configure(leaving)
	level.area_requested.connect(func(path: String) -> void: _requested = path)
	runner.get_tree().root.add_child(level)
	await frames(8)
	check(_requested == AREA_B, "after the intro the player is sent out through the named portal (%s)" % _requested)
	await end_level(level)

	var ending := _load_area(AREA_A).duplicate() as LevelData
	ending.id = &"test_area_ending"
	ending.complete_after_intro = true
	ending.chapter = &"test_area_no_chapter"
	var done := [false]
	var level_end := Level.new()
	GameState.start_new_run(GameState.difficulties[1])
	level_end.configure(ending)
	level_end.completed.connect(func() -> void: done[0] = true)
	runner.get_tree().root.add_child(level_end)
	await frames(8)
	check(done[0], "a level can end right after its intro")
	await end_level(level_end)


func _test_legacy_levels_unchanged() -> void:
	for path in ["res://data/levels/level_01.tres", "res://data/levels/level_02.tres"]:
		var data := load(path) as LevelData
		check(data != null and not data.persistent_world, "%s keeps the old rules (enemies respawn, rewind to checkpoint)" % path)
		check(data.after_intro_portal == &"" and not data.complete_after_intro, "%s has no automatic exit" % path)
