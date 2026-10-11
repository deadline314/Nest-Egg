extends Node
## 光池量測（BG-33）：對關卡裡每一盞亮著的場景燈，量「燈下的牆面」與「離開光池的牆面」差幾倍。
## 光影從光源出發的畫面，燈下要明顯比兩盞燈之間亮；這個數字太小代表環境光太亮、光池看不出來。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/light_pool_probe.tscn -- --out=<絕對資料夾> --level=<關卡檔名，逗號分隔>
##     [--tag=<標籤>] [--quality=low|medium|high] [--max=<每關最多量幾盞，預設 8>]
## 輸出 <標籤>-<關卡>-lamp<序號>.png 與 <標籤>-index.json：每盞燈的光池亮度、暗處亮度、倍數（有燈具款式時一併記下），以及每關的中位數。
## 量法：鏡頭拉遠對準燈，沿著燈下方一條水平帶取亮度（只取背後有牆的部分）。光池＝燈正下方那一段的中位數；
## 暗處＝離燈 1.1～1.6 倍光池半徑那一段的中位數（用中位數是為了略過擺設、窗與招牌）。燈下方 70 像素內沒有牆的燈不量
## （露天的天空不受燈影響）。主角與敵人都藏起來。

const Capture := preload("res://tools/viewport_capture.gd")
const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const SETTLE_FRAMES := 24
## 取樣帶在燈下方多遠、多高（世界像素）。
const BAND_DROPS: Array[float] = [40.0, 70.0]
const BAND_HEIGHT := 14.0
const POOL_HALF_WIDTH := 26.0
const FAR_FROM := 1.1
const FAR_TO := 1.6
const VIEW_ZOOM := 0.55

var _out := ""
var _levels: PackedStringArray = []
var _tag := "pools"
var _quality := ""
var _max := 8


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--level="):
			_levels = argument.trim_prefix("--level=").split(",", false)
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
		elif argument.begins_with("--max="):
			_max = clampi(int(argument.trim_prefix("--max=")), 1, 40)
	if not _out.is_absolute_path() or _levels.is_empty() or DisplayServer.get_name() == "headless":
		push_error("[LightPoolProbe] 需要原生視窗、--out=<絕對資料夾> 與 --level=<關卡檔名>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[LightPoolProbe] 無法建立輸出資料夾：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	Story._layer.visible = false
	var failures := 0
	var report := {"tag": _tag, "quality": _quality, "levels": {}}
	for level_id: String in _levels:
		var path := "res://data/levels/%s.tres" % level_id
		var data := load(path) as LevelData if ResourceLoader.exists(path) else null
		if data == null:
			push_error("[LightPoolProbe] 找不到關卡：%s" % path)
			failures += 1
			continue
		report["levels"][level_id] = await _measure_level(level_id, data)
	if QUALITY.has(_quality):
		Settings.set_light_quality(quality_before)
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[LightPoolProbe] 無法寫入索引：%s" % _out)
		failures += 1
	else:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	await AudioRelease.settle(get_tree())
	get_tree().quit(1 if failures > 0 else 0)


func _measure_level(level_id: String, data: LevelData) -> Dictionary:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(SETTLE_FRAMES)
	level.hud.visible = false
	for child: Node in level.get_children():
		if child is ChapterCard:
			child.queue_free()
	level.player.visible = false
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Node2D).visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
	level._lighting._lightning_gap = 1.0e9
	var lamps: Array[Lamp] = []
	for node: Node in level.find_children("*", "Node2D", true, false):
		var lamp := node as Lamp
		if lamp != null and not lamp.dead:
			lamps.append(lamp)
	lamps.sort_custom(func(a: Lamp, b: Lamp) -> bool: return a.position.x < b.position.x)
	# 量的是穩定亮著時的光池：先把閃爍停掉（正在閃的那一下也結束）。
	for lamp in lamps:
		lamp.flicker_chance = 0.0
		lamp._flicker_left = 0.0
	var step := maxi(1, ceili(float(lamps.size()) / float(_max)))
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	# 鏡頭拉遠：光池外面那一段（1.1～1.6 倍半徑）要拍得到。
	camera.zoom = Vector2.ONE * LevelCamera.ZOOM * VIEW_ZOOM
	var records: Array[Dictionary] = []
	var ratios: Array[float] = []
	for index in range(0, lamps.size(), step):
		var lamp := lamps[index]
		camera.global_position = lamp.global_position + Vector2(0.0, 60.0)
		camera.reset_smoothing()
		camera.force_update_scroll()
		await _settle(SETTLE_FRAMES)
		var image := Capture.image(get_viewport())
		var file := "%s-%s-lamp%02d.png" % [_tag, level_id, index]
		image.save_png(_out.path_join(file))
		var record := _measure_lamp(image, lamp, level._scenery_walls)
		record["file"] = file
		record["fixture"] = str(lamp.get("fixture_id")) if lamp.get("fixture_id") != null else ""
		record["tile"] = [int(lamp.position.x / 16.0), int(lamp.position.y / 16.0)]
		record["light_enabled"] = lamp._light != null and lamp._light.enabled and lamp._light.visible
		record["light_energy"] = lamp._light.energy if lamp._light != null else 0.0
		record["shadows"] = lamp._light != null and lamp._light.shadow_enabled
		records.append(record)
		if float(record["ratio"]) > 0.0:
			ratios.append(float(record["ratio"]))
	ratios.sort()
	var median := ratios[ratios.size() / 2] if not ratios.is_empty() else 0.0
	print("LIGHT_POOLS:", level_id, " lamps ", lamps.size(), " measured ", records.size(), " median ratio ", snappedf(median, 0.01),
			" min ", snappedf(ratios[0], 0.01) if not ratios.is_empty() else 0.0)
	level.queue_free()
	await _settle(6)
	return {"lamps": lamps.size(), "median_ratio": median, "min_ratio": ratios[0] if not ratios.is_empty() else 0.0, "records": records}


