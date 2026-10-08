extends ScenarioBase
## Reproduce clothing debris through actual fatal hits, using native game rendering.

func _ready() -> void:
	_review.call_deferred()


func _review() -> void:
	var legacy := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg == "--legacy-debris": legacy = true
		else:
			_fail("unknown argument " + arg)
			return
	if out_dir.is_empty() or DisplayServer.get_name() == "headless" or not get_viewport().use_hdr_2d:
		_fail("requires an output directory and native HDR 2D rendering")
		return
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		_fail("cannot create " + out_dir)
		return
	if legacy: RigLibrary.character("rin")["armor_debris"] = true
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	var rows: Array[Dictionary] = []
	for facing in [1, -1]:
		for side in [1, -1]:
			await open_arena("res://data/lighting/neutral.tres", 18.0)
			await clear_enemies()
			await settle(2)
			seed(222211)
			player.facing = facing
			var info := DamageInfo.create(9999, Combat.Team.ENEMY, &"rig_debris_review")
			info.origin = player.global_position + Vector2(side * 30, 0)
			info.ignore_invulnerability = true
			var before := RigDebris._active
			player.health.take_damage(info)
			var spawned := RigDebris._active - before
			if not player.is_dead() or (spawned <= 0 if legacy else spawned != 0):
				_fail("unexpected debris count after fatal hit: " + str(spawned))
				return
			var previous := 0.0
			for time in [0.0, 0.12, 0.28, 0.55, 0.99]:
				if time > previous: await wait(time - previous)
				previous = time
				await RenderingServer.frame_post_draw
				var name := "face%d_hit%d_%03d.png" % [facing, side, roundi(time * 100)]
				var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
				if image.save_png(out_dir.path_join(name)) != OK:
					_fail("cannot save " + name)
					return
				rows.append({"file": name, "facing": facing, "source_side": side, "requested_seconds": time, "legacy_debris": legacy, "spawned_body_parts": spawned, "active_debris": RigDebris._active, "window_size": [image.get_width(), image.get_height()]})
			await finish()
	var file := FileAccess.open(out_dir.path_join("samples.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot save samples.json")
		return
	file.store_string(JSON.stringify(rows, "\t"))
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("[rig_debris_review] " + message)
	get_tree().quit(1)
