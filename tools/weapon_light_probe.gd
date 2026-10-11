extends ScenarioBase
## 槍燈巡檢（NE-258）：在真實關卡裡套上暗的光影設定，每把槍各朝三個方向照一次並拍照；再用同一把槍對著 8 格外的敵人，
## 比較開、關槍燈時敵人的輪廓對比，以及開、關時每影格實際花的時間。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/weapon_light_probe.tscn -- --out=<絕對資料夾>
##     [--level=ch1_warehouse] [--lighting=blackout] [--quality=low|medium|high] [--tag=<標籤>] [--weapons=pistol,rifle]
## 輸出 <標籤>-<武器>-<方向>.png、<標籤>-on.png、<標籤>-off.png 與 <標籤>-index.json。

const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const WEAPONS: PackedStringArray = ["pistol", "rifle", "smg", "spread", "launcher", "laser", "railgun"]
const DIRECTIONS := {"right": Vector2(1, 0), "up": Vector2(0.7, -0.7), "down_left": Vector2(-0.8, 0.6)}
## 敵人站在主角前方幾格（驗收條件是 8 格內看得到）。
const ENEMY_TILES := 8.0
const COMPARE_WEAPON := "rifle"
const FRAME_SAMPLES := 180
const CONTRAST_SAMPLES := 6
const TIMING_ROUNDS := 3

var _lighting := "blackout"
var _level_id := "ch1_warehouse"
var _quality := ""
var _tag := "light"
var _weapons := WEAPONS
var _aim_dir := Vector2.ZERO


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--level="):
			_level_id = argument.trim_prefix("--level=")
		elif argument.begins_with("--lighting="):
			_lighting = argument.trim_prefix("--lighting=")
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--weapons="):
			_weapons = argument.trim_prefix("--weapons=").split(",", false)
	if not out_dir.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[WeaponLightProbe] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("[WeaponLightProbe] 無法建立輸出資料夾：%s" % out_dir)
		get_tree().quit(2)
		return
	run.call_deferred()


func run() -> void:
	Story.auto_skip = true
	Story._layer.visible = false
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	var failures := 0
	var report := {"tag": _tag, "level": _level_id, "lighting": _lighting, "quality": _quality, "weapons": {}}
	seed(258)
	if not await _open_level():
		get_tree().quit(2)
		return
	AimInput.using_gamepad = true
	# 敵人站在主角前方 8 格、不會動也不會攻擊。
	var enemy := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.position = player.global_position + Vector2(ENEMY_TILES * 16.0, 0.0)
	level._entities.add_child(enemy)
	await settle(10)
	enemy.health.setup(999999, 0.0)  # 量開火時的耗時會一直打到它
	for id: String in _weapons:
		var path := "res://data/weapons/%s.tres" % id
		var weapon := load(path) as WeaponData if ResourceLoader.exists(path) else null
		if weapon == null:
			push_error("[WeaponLightProbe] 找不到武器：%s" % path)
			failures += 1
			continue
		player.loadout.equip(weapon)
		for name: String in DIRECTIONS:
			await _aim(DIRECTIONS[name])
			capture("%s-%s-%s" % [_tag, id, name])
		if _has_light():
			var lit := bool(_gun_light().call("is_lit"))
			report["weapons"][id] = {"range": weapon.get("light_range"), "cone_degrees": weapon.get("light_cone_degrees"),
				"energy": weapon.get("light_energy"), "lit": lit}
			if not lit:
				failures += 1
	# 開、關槍燈：同一把槍對著 8 格外的敵人。
	player.loadout.equip(load("res://data/weapons/%s.tres" % COMPARE_WEAPON) as WeaponData)
	await _aim(Vector2.RIGHT)
	report["on"] = {"enemy": await _enemy_contrast(enemy)}
	capture(_tag + "-on")
	_suppress(true)
	await wait(1.0)
	report["off"] = {"enemy": await _enemy_contrast(enemy)}
	capture(_tag + "-off")
	# 耗時：開、關交替各量幾輪再取中位數，免得先量的那一邊吃虧。沒有槍燈的舊版本兩邊量到的是同一件事。
	var idle := {"on": [], "off": []}
	var firing := {"on": [], "off": []}
	for round in TIMING_ROUNDS:
		for key: String in ["on", "off"]:
			_suppress(key == "off")
			await wait(0.6)
			(idle[key] as Array).append(await _frame_ms(false))
			(firing[key] as Array).append(await _frame_ms(true))
	for key: String in ["on", "off"]:
		(idle[key] as Array).sort()
		(firing[key] as Array).sort()
		report[key]["frame_ms_median"] = idle[key][TIMING_ROUNDS / 2]
		report[key]["firing_frame_ms_median"] = firing[key][TIMING_ROUNDS / 2]
	report["has_gun_light"] = _has_light()
	_suppress(false)
	_aim_dir = Vector2.ZERO
	AimInput.using_gamepad = false
	Settings.set_light_quality(quality_before)
	var writer := FileAccess.open(out_dir.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[WeaponLightProbe] 無法寫入索引：%s" % out_dir)
		failures += 1
	else:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("WEAPON_LIGHT_RESULT: on ", report["on"], " off ", report["off"], " failures ", failures)
	level.queue_free()
	await settle(4)
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if failures == 0 else 1)


