extends Node2D
## NE-239 presentation samples. Run only with an isolated APPDATA profile.
## Boards are staged samples; the final frames exercise real input and projectiles.
## Neither replaces physical controller or full-chapter playtests.
const Capture := preload("res://tools/viewport_capture.gd")
var _out := ""
var _failed := false
## --reduced：「減少閃光」打開、畫面震動倍率 0（「減少動態」）時再拍一次亮暗兩張，檔名加 -reduced（只寫在隔離的設定檔裡）。
var _reduced := false

class LegacyField extends Node2D:
	var actor: Player
	func _draw() -> void:
		var origin := to_local(actor.aim_origin()) + actor.aim_dir * 6.0
		var angle := actor.aim_dir.angle()
		var half_arc := deg_to_rad(actor.tuning.block_arc_degrees * 0.5) * 0.8
		draw_arc(origin, 15.0, angle - half_arc, angle + half_arc, 16, Color(LightKit.glow(Palette.CYAN, 1.4), 0.25), 7.0)
		draw_arc(origin, 15.0, angle - half_arc, angle + half_arc, 16, LightKit.glow(Palette.CYAN, 1.4), 1.5)


func _ready() -> void:
	var profile := OS.get_environment("NE239_CAPTURE_PROFILE").replace("\\", "/").simplify_path()
	var actual := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path()
	if profile.is_empty() or not actual.to_lower().begins_with(profile.to_lower() + "/"):
		_failed = true
		push_error("[NE239] Capture requires an isolated APPDATA profile; refusing user-data writes.")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--reduced":
			_reduced = true
	if _out.is_empty() or not _out.is_absolute_path():
		_failed = true
		push_error("[NE239] Missing absolute --out path.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	GameState.story_autosave = false
	_run.call_deferred()


func _run() -> void:
	print("NE239_RENDERER ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	get_window().size = Vector2i(1280, 720)
	DisplayMode.ensure_scaling(get_window())
	var sample_environment := LightKit.create_environment()
	add_child(sample_environment)
	for frame in 4:
		await get_tree().process_frame
	if _reduced:
		Settings.set_reduce_flashes(true)
		Settings.set_feel_scale("shake", 0.0)
	for bright in [false, true]:
		var board := Node2D.new()
		add_child(board)
		var background := Polygon2D.new()
		background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)])
		background.color = Color(0.74, 0.73, 0.69) if bright else Color(0.05, 0.065, 0.09)
		LightKit.mark_emissive(background)
		board.add_child(background)
		var labels := ["Old / Hold", "Raise / Low energy", "Block / Parry", "Aim up / Aim down", "Left / Right", "Break / Lower"]
		for cell in 6:
			var offset := Vector2((cell % 3) * 213, (cell / 3) * 180)
			_label(board, labels[cell], offset + Vector2(8, 7), Color(0.1, 0.12, 0.15) if bright else Color.WHITE)
			for side in 2:
				var actor := Player.new()
				actor.configure(load("res://data/player/player_tuning.tres"), GameState.difficulty.player_max_health, {})
				actor.position = offset + Vector2(53 + side * 106, 152)
				board.add_child(actor)
				actor.set_physics_process(false)
				actor._visual.set_process(false)
				actor._visual.set_physics_process(false)
				actor._light.enabled = false
				actor.is_blocking = true
				actor._block_time = 1.0
				actor.aim_dir = Vector2.LEFT if cell == 4 and side == 0 else (Vector2.UP if cell == 3 and side == 0 else (Vector2.DOWN if cell == 3 else Vector2.RIGHT))
				actor.facing = -1 if actor.aim_dir.x < 0 else 1
				actor._visual._input.blocking = true
				actor._visual._input.on_floor = true
				actor._visual._input.aim_dir = actor.aim_dir
				actor._visual._input.facing = actor.facing
				for frame in 8:
					actor._visual.rig.animate(1.0 / 60.0, actor._visual._input)
				if cell == 0 and side == 0:
					var legacy := LegacyField.new()
					legacy.actor = actor
					LightKit.mark_emissive(legacy)
					actor._visual.add_child(legacy)
				else:
					actor._visual._shield.update(1.0, true, false, actor.aim_dir, actor.tuning.block_arc_degrees)
					if cell == 1:
						if side == 0:
							actor._visual._shield.extension = 0.45
						else:
							actor.guard = 20.0
					if cell == 2:
						if side == 0:
							actor._visual.notify_block(ShieldSurface.contact(actor.global_position + Vector2(0, -22), Vector2(1, -0.6), actor.aim_dir))
						else:
							actor._block_time = 0.0
							actor._visual.notify_parry()
					if cell == 5:
						actor.is_blocking = false
						actor._visual._shield.update(0.06, false, side == 0, actor.aim_dir, actor.tuning.block_arc_degrees)
				actor._visual.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := _out.path_join("NE-239-shield-%s%s.png" % ["bright" if bright else "dark", "-reduced" if _reduced else ""])
		var result := Capture.image(get_viewport()).save_png(path)
		if result != OK:
			_failed = true
			push_error("[NE239] Cannot save %s: %s" % [path, error_string(result)])
			get_tree().quit(1)
			return
		print("NE239_CAPTURE ", path)
		board.queue_free()
		await get_tree().process_frame
	sample_environment.queue_free()
	await get_tree().process_frame
	if _reduced:
		get_tree().quit(1 if _failed else 0)
		return
	await _combat_capture()
	get_tree().quit(1 if _failed else 0)


