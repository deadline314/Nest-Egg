extends ScenarioBase
## Existing pawnshop geometry and steam; baseline changes only in-memory data.
var baseline := false
var perf_only := false
var kettle_data: PropData

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

func open_kitchen() -> PropNode:
	var data := load("res://data/levels/ch1_pawnshop.tres").duplicate() as LevelData
	# Probe excludes narrative playback so the camera remains at the measured outlet.
	data.intro_scene = &""
	level = Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.configure(data)
	add_child(level)
	await settle(25)
	level._next_story_trigger = level._layout.story_triggers.size()
	await clear_enemies()
	player = level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(96 * 16 + 8, level._layout.floor_below(96, 14) - 2)
	player.velocity = Vector2.ZERO
	level.hud.visible = false
	snap_camera()
	await wait(TITLE_CARD_TIME)
	var kettle := level.find_child("pawnshop_kitchen__kettle_stove", true, false) as PropNode
	assert(kettle != null and kettle._on_screen)
	assert(player.global_position.y > 290 and player.global_position.y < 322)
	print("BG25_STEAM_SETUP baseline=%s outlet=%s local=%s spread=%f player=%s" % [baseline, kettle.steam_world_position(), kettle.data.steam_offset, kettle._steam_spread, player.global_position])
	return kettle

func run() -> void:
	seed(25026)
	GameState.start_new_run(GameState.difficulties[1])
	kettle_data = load("res://data/environment/scene_props/pawnshop_kitchen/pawnshop_kitchen__kettle_stove.tres") as PropData
	if baseline:
		kettle_data.steam_offset = Vector2(14, 6)
		kettle_data.steam_spread = 2.0
	var quality := Settings.get_light_quality()
	var kettle := await open_kitchen()
	for tier in ([] if perf_only else [LightQuality.Tier.LOW, LightQuality.Tier.HIGH]):
		Settings.set_light_quality(tier)
		await wait(0.5)
		for tick in 3:
			print("BG25_STEAM_FRAME quality=%d index=%d timer=%f particles=%d" % [tier, tick, kettle._steam_timer, Fx.particle_count()])
			capture("BG-25-steam-%s-q%d-t%d" % ["before" if baseline else "after", tier, tick])
			await wait(0.5)
	if not baseline and not perf_only:
		var timer := kettle._steam_timer
		var cursor: int = Fx._soft._cursor
		var life: PackedFloat32Array = Fx._soft._life.duplicate()
		get_tree().paused = true
		await wait(0.5)
		assert(is_equal_approx(kettle._steam_timer, timer) and cursor == Fx._soft._cursor and life == Fx._soft._life)
		print("BG25_STEAM_PAUSE timer=%f cursor=%d life_frozen=true" % [timer, cursor])
		get_tree().paused = false
		await wait(0.5)
		assert(cursor != Fx._soft._cursor)
		print("BG25_STEAM_RESUME cursor_before=%d cursor_after=%d" % [cursor, Fx._soft._cursor])
	if perf_only:
		var samples: Array[int] = []
		for frame in 60:
			var start := Time.get_ticks_usec()
			await get_tree().process_frame
			samples.append(Time.get_ticks_usec() - start)
		print("BG25_STEAM_PERF baseline=%s samples_us=%s static_memory=%d texture_bytes=%d nodes=%d" % [baseline, samples, OS.get_static_memory_usage(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var weak: WeakRef = weakref(kettle)
	await finish()
	assert(weak.get_ref() == null and Fx._soft == null)
	if not baseline and not perf_only:
		for cycle in 10:
			kettle = await open_kitchen()
			weak = weakref(kettle)
			await finish()
			assert(weak.get_ref() == null and Fx._soft == null)
			print("BG25_STEAM_CLEANUP cycle=%d prop_released=true field_released=true nodes=%d static_memory=%d" % [cycle + 1, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), OS.get_static_memory_usage()])
	Settings.set_light_quality(quality)
