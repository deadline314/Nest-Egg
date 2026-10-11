extends ScenarioBase
## 近戰武器外觀與刃光的原生驗證（NE-260）。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/melee_art_probe.tscn -- --out=<絕對資料夾> [--tag=<標籤>] [--lighting=warehouse_interior]
##       [--perf] [--weapon=glaive] [--quality=low|medium|high]
## 在測試場地（預設套用倉庫的暗光影、槍燈本來就不會亮因為拿的是近戰武器）對五把近戰武器各拍：
##   拿在手上的待機一張、連段每一段出招那一刻各一張（真的按出連段，不是手動設定動作進度）。
## 另外放一個敵人在刀刃夠得到的地方，量「揮動那一刻」與「沒拿近戰武器」時敵人身上的亮度，確認刃光真的照亮敵人；
## 並量主角頭部的全白像素比例（白色頭髮不能因為刃光過曝）。「減少閃光」打開時再量一次揮動那一刻的刃光亮度。
## 每把武器再拍蹲下、跳到空中與衝刺中各一張（武器要一直握在手上），最後把五把武器的掉落物排成一列拍一張，
## 並把背包卡片圖示與武器欄圖示存成圖（三處要看得出是同一把）。
## 輸出 <標籤>-<武器>-idle.png、<標籤>-<武器>-<第幾段>-<招式>.png、<標籤>-<武器>-crouch／air／dash.png、
## <標籤>-pickups.png、<標籤>-icons.png 與 <標籤>-index.json。
## 每把武器第一招另外連拍 8 張（<標籤>-<武器>-film-<n>.png，每 3 個物理影格一張），看握法與武器的拖曳、跟隨。
## --perf 只量耗時：拿著離子戰戟（刃光最大）站著，刃光開與關成對交替量每影格耗時，取比值的中位數（垂直同步關閉）。

const WEAPONS: PackedStringArray = ["blade", "dagger", "glaive", "maul", "whip"]
const HEAD_BOX := Vector2(26.0, 26.0)
## 頭部全白像素比例的上限（和既有的曝光量測相同的門檻）。
const MAX_HEAD_WHITE := 0.02
const WHITE := 0.92

var _tag := "melee"
var _lighting := "warehouse_interior"
var _failures := 0
var _perf_only := false
var _perf_weapon := "glaive"
var _quality := ""

