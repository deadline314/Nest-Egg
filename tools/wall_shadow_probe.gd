extends Node
## 牆上影子的原生驗證（BG-34）：角色依光源在背後的牆上投影。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/wall_shadow_probe.tscn -- --out=<絕對資料夾> [--level=ch1_warehouse] [--tag=<標籤>]
##     [--quality=low|medium|high] [--mode=lamp,gun,perf,reenter] [--at=<欄>]
## --at：gun 與 perf 把主角放在這一欄（要是一段平的地面、背後有牆）；不給就放在挑到的那盞燈旁邊。
## lamp：找一盞穩定亮著、背後有牆的場景燈，主角站在它左邊、正下方、右邊各拍一張，每張都有「影子開」與「影子關」。
## gun：主角用槍燈照著一排敵人，拍影子開與關。
## perf：畫面上 12 個敵人，影子開與關交替量每影格耗時（關垂直同步，各取中位數）。
## reenter：反覆進出關卡 10 次，記錄節點數與貼圖記憶體有沒有累積。
## 輸出 <標籤>-<情境>-on.png／-off.png 與 <標籤>-index.json：每張的投影燈數、輪廓圖裡有東西的像素比例、
## 影子把牆壓暗了多少（影子開與關兩張的平均亮度差），以及耗時與資源的數字。
## 沒有背牆、光影品質低（不投影）或找不到合適的燈時會寫在索引裡並以失敗結束。

const Capture := preload("res://tools/viewport_capture.gd")
const SETTLE_FRAMES := 40
const SIDE_OFFSET := 64.0
## 影子至少要讓這麼多比例的畫面變暗才算有影子（一個角色的影子大約是畫面的千分之五）。
const MIN_SHADOW_SHARE := 0.001
const ENEMY_PATH := "res://data/enemies/sweeper.tres"
const PERF_ENEMIES := 12
## 耗時量測：影子開與關緊接著各量一小段算一組，取很多組的比值的中位數。機器的負載會隨時間飄，
## 一組裡的兩段相隔不到半秒，飄移互相抵銷；整段各量一次再相除的做法在有其他程式在跑時誤差會到一成以上。
const PERF_FRAMES := 45
const PERF_ROUNDS := 60
const REENTER_TIMES := 10
const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}

var _out := ""
var _level := "ch1_warehouse"
var _tag := "walls"
var _quality := ""
var _modes: PackedStringArray = ["lamp", "gun", "perf", "reenter"]
var _failures := 0
var _aim := Vector2.ZERO
var _at := -1


## 滑鼠只要在視窗上動一下，瞄準就會改回跟滑鼠；量測期間每一格都把瞄準方向設回來。
func _process(_delta: float) -> void:
	if _aim != Vector2.ZERO:
		AimInput.using_gamepad = true
		AimInput._last_stick_dir = _aim


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--level="):
			_level = argument.trim_prefix("--level=")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
		elif argument.begins_with("--at="):
			_at = int(argument.trim_prefix("--at="))
		elif argument.begins_with("--mode="):
			_modes = argument.trim_prefix("--mode=").split(",", false)
	if not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[WallShadowProbe] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[WallShadowProbe] 無法建立輸出資料夾：%s" % _out)
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
	var report := {"tag": _tag, "level": _level, "quality": _quality}
	var path := "res://data/levels/%s.tres" % _level
	var data := load(path) as LevelData if ResourceLoader.exists(path) else null
	if data == null:
		push_error("[WallShadowProbe] 找不到關卡：%s" % path)
		_failures += 1
	else:
		if _modes.has("lamp") or _modes.has("gun") or _modes.has("perf"):
			var level := await _open(data)
			var shadows := level.find_child("WallShadows", true, false) as WallShadows
			report["enabled"] = shadows != null and shadows.is_enabled()
			if shadows == null:
				push_error("[WallShadowProbe] 關卡裡沒有 WallShadows")
				_failures += 1
			else:
				if _modes.has("lamp"):
					report["lamp"] = await _lamp_shots(level, shadows)
				if _modes.has("gun"):
					report["gun"] = await _gun_shot(level, shadows)
				if _modes.has("perf"):
					report["perf"] = await _perf(level, shadows)
			level.queue_free()
			await _settle(4)
		if _modes.has("reenter"):
			report["reenter"] = await _reenter(data)
	if QUALITY.has(_quality):
		Settings.set_light_quality(quality_before)
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[WallShadowProbe] 無法寫入索引：%s" % _out)
		_failures += 1
	else:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("WALL_SHADOW_PROBE:", _level, " failures ", _failures)
	await AudioRelease.settle(get_tree())
	get_tree().quit(1 if _failures > 0 else 0)


