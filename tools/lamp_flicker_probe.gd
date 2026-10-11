extends Node
## 閃爍燈的量測與連拍（BG-35）：對關卡裡每一盞亮著的場景燈，統計一段時間內「任何一秒內亮度明顯變化幾次」（光敏安全的上限是 3），
## 並替每一種會閃的狀態各挑一盞連拍 3 秒，排成一張圖。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/lamp_flicker_probe.tscn -- --out=<絕對資料夾> --level=<關卡檔名，逗號分隔>
##     [--tag=<標籤>] [--seconds=10] [--reduce-flashes]
## --reduce-flashes：這次量測把設定的「減少閃光」打開（結束時還原），看閃爍有沒有改成緩慢的明暗起伏。
## 輸出 <標籤>-<關卡>-<狀態>.png（每 0.1 秒一格，共 3 秒）與 <標籤>-index.json：每盞燈的狀態、款式、最暗與最亮的比例、
## 一秒內最多變化幾次，以及這段時間電流聲最大的音量比例。有任何一盞超過上限就以失敗結束。
## 變化的算法：亮度比例從上一個轉折點起，往反方向走了門檻（LampFlicker.change_threshold）以上才算一次，緩慢的起伏不會被重複計算。

const Capture := preload("res://tools/viewport_capture.gd")
const SETTLE_FRAMES := 30
const BURST_SECONDS := 3.0
const BURST_INTERVAL := 0.1
const BURST_COLUMNS := 10
## 連拍時每一格從畫面上裁下來的大小（像素）：燈在上方中央，下面是它的光池。
const CROP := Vector2i(200, 250)
const CROP_ABOVE := 40
## 連拍從第一次明顯變化的前幾秒開始，這樣拍得到變化前、變化中與之後。
const BURST_LEAD := 0.8

