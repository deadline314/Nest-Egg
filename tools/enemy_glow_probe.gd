extends Node
## 敵人自帶光源的原生驗證（NE-259）。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/enemy_glow_probe.tscn -- --out=<絕對資料夾> [--level=ch1_warehouse] [--tag=<標籤>]
##     [--quality=low|medium|high] [--enemies=watchdog,heavy_gunner] [--plain=sweeper]
## 在暗的區域把主角的槍燈關掉，放上帶燈的敵人與一個不帶燈的一般敵人當對照，拍三種狀態各一張
## （calm 平常、alert 發現主角、telegraph 準備攻擊），再擊殺拍熄滅的過程，最後放 6 個帶燈的敵人量燈數與每影格耗時。
## 輸出 <標籤>-<狀態>.png、<標籤>-death.png（擊殺後每 0.1 秒一格）與 <標籤>-index.json：
## 每個敵人在每種狀態下身上的亮度（取敵人所在的框裡最亮的 10% 的平均）、光的亮度比例與顏色、擊殺後多久熄滅，
## 以及 6 個帶燈敵人時同時亮著的燈數（不能超過光影品質的上限）與「光開、光關」成對交替量到的耗時比。

const Capture := preload("res://tools/viewport_capture.gd")
const SETTLE_FRAMES := 40
const STATES: Array[StringName] = [&"calm", &"alert", &"telegraph"]
const PERF_ENEMIES := 6
const PERF_FRAMES := 45
const PERF_ROUNDS := 60
const DEATH_SHOTS := 8
const DEATH_INTERVAL := 0.1
const DEATH_CROP := Vector2i(150, 190)
const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}

var _out := ""
var _level := "ch1_warehouse"
var _tag := "glow"
var _quality := ""
var _enemy_ids: PackedStringArray = ["watchdog", "heavy_gunner"]
var _plain := "sweeper"
var _failures := 0
var _forced: StringName = &"calm"
var _subjects: Array[Enemy] = []


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
		elif argument.begins_with("--enemies="):
			_enemy_ids = argument.trim_prefix("--enemies=").split(",", false)
		elif argument.begins_with("--plain="):
			_plain = argument.trim_prefix("--plain=")
	if not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[EnemyGlowProbe] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[EnemyGlowProbe] 無法建立輸出資料夾：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


## 每一格把敵人固定在要拍的狀態：戒備與攻擊預兆都會自己倒數結束。
func _process(_delta: float) -> void:
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	for enemy: Enemy in _subjects:
		if not is_instance_valid(enemy) or enemy.is_dying():
			continue
		enemy._alert_left = 5.0 if _forced != &"calm" else 0.0
		enemy._telegraph_left = 5.0 if _forced == &"telegraph" else 0.0
		# 主角就站在旁邊，會醒的敵人（看門狗）早就醒了：拍「平常」時把它放回資料列的平靜狀態。
		var calm := enemy.data.light_calm_states if not enemy.data.light_calm_states.is_empty() else enemy.data.relaxed_states
		if _forced == &"calm" and not calm.is_empty() and not calm.has(String(enemy.fsm.current)) and enemy.fsm.has(StringName(calm[0])):
			enemy.fsm.transition(StringName(calm[0]))


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
	var report := {"tag": _tag, "level": _level, "quality": _quality, "max_lights": LightQuality.max_lights()}
	var path := "res://data/levels/%s.tres" % _level
	var data := load(path) as LevelData if ResourceLoader.exists(path) else null
	if data == null:
		push_error("[EnemyGlowProbe] 找不到關卡：%s" % path)
		_failures += 1
	else:
		var level := await _open(data)
		var feet := _floor_spot(level)
		if feet == Vector2.INF:
			push_error("[EnemyGlowProbe] %s 找不到一段平的地面" % _level)
			_failures += 1
		else:
			report["states"] = await _state_shots(level, feet)
			report["death"] = await _death_shots(level)
			report["perf"] = await _perf(level, feet)
		level.queue_free()
		await _settle(4)
	if QUALITY.has(_quality):
		Settings.set_light_quality(quality_before)
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[EnemyGlowProbe] 無法寫入索引：%s" % _out)
		_failures += 1
	else:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("ENEMY_GLOW_PROBE:", _level, " failures ", _failures)
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
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for node: Node in level.find_children("*", "Node2D", true, false):
		if node is Lamp and not (node as Lamp).dead:
			(node as Lamp).use_flicker(LampFlicker.STABLE, 0)
	# 槍燈關掉：要看的是「不用槍燈也看得到帶燈的敵人在哪裡」。
	var gun_light := level.player.get("_weapon_light") as Object
	if gun_light != null:
		gun_light.set("suppressed", true)
	await _settle(4)
	return level