func _open(data: LevelData) -> Level:
	GameState.start_new_run(GameState.difficulties[1])
	var copy := data.duplicate() as LevelData
	copy.intro_scene = &""
	copy.show_chapter_card = false
	var level := Level.new()
	level.configure(copy)
	add_child(level)
	level._arena_triggered = true
	for node: Node in level.find_children("*", "", true, false):
		if node is EncounterZone:
			node.restore_state(true)
	await _settle(SETTLE_FRAMES)
	level.hud.visible = false
	level.player.health.setup(999, 0.0)
	level._lighting._lightning_gap = 1.0e9
	# 雨絲每一格都不一樣，會蓋過「影子開」與「影子關」兩張的差別：量測時把雨藏起來。
	for node: Node in level.find_children("*", "", true, false):
		if node is RainLayer:
			(node as CanvasItem).visible = false
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await _settle(4)
	return level


## gun 與 perf 的站位：--at 指定的那一欄，或挑到的那盞燈旁邊。回傳腳底的位置；找不到回傳 Vector2.INF。
func _stand(level: Level, beside := 0.0) -> Vector2:
	var layout := level._layout
	var x := 0.0
	var row := 0
	if _at >= 0:
		x = float(_at) * layout.tile_size + 8.0
		row = maxi(0, int(level.player.global_position.y / layout.tile_size) - 3)
	else:
		var lamp := _pick_lamp(level)
		if lamp == null:
			return Vector2.INF
		x = lamp.position.x + beside
		row = int(lamp.position.y / layout.tile_size)
	var floor_y := layout.floor_below(int(x / layout.tile_size), row)
	return Vector2(x, floor_y) if floor_y != INF else Vector2.INF


## 離地最近的一盞穩定亮著、背後有牆、腳下有地面的場景燈（燈越低，牆上的影子越明顯）。
func _pick_lamp(level: Level) -> Lamp:
	var best: Lamp = null
	for node: Node in level.find_children("*", "Node2D", true, false):
		var lamp := node as Lamp
		if lamp == null or lamp.dead or lamp.floor_y == INF:
			continue
		lamp.use_flicker(LampFlicker.STABLE, 0)
		lamp._flicker = 1.0
		if not level._scenery_walls.covers(Rect2(lamp.position + Vector2(-40.0, 20.0), Vector2(80.0, 40.0))):
			continue
		if best == null or lamp.floor_y - lamp.position.y < best.floor_y - best.position.y - 1.0:
			best = lamp
	return best


func _place_player(level: Level, feet: Vector2, aim: Vector2) -> void:
	var player := level.player
	player.global_position = feet - Vector2(0.0, 2.0)
	player.velocity = Vector2.ZERO
	_aim = aim.normalized()
	await _settle(40)
	# 鏡頭會朝瞄準方向慢慢偏過去：等它停下來，影子開與關兩張才是同一個畫面。
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null:
		camera.snap_to_target()
	await _settle(150)


## 離地最低的一盞亮著、背後有牆、腳下有地面的光源（場景燈或擺設上的燈）：光源越低，牆上的影子往旁邊偏得越明顯。
## 回傳 {position, floor_y, height}；找不到回傳空的。
func _pick_source(level: Level) -> Dictionary:
	_pick_lamp(level)  # 順便把會閃的燈定住
	var layout := level._layout
	var best := {}
	for node: Node in get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
		var light := node as PointLight2D
		# 只挑場景燈：擺設上的小燈照不到主角身後的牆，影子落在沒有光的地方看不出來。
		if light == null or not light.enabled or light.energy < 0.4 or not light.get_parent() is Lamp or not level.is_ancestor_of(light):
			continue
		var at := light.global_position
		var floor_y := layout.floor_below(int(at.x / layout.tile_size), int(at.y / layout.tile_size))
		var height := floor_y - at.y
		if floor_y == INF or height < 24.0 or height > 400.0:
			continue
		# 光源左右兩側都要有牆、有同一片地面，主角才有地方站、影子才有地方落。
		if not level._scenery_walls.covers(Rect2(at.x - SIDE_OFFSET - 60.0, floor_y - 70.0, SIDE_OFFSET * 2.0 + 120.0, 60.0)):
			continue
		var level_ground := true
		for offset: float in [-SIDE_OFFSET, SIDE_OFFSET]:
			level_ground = level_ground and is_equal_approx(layout.floor_below(int((at.x + offset) / layout.tile_size), int(at.y / layout.tile_size)), floor_y)
		if level_ground and (best.is_empty() or height < float(best["height"]) - 1.0):
			best = {"position": at, "floor_y": floor_y, "height": height}
	return best


