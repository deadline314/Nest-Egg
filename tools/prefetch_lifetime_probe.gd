extends Node
## BG-23 隔離生命週期探針；原生引擎請求對照與真實主選單／跨區。
const Capture := preload("res://tools/viewport_capture.gd")
const TEXTURE := "res://art/weapons/pistol.png"
const ROUTE := ["pawnshop", "rooftop", "street", "booth_alley", "warehouse", "vault", "lounge", "stall"]
var mode := "service"
var output := ""
var failures := 0
var checks := 0
var samples: Array[Dictionary] = []
var main: Node
var cycle_slots := 4

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--slots="):
			cycle_slots = clampi(int(arg.trim_prefix("--slots=")), 1, 4)
	var isolated := OS.get_environment("BG23_PREFETCH_PROFILE").replace("\\", "/").to_lower().trim_suffix("/")
	var actual := OS.get_user_data_dir().replace("\\", "/").to_lower()
	if isolated.is_empty() or not actual.begins_with(isolated + "/") or not output.is_absolute_path():
		push_error("BG23 requires isolated APPDATA and an output directory")
		get_tree().quit(2)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(output)
	if directory_error != OK:
		push_error("BG23 cannot create output directory: %s (%s)" % [output, error_string(directory_error)])
		get_tree().quit(2)
		return
	Engine.max_fps = 60
	Story.auto_skip = true
	GameState.story_autosave = false
	print("BG23_PID ", OS.get_process_id())
	print("BG23_RUNTIME ", Engine.get_version_info(), " renderer=", RenderingServer.get_current_rendering_method())
	_run.call_deferred()

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[BG23 probe] " + message)