var _out := ""
var _levels: PackedStringArray = []
var _tag := "flicker"
var _seconds := 10.0
var _reduce := false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--level="):
			_levels = argument.trim_prefix("--level=").split(",", false)
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--seconds="):
			_seconds = clampf(float(argument.trim_prefix("--seconds=")), 2.0, 60.0)
		elif argument == "--reduce-flashes":
			_reduce = true
	if not _out.is_absolute_path() or _levels.is_empty() or DisplayServer.get_name() == "headless":
		push_error("[LampFlickerProbe] 需要原生視窗、--out=<絕對資料夾> 與 --level=<關卡檔名>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[LampFlickerProbe] 無法建立輸出資料夾：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var reduce_before := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(_reduce)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	Story._layer.visible = false
	var failures := 0
	var report := {"tag": _tag, "reduce_flashes": _reduce, "seconds": _seconds, "limit": LampFlicker.change_limit(),
		"threshold": LampFlicker.change_threshold(), "levels": {}}
	for problem: String in LampFlicker.problems():
		push_error("[LampFlickerProbe] " + problem)
		failures += 1
	for level_id: String in _levels:
		var path := "res://data/levels/%s.tres" % level_id
		var data := load(path) as LevelData if ResourceLoader.exists(path) else null
		if data == null:
			push_error("[LampFlickerProbe] 找不到關卡：%s" % path)
			failures += 1
			continue
		var result := await _measure_level(level_id, data)
		report["levels"][level_id] = result
		failures += int(result["over_limit"])
	Settings.set_reduce_flashes(reduce_before)
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[LampFlickerProbe] 無法寫入索引：%s" % _out)
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
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.set_process(false)
	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	# 連拍：每一種會閃的狀態挑最左邊的一盞。
	var shot := {}
	var bursts := {}
	for lamp in lamps:
		if lamp.flicker_state != LampFlicker.STABLE and not shot.has(lamp.flicker_state):
			shot[lamp.flicker_state] = true
			bursts[String(lamp.flicker_state)] = await _burst(level_id, lamp, camera)
	# 統計：所有的燈同時記錄，鏡頭停在第一盞快壞的燈旁邊（順便看電流聲有沒有響）。
	var buzz := level.find_child("LampBuzz", true, false) as LampBuzz
	for lamp in lamps:
		if LampFlicker.buzz(lamp.flicker_state) > 0.0:
			camera.global_position = lamp.global_position + Vector2(0, 40)
			break
	var trackers: Array[Dictionary] = []
	for lamp in lamps:
		trackers.append({"ref": _shown(lamp), "dir": 0, "events": [], "low": 9.0, "high": 0.0})
	var elapsed := 0.0
	var buzz_peak := 0.0
	while elapsed < _seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		for index in lamps.size():
			_track(trackers[index], _shown(lamps[index]), elapsed)
		if buzz != null:
			buzz_peak = maxf(buzz_peak, buzz.gain())
	var records: Array[Dictionary] = []
	var over := 0
	var by_state := {}
	for index in lamps.size():
		var lamp := lamps[index]
		var worst := _worst_second(trackers[index]["events"])
		by_state[String(lamp.flicker_state)] = int(by_state.get(String(lamp.flicker_state), 0)) + 1
		if worst > LampFlicker.change_limit():
			over += 1
			push_error("[LampFlickerProbe] %s 第 %d 欄的燈一秒內亮度變化 %d 次，超過上限" % [level_id, int(lamp.position.x / 16.0), worst])
		records.append({"tile": [int(lamp.position.x / 16.0), int(lamp.position.y / 16.0)], "fixture": String(lamp.fixture_id),
			"state": String(lamp.flicker_state), "changes_total": (trackers[index]["events"] as Array).size(),
			"worst_second": worst, "lowest": snappedf(trackers[index]["low"], 0.01), "highest": snappedf(trackers[index]["high"], 0.01)})
	print("LAMP_FLICKER:%s lamps %d states %s worst-second %d buzz %.2f%s" % [level_id, lamps.size(), JSON.stringify(by_state),
		records.reduce(func(acc: int, r: Dictionary) -> int: return maxi(acc, int(r["worst_second"])), 0), buzz_peak,
		" (reduce flashes)" if _reduce else ""])
	level.queue_free()
	await _settle(4)
	return {"lamps": records, "states": by_state, "bursts": bursts, "buzz_peak": snappedf(buzz_peak, 0.01), "over_limit": over}


## 燈現在的亮度比例（閃爍、脈動、供電都算在內）。
func _shown(lamp: Lamp) -> float:
	if lamp._light == null or not lamp._light.enabled:
		return 0.0
	return lamp._light.energy / maxf(lamp.light_energy, 0.01)


## 轉折偵測：從上一個轉折點往反方向走了門檻以上才記一次變化。
func _track(tracker: Dictionary, value: float, time: float) -> void:
	tracker["low"] = minf(tracker["low"], value)
	tracker["high"] = maxf(tracker["high"], value)
	var threshold := LampFlicker.change_threshold()
	var ref: float = tracker["ref"]
	var dir: int = tracker["dir"]
	if dir == 0:
		if absf(value - ref) >= threshold:
			tracker["dir"] = 1 if value > ref else -1
			tracker["ref"] = value
			(tracker["events"] as Array).append(time)
	elif (value - ref) * dir > 0.0:
		tracker["ref"] = value
	elif absf(value - ref) >= threshold:
		tracker["dir"] = -dir
		tracker["ref"] = value
		(tracker["events"] as Array).append(time)


## 任何一秒內最多有幾次變化。
func _worst_second(events: Array) -> int:
	var worst := 0
	var first := 0
	for last in events.size():
		while events[last] - events[first] > 1.0:
			first += 1
		worst = maxi(worst, last - first + 1)
	return worst


## 把這盞燈的閃法倒回第一次明顯變化的前 BURST_LEAD 秒（「減少閃光」時是緩慢起伏，不用倒）。
func _rewind_before_change(lamp: Lamp) -> void:
	var values := lamp._pattern
	if values.is_empty() or _reduce:
		return
	for index in values.size():
		if absf(values[(index + 1) % values.size()] - values[index]) >= LampFlicker.change_threshold():
			var steps := posmod(index + 1 - lamp._pattern_offset, values.size())
			lamp._clock = fposmod(float(steps) / LampFlicker.step_hz() - BURST_LEAD, float(values.size()) / LampFlicker.step_hz())
			return


## 對準一盞燈連拍 3 秒，每 0.1 秒一格，裁出燈與它的光池排成一張。
func _burst(level_id: String, lamp: Lamp, camera: LevelCamera) -> String:
	camera.global_position = lamp.global_position + Vector2(0, 60)
	camera.reset_smoothing()
	await _settle(6)
	var view := get_viewport()
	var screen := view.get_final_transform() * view.get_canvas_transform() * lamp.global_position
	_rewind_before_change(lamp)
	var count := int(BURST_SECONDS / BURST_INTERVAL)
	var rows := ceili(float(count) / float(BURST_COLUMNS))
	var sheet := Image.create(CROP.x * BURST_COLUMNS, CROP.y * rows, false, Image.FORMAT_RGB8)
	var elapsed := 0.0
	var taken := 0
	while taken < count:
		await RenderingServer.frame_post_draw
		elapsed += get_process_delta_time()
		if elapsed < float(taken) * BURST_INTERVAL:
			continue
		var frame := Capture.image(view)
		frame.convert(Image.FORMAT_RGB8)
		var origin := Vector2i(int(screen.x) - CROP.x / 2, int(screen.y) - CROP_ABOVE)
		var source := Rect2i(origin, CROP).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
		sheet.blit_rect(frame, source, Vector2i((taken % BURST_COLUMNS) * CROP.x, (taken / BURST_COLUMNS) * CROP.y) + source.position - origin)
		taken += 1
	var file := "%s-%s-%s.png" % [_tag, level_id, lamp.flicker_state]
	sheet.save_png(_out.path_join(file))
	return file