## 開真實關卡並整關套上指定的光影設定；主角留在出生點，原本的敵人清掉。
func _open_level() -> bool:
	var level_path := "res://data/levels/%s.tres" % _level_id
	var lighting_path := "res://data/lighting/%s.tres" % _lighting
	if not ResourceLoader.exists(level_path) or not ResourceLoader.exists(lighting_path):
		push_error("[WeaponLightProbe] 找不到關卡或光影設定：%s、%s" % [level_path, lighting_path])
		return false
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var data := (load(level_path) as LevelData).duplicate() as LevelData
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load(lighting_path)
	data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(20)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level._lighting._lightning_gap = 1.0e9
	snap_camera()
	await wait(TITLE_CARD_TIME)
	return true


## 滑鼠只要在視窗上動一下，瞄準就會改回跟滑鼠；量測期間每一格都把瞄準方向設回來。
func _process(_delta: float) -> void:
	if _aim_dir != Vector2.ZERO:
		AimInput.using_gamepad = true
		AimInput._last_stick_dir = _aim_dir


## 主角的槍燈。用名稱取而不直接寫成員，這支工具才能原封不動拿去量還沒有槍燈的舊版本。
func _gun_light() -> Object:
	return player.get("_weapon_light") as Object


func _has_light() -> bool:
	return _gun_light() != null


func _suppress(off: bool) -> void:
	if _has_light():
		_gun_light().set("suppressed", off)


func _aim(direction: Vector2) -> void:
	_aim_dir = direction.normalized()
	AimInput._last_stick_dir = _aim_dir
	await wait(0.45)
	await RenderingServer.frame_post_draw


## 敵人的輪廓對比（和暗場可讀性量測同一套算法）與身上亮部的亮度（線性，0～1），各取幾次的中位數。
func _enemy_contrast(enemy: Enemy) -> Dictionary:
	var contrasts: Array[float] = []
	var brights: Array[float] = []
	for index in CONTRAST_SAMPLES:
		await RenderingServer.frame_post_draw
		var parts := ContrastProbe.capture(get_viewport()).character_parts(enemy.global_position)
		contrasts.append(maxf(parts["bright"], parts["dark"]))
		brights.append(parts["inner"])
		await wait(0.08)
	contrasts.sort()
	brights.sort()
	return {"contrast": contrasts[contrasts.size() / 2], "bright": brights[brights.size() / 2]}


## 關掉垂直同步，量相鄰兩格之間實際的間隔（毫秒）的中位數。firing＝量的時候用衝鋒槍連續開火（子彈、槍口火光、彈殼都在）。
func _frame_ms(firing: bool) -> float:
	var held := player.loadout.active_weapon()
	if firing:
		player.loadout.equip(load("res://data/weapons/smg.tres") as WeaponData)
		await settle(4)
	var vsync_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await settle(20)
	var values: Array[float] = []
	var last := Time.get_ticks_usec()
	for index in FRAME_SAMPLES:
		await get_tree().process_frame
		if firing:
			player.loadout.set_ammo(player.loadout.active_slot, 60, 600)
			player._fire_cooldown_left = minf(player._fire_cooldown_left, 0.05)
			player._try_fire()
		var now := Time.get_ticks_usec()
		values.append(float(now - last) / 1000.0)
		last = now
	DisplayServer.window_set_vsync_mode(vsync_before)
	if firing:
		player.loadout.equip(held)
		await wait(0.6)
	values.sort()
	return values[values.size() / 2]