func sample(label: String) -> void:
	var row := AssetPrefetch.stats()
	row["phase"] = label
	row["static_memory_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	row["render_texture_monitor_bytes"] = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	row["ms"] = Time.get_ticks_msec()
	samples.append(row)
	print("BG23_SAMPLE ", JSON.stringify(row))
	verify(row["inflight"] <= row["inflight_limit"] and row["queued"] <= AssetPrefetch.MAX_QUEUED and row["cached"] + row["retiring"] <= AssetPrefetch.MAX_CACHED and row["estimated_bytes"] <= AssetPrefetch.MAX_CACHE_BYTES, label + " remains within backend/service budgets")

func drain() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while AssetPrefetch.stats()["queued"] + AssetPrefetch.stats()["inflight"] > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	verify(AssetPrefetch.stats()["queued"] + AssetPrefetch.stats()["inflight"] == 0, "service drains before deadline")

func _raw(collect: bool) -> void:
	verify(ResourceLoader.load_threaded_request(TEXTURE) == OK, "native request accepted")
	var deadline := Time.get_ticks_msec() + 10000
	while ResourceLoader.load_threaded_get_status(TEXTURE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	verify(ResourceLoader.load_threaded_get_status(TEXTURE) == ResourceLoader.THREAD_LOAD_LOADED, "native texture completed")
	print("BG23_NATIVE completed_status=", ResourceLoader.load_threaded_get_status(TEXTURE))
	if collect:
		var texture := ResourceLoader.load_threaded_get(TEXTURE) as Texture2D
		verify(texture != null and texture.get_width() > 0, "collected native texture is valid")
		verify(ResourceLoader.load_threaded_get_status(TEXTURE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "native token disappears after get")
		texture = null
		print("BG23_NATIVE collected_status=", ResourceLoader.load_threaded_get_status(TEXTURE))
	sample("claimed" if collect else "unclaimed")

func _failure() -> void:
	var path := "user://bg23-intentional-invalid-texture.tres"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[gd_resource type=\"Texture2D\" format=3]\n[resource]\nthis_is_not_valid = !!!\n")
	file.close()
	print("BG23_EXPECTED_NATIVE_FAILURE ", path)
	var before: int = AssetPrefetch.stats()["failed_total"]
	AssetPrefetch.request(PackedStringArray([path]))
	await drain()
	verify(AssetPrefetch.stats()["failed_total"] > before, "failed native request is reported and released")
	verify(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "failed native token is collected")
	sample("failed-request-collected")
	AssetPrefetch.clear()
	verify(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "isolated corrupt resource is removed")

func _service() -> void:
	for cycle in 3:
		for area: String in ROUTE:
			var data := load("res://data/levels/ch1_%s.tres" % area) as LevelData
			AssetPrefetch.warm_neighbors(data)
			sample("%d-%s-enqueued" % [cycle, area])
			await drain()
			sample("%d-%s-complete" % [cycle, area])
		AssetPrefetch.clear()
		await drain()
		sample("%d-cleared" % cycle)
		verify(AssetPrefetch.stats()["cached"] == 0, "clear releases the managed cache")


## 獨立引擎重現：不經 AssetPrefetch，四槽反覆載入／領取／放掉引用。
func _cycle() -> void:
	var paths := ["res://art/weapons/pistol.png", "res://art/weapons/rifle.png", "res://art/weapons/smg.png", "res://art/weapons/railgun.png"]
	var active := [false, false, false, false]
	var issued := 0
	var collected := 0
	var deadline := Time.get_ticks_msec() + 30000
	while collected < 1000 and Time.get_ticks_msec() < deadline:
		for slot in cycle_slots:
			if active[slot] and ResourceLoader.load_threaded_get_status(paths[slot]) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var texture := ResourceLoader.load_threaded_get(paths[slot]) as Texture2D
				verify(texture != null, "minimal native cycle returns a texture")
				texture = null
				active[slot] = false
				collected += 1
			if not active[slot] and issued < 1000:
				verify(ResourceLoader.load_threaded_request(paths[slot], "Texture2D") == OK, "minimal native cycle request accepted")
				active[slot] = true
				issued += 1
		await get_tree().process_frame
	for slot in cycle_slots:
		if active[slot]:
			ResourceLoader.load_threaded_get(paths[slot])
	verify(collected == 1000, "minimal native cycle completes 1000 requests")
	sample("raw-cycle-collected")

func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := Capture.image(get_viewport())
	verify(image.save_png(output.path_join("BG-23-" + label + ".png")) == OK, "capture is written: " + label)

func _screen_settled() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not Transition.is_active():
			await get_tree().create_timer(0.2, true, false, true).timeout
			if not Transition.is_active():
				verify(true, "actual Main screen transition completes")
				return
	verify(false, "actual Main screen transition completes")

func _campaign() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _screen_settled()
	await drain()
	sample("main-menu-before")
	await _shot("main-menu-before")
	# 受控換區：凍結物理世界，避免出生點附近的真 portal／戰鬥改動
	# 自動路由與取景；場景仍使用真 Main、Level 與服務，不宣稱玩家通關。
	var controlled_lock := GameplayLock.acquire(self)
	main.call("_on_start_requested", GameState.difficulties[1])
	await _screen_settled()
	await drain()
	for cycle in 2:
		for area: String in ROUTE:
			GameState.pending_portal = &""
			main.call("_on_area_requested", "res://data/levels/ch1_%s.tres" % area)
			await _screen_settled()
			verify(main.get("_screen") is Level, "real Main routes to a Level")
			var level := main.get("_screen") as Level
			verify(level != null and str(level.data.id) == "ch1_" + area and is_instance_valid(level.player), "actual area and player are present: " + area)
			if level != null and is_instance_valid(level.player):
				await _settle_spawn(level)
			await drain()
			sample("campaign-%d-%s" % [cycle, area])
			if cycle == 0 and area in ["street", "warehouse", "vault"]:
				await _shot(area)
	GameplayLock.release(controlled_lock)
	main.call("_show_main_menu")
	await _screen_settled()
	await drain()
	sample("main-menu-after")
	await _shot("main-menu-after")
	main.queue_free()
	await get_tree().process_frame
	AssetPrefetch.clear()
	await drain()
	sample("campaign-exit")


func _settle_spawn(level: Level) -> void:
	var layout := level.get("_layout") as LevelLayout
	var player := level.player
	var floor_y := layout.floor_below(int(player.position.x / layout.tile_size), int(player.position.y / layout.tile_size))
	verify(is_finite(floor_y), "controlled spawn has an actual layout support surface")
	if not is_finite(floor_y):
		return
	player.position.y = floor_y - 0.01
	player.velocity = Vector2.ZERO
	await get_tree().physics_frame
	player.apply_floor_snap()
	verify(player.is_on_floor() and absf(player.position.y - floor_y) <= 1.0, "controlled player feet settle on the actual support")
	# 只讓取景與可見動畫繼續；沒有放開遊戲物理或動正式 actor/map source。
	for key in ["_visual"]:
		var visual := player.get(key) as Node
		if visual != null:
			visual.process_mode = Node.PROCESS_MODE_ALWAYS
	for key in ["hud", "_post", "_lighting"]:
		var visual := level.get(key) as Node
		if visual != null:
			visual.process_mode = Node.PROCESS_MODE_ALWAYS
	level.camera.process_mode = Node.PROCESS_MODE_ALWAYS
	level.camera.snap_to_target()
	level.camera.force_update_scroll()

func _run() -> void:
	match mode:
		"unclaimed": await _raw(false)
		"claimed": await _raw(true)
		"failure": await _failure()
		"service": await _service()
		"cycle": await _cycle()
		"campaign": await _campaign()
		"shutdown":
			AssetPrefetch.request(PackedStringArray([TEXTURE]))
			await drain()
			AssetPrefetch.clear()
			AssetPrefetch.request(PackedStringArray([TEXTURE]))
			sample("shutdown-with-active-request")
		_:
			verify(false, "unknown probe mode")
	var report := FileAccess.open(output.path_join("BG-23-" + mode + ".json"), FileAccess.WRITE)
	if report == null:
		verify(false, "probe report is writable")
	else:
		report.store_string(JSON.stringify({"mode": mode, "checks": checks, "failures": failures, "pid": OS.get_process_id(), "samples": samples}, "\t"))
		report.close()
	print("BG23_RESULT mode=%s checks=%d failures=%d" % [mode, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
