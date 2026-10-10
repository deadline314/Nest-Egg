extends "res://tools/scenarios/scenario_base.gd"
## Private pre-fix Warden core origin capture. Does not change Enemy/Warden code or rig/art.

const PROBE_SCRIPT := preload("res://.godot/ne81-core-origin-native/warden_origin_probe.gd")
const CASES := [
	{"name": "identity", "parent_position": Vector2.ZERO, "rotation": 0.0, "scale": Vector2.ONE, "local_position": Vector2(480.0, 320.0)},
	{"name": "translated", "parent_position": Vector2(38.0, -18.0), "rotation": 0.0, "scale": Vector2.ONE, "local_position": Vector2(480.0, 320.0)},
	{"name": "scaled_1p5", "parent_position": Vector2(480.0, 320.0), "rotation": 0.0, "scale": Vector2.ONE * 1.5, "local_position": Vector2.ZERO},
	{"name": "rotated_plus_0p15", "parent_position": Vector2(480.0, 320.0), "rotation": 0.15, "scale": Vector2.ONE, "local_position": Vector2.ZERO},
	{"name": "rotated_minus_0p15", "parent_position": Vector2(480.0, 320.0), "rotation": -0.15, "scale": Vector2.ONE, "local_position": Vector2.ZERO},
]
const GAME_ZOOM := 1.5
const CLOSE_ZOOM := 1.8

var _out := ""
var _label := "before-b4"
var _expected_origin := "legacy"
var _parse_only := false
var _failures := 0
var _records: Array[Dictionary] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
		elif arg.begins_with("--expected-origin="):
			_expected_origin = arg.trim_prefix("--expected-origin=")
		elif arg == "--parse-only":
			_parse_only = true
	if _expected_origin not in ["legacy", "world"]:
		push_error("[NE81 core origin] expected-origin must be legacy or world")
		get_tree().quit(2)
		return
	if _parse_only:
		print("NE81_CORE_ORIGIN_PARSE_OK expected_origin=%s" % _expected_origin)
		get_tree().quit(0)
		return
	if _out.is_empty():
		_out = "D:/NestEggVerification/ne81-core-origin-native/before-b4"
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(LightKit.create_environment())
	_run_probe.call_deferred()


func _run_probe() -> void:
	await open_arena("res://data/lighting/hangar.tres", 24.0)
	var data := load("res://data/enemies/warden.tres") as EnemyData
	if data == null or data.max_health != 90:
		push_error("[NE81 core origin] Warden EnemyData missing or max_health != 90")
		_failures += 1
		_finish_report()
		return
	for case_def: Dictionary in CASES:
		for facing: int in [1, -1]:
			await _run_case(data, case_def, facing)
	var report := {
		"base": "b4c186ea401dfb29b92e28a0a9c8e7de46f604e3",
		"label": _label,
		"expected_origin": _expected_origin,
		"variant": "before: D game/enemies/warden_boss.gd unchanged; probe subclass calls super._core_windup_tick",
		"actor": "real WardenBoss behavior subclass + res://data/enemies/warden.tres, EnemyData max_health retained at 90",
		"core_attack": "phase2 FSM core_windup telegraph then actual _core_windup_tick and WeaponSystem.fire_spread boss_fan x3",
		"transforms": "identity, translated, scaled parent 1.5, rotated parent +/-0.15 radians; both requested facings",
		"renderer": "Forward+ Vulkan expected; verify capture log",
		"records": _records,
		"passed": _failures == 0,
		"failures": _failures,
	}
	var path := _out.path_join("core-origin-capture.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[NE81 core origin] unable to write manifest " + path)
		_failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	_finish_report(path)


