extends ScenarioBase
## Diagnostic: real Player HP events, fixed aim/camera; no input or combat-play acceptance.

var records: Array[Dictionary] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await run()
	var file := FileAccess.open(out_dir.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	await finish()
	RigDebris.clear_pool()
	RigLibrary.clear_cache()
	await settle(3)
	get_tree().quit()

func run() -> void:
	seed(22228)
	await open_arena("res://data/lighting/neutral.tres", 20.0)
	player.set_physics_process(false)
	level.camera.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	level.camera.limit_left = -100000
	level.camera.limit_right = 100000
	level.camera.limit_top = -100000
	level.camera.limit_bottom = 100000
	level.camera.offset = Vector2.ZERO
	level._post.visible = false
	level._fog.visible = false
	for face in [1, -1]:
		player.facing = face
		player.aim_dir = Vector2(face, 0.0)
		for zoom in [1.0, 3.4]:
			level.camera.zoom = Vector2.ONE * zoom
			level.camera.global_position = player.global_position + Vector2(0.0, -26.0)
			player.health.setup(6, 0.0)
			player.velocity = Vector2.ZERO
			await wait(0.7)
			shot(face, zoom, 0, "intact")
			for hit in range(1, 6):
				var info := DamageInfo.create(1, Combat.Team.ENEMY, &"test_cloth")
				info.ignore_invulnerability = true
				info.origin = player.global_position + Vector2(-face * 40.0, -20.0)
				player.health.take_damage(info)
				player.velocity = Vector2.ZERO
				await wait(0.23)
				shot(face, zoom, hit, "tear")
				await wait(0.5)
				shot(face, zoom, hit, "settled")
			player.health.heal(6)
			await wait(0.7)
			shot(face, zoom, 0, "healed")

func shot(face: int, zoom: float, hit: int, phase: String) -> void:
	var name := "face%d_zoom%s_hit%d_%s" % [face, str(zoom).replace(".", "p"), hit, phase]
	capture(name)
	var cloth: Array[Dictionary] = []
	if Fx._soft != null:
		for i in ParticleField.CAPACITY:
			if Fx._soft._life[i] > 0.0 and Fx._soft._cell[i] == VfxAtlas.Cell.SHARD:
				cloth.append({"position": [Fx._soft._pos[i].x, Fx._soft._pos[i].y], "color": str(Fx._soft._col0[i])})
	records.append({"image": name + ".png", "hp": player.health.current, "face": face,
		"camera_zoom": zoom, "phase": phase, "cloth_shards": cloth, "rig_debris": RigDebris._active,
		"aim": [player.aim_dir.x, player.aim_dir.y], "hdr_2d": get_viewport().use_hdr_2d})
