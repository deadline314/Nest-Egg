extends "res://tools/scenarios/scenario_base.gd"
## NE-118: actual chapter-two spawns and native wind-ups, without replacing lighting or terrain.
func run() -> void:
	Story.auto_skip = true
	for target in [
		["chainsaw_arm", 202, 20, 40.0], ["hydraulic_claw", 160, 20, 36.0],
		["plasma_whip", 352, 20, 90.0], ["chain_hook", 426, 20, 110.0],
	]:
		GameState.start_new_run(GameState.difficulties[1])
		for id in Story.scene_ids():
			Story._seen[StringName(id)] = true
		var data := (load("res://data/levels/level_02.tres") as LevelData).duplicate()
		data.intro_scene = &""
		data.show_chapter_card = false
		level = Level.new()
		level.configure(data)
		add_child(level)
		await settle(3)
		player = level.player
		player.health.setup(9999, 0.0)
		var focus: StrikeEnemy
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			enemy.set_physics_process(false)
			if String(enemy.data.id) == target[0]:
				focus = enemy as StrikeEnemy
			else:
				enemy.visible = false # isolate this placed encounter for review
		assert(focus != null, "Required chapter-two spawn is missing")
		player.global_position = Vector2(focus.global_position.x - float(target[3]), float(target[2]) * 16.0)
		player.velocity = Vector2.ZERO
		snap_camera()
		focus._drive_rig(0.0)
		await wait(1.2)
		capture("NE-118-%s-placement" % target[0])
		focus.set_physics_process(true)
		var frames := 0
		while not focus.fsm.is_in(&"windup") and frames < 360:
			await get_tree().physics_frame
			frames += 1
		assert(focus.fsm.is_in(&"windup"), "The placed enemy cannot reach a native wind-up")
		await wait(0.18)
		capture("NE-118-%s-chapter-windup" % target[0])
		player.end_pull()
		level.queue_free()
		await settle(5)
	await settle(10)
