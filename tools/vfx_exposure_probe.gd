extends ScenarioBase
## 特效曝光巡檢（NE-95）：在每一份光影設定下各演一次槍口、敵人死亡與油桶爆炸，連拍幾個時刻。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/vfx_exposure_probe.tscn -- --out=<絕對資料夾>
##     [--lighting=market,blackout] [--quality=low|medium|high] [--tag=<標籤>] [--stress=<每波幾個爆炸>]
##     [--level=<關卡檔名> [--column=<主角站的欄>]]
## 輸出 <標籤>-<光影>-<時刻>.png 與 <標籤>-index.json（每張圖裡主角、敵人與爆炸在畫面上的位置），
## 再用 tools/vfx_exposure_sheet.py 算過曝比例並拼成一覽圖。油桶走真正的受擊與延遲爆炸。
## --level：不用測試場地，改在真實關卡演同一套（用關卡自己的光影、牆面與擺設；--lighting 不適用）。
##   沒給 --column 就在主角的出生點演；給了就站到那一欄最上面的地面。
## --stress：不拍照，改成連續幾波同時爆炸，關掉垂直同步量每影格實際間隔（<標籤>-stress.json）。

const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const PLAYER_TILE := 13.0
const WATCHER_TILE := 26.0
const VICTIM_TILE := 17.0
const BARREL_TILE := 19
## 爆炸後拍照的時刻（秒，從油桶被打破起算；爆炸在 Breakable.EXPLOSION_DELAY 之後）。
const BLAST_TIMES: Array[float] = [0.15, 0.25, 0.45, 0.85]
const BODY_SIZE := Vector2(26.0, 58.0)
const STRESS_WAVES := 12
const STRESS_GAP := 0.25

var _profiles: PackedStringArray = []
var _quality := ""
var _tag := "vfx"
var _stress := 0
var _level_id := ""
var _column := -1
## 主角腳底的位置；其他東西都用「離主角幾格」排。
var _origin := Vector2(PLAYER_TILE * 16.0, FLOOR_Y)
var _shots: Array[Dictionary] = []


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--lighting="):
			_profiles = argument.trim_prefix("--lighting=").split(",", false)
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--level="):
			_level_id = argument.trim_prefix("--level=")
		elif argument.begins_with("--column="):
			_column = int(argument.trim_prefix("--column="))
		elif argument.begins_with("--stress="):
			_stress = clampi(int(argument.trim_prefix("--stress=")), 1, 24)
	if not out_dir.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[VfxExposureProbe] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("[VfxExposureProbe] 無法建立輸出資料夾：%s" % out_dir)
		get_tree().quit(2)
		return
	if not _level_id.is_empty():
		_profiles = PackedStringArray([_level_id])
	if _profiles.is_empty():
		for file: String in DirAccess.get_files_at("res://data/lighting"):
			if file.ends_with(".tres"):
				_profiles.append(file.trim_suffix(".tres"))
		_profiles.sort()
	run.call_deferred()


func run() -> void:
	Story.auto_skip = true
	Story._layer.visible = false
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	var failures := 0
	for profile: String in _profiles:
		var path := "res://data/%s/%s.tres" % ["levels" if not _level_id.is_empty() else "lighting", profile]
		if not ResourceLoader.exists(path):
			push_error("[VfxExposureProbe] 找不到光影設定或關卡：%s" % path)
			failures += 1
			continue
		seed(95)
		if _level_id.is_empty():
			await open_arena(path, PLAYER_TILE)
		else:
			await _open_level(path)
		level._lighting._lightning_gap = 1.0e9
		if _stress > 0:
			await _stress_profile(profile)
		else:
			await _play_profile(profile)
		level.queue_free()
		level = null
		await settle(6)
	Settings.set_light_quality(quality_before)
	var writer := FileAccess.open(out_dir.path_join(_tag + ("-stress.json" if _stress > 0 else "-index.json")), FileAccess.WRITE)
	if writer == null:
		push_error("[VfxExposureProbe] 無法寫入索引：%s" % out_dir)
		failures += 1
	else:
		writer.store_string(JSON.stringify({"tag": _tag, "quality": _quality, "profiles": _profiles, "shots": _shots}, "\t"))
		writer.close()
	print("VFX_EXPOSURE_RESULT:", _shots.size(), " shots / ", failures, " failures")
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if failures == 0 else 1)


## 開真實關卡，主角站在 --column 那一欄的地面上，清掉原本的敵人。
func _open_level(path: String) -> void:
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(path) as LevelData)
	add_child(level)
	await settle(20)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	_origin = player.global_position
	if _column >= 0:
		var layout: LevelLayout = level._layout
		var column := mini(_column, layout.surface_heights.size() - 1)
		_origin = Vector2(column * layout.tile_size + layout.tile_size * 0.5, layout.surface_heights[column])
		player.global_position = _origin
		player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)


## 離主角 tiles 格的地面位置。
func _spot(tile: float) -> Vector2:
	return _origin + Vector2((tile - PLAYER_TILE) * 16.0, 0.0)