func _label(parent: Node, text: String, at: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


## Use actual first-chapter geometry, lighting and actors. Suppress entry dialogue in
## this isolated sample so it cannot obscure the shield; story logic is not tested.
func _combat_capture() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var data := (load("res://data/levels/ch1_pawnshop.tres") as LevelData).duplicate() as LevelData
	data.intro_scene = &""
	data.channel_scenes = {}
	var level := Level.new()
	level.configure(data)
	add_child(level)
	for frame in 30:
		await get_tree().physics_frame
	var actor := level.player
	actor.global_position = Vector2(65 * 16 + 8, level._layout.floor_below(65, 17) - 2)
	actor.velocity = Vector2.ZERO
	AimInput.set_virtual_gamepad(actor, true)
	Input.action_press(&"aim_right")
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null:
		camera.snap_to_target()
	await get_tree().create_timer(4.0).timeout
	if not actor.global_position.is_finite():
		_failed = true
		push_error("[NE239] Capture actor must be on a finite real floor.")
		get_tree().quit(1)
		return
	level.hud.visible = false
	var hp := actor.health.current
	var energy := actor.guard
	Input.action_press(&"block")
	for frame in 2:
		await get_tree().physics_frame
	await _combat_frame("raise")
	await get_tree().create_timer(0.25).timeout
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	ProjectilePool.spawn(spec, actor.global_position + Vector2(24, -22), Vector2.LEFT, Combat.Team.ENEMY)
	for frame in 15:
		await get_tree().physics_frame
		if actor.guard < energy:
			break
	if actor.guard >= energy or actor.health.current != hp:
		_failed = true
		push_error("[NE239] Normal block did not consume guard while preserving health.")
		get_tree().quit(1)
		return
	await _combat_frame("block")
	Input.action_release(&"block")
	await get_tree().create_timer(0.2).timeout
	Input.action_press(&"block")
	for frame in 2:
		await get_tree().physics_frame
	ProjectilePool.spawn(spec, actor.global_position + Vector2(16, -22), Vector2.LEFT, Combat.Team.ENEMY)
	for frame in 12:
		await get_tree().physics_frame
		if actor._visual._parry_flash > 0.0:
			break
	if actor._visual._parry_flash <= 0.0 or actor.health.current != hp:
		_failed = true
		push_error("[NE239] Perfect block did not reflect through the real projectile path.")
		get_tree().quit(1)
		return
	await _combat_frame("parry")
	await get_tree().create_timer(0.25).timeout
	actor.guard = 1.0
	ProjectilePool.spawn(spec, actor.global_position + Vector2(24, -22), Vector2.LEFT, Combat.Team.ENEMY)
	for frame in 15:
		await get_tree().physics_frame
		if actor.is_guard_broken():
			break
	if not actor.is_guard_broken() or actor.health.current != hp:
		_failed = true
		push_error("[NE239] Guard depletion did not break the real front shield.")
		get_tree().quit(1)
		return
	await _combat_frame("break")
	print("NE239_COMBAT normal / perfect / break: guard, health and feedback verified")
	Input.action_release(&"block")
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(actor, false)
	level.queue_free()
	for frame in 3:
		await get_tree().process_frame


func _combat_frame(state: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-239-combat-%s.png" % state)
	var result := Capture.image(get_viewport()).save_png(path)
	if result != OK:
		_failed = true
		push_error("[NE239] Cannot save %s: %s" % [path, error_string(result)])
		get_tree().quit(1)
		return
	print("NE239_CAPTURE ", path)
