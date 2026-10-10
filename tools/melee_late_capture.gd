extends ScenarioBase
## NE-236 自然掃擊取證；不手動呼叫命中判定或 thaw 攻擊者。
class PhysicsPulse extends Node:
	var ticks := 0
	func _physics_process(_delta: float) -> void:
		ticks += 1


func _ready() -> void:
	out_dir = "res://pm/Nest-Egg/images"
	_run.call_deferred()


func _run() -> void:
	print("NE236_LATE_RENDERER ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	Story.auto_skip = true
	await open_arena("res://data/lighting/neutral.tres", 12.0)
	var camera := get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE * 3.4
	camera.global_position = player.global_position + Vector2(24, -32)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	player.loadout.reset(load("res://data/weapons/melee/melee_blade.tres"))
	var first := _target(24.0)
	var late := _target(150.0)
	var pulse := PhysicsPulse.new()
	level.add_child(pulse)
	var hits: Array[Dictionary] = []
	late.health.damaged.connect(func(info: DamageInfo) -> void:
		hits.append({"damage": info.amount, "velocity_x": late.velocity.x, "stun": late._stun_left,
			"flash": late._flash_left, "true_attacker": info.attacker.get_ref() == player,
			"freeze_attacker": info.freeze_attacker, "phase": player._melee_phase, "third_ticks": pulse.ticks}))
	await settle(5)
	player._try_melee()
	var limit := 120
	while not player._melee_feedback_done and limit > 0:
		await get_tree().physics_frame
		limit -= 1
	await get_tree().process_frame
	if player._melee_phase != Player.MeleePhase.ACTIVE or first.health.current >= 999:
		push_error("natural first contact did not leave an ACTIVE sweep")
		get_tree().quit(1)
		return
	var ticks_before := pulse.ticks
	late.global_position.x = player.global_position.x + 24.0
	limit = 120
	while hits.is_empty() and player._melee_phase != Player.MeleePhase.NONE and limit > 0:
		await get_tree().physics_frame
		limit -= 1
	await get_tree().process_frame
	if hits.size() != 1 or is_zero_approx(float(hits[0].velocity_x)) or bool(hits[0].freeze_attacker) or Fx._frozen.has(player) or pulse.ticks <= ticks_before:
		push_error("natural late contact lost damage, own reaction or bounded attacker pause")
		get_tree().quit(1)
		return
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var label := Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 16)
	overlay.add_child(label)
	label.text = "Natural sweep / late HP %d / one hit / own knockback %.0f / third physics %d" % [late.health.current, hits[0].velocity_x, pulse.ticks]
	await RenderingServer.frame_post_draw
	capture("NE-236-natural-late-contact")
	print("NE236_LATE_CAPTURE ", JSON.stringify({"hits": hits, "first_hp": first.health.current, "late_hp": late.health.current,
		"third_before": ticks_before, "third_after": pulse.ticks, "phase_at_image": player._melee_phase, "attacker_frozen": Fx._frozen.has(player), "zoom": str(camera.zoom)}))
	limit = 120
	while player._melee_phase != Player.MeleePhase.NONE and limit > 0:
		await get_tree().physics_frame
		limit -= 1
	if hits.size() != 1 or player._melee_phase != Player.MeleePhase.NONE:
		push_error("natural swing did not recover with exactly one late damage event")
		get_tree().quit(1)
		return
	label.text = "Recovered / late HP %d / hits %d / third physics %d" % [late.health.current, hits.size(), pulse.ticks]
	await RenderingServer.frame_post_draw
	capture("NE-236-natural-late-recovered")
	await finish()
	get_tree().quit()


func _target(offset: float) -> Enemy:
	var enemy := spawn_enemy("res://data/enemies/grunt.tres", 12.0)
	enemy.global_position = player.global_position + Vector2(offset, 0)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.health.setup(999, 0.0)
	return enemy
