extends ScenarioBase
## NE-238 real Forward+ atlas and dense in-level flight. No texture/model preload.
## godot --path . res://tools/projectile_visual_capture.tscn -- --out=<absolute dir>
const Capture := preload("res://tools/viewport_capture.gd")
const GUNS := ["pistol", "rifle", "smg", "spread", "laser", "railgun", "launcher", "mech_cannon"]

class LegacyBullet extends Node2D:
	var spec: ProjectileSpec
	func _draw() -> void:
		var half := maxf(spec.length, spec.radius * 2.0) * 0.5
		var tail := clampf(spec.speed * 0.02, 0.0, 14.0)
		var glow := LightKit.glow(spec.color, 2.0)
		draw_line(Vector2(-half - tail, 0), Vector2(-half, 0), Color(spec.color, 0.35), spec.radius)
		draw_line(Vector2(-half + spec.radius, 0), Vector2(half - spec.radius, 0), glow, spec.radius * 2.0)
		draw_circle(Vector2(-half + spec.radius, 0), spec.radius, glow)
		draw_circle(Vector2(half - spec.radius, 0), spec.radius, glow)
		draw_line(Vector2(-half + spec.radius, 0), Vector2(half - spec.radius, 0), LightKit.glow(Palette.WHITE, 2.5), maxf(1.0, spec.radius * 0.8))


func _ready() -> void:
	out_dir = "res://pm/Nest-Egg/images"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var original_quality := Settings.get_light_quality()
	print("NE238_RENDERER ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	for quality in [LightQuality.Tier.HIGH, LightQuality.Tier.LOW]:
		Settings.set_light_quality(quality)
		await _atlas(quality)
		for bright in [false, true]:
			await _live(quality, bright)
	Settings.set_light_quality(original_quality)
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await wait(0.3)
	get_tree().quit()


func _label(parent: Node, text: String, at: Vector2, color := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _atlas(quality: int) -> void:
	var board := Node2D.new()
	add_child(board)
	ProjectilePool.bind_container(board)
	_label(board, "NE-238 / flight heads at 2x / %s / dim rear geometry = decoration" % LightQuality.NAMES[quality], Vector2(10, 2))
	for bright in [false, true]:
		var offset := 320.0 if bright else 0.0
		var background := Polygon2D.new()
		background.polygon = PackedVector2Array([Vector2(offset, 24), Vector2(offset + 320, 24), Vector2(offset + 320, 342), Vector2(offset, 342)])
		background.color = Color(0.74, 0.73, 0.69) if bright else Color(0.065, 0.08, 0.1)
		background.z_index = -1
		LightKit.mark_emissive(background)
		board.add_child(background)
		var label_color := Color(0.1, 0.12, 0.15) if bright else Color.WHITE
		_label(board, "Gun", Vector2(offset + 5, 27), label_color)
		_label(board, "Old", Vector2(offset + 82, 27), label_color)
		_label(board, "Player", Vector2(offset + 144, 27), label_color)
		_label(board, "Hostile", Vector2(offset + 207, 27), label_color)
		_label(board, "Reflected", Vector2(offset + 263, 27), label_color)
		for row in GUNS.size():
			var y := 62.0 + row * 37.0
			var weapon := load("res://data/weapons/%s.tres" % GUNS[row]) as WeaponData
			_label(board, GUNS[row], Vector2(offset + 5, y - 8), label_color)
			var legacy := LegacyBullet.new()
			legacy.spec = weapon.projectile
			legacy.scale = Vector2.ONE * 2.0
			legacy.position = Vector2(offset + 110, y)
			LightKit.mark_emissive(legacy)
			board.add_child(legacy)
			# Spawn another type, reflect it, then recycle into each final sample.
			for column in 3:
				var at := Vector2(offset + 169 + column * 63, y)
				var previous := ProjectilePool.spawn(load("res://data/projectiles/grenade.tres"), at, Vector2.RIGHT, Combat.Team.ENEMY)
				previous._reflect(Vector2.LEFT)
				previous.deactivate()
				var bullet := ProjectilePool.spawn(weapon.projectile, at, Vector2.RIGHT, Combat.Team.ENEMY if column == 1 else Combat.Team.PLAYER)
				bullet.set_physics_process(false)
				if column == 2:
					bullet.team = Combat.Team.ENEMY
					bullet._reflect(Vector2.RIGHT)
					bullet.set_physics_process(false)
				bullet.scale = Vector2.ONE * 2.0
				for age in 6:
					bullet._trail_head = age
					bullet._trail[age] = at - Vector2(weapon.projectile.speed / 60.0 * (5 - age), 0)
				bullet._trail_len = 6
				bullet.queue_redraw()
	await settle(3)
	await RenderingServer.frame_post_draw
	capture("NE-238-atlas-%s" % ("high" if quality == LightQuality.Tier.HIGH else "low"))
	board.queue_free()
	await settle(3)


func _live(quality: int, bright: bool) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var data := (load("res://data/levels/ch1_street.tres") as LevelData).duplicate()
	data.show_chapter_card = false
	data.intro_scene = &""
	if bright:
		var zone := LightingZone.new()
		zone.start_tile = 0
		zone.profile = load("res://data/lighting/neutral.tres")
		var zones: Array[LightingZone] = [zone]
		data.lighting_zones = zones
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(25)
	for entity in level._entities.get_children():
		if entity is HintSign:
			entity.queue_free()
	await clear_enemies()
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	var floor_y := level._layout.floor_below(52, 16)
	player.global_position = Vector2(52 * 16, floor_y)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	snap_camera()
	await settle(3)
	# Actual physics flight at 60Hz, both teams and all eight real gun resources.
	for row in GUNS.size():
		var weapon := load("res://data/weapons/%s.tres" % GUNS[row]) as WeaponData
		for shot in 4:
			var at := player.global_position + Vector2(24 + shot * 24, -20 - row * 10)
			ProjectilePool.spawn(weapon.projectile, at, Vector2.RIGHT, Combat.Team.PLAYER)
			if row < 4:
				ProjectilePool.spawn(weapon.projectile, at + Vector2(135, -5), Vector2.LEFT, Combat.Team.ENEMY)
	for i in 3:
		await get_tree().physics_frame
	for node in ProjectilePool.container().get_children():
		if node is Projectile:
			node.set_physics_process(false)
	await RenderingServer.frame_post_draw
	capture("NE-238-live-%s-%s" % ["bright" if bright else "dark", "high" if quality == LightQuality.Tier.HIGH else "low"])
	await finish()