## 沿著燈下方的水平帶取亮度（線性空間）：光池與暗處各一個百分位，回傳兩者與倍數。暗處取不到（出畫面）時倍數是 0。
func _measure_lamp(image: Image, lamp: Lamp, walls: BackWallGeometry) -> Dictionary:
	var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var scale := to_screen.get_scale().x
	# 只量背後有牆的地方：露天的天空不受燈影響，量了沒有意義。燈下方依序往下找第一段有牆的高度。
	var world := Vector2.INF
	for drop: float in BAND_DROPS:
		var candidate := lamp.global_position + Vector2(0.0, drop)
		if walls != null and drop < lamp.radius * 0.8 				and walls.covers(Rect2(candidate - Vector2(POOL_HALF_WIDTH, BAND_HEIGHT * 0.5), Vector2(POOL_HALF_WIDTH * 2.0, BAND_HEIGHT))):
			world = candidate
			break
	if world == Vector2.INF:
		return {"pool": 0.0, "far": 0.0, "ratio": 0.0, "note": "燈下沒有背牆"}
	var center := to_screen * world
	var rows := maxi(1, int(BAND_HEIGHT * scale))
	var pool := _band(image, center.x - POOL_HALF_WIDTH * scale, center.x + POOL_HALF_WIDTH * scale, center.y, rows)
	var far := PackedFloat32Array()
	for side: float in [-1.0, 1.0]:
		var from_world := world.x + side * lamp.radius * FAR_FROM
		var to_world := world.x + side * lamp.radius * FAR_TO
		if not walls.covers(Rect2(minf(from_world, to_world), world.y - BAND_HEIGHT * 0.5, absf(to_world - from_world), BAND_HEIGHT)):
			continue
		var from := center.x + side * lamp.radius * FAR_FROM * scale
		var to := center.x + side * lamp.radius * FAR_TO * scale
		far.append_array(_band(image, minf(from, to), maxf(from, to), center.y, rows))
	var pool_luma := _percentile(pool, 0.5)
	var far_luma := _percentile(far, 0.5)
	return {"pool": pool_luma, "far": far_luma, "ratio": pool_luma / maxf(far_luma, 0.004) if not far.is_empty() and not pool.is_empty() else 0.0}


## 畫面上一段水平帶的每欄平均亮度（把 sRGB 截圖轉回線性再算）。超出畫面的部分略過。
func _band(image: Image, from_x: float, to_x: float, center_y: float, rows: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var top := int(center_y) - rows / 2
	for x in range(maxi(0, int(from_x)), mini(image.get_width(), int(to_x))):
		var total := 0.0
		var count := 0
		for y in range(maxi(0, top), mini(image.get_height(), top + rows)):
			total += LightKit.luminance(image.get_pixel(x, y).srgb_to_linear())
			count += 1
		if count > 0:
			result.append(total / float(count))
	return result


func _percentile(values: PackedFloat32Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(float(sorted.size() - 1) * q), 0, sorted.size() - 1)]
