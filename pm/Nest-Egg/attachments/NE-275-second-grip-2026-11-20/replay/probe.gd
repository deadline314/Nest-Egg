extends "res://tools/melee_art_probe.gd"

var _events := 0
var _emission_events := 0

func _run() -> void:
	seed(275)
	Engine.max_physics_steps_per_frame = 1
	Story.auto_skip = true
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	await open_arena("res://data/lighting/warehouse_interior.tres", 12.0)
	await clear_enemies()
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	var camera := get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.limit_enabled = false
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 2.3
	level.hud.visible = false
	var records := {}
	var connected: Sprite2D
	for id: String in ["blade","dagger","glaive","maul","whip","fallback","blade-left"]:
		var stock := id if id in WEAPONS else "blade"
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % stock) as WeaponData
		if id == "fallback":
			weapon = weapon.duplicate() as WeaponData
			weapon.id = &"missing_melee_art_probe"
		var side := -1 if id == "blade-left" else 1
		AimInput._last_stick_dir = Vector2(side,0)
		await _arm(weapon,camera)
		player.facing = side
		player.aim_dir = Vector2(side,0)
		await settle(35)
		var held := player._visual.melee_held()
		var sprite: Sprite2D = held._base_sprite
		if connected != sprite:
			sprite.draw.connect(func() -> void: _events += 1)
			held.draw.connect(func() -> void: _emission_events += 1)
			connected = sprite
		var real_art := sprite.texture != null
		_check(real_art == (id != "fallback"), "held base art case " + id)
		_check(player.facing == side, "facing case " + id)
		_events = 0
		_emission_events = 0
		var idle: Array = []
		for i in 60:
			await _step()
			if i % 10 == 0:
				idle.append(_pose(sprite,held))
		await RenderingServer.frame_post_draw
		capture(id+"-idle")
		var idle_draws := _events
		var idle_emission := _emission_events
		_events = 0
		_emission_events = 0
		var active: Array = []
		var showed := false
		Input.action_press(&"melee")
		for i in 75:
			await _step()
			if i == 1:
				Input.action_release(&"melee")
			if not showed and player.melee.is_active():
				showed = true
				await RenderingServer.frame_post_draw
				capture(id+"-attack")
			if i % 5 == 0:
				active.append(_pose(sprite,held))
		Input.action_release(&"melee")
		_check(showed, "real attack appears for " + id)
		records[id]={"idle_draws":idle_draws,"attack_draws":_events,"idle_emission":idle_emission,"attack_emission":_emission_events,"textured":real_art,
			"idle":idle,"attack":active,"visible_attack":showed,"facing":player.facing}
	var result := {"cases":records,"failures":_failures,"gpu":RenderingServer.get_video_adapter_name()}
	FileAccess.open(out_dir.path_join("base-redraw.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("NE275_BASE_REDRAW cases=", records.size(), " failures=", _failures)
	AudioRelease.begin_shutdown()
	await finish()
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if _failures == 0 else 1)

func _step() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func _pose(sprite: Sprite2D, held: MeleeHeld) -> Array:
	var t := sprite.global_transform
	return [str(t),str(held.hold()),player.melee.is_active(),player.melee_pose_progress()]

func _check(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failures += 1