func _lamp_shots(level: Level, shadows: WallShadows) -> Dictionary:
	var source := _pick_source(level)
	if source.is_empty():
		push_error("[WallShadowProbe] %s 找不到左右有地面、背後有牆的光源" % _level)
		_failures += 1
		return {"note": "找不到左右有地面、背後有牆的光源"}
	var at: Vector2 = source["position"]
	var result := {"light_tile": [int(at.x / 16.0), int(at.y / 16.0)], "height_px": snappedf(source["height"], 0.1), "shots": {}}
	for side: Array in [["left", -SIDE_OFFSET], ["under", 0.0], ["right", SIDE_OFFSET]]:
		await _place_player(level, Vector2(at.x + float(side[1]), source["floor_y"]), Vector2.RIGHT if float(side[1]) <= 0.0 else Vector2.LEFT)
		result["shots"][side[0]] = await _pair(shadows, "lamp-" + str(side[0]))
	return result


func _gun_shot(level: Level, shadows: WallShadows) -> Dictionary:
	# 站在燈的左邊朝右照：敵人排在槍燈的光錐裡。
	var feet := _stand(level, -110.0)
	if feet == Vector2.INF:
		push_error("[WallShadowProbe] gun：找不到站的地方（用 --at=<欄> 指定）")
		_failures += 1
		return {"note": "找不到站的地方"}
	var layout := level._layout
	await _place_player(level, feet, Vector2.RIGHT)
	var foes := 0
	for step in 3:
		var at := feet + Vector2(56.0 + 34.0 * float(step), 0.0)
		if is_equal_approx(layout.floor_below(int(at.x / layout.tile_size), int(feet.y / layout.tile_size) - 3), feet.y):
			_spawn_foe(level, at - Vector2(0.0, 2.0))
			foes += 1
	await _settle(50)
	var result := await _pair(shadows, "gun")
	result["enemies"] = foes
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await _settle(4)
	return result


## 同一個畫面拍「影子開」與「影子關」，回傳診斷數字。
func _pair(shadows: WallShadows, name: String) -> Dictionary:
	# 把整個場景停住再拍：呼吸、蒸汽、閃爍與提示牌的動畫都停下來，兩張的差別就只剩影子。影子自己繼續更新。
	var mode_before := shadows.process_mode
	shadows.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	shadows.suspended = false
	await _settle(8)
	var on := Capture.image(get_viewport())
	var record := {"lights": shadows.active_lights(), "silhouette_share": _silhouette_share(shadows)}
	on.save_png(_out.path_join("%s-%s-on.png" % [_tag, name]))
	shadows.suspended = true
	await _settle(8)
	var off := Capture.image(get_viewport())
	off.save_png(_out.path_join("%s-%s-off.png" % [_tag, name]))
	shadows.suspended = false
	get_tree().paused = false
	shadows.process_mode = mode_before
	record["shadowed_share"] = _shadowed_share(on, off)
	if shadows.is_enabled() and (int(record["lights"]) == 0 or float(record["silhouette_share"]) <= 0.0 or float(record["shadowed_share"]) < MIN_SHADOW_SHARE):
		push_error("[WallShadowProbe] %s 沒有影子（燈 %d 盞、輪廓 %.4f、變暗的畫面比例 %.4f）" % [name, record["lights"], record["silhouette_share"], record["shadowed_share"]])
		_failures += 1
	print("WALL_SHADOW:", name, " ", JSON.stringify(record))
	return record


func _silhouette_share(shadows: WallShadows) -> float:
	var texture := shadows.silhouette()
	if texture == null:
		return 0.0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return 0.0
	var covered := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			covered += int(image.get_pixel(x, y).a > 0.5)
	return snappedf(float(covered) * 4.0 / float(image.get_width() * image.get_height()), 0.0001)


## 影子開的那張比影子關的那張暗兩成以上的畫面比例，扣掉反過來（關的比開的暗）的比例：
## 蒸汽、雨與閃爍讓兩張本來就有些不同，兩個方向相減才是影子造成的。
func _shadowed_share(on: Image, off: Image) -> float:
	var darker := 0
	var brighter := 0
	var count := 0
	for y in range(0, on.get_height(), 3):
		for x in range(0, on.get_width(), 3):
			var with_shadow := on.get_pixel(x, y).get_luminance()
			var without := off.get_pixel(x, y).get_luminance()
			count += 1
			if maxf(with_shadow, without) < 0.004:
				continue
			darker += int(with_shadow < without * 0.8)
			brighter += int(without < with_shadow * 0.8)
	return snappedf(float(darker - brighter) / float(maxi(count, 1)), 0.0001)


