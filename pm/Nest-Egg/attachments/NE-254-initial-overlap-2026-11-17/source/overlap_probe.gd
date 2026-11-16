extends Node

var level: Level
var checks := 0
var failures := 0
var out := ""
var results: Array[Dictionary] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	assert(not out.is_empty())
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _run() -> void:
	Story.auto_skip = true
	Enemy.activation_culling_enabled = false
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load("res://data/levels/ch1_street.tres"))
	add_child(level)
	await _frames(30)
	for node in get_tree().get_nodes_in_group(&"enemies"): node.queue_free()
	for node in get_tree().get_nodes_in_group(Throwable.GROUP): node.queue_free()
	await _frames(3)
	var player := level.player
	var floor_y := float(level._layout.floor_below(95, 4)) * 16.0
	player.global_position = Vector2(95 * 16, floor_y)
	player.velocity = Vector2.ZERO
	player.health.setup(999, 0)
	player.health.grant_invulnerability(600)
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null: camera.snap_to_target()
	await _frames(240)
	for path: String in ["res://data/throwables/pipe.tres", "res://data/throwables/crate_small.tres"]:
		var item := Throwable.new()
		item.configure(load(path))
		item.global_position = player.global_position + Vector2(12, 0)
		level._entities.add_child(item)
		await _frames(10)
		Input.action_press(&"interact")
		await _frames(2)
		Input.action_release(&"interact")
		for frame in 90:
			if player.carry.phase == PlayerCarry.Phase.HOLDING: break
			await _frames(1)
		_check(player.carry.held == item and player.carry.phase == PlayerCarry.Phase.HOLDING, "public interact lifts " + String(item.data.id))
		AimInput.set_virtual_gamepad(player, true)
		Input.action_press(&"aim_right")
		await _frames(4)
		var enemy := level._create_enemy(load("res://data/enemies/drone.tres"))
		level._entities.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.global_position = item.world_center() + Vector2(0, enemy.data.body_size.y * 0.5)
		await _frames(3)
		var initial_health := enemy.health.current
		var tag := String(item.data.id)
		await _capture(tag + "-before-throw")
		var initial_overlap := item.world_center().distance_to(enemy.hurtbox.center())
		Input.action_press(&"shoot")
		await _frames(2)
		Input.action_release(&"shoot")
		await _frames(10)
		var health_after := enemy.health.current
		_check(health_after < initial_health, "public throw hits already overlapping " + tag)
		results.append({"item": tag, "initial_center_distance": initial_overlap, "health_before": initial_health, "health_after": health_after})
		await _capture(tag + "-after-throw")
		enemy.queue_free()
		if is_instance_valid(item): item.queue_free()
		Input.action_release(&"aim_right")
		AimInput.set_virtual_gamepad(player, false)
		await _frames(30)
	var file := FileAccess.open(out.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": results, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	level.queue_free()
	await _frames(10)
	print("checks: %d, failures: %d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var err := img.save_png(out.path_join(tag + ".png"))
	_check(err == OK, "capture " + tag)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)