func _play_profile(profile: String) -> void:
	player.facing = 1
	await settle(10)
	_shoot(profile, "0-calm", Vector2.ZERO, 0.0)
	# 槍口：步槍一發，開火那一格。
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	player._fire_cooldown_left = 0.0
	player._try_fire()
	await RenderingServer.frame_post_draw
	_shoot(profile, "1-muzzle", player.aim_origin(), 24.0)
	AimInput.using_gamepad = false
	await wait(0.5)
	# 旁觀的敵人站在爆炸傷害範圍外、爆炸的光照得到的地方（子彈飛走之後才放，免得被打中）。
	var watcher := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	watcher.position = _spot(WATCHER_TILE)
	level._entities.add_child(watcher)
	watcher.process_mode = Node.PROCESS_MODE_DISABLED
	# 敵人死亡：一擊打倒，演出最亮的時候。
	var victim := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	victim.position = _spot(VICTIM_TILE)
	level._entities.add_child(victim)
	await wait(0.3)
	var at := victim.global_position + Vector2(0.0, -24.0)
	var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	lethal.bypass_guard = true
	lethal.origin = player.global_position
	victim.health.take_damage(lethal)
	await wait(0.1)
	_shoot(profile, "2-death", at, 40.0)
	await wait(1.4)
	# 油桶：真的受擊，延遲後爆炸。
	var barrel := Breakable.new()
	var barrel_at := _spot(float(BARREL_TILE)) - Vector2(8.0, 0.0)
	barrel.configure(load("res://data/props/barrel.tres") as BreakableData, Vector2i(int(barrel_at.x / 16.0), int(barrel_at.y / 16.0) - 1), 16)
	barrel.position = barrel_at
	level._entities.add_child(barrel)
	await settle(6)
	var center := barrel.world_center()
	var radius := barrel.data.explosion_radius
	barrel.hit_by_projectile(DamageInfo.create(9, Combat.Team.PLAYER, &"shot"))
	var elapsed := 0.0
	for index in BLAST_TIMES.size():
		await wait(BLAST_TIMES[index] - elapsed)
		elapsed = BLAST_TIMES[index]
		_shoot(profile, "%d-blast-%03d" % [3 + index, int(BLAST_TIMES[index] * 100.0)], center, radius)
	await wait(0.8)
	# 半空中的小爆炸（頭目身上的連環爆）與冷色的爆炸（自爆兵的連鎖）：不貼地、不同顏色也要成形。
	var air := _spot(BARREL_TILE - 1.5) + Vector2(0.0, -70.0)
	var chain := _spot(BARREL_TILE + 3.5) + Vector2(0.0, -60.0)
	Fx.explosion(air, 26.0, 0, Combat.Team.PLAYER, &"vfx_probe", Palette.WARNING)
	Fx.explosion(chain, 40.0, 0, Combat.Team.PLAYER, &"vfx_probe", Palette.CYAN)
	var middle := (air + chain) * 0.5
	await wait(0.05)
	_shoot(profile, "7-air-005", middle, 64.0)
	await wait(0.2)
	_shoot(profile, "8-air-025", middle, 64.0)
	await wait(0.9)


## 連續幾波同時爆炸（排在主角前方的地面上），量每影格實際間隔的中位數與最慢的一成。
func _stress_profile(profile: String) -> void:
	var vsync_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await settle(20)
	var frame_ms: Array[float] = []
	var last_usec := Time.get_ticks_usec()
	for wave in STRESS_WAVES:
		for index in _stress:
			var at := _spot(PLAYER_TILE + 4.0 + float(index) * 1.5) + Vector2(0.0, -8.0)
			Fx.explosion(at, 44.0, 0, Combat.Team.PLAYER, &"vfx_probe")
		var until := Time.get_ticks_msec() + int(STRESS_GAP * 1000.0)
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			var now_usec := Time.get_ticks_usec()
			frame_ms.append(float(now_usec - last_usec) / 1000.0)
			last_usec = now_usec
	DisplayServer.window_set_vsync_mode(vsync_before)
	frame_ms.sort()
	_shots.append({"profile": profile, "explosions_per_wave": _stress, "waves": STRESS_WAVES, "frames": frame_ms.size(),
		"frame_ms_median": frame_ms[frame_ms.size() / 2], "frame_ms_p90": frame_ms[int(frame_ms.size() * 0.9)], "frame_ms_max": frame_ms[-1]})
	print("VFX_STRESS:", profile, " median ", frame_ms[frame_ms.size() / 2], " ms p90 ", frame_ms[int(frame_ms.size() * 0.9)], " ms max ", frame_ms[-1], " ms")
	await wait(1.5)


## 拍一張並記下主角、旁觀敵人與特效中心在畫面上的位置。
func _shoot(profile: String, moment: String, effect_at: Vector2, effect_radius: float) -> void:
	var file := "%s-%s-%s" % [_tag, profile, moment]
	capture(file)
	var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var scale := to_screen.get_scale().x
	var effect := to_screen * effect_at
	_shots.append({"file": file + ".png", "profile": profile, "moment": moment,
		"player": _body_rect(to_screen, player.global_position), "watcher": _body_rect(to_screen, _spot(WATCHER_TILE)),
		"effect": [effect.x, effect.y, effect_radius * scale]})


func _body_rect(to_screen: Transform2D, feet: Vector2) -> Array:
	var top_left := to_screen * (feet + Vector2(-BODY_SIZE.x * 0.5, -BODY_SIZE.y))
	var bottom_right := to_screen * (feet + Vector2(BODY_SIZE.x * 0.5, 0.0))
	return [top_left.x, top_left.y, bottom_right.x - top_left.x, bottom_right.y - top_left.y]
