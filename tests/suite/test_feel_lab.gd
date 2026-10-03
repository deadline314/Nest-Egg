class_name FeelLabSuite
extends TestSuite
## 打擊感實驗室（NE-133）：只能從命令列開、遊戲流程進不去；場地有材質靶、移動靶與所有真實敵人，每種都能重生；
## 能切換武器、開壓力模式；用的是正式的玩家與回饋系統。

const LAB_SCENE := "res://tools/feel_lab/feel_lab.tscn"


func run() -> void:
	_test_not_reachable_from_the_game()
	await _test_lab_runs()


func _script_paths(dir: String, into: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_script_paths(dir.path_join(sub), into)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres"):
			into.append(dir.path_join(file))


func _test_not_reachable_from_the_game() -> void:
	var paths := PackedStringArray()
	for dir in ["res://game", "res://ui", "res://autoload", "res://core", "res://scenes", "res://data"]:
		_script_paths(dir, paths)
	var leaked := PackedStringArray()
	for path in paths:
		if FileAccess.get_file_as_string(path).contains("tools/feel_lab") or FileAccess.get_file_as_string(path).contains("FeelLab"):
			leaked.append(path)
	check(leaked.is_empty(), "the lab is not referenced by game files: %s" % ", ".join(leaked))
	check(not String(ProjectSettings.get_setting("application/run/main_scene", "")).contains("feel_lab"), "the lab is not the main scene")


func _test_lab_runs() -> void:
	var lab := (load(LAB_SCENE) as PackedScene).instantiate() as FeelLab
	runner.get_tree().root.add_child(lab)
	var waited := 0
	while lab.player == null and waited < 100:
		await runner.get_tree().create_timer(0.1, true, false, true).timeout
		waited += 1
	check(lab.player != null and lab.panel != null, "the lab builds a real player and its panel")
	if lab.player == null:
		lab.queue_free()
		return
	check(lab.player is Player, "the lab uses the game's real player")
	# 每一種真實敵人都能重生。
	var ids := lab.enemy_ids()
	check(ids.size() >= 15, "every enemy is listed (%d)" % ids.size())
	var spawned := 0
	for id in ids:
		if lab.spawn_enemy(id) != null:
			spawned += 1
	check(spawned == ids.size(), "every enemy can be respawned (%d of %d)" % [spawned, ids.size()])
	await runner.get_tree().physics_frame
	await runner.get_tree().physics_frame
	lab.clear_all()
	await physics_frames(3)
	check(runner.get_tree().get_nodes_in_group(&"enemies").is_empty(), "clear removes every enemy")
	# 材質靶與移動靶。
	for material in HitFeedback.material_ids():
		lab.spawn_material_target(StringName(material))
	var mover := lab.spawn_material_target(&"metal", true)
	await physics_frames(5)
	check(runner.get_tree().get_nodes_in_group(&"feel_lab_targets").size() == HitFeedback.material_ids().size() + 1, "a target exists for every material plus a moving one")
	var start_x := mover.position.x
	await physics_frames(30)
	check(not is_equal_approx(mover.position.x, start_x), "the moving target moves")
	# 預兆靶：預兆期間閃紅，之後朝玩家開火。
	var shooter := lab.spawn_material_target(&"metal", false, true)
	shooter._attack_cooldown = 0.01
	var before_projectiles := ProjectilePool.active_count()
	await physics_frames(5)
	check(shooter.telegraph_left > 0.0, "the telegraph target warns before it fires")
	await physics_frames(int(MaterialDummy.TELEGRAPH_TIME * 60.0) + 6)
	check(ProjectilePool.active_count() > before_projectiles, "the telegraph target fires after its warning")
	# 打得到靶：用正式受擊框收傷害，且打不死。
	var info := DamageInfo.create(5, Combat.Team.PLAYER, &"lab_test")
	mover.hurtbox.receive(info)
	check(mover.hits == 1 and mover.total_damage == 5 and not mover.health.is_dead, "targets take real hits but never die")
	# 切換武器。
	for id in lab.weapon_ids():
		check(lab.equip_weapon(id), "the lab can equip weapon %s" % id)
	# 壓力模式。
	lab.set_pressure(true)
	await physics_frames(5)
	check(runner.get_tree().get_nodes_in_group(&"enemies").size() >= FeelLab.PRESSURE_COUNT, "pressure mode brings in several enemies at once")
	lab.set_pressure(false)
	check(not lab.equip_weapon("test_no_such_weapon") and lab.spawn_enemy("test_no_such_enemy") == null, "unknown weapons and enemies are reported without crashing")
	lab.clear_all()
	await physics_frames(3)
	lab.queue_free()
	await physics_frames(3)