const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const PERF_FRAMES := 45
const FILM_SHOTS := 8
const FILM_EVERY := 3
const WHIP_FILM_SHOTS := 24
const WHIP_FILM_EVERY := 2
const WHIP_FILM_ZOOM := 2.2
const PERF_ROUNDS := 60


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--lighting="):
			_lighting = argument.trim_prefix("--lighting=")
		elif argument.begins_with("--quality="):
			_quality = argument.trim_prefix("--quality=")
		elif argument == "--perf":
			_perf_only = true
		elif argument.begins_with("--weapon="):
			_perf_weapon = argument.trim_prefix("--weapon=")
	if not out_dir.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[MeleeArtProbe] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	await open_arena("res://data/lighting/%s.tres" % _lighting, 12.0)
	if _perf_only:
		level.hud.visible = false
		await _perf()
		Settings.set_light_quality(quality_before)
		await finish()
		get_tree().quit(1 if _failures > 0 else 0)
		return
	var camera := get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE * 3.4
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	level.hud.visible = false
	player.health.setup(999, 0.0)
	var reduce_before := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(false)
	var report := {"tag": _tag, "lighting": _lighting, "weapons": {}}
	for weapon_id: String in WEAPONS:
		report["weapons"][weapon_id] = await _one_weapon(weapon_id, camera)
		await _poses(weapon_id, camera)
		report["weapons"][weapon_id]["film_hands"] = await _film(weapon_id, camera)
	Settings.set_reduce_flashes(reduce_before)
	await _pickups_and_icons(camera)
	var writer := FileAccess.open(out_dir.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer != null:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("MELEE_ART_PROBE failures ", _failures)
	Settings.set_light_quality(quality_before)
	await finish()
	get_tree().quit(1 if _failures > 0 else 0)


## 刃光開與關成對交替量每影格耗時。
func _perf() -> void:
	var camera := get_viewport().get_camera_2d()
	await _arm(load("res://data/weapons/melee/melee_%s.tres" % _perf_weapon) as WeaponData, camera)
	var blade := player.find_child("BladeLight", true, false) as BladeLight
	if blade == null or blade.energy() <= 0.0:
		push_error("[MeleeArtProbe] 沒有刃光可量")
		_failures += 1
		return
	var budget := level._light_budget
	budget.refresh()
	var active := budget.active_lights
	if active > LightQuality.max_lights():
		push_error("[MeleeArtProbe] 同時亮著 %d 盞燈，超過上限 %d" % [active, LightQuality.max_lights()])
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
			blade.light().visible = enabled
			await settle(6)
			pair[int(enabled)] = await _frame_ms()
		on_ms.append(pair[1])
		off_ms.append(pair[0])
		ratios.append(pair[1] / maxf(pair[0], 0.0001))
	blade.light().visible = true
	DisplayServer.window_set_vsync_mode(vsync_before)
	Engine.max_fps = fps_before
	ratios.sort()
	on_ms.sort()
	off_ms.sort()
	print("MELEE_ART_PERF:", JSON.stringify({"quality": _quality, "active_lights": active, "max_lights": LightQuality.max_lights(),
		"frame_ms_on": snappedf(on_ms[on_ms.size() / 2], 0.001), "frame_ms_off": snappedf(off_ms[off_ms.size() / 2], 0.001),
		"ratio": snappedf((ratios[ratios.size() / 2 - 1] + ratios[ratios.size() / 2]) * 0.5, 0.001)}))


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


## 第一招的連續影格（每 3 個物理影格一張，共 8 張）：看武器相對前臂怎麼落後、怎麼甩過去、怎麼收。
## 回傳每一張裡兩隻手在畫面上的位置（像素），放大檢查手腕與握把用。
func _film(weapon_id: String, camera: Camera2D) -> Array:
	var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
	var hands: Array = []
	await clear_enemies()
	await _arm(weapon, camera)
	# 鞭子甩得遠、繞過頭頂：鏡頭拉遠一點，拍密一點、久一點（連同收招後落下）。
	var whip := weapon.melee_shape == "whip"
	var zoom_before := camera.zoom
	if whip:
		camera.zoom = Vector2.ONE * WHIP_FILM_ZOOM
		camera.global_position = player.global_position + Vector2(60, -50)
		await settle(4)
	if not player._try_melee():
		camera.zoom = zoom_before
		return hands
	var rig := player._visual.rig
	for shot in (WHIP_FILM_SHOTS if whip else FILM_SHOTS):
		for i in (WHIP_FILM_EVERY if whip else FILM_EVERY):
			await get_tree().physics_frame
		await get_tree().process_frame
		# 先記下手的位置、等這一格畫完再存圖：直接存會拿到上一格的畫面，位置對不上。
		var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
		var front := to_screen * rig.bone(&"hand_front").global_position
		var back := to_screen * rig.bone(&"hand_back").global_position
		hands.append([front.x, front.y, back.x, back.y])
		await RenderingServer.frame_post_draw
		capture("%s-%s-film-%d" % [_tag, weapon_id, shot + 1])
	player._interrupt_melee()
	camera.zoom = zoom_before
	await settle(20)
	return hands


func _arm(weapon: WeaponData, camera: Camera2D) -> void:
	player._interrupt_melee()
	player.loadout.reset(weapon)
	player._melee_cooldown_left = 0.0
	player._melee_combo_left = 0.0
	place_player(12.0)
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	camera.global_position = player.global_position + Vector2(34, -30)
	await settle(40)


func _one_weapon(weapon_id: String, camera: Camera2D) -> Dictionary:
	var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
	var result := {"has_art": not MeleeArt.art(weapon).is_empty(), "moves": []}
	if not result["has_art"]:
		push_error("[MeleeArtProbe] %s 沒有圖（退回線條）" % weapon.id)
		_failures += 1
	await clear_enemies()
	await settle(4)
	# 對照：手上不是近戰武器時，敵人身上有多亮（槍燈先關掉）。
	var foe := spawn_enemy("res://data/enemies/sweeper.tres", 12.0 + maxf(1.6, weapon.melee_length * 0.75 / 16.0))
	foe.data = foe.data.duplicate()
	foe.data.detect_range = 0.0
	foe.data.attack_range = 0.0
	foe.data.move_speed = 0.0
	foe.health.setup(9999, 0.0)
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	await _arm(pistol, camera)
	var gun_light := player.get("_weapon_light") as Object
	if gun_light != null:
		gun_light.set("suppressed", true)
	await settle(30)
	result["foe_luma_without"] = _luma_at(foe)
	# 待機：拿在手上。
	await _arm(weapon, camera)
	var blade := player.find_child("BladeLight", true, false) as BladeLight
	capture("%s-%s-idle" % [_tag, weapon_id])
	result["idle_light"] = snappedf(blade.energy(), 0.001) if blade != null else 0.0
	result["foe_luma_idle"] = _luma_at(foe)
	result["head_white_idle"] = _head_white()
	if blade == null or blade.energy() <= 0.0:
		push_error("[MeleeArtProbe] %s 拿在手上沒有刃光" % weapon.id)
		_failures += 1
	# 連段：每一段在出招那一刻拍一張。
	var step := 0
	var swing_light := 0.0
	var swing_luma := 0.0
	var head_white := float(result["head_white_idle"])
	while step < 8:
		var started := player._try_melee() if step == 0 else player._start_melee_attack(true)
		if not started:
			break
		step += 1
		var limit := 240
		while player._melee_phase != Player.MeleePhase.ACTIVE and limit > 0:
			await get_tree().physics_frame
			limit -= 1
		if limit == 0:
			push_error("[MeleeArtProbe] %s 第 %d 段沒有進到出招" % [weapon.id, step])
			_failures += 1
			break
		await get_tree().process_frame
		await get_tree().process_frame
		player.set_physics_process(false)
		await settle(3)
		var name := str(player._melee_attack.get("id", player._melee_attack.get("pose", "move")))
		capture("%s-%s-%d-%s" % [_tag, weapon_id, step, name])
		swing_light = maxf(swing_light, blade.energy() if blade != null else 0.0)
		swing_luma = maxf(swing_luma, _luma_at(foe))
		head_white = maxf(head_white, _head_white())
		(result["moves"] as Array).append({"step": step, "move": name, "light": snappedf(blade.energy(), 0.001) if blade != null else 0.0})
		player.set_physics_process(true)
		# 等到可以接下一段（收招）。
		limit = 240
		while player._melee_phase != Player.MeleePhase.RECOVERY and player._melee_phase != Player.MeleePhase.NONE and limit > 0:
			await get_tree().physics_frame
			limit -= 1
		if player._melee_phase == Player.MeleePhase.NONE:
			break
	player._interrupt_melee()
	result["swing_light"] = snappedf(swing_light, 0.001)
	result["foe_luma_swing"] = snappedf(swing_luma, 0.0001)
	result["head_white_max"] = snappedf(head_white, 0.0001)
	if swing_light <= float(result["idle_light"]) * 1.2:
		push_error("[MeleeArtProbe] %s 揮動時刃光沒有變亮（%.3f → %.3f）" % [weapon.id, result["idle_light"], swing_light])
		_failures += 1
	if swing_luma <= float(result["foe_luma_without"]) * 1.15:
		push_error("[MeleeArtProbe] %s 揮動時敵人沒有被照亮（%.4f → %.4f）" % [weapon.id, result["foe_luma_without"], swing_luma])
		_failures += 1
	if head_white > MAX_HEAD_WHITE:
		push_error("[MeleeArtProbe] %s 的刃光讓主角的頭過曝（全白 %.3f）" % [weapon.id, head_white])
		_failures += 1
	# 減少閃光：揮動那一刻的刃光要比較暗。
	Settings.set_reduce_flashes(true)
	await _arm(weapon, camera)
	if player._try_melee():
		var limit := 240
		while player._melee_phase != Player.MeleePhase.ACTIVE and limit > 0:
			await get_tree().physics_frame
			limit -= 1
		await settle(3)
		result["swing_light_reduced"] = snappedf(blade.energy(), 0.001) if blade != null else 0.0
		if float(result["swing_light_reduced"]) >= swing_light * 0.95:
			push_error("[MeleeArtProbe] %s 打開減少閃光後揮動的刃光沒有降低（%.3f → %.3f）" % [weapon.id, swing_light, result["swing_light_reduced"]])
			_failures += 1
	player._interrupt_melee()
	Settings.set_reduce_flashes(false)
	print("MELEE_ART:", weapon_id, " ", JSON.stringify(result))
	return result


## 蹲下、空中、衝刺：武器握在手上的樣子。
func _poses(weapon_id: String, camera: Camera2D) -> void:
	var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
	await clear_enemies()
	await _arm(weapon, camera)
	Input.action_press(&"move_down")
	await settle(30)
	capture("%s-%s-crouch" % [_tag, weapon_id])
	Input.action_release(&"move_down")
	await settle(20)
	Input.action_press(&"jump")
	await settle(3)
	Input.action_release(&"jump")
	await settle(10)
	camera.global_position = player.global_position + Vector2(34, -30)
	await settle(2)
	capture("%s-%s-air" % [_tag, weapon_id])
	await settle(70)
	Input.action_press(&"dash")
	await settle(2)
	Input.action_release(&"dash")
	await settle(4)
	camera.global_position = player.global_position + Vector2(34, -30)
	await settle(1)
	capture("%s-%s-dash" % [_tag, weapon_id])
	await settle(50)
	# 朝左站著一張：握法、圖層與另一隻手左右對調後要一樣。
	await _arm(weapon, camera)
	AimInput._last_stick_dir = Vector2.LEFT
	player.facing = -1
	player.aim_dir = Vector2.LEFT
	camera.global_position = player.global_position + Vector2(-34, -30)
	await settle(40)
	capture("%s-%s-left" % [_tag, weapon_id])
	AimInput._last_stick_dir = Vector2.RIGHT
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	await settle(10)


## 五把武器的掉落物排成一列，以及背包卡片與武器欄的圖示。
func _pickups_and_icons(camera: Camera2D) -> void:
	await clear_enemies()
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	await _arm(pistol, camera)
	var pickups: Array[Node] = []
	for index in WEAPONS.size():
		var pickup := WeaponPickup.new()
		pickup.weapon = load("res://data/weapons/melee/melee_%s.tres" % WEAPONS[index]) as WeaponData
		pickup.position = player.global_position + Vector2(26.0 + 24.0 * float(index), -14.0)
		level._entities.add_child(pickup)
		pickups.append(pickup)
	camera.global_position = player.global_position + Vector2(70, -30)
	await settle(30)
	capture("%s-pickups" % _tag)
	for pickup in pickups:
		pickup.queue_free()
	var scale := 4
	var sheet := Image.create(WEAPONS.size() * 80 * scale, (MeleeArt.ITEM_SIZE.y + MeleeArt.AMMO_SIZE.y + 12) * scale, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.11))
	for index in WEAPONS.size():
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % WEAPONS[index]) as WeaponData
		for pair: Array in [[MeleeArt.item_icon(weapon), 4], [MeleeArt.ammo_icon(weapon), MeleeArt.ITEM_SIZE.y + 8]]:
			var icon := (pair[0] as Texture2D).get_image()
			icon.convert(Image.FORMAT_RGBA8)
			icon.resize(icon.get_width() * scale, icon.get_height() * scale, Image.INTERPOLATE_NEAREST)
			sheet.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i((index * 80 + 8) * scale, int(pair[1]) * scale))
	sheet.save_png(out_dir.path_join(_tag + "-icons.png"))