## 主角腳下往右有一段平的地面可以排敵人。回傳主角腳底的位置。
func _floor_spot(level: Level) -> Vector2:
	var layout := level._layout
	var start := level.player.global_position
	var row := maxi(0, int(start.y / layout.tile_size) - 3)
	for column in range(int(start.x / layout.tile_size), layout.surface_heights.size() - 22):
		var floor_y := layout.floor_below(column, row)
		if floor_y == INF:
			continue
		var flat := true
		for step in range(1, 20):
			flat = flat and is_equal_approx(layout.floor_below(column + step, row), floor_y)
		if flat:
			return Vector2(float(column) * layout.tile_size + 8.0, floor_y)
	return Vector2.INF


func _spawn(level: Level, id: String, feet: Vector2) -> Enemy:
	var path := "res://data/enemies/%s.tres" % id
	var data := load(path) as EnemyData if ResourceLoader.exists(path) else null
	if data == null:
		push_error("[EnemyGlowProbe] 找不到敵人資料：%s" % path)
		_failures += 1
		return null
	var enemy := level._create_enemy(data)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.position = feet - Vector2(0.0, 2.0)
	enemy.facing = -1
	level._entities.add_child(enemy)
	enemy.health.setup(999, 0.0)
	return enemy


func _state_shots(level: Level, feet: Vector2) -> Dictionary:
	level.player.global_position = feet - Vector2(0.0, 2.0)
	level.player.velocity = Vector2.ZERO
	_subjects.clear()
	var x := feet.x + 70.0
	for id: String in _enemy_ids:
		var enemy := _spawn(level, id, Vector2(x, feet.y))
		if enemy != null:
			_subjects.append(enemy)
			x += enemy.data.body_size.x + 60.0
	var plain := _spawn(level, _plain, Vector2(x + 10.0, feet.y))
	await _settle(40)
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null:
		camera.snap_to_target()
	await _settle(150)
	var result := {}
	for state: StringName in STATES:
		_forced = state
		await _settle(60)
		var image := Capture.image(get_viewport())
		image.save_png(_out.path_join("%s-%s.png" % [_tag, state]))
		var row := {}
		for enemy: Enemy in _subjects:
			var glow := enemy.find_child("EnemyGlow", false, false) as EnemyGlow
			if glow == null:
				push_error("[EnemyGlowProbe] %s 沒有自帶的光（資料的 Light 群組沒有設定）" % enemy.data.id)
				_failures += 1
				continue
			if glow.state() != state:
				push_error("[EnemyGlowProbe] %s 應該是 %s，實際是 %s" % [enemy.data.id, state, glow.state()])
				_failures += 1
			row[String(enemy.data.id)] = {"state": String(glow.state()), "level": snappedf(glow.level(), 0.01),
				"color": glow.light().color.to_html(false), "body_luma": _body_luma(image, enemy)}
		if is_instance_valid(plain):
			row[String(plain.data.id) + "（不帶燈）"] = {"glow": plain.find_child("EnemyGlow", false, false) != null, "body_luma": _body_luma(image, plain)}
		result[String(state)] = row
		print("ENEMY_GLOW:", state, " ", JSON.stringify(row))
	_forced = &"calm"
	if is_instance_valid(plain) and plain.find_child("EnemyGlow", false, false) != null:
		push_error("[EnemyGlowProbe] 一般敵人 %s 不應該帶燈" % _plain)
		_failures += 1
	return result


