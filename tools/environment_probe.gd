extends Node
## Same script, renderer and machine for BG-17 comparisons. Capture only after timing.
## --level=level_01 --quality=low --frames=180 --out=<directory>
## --spots=30,115,200: columns to stand on (defaults: three per legacy level).
## --no-characters: no enemies, player hidden and not processing. Isolates the cost of the environment itself.
## --hide=LevelBackground,PropNode: DIAGNOSTIC ONLY. Hides and stops every node of those script classes to see what each part costs.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var level_id := "level_01"
	var quality := "low"
	var frames := 180
	var out := ""
	var diagnostic_native_lighting := false
	var no_characters := false
	var hide_classes := PackedStringArray()
	var spot_columns: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level_id = arg.trim_prefix("--level=")
		if arg.begins_with("--quality="): quality = arg.trim_prefix("--quality=")
		if arg.begins_with("--frames="): frames = maxi(30, int(arg.trim_prefix("--frames=")))
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg == "--diagnostic-native-character-lighting": diagnostic_native_lighting = true
		if arg == "--no-characters": no_characters = true
		if arg.begins_with("--spots="):
			for part: String in arg.trim_prefix("--spots=").split(",", false): spot_columns.append(int(part))
		if arg.begins_with("--hide="): hide_classes = arg.trim_prefix("--hide=").split(",", false)
	if diagnostic_native_lighting:
		out = ""
		print("DIAGNOSTIC: temporary native character lighting; no production settings changed; NOT acceptance data")
	print("SAMPLER viewport_default=%d LINEAR=%d" % [get_viewport().canvas_item_default_texture_filter, Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR])
	seed(17)
	var previous := Settings.get_light_quality()
	Settings.set_light_quality({"low": 0, "medium": 1, "high": 2}.get(quality, 0))
	Story.auto_skip = true
	for id: String in Story.scene_ids(): Story._seen[StringName(id)] = true
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load("res://data/levels/%s.tres" % level_id))
	add_child(level)
	for i in 60: await get_tree().process_frame
	level.hud.visible = false
	level.player.health.setup(999, 0.0)
	for enemy in get_tree().get_nodes_in_group(&"enemies"): enemy.queue_free()
	if not hide_classes.is_empty():
		var hidden := 0
		for node: Node in level.find_children("*", "", true, false):
			var script := node.get_script() as Script
			var name := String(script.get_global_name()) if script != null else node.get_class()
			if name in hide_classes:
				node.process_mode = Node.PROCESS_MODE_DISABLED
				if node is CanvasItem:
					(node as CanvasItem).visible = false
				elif node is CanvasLayer:
					(node as CanvasLayer).visible = false
				hidden += 1
		out = ""
		print("DIAGNOSTIC hide=%s nodes=%d; NOT acceptance data" % [",".join(hide_classes), hidden])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var spots: Array = [30, 115, 200] if level_id == "level_01" else [30, 175, 350]
	if not spot_columns.is_empty(): spots = spot_columns
	for tile: int in spots:
		var y: float = level._layout.floor_below(tile, 4) - 2.0
		level.player.process_mode = Node.PROCESS_MODE_INHERIT
		level.player.global_position = Vector2(tile * 16.0 + 8.0, y)
		level.player.velocity = Vector2.ZERO
		for enemy in get_tree().get_nodes_in_group(&"enemies"): enemy.queue_free()
		for n in (0 if no_characters else 5):
			var foe: Enemy = level._create_enemy(load("res://data/enemies/grunt.tres"))
			foe.data = foe.data.duplicate()
			foe.data.detect_range = 0.0
			foe.data.attack_range = 0.0
			foe.data.move_speed = 0.0
			foe.position = Vector2((tile + 4 + n * 2) * 16.0, y)
			level._entities.add_child(foe)
		var camera := get_viewport().get_camera_2d()
		if camera != null: camera.snap_to_target()
		if no_characters:
			for i in 4: await get_tree().process_frame
			level.player.visible = false
			level.player.process_mode = Node.PROCESS_MODE_DISABLED
		for i in 120: await get_tree().process_frame
		if diagnostic_native_lighting:
			var overridden := 0
			for item: CanvasItem in level.find_children("*", "CanvasItem", true, false):
				var material := item.material as ShaderMaterial
				if material != null and material.shader != null and material.shader.resource_path == "res://art/shaders/character_light.gdshader":
					item.material = null
					overridden += 1
			print("DIAGNOSTIC tile=%d temporary_material_overrides=%d" % [tile, overridden])
			for i in 60: await get_tree().process_frame
		var times: Array[float] = []
		var draws := 0.0
		var last := Time.get_ticks_usec()
		for i in frames:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME) / float(frames)
		var total := 0.0
		for t in times: total += t
		times.sort()
		print("PROBE%s level=%s tile=%d quality=%s frames=%d mean_ms=%.3f median_ms=%.3f p95_ms=%.3f draws=%.1f renderer_texture_bytes=%d" % ["_NO_CHARACTERS" if no_characters else "", level_id, tile, quality, frames, total / frames, times[frames / 2], times[int(frames * 0.95)], draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)])
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out)
			# HDR 2D readback is linear; PNG viewers expect sRGB.
			var shot := get_viewport().get_texture().get_image()
			if get_viewport().use_hdr_2d:
				shot.convert(Image.FORMAT_RGBA8)
				shot.linear_to_srgb()
			shot.save_png(out.path_join("%s_%d_%s.png" % [level_id, tile, quality]))
	var bytes := 0
	var count := 0
	# 舊的版本沒有釋放機制；有的話先等它做完（換區域之後幾個影格才釋放）。
	for i in 12: await get_tree().process_frame
	var textures := RigLibrary._texture_cache.duplicate()
	for path: String in LitTextures._normals:
		var normal: Texture2D = LitTextures._normals[path]
		textures[normal.resource_path] = normal
	for path: String in textures:
		if not path.begins_with("res://art/environment/"): continue
		var tex: Texture2D = textures[path]
		var image := tex.get_image()
		if image == null: continue
		var size := image.get_data_size()
		bytes += size
		count += 1
		print("TEXTURE %s %dx%d format=%d mipmaps=%s bytes=%d" % [path, image.get_width(), image.get_height(), image.get_format(), image.has_mipmaps(), size])
	print("ENVIRONMENT imported_payload_bytes=%d textures=%d (cached level textures; not PNG size or dedicated GPU allocation)" % [bytes, count])
	# 預載（有上限的 LRU）手上另外拿著的環境貼圖：不在上面的清單裡的另外列出來，兩邊加起來才是全部。
	var prefetch_bytes := 0
	var prefetch_count := 0
	for path: String in AssetPrefetch._cache:
		if not path.begins_with("res://art/environment/") or textures.has(path): continue
		var extra := (AssetPrefetch._cache[path] as Texture2D).get_image()
		if extra == null: continue
		prefetch_bytes += extra.get_data_size()
		prefetch_count += 1
		print("PREFETCH %s bytes=%d" % [path, extra.get_data_size()])
	print("ENVIRONMENT_PREFETCH imported_payload_bytes=%d textures=%d (held only by the bounded prefetch cache)" % [prefetch_bytes, prefetch_count])
	# 釋放之後又被載入的次數：大於 0 代表有東西每次都靠快取、自己不留著貼圖（會反覆重載）。舊版本沒有這個計數。
	var library: Script = RigLibrary
	if "reloads_after_release" in library:
		print("ENVIRONMENT_RELEASE released_total=%d reloads_after_release=%d" % [load("res://core/texture_release.gd").released_total, library.get("reloads_after_release")])
	Settings.set_light_quality(previous)
	textures.clear()
	level.queue_free()
	for i in 4: await get_tree().process_frame
	# Older checkouts used for comparison do not have the audio release helper.
	if ResourceLoader.exists("res://core/audio/audio_release.gd"):
		await load("res://core/audio/audio_release.gd").settle(get_tree())
	get_tree().quit()
