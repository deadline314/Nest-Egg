class_name KeyLightReadabilityScenario
extends ScenarioBase
## 主角站在主光裡（BG-79）：每個有主光的區域，主角站在主光底下（燈的正下方、月光與陽光的光柱落點），
## 量主角的輪廓對比，主光顯示與藏起來各量一次（同一格畫面、暫停），夜景的主光（燈、月光）有主光時不能低於沒有時的 MIN_SHARE。
## 也拍一張存檔（光柱、光暈有沒有蓋過主角一眼看得出）。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=key_light_readability [--areas=a,b]

const MIN_SHARE := 0.85
const SAMPLES := 6


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	Settings.set_reduce_flashes(true)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var areas: Array = []
	for file in DirAccess.get_files_at("res://data/levels"):
		if file.ends_with("_map.json"):
			var id := file.trim_suffix("_map.json")
			var data := load("res://data/levels/%s.tres" % id) as LevelData if ResourceLoader.exists("res://data/levels/%s.tres" % id) else null
			if data != null and data.load_layout_value("key_light") != null:
				areas.append(id)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--areas="):
			areas = Array(arg.trim_prefix("--areas=").split(",", false))
	areas.sort()
	for area: String in areas:
		await _check(area)
	print("KEY_LIGHT_READABILITY areas=%d failures=%d" % [areas.size(), failures])
	await finish()


func _check(area: String) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load("res://data/levels/%s.tres" % area) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	await clear_enemies()
	var key := level._lighting.key_light
	if not is_instance_valid(key):
		print("KEY_LIGHT_READABILITY %s no key light (refused or none)" % area)
		level.queue_free()
		await settle(4)
		return
	var layout: LevelLayout = level._layout
	var x := key.global_position.x
	if key.data.source != "lamp":
		# 光柱落點：往主光的方向斜下去，取畫面上大約一個螢幕高的位置。
		x += tan(deg_to_rad(key.data.shaft_angle)) * 180.0
	var col := clampi(int(x / layout.tile_size), 1, layout.width - 2)
	# 站在主光下方的那一層地面（多層的室內，最上面的可站面可能是天花板）。
	var floor_y := layout.floor_below(col, clampi(int(key.global_position.y / layout.tile_size), 0, layout.height - 1))
	player.global_position = Vector2(col * layout.tile_size + 8.0, floor_y - 2.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	while UiLayers.presentation_busy(get_tree()):
		await get_tree().process_frame
	get_tree().paused = true
	await settle(4)
	var lit := _contrast()
	capture("%s-lit" % area)
	key.visible = false
	await settle(4)
	var dark := _contrast()
	key.visible = true
	get_tree().paused = false
	var share := lit / maxf(dark, 0.001)
	print("KEY_LIGHT_READABILITY %s source=%s col=%d lit %.2f unlit %.2f share %.2f" % [area, key.data.source, col, lit, dark, share])
	# 門檻只對夜景的主光（燈、月光）；陽光的區域（向陽區）有自己的可讀性取樣點，這裡只記錄。
	if share < MIN_SHARE and key.data.source != "sun":
		failures += 1
		push_error("[KeyLightReadabilityScenario] %s 主角站在主光裡的對比只有沒有主光時的 %.0f%%（至少 %.0f%%）" % [area, share * 100.0, MIN_SHARE * 100.0])
	level.queue_free()
	await settle(4)


func _contrast() -> float:
	var total := 0.0
	for i in SAMPLES:
		total += ContrastProbe.capture(get_viewport()).character_contrast(player.global_position, true)
	return total / SAMPLES