## 敵人所在的框裡最亮的一成像素的平均亮度：暗的區域裡看不看得到它。
func _body_luma(image: Image, enemy: Enemy) -> float:
	var view := get_viewport()
	var to_screen := view.get_final_transform() * view.get_canvas_transform()
	var size := enemy.data.body_size
	var top_left := to_screen * (enemy.global_position + Vector2(-size.x * 0.5, -size.y))
	var bottom_right := to_screen * (enemy.global_position + Vector2(size.x * 0.5, 0.0))
	var rect := Rect2i(Vector2i(top_left), Vector2i(bottom_right - top_left)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var values := PackedFloat32Array()
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			values.append(image.get_pixel(x, y).get_luminance())
	if values.is_empty():
		return 0.0
	values.sort()
	var from := int(values.size() * 0.9)
	var total := 0.0
	for index in range(from, values.size()):
		total += values[index]
	return snappedf(total / float(maxi(1, values.size() - from)), 0.0001)


## 擊殺第一個帶燈的敵人，每 0.1 秒拍一格，看光在死亡演出內熄滅。
func _death_shots(level: Level) -> Dictionary:
	if _subjects.is_empty() or not is_instance_valid(_subjects[0]):
		return {"note": "沒有帶燈的敵人"}
	var enemy := _subjects[0]
	var glow := enemy.find_child("EnemyGlow", false, false) as EnemyGlow
	var light := glow.light() if glow != null else null
	var view := get_viewport()
	var screen := view.get_final_transform() * view.get_canvas_transform() * (enemy.global_position - Vector2(0.0, enemy.data.body_size.y * 0.5))
	var sheet := Image.create(DEATH_CROP.x * DEATH_SHOTS, DEATH_CROP.y, false, Image.FORMAT_RGB8)
	var info := DamageInfo.new()
	info.amount = 99999
	info.team = Combat.Team.PLAYER
	enemy.health.kill(info)
	var elapsed := 0.0
	var taken := 0
	var dark_at := -1.0
	while taken < DEATH_SHOTS or (dark_at < 0.0 and elapsed < 3.0):
		await RenderingServer.frame_post_draw
		elapsed += get_process_delta_time()
		if dark_at < 0.0 and (light == null or not is_instance_valid(light) or not light.enabled or light.energy <= 0.02):
			dark_at = elapsed
		if taken < DEATH_SHOTS and elapsed >= float(taken) * DEATH_INTERVAL:
			var frame := Capture.image(view)
			frame.convert(Image.FORMAT_RGB8)
			var origin := Vector2i(int(screen.x) - DEATH_CROP.x / 2, int(screen.y) - DEATH_CROP.y / 2)
			var source := Rect2i(origin, DEATH_CROP).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
			sheet.blit_rect(frame, source, Vector2i(taken * DEATH_CROP.x, 0) + source.position - origin)
			taken += 1
	sheet.save_png(_out.path_join(_tag + "-death.png"))
	if dark_at < 0.0:
		push_error("[EnemyGlowProbe] %s 死亡 3 秒後光還亮著" % enemy.data.id)
		_failures += 1
	print("ENEMY_GLOW_DEATH:", enemy.data.id, " dark after ", snappedf(dark_at, 0.01), " s")
	return {"enemy": String(enemy.data.id), "dark_after_seconds": snappedf(dark_at, 0.01)}


## 6 個帶燈的敵人：同時亮著的燈數與「光開、光關」成對交替的耗時比。
func _perf(level: Level, feet: Vector2) -> Dictionary:
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	_subjects.clear()
	await _settle(6)
	var glows: Array[EnemyGlow] = []
	for index in PERF_ENEMIES:
		var enemy := _spawn(level, _enemy_ids[_enemy_ids.size() - 1], Vector2(feet.x + 40.0 + 32.0 * float(index), feet.y))
		if enemy == null:
			continue
		var glow := enemy.find_child("EnemyGlow", false, false) as EnemyGlow
		if glow != null:
			glows.append(glow)
	await _settle(90)
	var budget := level._light_budget
	budget.refresh()
	var active := budget.active_lights
	if active > LightQuality.max_lights():
		push_error("[EnemyGlowProbe] 同時亮著 %d 盞燈，超過上限 %d" % [active, LightQuality.max_lights()])
		_failures += 1
	var vsync_before := DisplayServer.window_get_vsync_mode()
	var fps_before := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ratios: Array[float] = []
	var on_ms: Array[float] = []
	var off_ms: Array[float] = []
	for round_index in PERF_ROUNDS:
		var pair := [0.0, 0.0]
		for enabled: bool in ([true, false] if round_index % 2 == 0 else [false, true]):
			for glow in glows:
				glow.visible = enabled
				glow.set_process(enabled)
				glow.light().visible = enabled
			await _settle(6)
			pair[int(enabled)] = await _frame_ms()
		on_ms.append(pair[1])
		off_ms.append(pair[0])
		ratios.append(pair[1] / maxf(pair[0], 0.0001))
	for glow in glows:
		glow.visible = true
		glow.set_process(true)
		glow.light().visible = true
	DisplayServer.window_set_vsync_mode(vsync_before)
	Engine.max_fps = fps_before
	ratios.sort()
	on_ms.sort()
	off_ms.sort()
	var record := {"glowing_enemies": glows.size(), "active_lights": active, "max_lights": LightQuality.max_lights(),
		"frame_ms_on": snappedf(on_ms[on_ms.size() / 2], 0.001), "frame_ms_off": snappedf(off_ms[off_ms.size() / 2], 0.001),
		"ratio": snappedf((ratios[ratios.size() / 2 - 1] + ratios[ratios.size() / 2]) * 0.5, 0.001)}
	print("ENEMY_GLOW_PERF:", JSON.stringify(record))
	return record


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
