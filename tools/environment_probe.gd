extends Node
## Same script, renderer and machine for BG-17 comparisons. Capture only after timing.
## --level=level_01 --quality=low --frames=180 --out=<directory>
## --spots=30,115,200: columns to stand on (defaults: three per legacy level).
## --no-characters: no enemies or NPC updates; player hidden and stopped. Isolates the environment.
## --hide=LevelBackground,PropNode: DIAGNOSTIC ONLY. Hides and stops every node of those script classes to see what each part costs.

var _exit_code := 0


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
	var migration_helper := load("res://core/navigation/map_layout_migration.gd") as Script if ResourceLoader.exists("res://core/navigation/map_layout_migration.gd") else null
	var migration: Dictionary = migration_helper.read(level.data) if migration_helper != null else {"revision": 1}
	if migration.has("error"):
		push_error("[EnvironmentProbe] " + str(migration["error"]))
		Settings.set_light_quality(previous)
		level.free()
		get_tree().quit(2)
		return
	add_child(level)
	for i in 60: await get_tree().process_frame
	level.hud.visible = false
	level.player.health.setup(999, 100000.0 if no_characters else 0.0)
	for enemy in get_tree().get_nodes_in_group(&"enemies"): enemy.queue_free()
	var excluded_npcs := 0
	if no_characters:
		for node: Node in level.find_children("*", "Node2D", true, false):
			if node is NpcActor:
				node.hide()
				node.process_mode = Node.PROCESS_MODE_DISABLED
				# Actor rigs and prompts can explicitly process ALWAYS beneath the NPC.
				for child: Node in node.find_children("*", "", true, false): child.process_mode = Node.PROCESS_MODE_DISABLED
				excluded_npcs += 1
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
		var query := Vector2(tile, 4) * level._layout.tile_size
		if migration_helper != null:
			query = migration_helper.position(query, migration)
		var column := floori(query.x / level._layout.tile_size)
		var y: float = level._layout.floor_below(column, floori(query.y / level._layout.tile_size)) - 2.0
		var feet := Vector2((column + 0.5) * level._layout.tile_size, y)
		var fits := false
		if level._layout.has_method("fits_body"):
			fits = bool(level._layout.call("fits_body", feet, Player.BODY_SIZE))
		elif feet.is_finite():
			# Historical comparison checkouts predate LevelLayout.fits_body.
			var body := Rect2(feet - Vector2(Player.BODY_SIZE.x * 0.5, Player.BODY_SIZE.y), Player.BODY_SIZE)
			fits = Rect2(Vector2.ZERO, level._layout.pixel_size()).encloses(body)
			for solid: Rect2i in level._layout.solid_rects:
				if body.intersects(level._layout.cells_to_pixels(solid)):
					fits = false
					break
		if not fits:
			push_error("[EnvironmentProbe] %s tile %d: invalid sample position %s" % [level_id, tile, feet])
			_exit_code = 2
			break
		print("ENVIRONMENT_PLACEMENT ", JSON.stringify({"level": level_id, "tile": tile, "migration_revision": migration["revision"], "query_cell": [column, floori(query.y / level._layout.tile_size)], "feet": [feet.x, feet.y], "fits_body": true}))
		level.player.process_mode = Node.PROCESS_MODE_INHERIT
		level.player.global_position = feet
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
		var active_npcs := 0
		var active_rigs := 0
		for node: Node in level.find_children("*", "Node2D", true, false):
			if node.can_process():
				if node is NpcActor: active_npcs += 1
				if node is CutsceneActor: active_rigs += 1
		var enemies := get_tree().get_nodes_in_group(&"enemies").size()
		print("ENVIRONMENT_ACTORS ", JSON.stringify({"tile": tile, "no_characters": no_characters, "excluded_npcs": excluded_npcs, "active_npcs": active_npcs, "active_rigs": active_rigs, "enemies": enemies, "player_can_process": level.player.can_process()}))
		if no_characters and (active_npcs > 0 or active_rigs > 0 or enemies > 0 or level.player.can_process()):
			push_error("[EnvironmentProbe] %s tile %d: characters still update in environment-only mode" % [level_id, tile])
			_exit_code = 2
			break
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
		print("ENVIRONMENT_SAMPLES ", JSON.stringify({"level": level_id, "tile": tile, "quality": quality, "no_characters": no_characters, "samples_ms": times}))
		times.sort()
		print("PROBE%s level=%s tile=%d quality=%s frames=%d mean_ms=%.3f median_ms=%.3f p95_ms=%.3f draws=%.1f renderer_texture_bytes=%d" % ["_NO_CHARACTERS" if no_characters else "", level_id, tile, quality, frames, total / frames, times[frames / 2], times[int(frames * 0.95)], draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)])
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out)
			# HDR 2D readback is linear; PNG viewers expect sRGB.
			var shot := get_viewport().get_texture().get_image()
			if get_viewport().use_hdr_2d:
				shot.convert(Image.FORMAT_RGBA8)
				shot.linear_to_srgb()
			var path := out.path_join("%s_%d_%s.png" % [level_id, tile, quality])
			var error := shot.save_png(path)
			if error != OK:
				push_error("[EnvironmentProbe] %s: %s" % [path, error_string(error)])
				_exit_code = 1
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
	var prefetch := load("res://core/asset_prefetch.gd") as Script if ResourceLoader.exists("res://core/asset_prefetch.gd") else null
	var prefetch_value: Variant = prefetch.get("_cache") if prefetch != null else null
	var prefetch_cache: Dictionary = prefetch_value if prefetch_value is Dictionary else {}
	for path: String in prefetch_cache:
		if not path.begins_with("res://art/environment/") or textures.has(path): continue
		var extra := (prefetch_cache[path] as Texture2D).get_image()
		if extra == null: continue
		prefetch_bytes += extra.get_data_size()
		prefetch_count += 1
		print("PREFETCH %s bytes=%d" % [path, extra.get_data_size()])
	print("ENVIRONMENT_PREFETCH imported_payload_bytes=%d textures=%d (held only by the bounded prefetch cache) supported=%s" % [prefetch_bytes, prefetch_count, prefetch_value is Dictionary])
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
	get_tree().quit(_exit_code)
