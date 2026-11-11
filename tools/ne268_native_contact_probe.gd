extends ScenarioBase
## Arranged native GPU capture, using public melee/aim actions; never a physical-controller claim.
## --out=<absolute directory> [--legacy] restores only historical feedback coordinates.

var _legacy := false
var _records: Array[Dictionary] = []
var _failed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--legacy":
			_legacy = true
	if not out_dir.is_absolute_path():
		push_error("[NE268] --out requires an absolute evidence directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.use_storage(out_dir.path_join("probe-settings.cfg"))
	get_window().size = Vector2i(1280, 720)
	DisplayMode.ensure_scaling(get_window())
	GameState.story_autosave = false
	Story.auto_skip = true
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	var arena := NewEnemiesSuite.arena_data()
	# Explicit current chapter. The unassigned legacy chapter_01 shutdown failure is retained separately.
	arena.chapter = &"ch1_kasa"
	await open_arena("res://data/lighting/neutral.tres", 30.0, arena)
	await clear_enemies()
	if _legacy:
		var previous := player.melee
		player.remove_child(previous)
		previous.queue_free()
		player.melee = preload("res://tools/ne268_legacy_melee.gd").new(player)
		player.add_child(player.melee)
	var camera := get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE * 3.4
	AimInput.set_virtual_gamepad(player, true)
	for side in [1, -1]:
		await _case(side)
	AimInput.set_virtual_gamepad(player, false)
	Engine.time_scale = 1.0
	var report := {"legacy_coordinates": _legacy, "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "hdr_2d": get_viewport().use_hdr_2d,
		"zoom": 3.4, "chapter": str(arena.chapter), "arranged_arena": true, "virtual_aim": true, "records": _records, "failed": _failed}
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("NE268_REPORT ", JSON.stringify(report))
	await finish()
	get_tree().quit(1 if _failed else 0)


func _case(side: int) -> void:
	Engine.time_scale = 1.0
	player._end_melee(false)
	player.loadout.reset(load("res://data/weapons/melee/melee_maul.tres") as WeaponData)
	place_player(30.0)
	var camera := get_viewport().get_camera_2d()
	camera.global_position = player.global_position + Vector2(side * 20, -32)
	var target := spawn_enemy("res://data/enemies/grunt.tres", 30.0 + side * 2.0)
	target.data = target.data.duplicate()
	target.data.detect_range = 0.0
	target.data.attack_range = 0.0
	target.data.move_speed = 0.0
	target.health.setup(999, 0.0)
	var action := &"aim_right" if side > 0 else &"aim_left"
	Input.action_press(action)
	await wait(0.5)
	var events: Array[Dictionary] = []
	var numbers: Array[Vector2] = []
	var damage: Array[Dictionary] = []
	var on_damage := func(info: DamageInfo) -> void:
		damage.append({"amount": info.amount, "part": str(info.part), "weak": info.weak_hit,
			"contact": _vec(info.contact_point), "knockback": _vec(info.knockback), "stagger": info.stagger})
	var on_hit := func(at: Vector2, _killed: bool) -> void:
		events.append({"feedback": _vec(at), "feet": _vec(target.global_position),
			"inside_hurtbox": target.hurtbox.contains_point(at, 1.0),
			"above_feet": target.global_position.y - at.y})
	var on_number := func(at: Vector2, _amount: int, _kind: StringName, _id: int) -> void: numbers.append(at)
	target.health.damaged.connect(on_damage)
	EventBus.hit_confirmed.connect(on_hit)
	EventBus.damage_number.connect(on_number)
	Engine.time_scale = 0.1
	Input.action_press(&"melee")
	# Release before hold threshold; the ordinary first strike remains formal gameplay.
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(&"melee")
	for i in 600:
		await get_tree().physics_frame
		if not events.is_empty():
			break
	await settle(2)
	await RenderingServer.frame_post_draw
	capture("side%d-hit" % side)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await settle(1)
	await RenderingServer.frame_post_draw
	capture("side%d-after" % side)
	var okay := events.size() == 1 and damage.size() == 1 and numbers.size() == 1
	if okay:
		okay = bool(events[0].inside_hurtbox) and float(events[0].above_feet) > target.data.body_size.y * 0.4
		okay = okay and numbers[0].distance_to(Vector2(events[0].feedback[0], events[0].feedback[1])) < 0.01
	_records.append({"side": side, "events": events, "numbers": numbers.map(_vec), "damage": damage,
		"contact_checks_pass": okay, "hit_count": events.size(), "hp": target.health.current})
	if not _legacy and not okay:
		_failed = true
		push_error("[NE268] contact assertions failed for side %d" % side)
	EventBus.hit_confirmed.disconnect(on_hit)
	EventBus.damage_number.disconnect(on_number)
	Input.action_release(action)
	Engine.time_scale = 1.0
	player._end_melee(false)
	target.queue_free()
	await wait(0.6)


func _vec(value: Vector2) -> Array:
	return [value.x, value.y] if value.is_finite() else []