## 敵人身上最亮的一成像素的平均亮度。
func _luma_at(foe: Enemy) -> float:
	if not is_instance_valid(foe):
		return 0.0
	var size := foe.data.body_size
	return _box_stat(Rect2(foe.global_position + Vector2(-size.x * 0.5, -size.y), size), false)


## 主角頭部全白像素的比例。
func _head_white() -> float:
	var head := player.global_position + Vector2(0.0, -Player.BODY_SIZE.y - 6.0)
	return _box_stat(Rect2(head - HEAD_BOX * 0.5, HEAD_BOX), true)


func _box_stat(world: Rect2, white_share: bool) -> float:
	var view := get_viewport()
	var image := preload("res://tools/viewport_capture.gd").image(view)
	var to_screen := view.get_final_transform() * view.get_canvas_transform()
	var a := to_screen * world.position
	var b := to_screen * world.end
	var rect := Rect2i(Vector2i(a), Vector2i(b - a)).abs().intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var values := PackedFloat32Array()
	var white := 0
	var count := 0
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			var pixel := image.get_pixel(x, y)
			count += 1
			white += int(pixel.r > WHITE and pixel.g > WHITE and pixel.b > WHITE)
			values.append(pixel.get_luminance())
	if count == 0:
		return 0.0
	if white_share:
		return snappedf(float(white) / float(count), 0.0001)
	values.sort()
	var from := int(values.size() * 0.9)
	var total := 0.0
	for index in range(from, values.size()):
		total += values[index]
	return snappedf(total / float(maxi(1, values.size() - from)), 0.0001)