func _run_case(data: EnemyData, case_def: Dictionary, requested_facing: int) -> void:
	var parent := Node2D.new()
	parent.name = "CoreOriginFixture_" + str(case_def["name"])
	parent.position = case_def["parent_position"]
	parent.rotation = case_def["rotation"]
	parent.scale = case_def["scale"]
	level._entities.add_child(parent)
	var boss = PROBE_SCRIPT.new()
	boss.configure(data)
	boss.position = case_def["local_position"]
	parent.add_child(boss)
	await settle(4)
	if boss.health == null or boss.health.max_health != 90 or boss.rig == null or not boss.rig.has_bone(&"core_port"):
		push_error("[NE81 core origin] Warden failed to build real health/rig/core_port in " + str(case_def["name"]))
		_failures += 1
		parent.queue_free()
		await settle(2)
		return
	player.global_position = boss.global_position + Vector2(float(requested_facing) * 120.0, 0.0)
	player.velocity = Vector2.ZERO
	boss.call("begin_probe_fire")
	await settle(6)
	var windup_state: String = String(boss.fsm.current)
	var local_core: Vector2 = boss.call("_core_point")
	var expected_world: Vector2 = boss.to_global(local_core)
	var legacy_world: Vector2 = local_core + boss.global_position
	var rig_core_world: Vector2 = boss.rig.bone(&"core_port").global_position
	var windup := {
		"parent_case": case_def["name"], "facing": boss.facing,
		"windup_state": windup_state, "telegraphing": boss.is_telegraphing(),
		"hp": boss.health.current, "max_hp": boss.health.max_health,
		"local_core": [local_core.x, local_core.y],
		"expected_core_world": [expected_world.x, expected_world.y],
		"legacy_formula_world": [legacy_world.x, legacy_world.y],
		"legacy_to_expected_error": legacy_world.distance_to(expected_world),
		"rig_core_bone_world": [rig_core_world.x, rig_core_world.y],
		"local_to_bone_error": expected_world.distance_to(rig_core_world),
	}
	await _capture_frame(boss, case_def, requested_facing, "windup", GAME_ZOOM)
	await _capture_frame(boss, case_def, requested_facing, "windup", CLOSE_ZOOM)
	await wait(maxf(0.05, data.telegraph_time * 0.8 + 0.12))
	await settle(2)
	var fire_probe: Dictionary = boss.get("core_fire_probe")
	if fire_probe.is_empty() or int(fire_probe.get("spawn_count", 0)) != 3:
		push_error("[NE81 core origin] expected three actual boss_fan projectiles case=%s face=%d state=%s probe=%s" % [case_def["name"], requested_facing, boss.fsm.current, fire_probe])
		_failures += 1
	else:
		var world_array: Array = fire_probe["expected_core_world"]
		var expected_fire := Vector2(float(world_array[0]), float(world_array[1]))
		for shot: Dictionary in fire_probe["spawned_projectiles"]:
			var p: Array = shot["global_position"]
			var actual_fire := Vector2(float(p[0]), float(p[1]))
			var legacy_array: Array = fire_probe["legacy_formula_world"]
			var legacy_fire := Vector2(float(legacy_array[0]), float(legacy_array[1]))
			var world_error := actual_fire.distance_to(expected_fire)
			var legacy_error := actual_fire.distance_to(legacy_fire)
			var required_error := world_error if _expected_origin == "world" else legacy_error
			if required_error > 0.05:
				push_error("[NE81 core origin] projectile origin did not match requested %s origin case=%s face=%d error=%.6f" % [_expected_origin, case_def["name"], requested_facing, required_error])
				_failures += 1
			# Pure translation leaves a local offset numerically unchanged; only scale/rotation reveal the bug.
			if _expected_origin == "legacy" and case_def["name"] not in ["identity", "translated"] and float(fire_probe["legacy_to_expected_error"]) <= 0.5:
				push_error("[NE81 core origin] transformed control did not separate legacy and world origins case=%s" % case_def["name"])
				_failures += 1
			print("NE81_CORE_ORIGIN_SHOT case=%s face=%d actual=%s world_error=%.6f legacy_error=%.6f" % [case_def["name"], requested_facing, actual_fire, world_error, legacy_error])
	windup["fire_state"] = String(boss.fsm.current)
	windup["core_fire_probe"] = fire_probe
	_records.append(windup)
	await _capture_frame(boss, case_def, requested_facing, "fired", GAME_ZOOM)
	await _capture_frame(boss, case_def, requested_facing, "fired", CLOSE_ZOOM)
	ProjectilePool.clear_in_radius(boss.global_position, 10000.0, Combat.Team.ENEMY)
	parent.queue_free()
	await settle(3)


func _capture_frame(boss: Node2D, case_def: Dictionary, facing: int, stage: String, zoom_value: float) -> void:
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera == null:
		push_error("[NE81 core origin] LevelCamera missing")
		_failures += 1
		return
	if is_equal_approx(zoom_value, GAME_ZOOM):
		camera.set_physics_process(true)
		camera.target = boss
		camera.zoom = Vector2.ONE * GAME_ZOOM
		camera.snap_to_target()
	else:
		camera.target = null
		camera.zoom = Vector2.ONE * CLOSE_ZOOM
		camera.global_position = boss.global_position + Vector2(0.0, -float(boss.data.body_size.y) * 0.35)
		camera.offset = Vector2.ZERO
		camera.reset_smoothing()
		camera.set_physics_process(false)
	await settle(2)
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var tag := "%s_face%+d_%s_z%s" % [case_def["name"], facing, stage, str(zoom_value).replace(".", "p")]
	var path := _out.path_join(tag + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("[NE81 core origin] image save failed %s (%s)" % [path, error_string(error)])
		_failures += 1
	print("NE81_CORE_ORIGIN_FRAME %s state=%s facing=%d zoom=%.1f path=%s" % [case_def["name"], stage, facing, zoom_value, path])


func _finish_report(path := "") -> void:
	print("NE81_CORE_ORIGIN_CAPTURE records=%d failures=%d manifest=%s" % [_records.size(), _failures, path])
	get_tree().quit(0 if _failures == 0 else 1)