func _spawn_foe(level: Level, position: Vector2) -> Enemy:
	var data := load(ENEMY_PATH) as EnemyData
	var enemy := level._create_enemy(data)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.position = position
	enemy.facing = -1
	level._entities.add_child(enemy)
	enemy.health.setup(999, 0.0)
	return enemy


## 12 個敵人：影子開與關交替量每影格耗時。
func _perf(level: Level, shadows: WallShadows) -> Dictionary:
	var feet := _stand(level)
	if feet == Vector2.INF:
		push_error("[WallShadowProbe] perf：找不到站的地方（用 --at=<欄> 指定）")
		_failures += 1
		return {"note": "找不到站的地方"}
	var layout := level._layout
	await _place_player(level, feet, Vector2.RIGHT)
	var placed := 0
	var column := 0
	while placed < PERF_ENEMIES and column < 60:
		column += 1
		var x := feet.x + (float(column) * 18.0 if column % 2 == 0 else -float(column) * 18.0)
		var floor_y := layout.floor_below(int(x / layout.tile_size), int(feet.y / layout.tile_size) - 3)
		if floor_y != INF and absf(floor_y - feet.y) <= 48.0:
			_spawn_foe(level, Vector2(x, floor_y - 2.0))
			placed += 1
	await _settle(60)
	var vsync_before := DisplayServer.window_get_vsync_mode()
	var fps_before := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var on: Array[float] = []
	var off: Array[float] = []
	var ratios: Array[float] = []
	for round_index in PERF_ROUNDS:
		var pair := [0.0, 0.0]
		for enabled: bool in ([true, false] if round_index % 2 == 0 else [false, true]):
			shadows.suspended = not enabled
			await _settle(6)
			pair[int(enabled)] = await _frame_ms()
		on.append(pair[1])
		off.append(pair[0])
		ratios.append(pair[1] / maxf(pair[0], 0.0001))
	shadows.suspended = false
	DisplayServer.window_set_vsync_mode(vsync_before)
	Engine.max_fps = fps_before
	on.sort()
	off.sort()
	ratios.sort()
	var record := {"enemies": placed, "lights": shadows.active_lights(), "frame_ms_on": snappedf(on[on.size() / 2], 0.001),
		"frame_ms_off": snappedf(off[off.size() / 2], 0.001), "ratio": snappedf((ratios[ratios.size() / 2 - 1] + ratios[ratios.size() / 2]) * 0.5, 0.001),
		"ratio_quartiles": [snappedf(ratios[ratios.size() / 4], 0.001), snappedf(ratios[ratios.size() * 3 / 4], 0.001)]}
	print("WALL_SHADOW_PERF:", JSON.stringify(record))
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await _settle(4)
	return record


## 相鄰兩格間隔的中位數（毫秒）。
func _frame_ms() -> float:
	var samples := PackedFloat32Array()
	samples.resize(PERF_FRAMES)
	var last := Time.get_ticks_usec()
	for index in PERF_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples[index] = float(now - last) / 1000.0
		last = now
	samples.sort()
	return samples[PERF_FRAMES / 2]


## 反覆進出關卡：節點數與貼圖記憶體不應該一次比一次多。
func _reenter(data: LevelData) -> Dictionary:
	var nodes: Array[int] = []
	var textures: Array[float] = []
	for index in REENTER_TIMES:
		var level := await _open(data)
		await _settle(20)
		level.queue_free()
		await _settle(12)
		nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		textures.append(snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.01))
	# 貼圖記憶體會在幾個數字之間來回（釋放的時機不固定），所以比的是最後三次與最前面三次的最大值。
	var early := maxf(textures[0], maxf(textures[1], textures[2]))
	var late := maxf(textures[REENTER_TIMES - 1], maxf(textures[REENTER_TIMES - 2], textures[REENTER_TIMES - 3]))
	var grew := nodes[REENTER_TIMES - 1] > nodes[1] or late > early * 1.02 + 0.5
	if grew:
		push_error("[WallShadowProbe] 反覆進出關卡後資源累積：節點 %s、貼圖 %s MiB" % [str(nodes), str(textures)])
		_failures += 1
	print("WALL_SHADOW_REENTER:nodes ", nodes, " textures_mib ", textures)
	return {"nodes": nodes, "texture_mib": textures, "accumulates": grew}
