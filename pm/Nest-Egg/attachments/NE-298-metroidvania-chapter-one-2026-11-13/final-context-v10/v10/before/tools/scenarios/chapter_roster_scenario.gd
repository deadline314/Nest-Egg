extends "res://tools/scenarios/scenario_base.gd"
## Actual placed enemies, frozen for comparable roster review frames.
func run() -> void:
	var variant := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):
			variant = arg.trim_prefix("--variant=")
	Story.auto_skip = true
	for target in [
		["legacy", "level_01", 185, 20],
		["street", "ch1_street", 98, 20],
		["shaft", "level_02", 112, 14],
		["mezzanine", "level_02", 174, 20],
		["power", "level_02", 360, 20],
		["ward", "level_02", 455, 20],
	]:
		GameState.start_new_run(GameState.difficulties[1])
		for id in Story.scene_ids():
			Story._seen[StringName(id)] = true
		var data := (load("res://data/levels/%s.tres" % target[1]) as LevelData).duplicate()
		data.intro_scene = &""
		data.show_chapter_card = false
		level = Level.new()
		level.configure(data)
		add_child(level)
		await settle(5)
		player = level.player
		player.health.setup(9999, 0.0)
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			enemy.set_physics_process(false)
		player.global_position = Vector2((float(target[2]) + 0.5) * 16, float(target[3]) * 16)
		player.velocity = Vector2.ZERO
		snap_camera()
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			enemy._drive_rig(0.0)
			enemy._drive_creature(0.0)
		await settle(5)
		capture("NE-97-%s-%s" % [target[0], variant])
		level.queue_free()
		await settle(5)
	await settle(10)
