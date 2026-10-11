extends Node
## 序章訓練器材的畫面檢查（BG-37）：在正式的序章地圖上，把鏡頭對準每一站，拍三種狀態
## （還沒輪到、現在練這個、完成），鋼靶與假人拍被打中的晃動連續格，訓練器拍後拉、出手、收回，
## 並量狀態燈周圍的全白像素比例（門檻 2%）與器材本體的平均亮度（太暗表示輪廓看不到）。
## 用法（原生 Forward+）：
##   godot --path . res://tools/training_art_probe.tscn -- --out=<絕對資料夾> [--quality=low|medium|high] [--tag=<名稱>] [--fallback]
##   --fallback：不載入器材圖，拍原本的簡單畫法（當修前對照）。
## 輸出 <tag>-<站>-<狀態>.png 與 <tag>-report.json；任一站超標以非零結束。

const Capture := preload("res://tools/viewport_capture.gd")
const LEVEL := "res://data/levels/ch1_prologue.tres"
const WHITE := 0.92
const MAX_LAMP_WHITE := 0.02
## 器材本體的平均亮度低於這個值，在畫面上只剩一塊黑影。
const MIN_BODY_LUMA := 0.035
const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const KIND_NAMES := {
	TrainingData.Kind.TARGET: "target",
	TrainingData.Kind.DUMMY: "dummy",
	TrainingData.Kind.TRAINER: "trainer",
	TrainingData.Kind.DASH_LINE: "dash",
}

var _out := ""
var _tag := "training"
var _quality := ""
var _fallback := false
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--quality="):
			_quality = arg.trim_prefix("--quality=")
		elif arg == "--fallback":
			_fallback = true
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[TrainingArtProbe] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await _settle(30)
	level.hud.visible = false
	for child: Node in level.get_children():
		if child is ChapterCard:
			child.queue_free()
	# 主角藏起來、停住，但每一站都擺到器材旁邊：光影分區與他身上的光和實際遊玩時一樣。
	level.player.visible = false
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	level._lighting._lightning_gap = 1.0e9
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.set_physics_process(false)
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * LevelCamera.base_zoom()
	var report: Array[Dictionary] = []
	for node in level.find_children("*", "TrainingStation", true, false):
		var station := node as TrainingStation
		if not KIND_NAMES.has(station.data.kind):
			continue
		report.append(await _shoot(station, camera))
	var file := FileAccess.open(_out.path_join("%s-report.json" % _tag), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"quality": _quality, "fallback": _fallback, "stations": report}, "  "))
	Settings.set_light_quality(quality_before)
	print("[TrainingArtProbe] %d 站，超標 %d 項" % [report.size(), _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _shoot(station: TrainingStation, camera: LevelCamera) -> Dictionary:
	var kind: String = KIND_NAMES[station.data.kind]
	var label := "%s-%s" % [kind, String(station.data.id).trim_prefix("ch1_training_")]
	if _fallback and station._art != null:
		station._art.queue_free()
		station._art = null
		station.material = null
	# 這個工具自己切換狀態，不讓訓練站依旗標改回去，也不讓它真的出手。
	station.set_physics_process(false)
	station.get_tree().get_first_node_in_group(&"player").global_position = station.global_position + Vector2(-44.0, 0.0)
	camera.global_position = station.global_position + Vector2(0.0, -34.0)
	camera.reset_smoothing()
	camera.force_update_scroll()
	var result := {"station": String(station.data.id), "kind": kind, "has_art": station._art != null}
	for state: String in ["idle", "active", "done"]:
		station._active = state == "active"
		station._done = state == "done"
		station._phase = &"idle"
		station.queue_redraw()
		await _settle(20)
		var image := _capture("%s-%s" % [label, state])
		result["lamp_white_" + state] = snappedf(_lamp_white(station, image), 0.0001)
		if state == "idle":
			result["body_luma"] = snappedf(_body_luma(station, image), 0.0001)
	station._done = false
	station._active = true
	if station.data.kind in [TrainingData.Kind.TARGET, TrainingData.Kind.DUMMY] and station._art != null:
		station._flash = 0.2
		station._art.hit(1.0)
		for frame in 6:
			await _wait(0.05)
			_capture("%s-hit-%d" % [label, frame])
		await _wait(1.2)
	if station.data.kind == TrainingData.Kind.TRAINER:
		station._phase = &"warn"
		station._pose_arms(&"warn")
		station.queue_redraw()
		await _wait(TrainingStation.TRAINER_WARN)
		var warn := _capture("%s-warn" % label)
		result["lamp_white_warn"] = snappedf(_lamp_white(station, warn), 0.0001)
		station._phase = &"cooldown"
		station._flash = 0.25
		station._strike_side = -1.0
		station._pose_arms(&"strike", -1)
		station.queue_redraw()
		await _wait(0.08)
		_capture("%s-strike" % label)
		station._pose_arms(&"rest")
		await _wait(1.0)
		_capture("%s-rest" % label)
	for key: String in result.keys():
		if key.begins_with("lamp_white_") and float(result[key]) > MAX_LAMP_WHITE:
			_failures += 1
			push_error("[TrainingArtProbe] %s 的狀態燈過曝（%s 全白比例 %.3f，門檻 %.2f）" % [label, key, result[key], MAX_LAMP_WHITE])
	if float(result.get("body_luma", 1.0)) < MIN_BODY_LUMA:
		_failures += 1
		push_error("[TrainingArtProbe] %s 的器材太暗，輪廓看不到（平均亮度 %.3f，門檻 %.3f）" % [label, result["body_luma"], MIN_BODY_LUMA])
	print("[TrainingArtProbe] %s %s" % [label, result])
	return result


func _capture(file_name: String) -> Image:
	var image := Capture.image(get_viewport())
	var path := _out.path_join("%s-%s.png" % [_tag, file_name])
	var err := image.save_png(path)
	if err != OK:
		push_error("[TrainingArtProbe] 無法寫入 %s（%s）" % [path, error_string(err)])
	return image


## 世界座標的矩形在截圖上的位置（專案用 stretch，要連最後的視窗變換一起算）。
func _screen_rect(world: Rect2, image: Image) -> Rect2i:
	var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var a := to_screen * world.position
	var b := to_screen * world.end
	var rect := Rect2(a, b - a).abs()
	return Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))


func _lamp_white(station: TrainingStation, image: Image) -> float:
	var at := station.global_position + (station._art.lamp_at if station._art != null else Vector2(0.0, -station.data.height))
	var rect := _screen_rect(Rect2(at - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), image)
	var white := 0
	var total := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pixel := image.get_pixel(x, y)
			total += 1
			if pixel.r > WHITE and pixel.g > WHITE and pixel.b > WHITE:
				white += 1
	return float(white) / float(maxi(total, 1))


func _body_luma(station: TrainingStation, image: Image) -> float:
	var height := station.data.height
	var rect := _screen_rect(Rect2(station.global_position + Vector2(-6.0, -height * 0.9), Vector2(12.0, height * 0.8)), image)
	var sum := 0.0
	var total := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			sum += image.get_pixel(x, y).get_luminance()
			total += 1
	return sum / float(maxi(total, 1))


## 動作用實際時間等（影格數會隨更新率變，量不到同一個瞬間）。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
