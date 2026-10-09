extends Node
## BG-19: fixed native Forward+ comparisons without teleporting indoor players above the ceiling.

const SPOTS := [["level_01", 32], ["level_01", 64], ["ch1_pawnshop", 91], ["level_01", 84], ["level_01", 250], ["level_01", 324], ["level_02", 198], ["level_02", 400], ["ch1_rooftop", 22], ["ch1_street", 105], ["ch1_pawnshop", 55], ["ch1_stall", 22], ["ch1_lounge", 24], ["ch1_booth_alley", 28], ["ch1_vault", 18], ["ch1_warehouse", 34], ["ch1_pawnshop_dawn", 55]]
const ViewportCapture := preload("res://tools/viewport_capture.gd")

func _ready() -> void:
	var out := "C:/tmp/scenery-baseline"
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	for spot in SPOTS:
		if not only.is_empty() and not only.has("%s:%d" % [spot[0], spot[1]]):
			continue
		GameState.start_new_run(GameState.difficulties[1])
		var level := Level.new()
		var level_data := (load("res://data/levels/%s.tres" % spot[0]) as LevelData).duplicate() as LevelData
		level_data.show_chapter_card = false
		level_data.intro_scene = &""
		for id in Story.scene_ids():
			Story._seen[StringName(id)] = true
		level.configure(level_data)
		add_child(level)
		for i in 15:
			await get_tree().process_frame
		level.hud.visible = false
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			enemy.queue_free()
		var layout := level._layout
		var x := int(spot[1])
		var feet := layout.floor_below(x, int(layout.player_start.y / layout.tile_size) - 1)
		level.player.global_position = Vector2(x * layout.tile_size + 8, feet - 1)
		level.player.velocity = Vector2.ZERO
		level.player.health.setup(9999, 0)
		level.process_mode = Node.PROCESS_MODE_DISABLED
		_hide_prompts(level)
		var camera := get_viewport().get_camera_2d()
		if camera != null:
			(camera as LevelCamera).snap_to_target()
			camera.reset_smoothing()
			camera.force_update_scroll()
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/BG-19-%s-%d.png" % [out, spot[0], x]
		ViewportCapture.image(get_viewport()).save_png(path)
		print("[scenery_capture] " + path)
		level.queue_free()
		for i in 3:
			await get_tree().process_frame
	get_tree().quit()


func _hide_prompts(node: Node) -> void:
	if node is WorldPrompt or node is MapBubbles:
		(node as CanvasItem).visible = false
	if node is ChapterCard:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_prompts(child)
