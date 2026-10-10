extends ScenarioBase
## BG-25 real chapter rendering and lifecycle evidence; no permanent map edits.
var baseline := false
var perf_only := false
var baseline_data: PropData

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		baseline = baseline or arg == "--baseline"
		perf_only = perf_only or arg == "--perf-only"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await run()
	await settle(3)
	get_tree().quit()

func open_chapter(id: String, tile: int) -> void:
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.configure(load("res://data/levels/%s.tres" % id) as LevelData)
	add_child(level)
	await settle(25)
	await clear_enemies()
	player = level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(tile * 16 + 8, level._layout.floor_below(tile, 0) - 2)
	player.velocity = Vector2.ZERO
	level.hud.visible = false
	for sign in level.find_children("*", "HintSign", true, false):
		sign.visible = false
	snap_camera()
	await wait(TITLE_CARD_TIME)

func run() -> void:
	var quality_before := Settings.get_light_quality()
	Story.auto_skip = true
	seed(25025)
	GameState.start_new_run(GameState.difficulties[1])
	if baseline:
		baseline_data = load("res://data/environment/scene_props/anchor_phone_booth/anchor_phone_booth__gutter_downpipe.tres") as PropData
		baseline_data.flow_region = Rect2()
		baseline_data.ripple = true
	await open_chapter("ch1_booth_alley", 24)
	var prop := level.find_child("anchor_phone_booth__gutter_downpipe", true, false) as PropNode
	assert(prop != null)
	var flow: Node = prop.get_node_or_null("LocalWaterFlow")
	assert(flow == null if baseline else flow != null)
	print("BG25_SETUP baseline=%s local_flow_created=%s" % [baseline, flow != null])
	for tier in ([] if perf_only else [LightQuality.Tier.LOW, LightQuality.Tier.MEDIUM, LightQuality.Tier.HIGH]):
		Settings.set_light_quality(tier)
		await wait(0.3)
		for tick in 3:
			print("BG25_FRAME quality=%d index=%d clock=%f" % [tier, tick, 0.0 if baseline else flow.clock])
			capture("BG-25-%s-q%d-t%d" % ["before" if baseline else "water", tier, tick])
			await wait(0.5)
	if not baseline and not perf_only:
		var before: float = flow.clock
		get_tree().paused = true
		await wait(0.5)
		capture("BG-25-paused")
		assert(is_equal_approx(before, flow.clock))
		print("BG25_PAUSE clock_before=%f clock_after=%f" % [before, flow.clock])
		get_tree().paused = false
		await wait(0.5)
		assert(flow.clock != before)
		capture("BG-25-resumed")
		Input.action_press(&"shoot")
		await wait(0.25)
		Input.action_release(&"shoot")
		capture("BG-25-shooting")
	var frames_us: Array[int] = []
	for frame in 60:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		frames_us.append(Time.get_ticks_usec() - start)
	var rss_kib := -1
	if FileAccess.file_exists("/proc/self/status"):
		for line in FileAccess.get_file_as_string("/proc/self/status").split("\n"):
			if line.begins_with("VmRSS:"):
				rss_kib = int(line.replace("\t", " ").split(" ", false)[1])
	print("BG25_PERF baseline=%s samples_us=%s static_memory=%d texture_bytes=%d nodes=%d rss_kib=%d" % [baseline, frames_us, OS.get_static_memory_usage(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), rss_kib])
	await finish()
	if not baseline and not perf_only:
		for cycle in 10:
			await open_chapter("ch1_booth_alley", 24)
			var local: Node = level.find_child("LocalWaterFlow", true, false)
			assert(local != null)
			var weak: WeakRef = weakref(local)
			await finish()
			assert(weak.get_ref() == null)
			await open_chapter("ch1_street", 118)
			if cycle == 0:
				capture("BG-25-street-steam")
			await finish()
			print("BG25_SWITCH cycle=%d local_released=true static_memory=%d nodes=%d" % [cycle + 1, OS.get_static_memory_usage(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	Settings.set_light_quality(quality_before)
