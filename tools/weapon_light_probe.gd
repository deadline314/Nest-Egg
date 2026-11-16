extends ScenarioBase
## 槍燈巡檢（NE-258）：在真實關卡裡套上暗的光影設定，每把槍各朝三個方向照一次並拍照；再用同一把槍對著 8 格外的敵人，
## 比較開、關槍燈時敵人的輪廓對比，以及開、關時每影格實際花的時間。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/weapon_light_probe.tscn -- --out=<絕對資料夾>
##     [--level=ch1_warehouse] [--lighting=blackout] [--quality=low|medium|high] [--tag=<標籤>] [--weapons=pistol,rifle]
##     [--phase=visual|exposure|perf-whole|perf-fixed|all] [--blank-head-mask] [--self-check]
## PNG、原格式HDR bytes與JSON保留實際幾何、門檻及逐格時間。效能須在沒有其他工作負載時獨占量測。

const QUALITY := {"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}
const WEAPONS: PackedStringArray = ["pistol", "rifle", "smg", "spread", "launcher", "laser", "railgun"]
const DIRECTIONS := {"right": Vector2(1, 0), "up": Vector2(0.7, -0.7), "down_left": Vector2(-0.8, 0.6)}
## 敵人站在主角前方幾格（驗收條件是 8 格內看得到）。
const ENEMY_TILES := 8.0
const COMPARE_WEAPON := "rifle"
const FRAME_SAMPLES := 45
const CONTRAST_SAMPLES := 6
const TIMING_ROUNDS := 60

var _lighting := "blackout"
var _level_id := "ch1_warehouse"
var _quality := ""
var _tag := "light"
var _weapons := WEAPONS
var _aim_dir := Vector2.ZERO
var _phase := "all"
var _failures := 0
var _checks: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _fixed_body_glow := false
var _render_glow_radius := 0.0
var _projectiles_spawned := 0
var _accepted_shots := 0
var _perf_sound: StringName = &""
var _blank_head_mask := false
var _comparison := "whole_feature"
var _reload_events: Array[Dictionary] = []
var _hidden_prompts := 0


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reload") and is_instance_valid(player):
		_reload_events.append({"route": "input", "type": event.get_class(), "can_process": player.can_process(), "reloading": player.loadout.is_reloading()})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reload") and is_instance_valid(player):
		_reload_events.append({"route": "unhandled", "type": event.get_class(), "can_process": player.can_process(), "reloading": player.loadout.is_reloading()})


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--blank-head-mask":
			_blank_head_mask = true
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
		elif argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
	if OS.get_cmdline_user_args().has("--self-check"):
		var valid := _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 1.0, "sample_pixels": 20, "feet_distance": 128.0})
		valid = valid and not _readability_passes({"enemy_contrast": 0.44, "edge_contrast": 1.0, "sample_pixels": 20, "feet_distance": 128.0})
		valid = valid and not _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 0.99, "sample_pixels": 20, "feet_distance": 128.0})
		valid = valid and not _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 1.0, "sample_pixels": 0, "feet_distance": 128.0})
		valid = valid and not _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 1.0, "sample_pixels": 20, "feet_distance": 129.0})
		valid = valid and not _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 1.0, "sample_pixels": 20, "feet_distance": 128.0, "enemy_floor": false})
		valid = valid and not _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 1.0, "sample_pixels": 20, "feet_distance": 128.0, "body_fully_in_bounds": false})
		valid = valid and not _readability_passes({"enemy_contrast": 0.45, "edge_contrast": 1.0, "sample_pixels": 20, "feet_distance": 64.0})
		print("WEAPON_LIGHT_SELF_CHECK checks=8 failures=", 0 if valid else 1)
		get_tree().quit(0 if valid else 1)
		return
	if _phase not in ["all", "visual", "perf-whole", "perf-fixed", "exposure"]:
		push_error("[WeaponLightProbe] unknown --phase=" + _phase)
		get_tree().quit(2)
		return
	if _quality.is_empty():
		for key: String in QUALITY:
			if int(QUALITY[key]) == Settings.get_light_quality():
				_quality = key
				break
	if not QUALITY.has(_quality):
		push_error("[WeaponLightProbe] unknown --quality=" + _quality)
		get_tree().quit(2)
		return
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
	Settings.use_storage(out_dir.path_join("probe-settings.cfg"))
	GameState.story_autosave = false
	Story.auto_skip = true
	Story._layer.visible = false
	var quality_before := Settings.get_light_quality()
	if QUALITY.has(_quality):
		Settings.set_light_quality(QUALITY[_quality])
	_gate(QUALITY.has(_quality) and Settings.get_light_quality() == QUALITY.get(_quality), "requested light quality is actually applied")
	var report := {"tag": _tag, "level": _level_id, "lighting": _lighting, "quality": _quality, "weapons": {}}
	report["renderer"] = {"driver": RenderingServer.get_current_rendering_driver_name(), "method": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "hdr_2d": get_viewport().use_hdr_2d}
	report["phase"] = _phase
	seed(258)
	if not await _open_level():
		get_tree().quit(2)
		return
	report["fixture"] = {"player_health": 999, "target_health": 999999, "stock_enemies_removed": true,
		"hidden_hud": true, "hidden_world_prompts": _hidden_prompts, "lighting_override": _lighting,
		"scope": "world prompts hidden only for visual/exposure sampling; performance preserves their original updates"}
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
	if _phase == "exposure":
		await _aim(Vector2.RIGHT)
		report["exposure"] = await _measure_exposure_states()
		await _finish(report, quality_before)
		return
	if _phase.begins_with("perf"):
		await _aim(Vector2.RIGHT)
		report["performance"] = await _measure_performance()
		await _finish(report, quality_before)
		return
	for id: String in _weapons:
		var path := "res://data/weapons/%s.tres" % id
		var weapon := load(path) as WeaponData if ResourceLoader.exists(path) else null
		if weapon == null:
			push_error("[WeaponLightProbe] 找不到武器：%s" % path)
			_failures += 1
			continue
		player.loadout.equip(weapon)
		for name: String in DIRECTIONS:
			await _aim(DIRECTIONS[name])
			_gate(_has_light() and bool(_gun_light().call("is_lit")) and absf(angle_difference(float(_gun_light().get("global_rotation")), _aim_dir.angle())) < 0.05,
				"real configured light follows " + id + "/" + name)
			_save_frame("%s-%s-%s" % [_tag, id, name])
		# Fixed gallery directions stay intact; readability separately aims at the real target center.
		_comparison = "aimed-eight-tiles-" + id
		await _aim((enemy._center() - player.aim_origin()).normalized())
		var eight_tile := await _enemy_contrast(enemy)
		_gate(bool(eight_tile["readability_passes"]), "actual target-centered eight-tile enemy/platform readability: " + id)
		if _has_light():
			var lit := bool(_gun_light().call("is_lit"))
			report["weapons"][id] = {"range": weapon.get("light_range"), "cone_degrees": weapon.get("light_cone_degrees"),
				"energy": weapon.get("light_energy"), "lit": lit, "eight_tile": eight_tile,
				"readability_aim": "real enemy center from real player aim origin; gallery directions are separate"}
			if not lit:
				_failures += 1
	# 開、關槍燈：同一把槍對著 8 格外的敵人。
	_comparison = "whole_feature"
	player.loadout.equip(load("res://data/weapons/%s.tres" % COMPARE_WEAPON) as WeaponData)
	await _aim(Vector2.RIGHT)
	report["on"] = {"enemy": await _enemy_contrast(enemy)}
	_save_frame(_tag + "-on")
	_suppress(true)
	await wait(1.0)
	report["off"] = {"enemy": await _enemy_contrast(enemy)}
	_save_frame(_tag + "-off")
	_gate(bool(report["on"]["enemy"]["readability_passes"]), "rifle lights the actual in-bounds eight-tile enemy and platform edge")
	_gate(float(report["off"]["enemy"]["contrast"]) < ContrastProbe.MIN_ENEMY_CONTRAST, "same-version suppressed enemy falls below the unchanged readability threshold")
	report["comparison_scope"] = "same current version: naturally armed body glow84 vs suppressed whole-feature-off body glow150; not a historical checkout"
	_comparison = "fixed_body150"
	_fixed_body_glow = true
	_suppress(false)
	await wait(1.0)
	report["fixed_body150_on"] = {"enemy": await _enemy_contrast(enemy)}
	_save_frame(_tag + "-fixed-body150-on")
	_suppress(true)
	await wait(1.0)
	report["fixed_body150_off"] = {"enemy": await _enemy_contrast(enemy)}
	_save_frame(_tag + "-fixed-body150-off")
	report["fixed_body150_scope"] = "diagnostic only: probe expands ON as well as OFF body glow to150; same-version gun-light-only comparison, not production ON or historical checkout"
	_gate(bool(report["fixed_body150_on"]["enemy"]["readability_passes"]), "single-factor fixed-body150 gun light retains eight-tile readability")
	_gate(float(report["fixed_body150_off"]["enemy"]["contrast"]) < ContrastProbe.MIN_ENEMY_CONTRAST, "single-factor fixed-body150 suppressed enemy is below the unchanged threshold")
	_fixed_body_glow = false
	if _phase != "visual":
		report["performance"] = await _measure_performance()
	await _finish(report, quality_before)


func _finish(report: Dictionary, quality_before: int) -> void:
	report["has_gun_light"] = _has_light()
	_suppress(false)
	_aim_dir = Vector2.ZERO
	AimInput.using_gamepad = false
	Settings.set_light_quality(quality_before)
	var writer := FileAccess.open(out_dir.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[WeaponLightProbe] 無法寫入索引：%s" % out_dir)
		_failures += 1
	else:
		report["checks"] = _checks
		report["failures"] = _failures
		report["frames"] = _frames
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("WEAPON_LIGHT_RESULT phase=", _phase, " failures=", _failures)
	level.queue_free()
	await settle(4)
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if _failures == 0 else 1)


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
	GameState.story_autosave = false
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(20)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	if not _phase.begins_with("perf"):
		# Same measurement-only UI policy as the existing held-world lighting probes.
		for node in level.find_children("*", "", true, false):
			if node is WorldPrompt:
				node.visible = false
				node.process_mode = Node.PROCESS_MODE_DISABLED
				_hidden_prompts += 1
	level._lighting._lightning_gap = 1.0e9
	snap_camera()
	await wait(TITLE_CARD_TIME)
	return true


## 滑鼠只要在視窗上動一下，瞄準就會改回跟滑鼠；量測期間每一格都把瞄準方向設回來。
func _process(_delta: float) -> void:
	if _aim_dir != Vector2.ZERO:
		AimInput.using_gamepad = true
		AimInput._last_stick_dir = _aim_dir
	if is_instance_valid(player):
		if _fixed_body_glow:
			player._light.texture_scale = 150.0 * 2.0 / LightKit.TEXTURE_SIZE
		_render_glow_radius = player._light.texture_scale * LightKit.TEXTURE_SIZE * 0.5


## Missing light remains an explicit failed condition, never an exit-0 feature baseline.
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
	await wait(2.2)
	await RenderingServer.frame_post_draw


## 敵人的輪廓對比（和暗場可讀性量測同一套算法）與身上亮部的亮度（線性，0～1），各取幾次的中位數。
func _enemy_contrast(enemy: Enemy) -> Dictionary:
	var contrasts: Array[float] = []
	var brights: Array[float] = []
	var samples: Array[Dictionary] = []
	for index in CONTRAST_SAMPLES:
		await RenderingServer.frame_post_draw
		var probe := ContrastProbe.capture(get_viewport())
		var parts := probe.character_parts(enemy.global_position)
		var metric := {"enemy_contrast": maxf(parts["bright"], parts["dark"]), "edge_contrast": probe.edge_contrast(enemy.global_position),
			"sample_pixels": probe._pixel_count(probe._body_box(enemy.global_position, false)), "feet_distance": enemy.global_position.distance_to(player.global_position),
			"enemy_feet": [enemy.global_position.x, enemy.global_position.y], "player_feet": [player.global_position.x, player.global_position.y],
			"enemy_floor": enemy.is_on_floor(), "parts": parts, "body_glow_radius": player._light.texture_scale * LightKit.TEXTURE_SIZE * 0.5}
		var box := probe._body_box(enemy.global_position, false)
		var start := (probe._to_screen * box.position) * probe._scale
		var end := (probe._to_screen * box.end) * probe._scale
		metric["body_fully_in_bounds"] = start.x >= 0.0 and start.y >= 0.0 and end.x <= probe._image.get_width() and end.y <= probe._image.get_height()
		var visible_prompts := 0
		for node in level.find_children("*", "", true, false):
			if node is WorldPrompt and node.is_visible_in_tree():
				visible_prompts += 1
		metric["visible_prompt_count"] = visible_prompts
		metric["readability_passes"] = _readability_passes(metric)
		samples.append(metric)
		_save_frame("%s-%s-%s-sample-%d" % [_tag, _comparison, "off" if _has_light() and bool(_gun_light().get("suppressed")) else "on", index], metric)
		contrasts.append(maxf(parts["bright"], parts["dark"]))
		brights.append(parts["inner"])
		await wait(0.08)
	contrasts.sort()
	brights.sort()
	return {"contrast": contrasts[contrasts.size() / 2], "bright": brights[brights.size() / 2], "samples": samples,
		"readability_passes": samples.all(func(row: Dictionary) -> bool: return row["readability_passes"])}


func _readability_passes(row: Dictionary) -> bool:
	return float(row.get("enemy_contrast", -1.0)) >= ContrastProbe.MIN_ENEMY_CONTRAST \
		and float(row.get("edge_contrast", -1.0)) >= ContrastProbe.MIN_EDGE_CONTRAST \
		and int(row.get("sample_pixels", 0)) > 0 and absf(float(row.get("feet_distance", INF)) - ENEMY_TILES * 16.0) <= 0.01 \
		and bool(row.get("enemy_floor", true)) and bool(row.get("body_fully_in_bounds", true)) and int(row.get("visible_prompt_count", 0)) == 0


func _gate(passed: bool, name: String) -> void:
	_checks.append({"passed": passed, "name": name})
	if not passed:
		_failures += 1
	print("WEAPON_LIGHT_GATE ", passed, " ", name)


func _save_frame(name: String, metric: Dictionary = {}) -> void:
	var viewport := get_viewport()
	var raw := viewport.get_texture().get_image()
	var writer := FileAccess.open(out_dir.path_join(name + ".hdr.bin"), FileAccess.WRITE)
	if writer == null:
		_failures += 1
		return
	writer.store_buffer(raw.get_data())
	writer.close()
	if preload("res://tools/viewport_capture.gd").encode(raw, viewport.use_hdr_2d).save_png(out_dir.path_join(name + ".png")) != OK:
		_failures += 1
	var transform := viewport.get_final_transform() * viewport.get_canvas_transform()
	_frames.append({"name": name, "width": raw.get_width(), "height": raw.get_height(), "format": raw.get_format(),
		"world_to_image": [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y],
		"physics_frame": Engine.get_physics_frames(), "metric": metric, "aim": [player.aim_dir.x, player.aim_dir.y],
		"light_enabled": _has_light() and bool(_gun_light().get("_light").enabled), "actual_quality": Settings.get_light_quality(),
		"actual_light_rotation": float(_gun_light().get("global_rotation")) if _has_light() else null,
		"actual_light_energy": float(_gun_light().get("_light").energy) if _has_light() else null,
		"actual_light_color": str(_gun_light().get("_light").color) if _has_light() else null,
		"actual_light_reach": float(_gun_light().get("_light").get_meta(LightKit.META_REACH, 0.0)) if _has_light() else null,
		"actual_weapon": str(player.loadout.active_weapon().id), "requested_aim": [_aim_dir.x, _aim_dir.y]})
	_frames.back()["body_glow_override"] = 150.0 if _fixed_body_glow else null


## Real projectile activation, observed after activate() sets its team/active flag and shows it.
func _watch_projectile(node: Node) -> void:
	if node is Projectile:
		node.visibility_changed.connect(_projectile_visible.bind(node))


func _head_exposure(name: String, require_muzzle := false) -> Dictionary:
	var result := await preload("res://tools/weapon_head_probe.gd").capture(self, level, out_dir, _tag + "-" + name, _blank_head_mask, require_muzzle)
	result["state"] = player.state
	result["health"] = player.health.current
	result["blocking"] = player.is_blocking
	result["reloading"] = player.loadout.is_reloading()
	result["muzzle_energy"] = _muzzle_energy()
	_gate(bool(result.get("bound_valid", false)) and float(result.get("white_ratio_upper_bound") if result.get("white_ratio_upper_bound") != null else 1.0) <= 0.02,
		"actual head conservative white bound <=2%: " + name)
	_gate(bool(result.get("gun_light_enabled_at_raw_capture", false)) and bool(result.get("gun_light_lit_at_raw_capture", false)), "gun remains lit during actual " + name)
	return result


func _muzzle_energy() -> float:
	var energy := 0.0
	var weapon := player.loadout.active_weapon()
	for light: PointLight2D in Fx._lights:
		if light.enabled and light.global_position.distance_to(player.muzzle_position()) <= 16.0 \
				and is_equal_approx(light.texture_scale * LightKit.TEXTURE_SIZE * 0.5, weapon.muzzle_light_radius) \
				and light.color.is_equal_approx(weapon.color):
			energy += light.energy
	return energy


func _measure_exposure_states() -> Dictionary:
	var result := {"states": {}, "reduce_flashes": [], "scope": "real inputs and arranged public damage; actual head alpha with conservative W/H; no human playthrough claim"}
	var container := ProjectilePool.container()
	for node in container.get_children():
		_watch_projectile(node)
	container.child_entered_tree.connect(_watch_projectile)
	player.loadout.equip(load("res://data/weapons/rifle.tres"))
	await wait(0.5)
	result["states"]["idle"] = await _head_exposure("idle")
	if _blank_head_mask:
		return result
	var health_before := player.health.current
	var hit := DamageInfo.create(1, Combat.Team.ENEMY, &"ne258_exposure_fixture")
	hit.ignore_invulnerability = true
	hit.bypass_guard = true
	player.hurtbox.receive(hit)
	_gate(player.health.current == health_before - 1, "public damage genuinely reaches the player")
	await get_tree().physics_frame
	result["states"]["hurt"] = await _head_exposure("hurt")
	await wait(0.6)
	Input.action_press(&"block")
	for frame in 4:
		await get_tree().physics_frame
	_gate(player.is_blocking, "real block input enters blocking")
	result["states"]["block"] = await _head_exposure("block")
	Input.action_release(&"block")
	await wait(0.3)
	Input.action_press(&"dash")
	for frame in 2:
		await get_tree().physics_frame
	Input.action_release(&"dash")
	_gate(player.state == Player.State.DASH, "real dash input enters dash")
	result["states"]["dash"] = await _head_exposure("dash")
	await wait(0.6)
	for id: String in _weapons:
		var weapon := load("res://data/weapons/%s.tres" % id) as WeaponData
		player.loadout.equip(weapon)
		player.loadout.set_ammo(player.loadout.active_slot, weapon.magazine_size, -1)
		for frame in 240:
			if player._fire_cooldown_left <= 0:
				break
			await get_tree().physics_frame
		await settle(6)
		var before_shots := _projectiles_spawned
		Input.action_press(&"shoot")
		for frame in 2:
			await get_tree().physics_frame
		var name := "fire-" + id
		result["states"][name] = await _head_exposure(name, true)
		Input.action_release(&"shoot")
		_gate(_projectiles_spawned > before_shots and float(result["states"][name].get("muzzle_energy_at_raw_capture", 0.0)) > 0.0,
			"real " + id + " shot spawns projectiles and appears with active muzzle light in its head evidence")
		await wait(0.3)
	var reduced_before := Settings.get_reduce_flashes()
	player.loadout.equip(load("res://data/weapons/smg.tres"))
	for reduced: bool in [false, true]:
		Settings.set_reduce_flashes(reduced)
		player.loadout.set_ammo(player.loadout.active_slot, player.loadout.active_weapon().magazine_size, -1)
		await wait(0.4)
		var shots_before := _projectiles_spawned
		var peak_jitter := 0.0
		var peak_muzzle := 0.0
		Input.action_press(&"shoot")
		for frame in 12:
			await get_tree().physics_frame
			peak_jitter = maxf(peak_jitter, absf(angle_difference(float(_gun_light().get("global_rotation")), player.aim_dir.angle())))
			peak_muzzle = maxf(peak_muzzle, _muzzle_energy())
			if frame in [1, 4, 8]:
				result["states"]["fire-%s-%d" % [str(reduced), frame]] = await _head_exposure("fire-%s-%d" % [str(reduced), frame], true)
		Input.action_release(&"shoot")
		var shots := _projectiles_spawned - shots_before
		_gate(shots > 0 and peak_muzzle > 0.0, "public sustained fire genuinely spawns projectiles and muzzle light, reduced=" + str(reduced))
		var muzzle_in_head_frame := false
		for frame in [1, 4, 8]:
			muzzle_in_head_frame = muzzle_in_head_frame or float(result["states"]["fire-%s-%d" % [str(reduced), frame]].get("muzzle_energy_at_raw_capture", 0.0)) > 0.0
		_gate(muzzle_in_head_frame, "white-hair fire evidence actually includes active muzzle light, reduced=" + str(reduced))
		result["reduce_flashes"].append({"reduced": reduced, "projectiles_spawned": shots, "peak_jitter_radians": peak_jitter, "peak_muzzle_energy": peak_muzzle})
	var normal: Dictionary = result["reduce_flashes"][0]
	var reduced: Dictionary = result["reduce_flashes"][1]
	_gate(normal["peak_jitter_radians"] > 0.01 and reduced["peak_jitter_radians"] < normal["peak_jitter_radians"] * 0.75, "reduce-flashes calms real firing jitter using the unchanged 75% gate")
	_gate(normal["peak_muzzle_energy"] > 0.0 and reduced["peak_muzzle_energy"] < normal["peak_muzzle_energy"] * 0.75, "reduce-flashes lowers actual muzzle light using the unchanged 75% gate")
	Settings.set_reduce_flashes(reduced_before)
	result["reload_before_wait"] = {"can_process": player.can_process(), "frozen": Fx.is_frozen(player), "state": player.state,
		"mag": player.loadout.mag_in(player.loadout.active_slot), "reserve": player.loadout.reserve_in(player.loadout.active_slot)}
	# A real hitstop can still own the player after the last shot; don't send an event to a disabled owner.
	for frame in 120:
		if player.can_process() and not Fx.is_frozen(player) and player.state == Player.State.NORMAL:
			break
		await get_tree().process_frame
	result["reload_at_input"] = {"can_process": player.can_process(), "frozen": Fx.is_frozen(player), "state": player.state,
		"mag": player.loadout.mag_in(player.loadout.active_slot), "reserve": player.loadout.reserve_in(player.loadout.active_slot)}
	_gate(player.can_process() and not Fx.is_frozen(player) and player.state == Player.State.NORMAL, "actual reload input owner is available after real hitstop")
	# Reload is event-owned, unlike polled block/dash/shoot; send the real public event.
	var reload := InputEventAction.new()
	reload.action = &"reload"
	reload.pressed = true
	Input.parse_input_event(reload)
	result["reload_immediately_after_input"] = {"started": player.loadout.is_reloading(), "input_handled": get_viewport().is_input_handled()}
	for frame in 2:
		await get_tree().physics_frame
	result["reload_after_two_physics"] = player.loadout.is_reloading()
	await get_tree().process_frame
	await get_tree().process_frame
	reload = InputEventAction.new()
	reload.action = &"reload"
	reload.pressed = false
	Input.parse_input_event(reload)
	result["reload_events"] = _reload_events
	_gate(player.loadout.is_reloading(), "real reload input starts the reload owner")
	result["states"]["reload"] = await _head_exposure("reload")
	container.child_entered_tree.disconnect(_watch_projectile)
	player.health.kill(DamageInfo.create(9999, Combat.Team.ENEMY, &"ne258_death_fixture"))
	_gate(player.state == Player.State.DEAD and not bool(_gun_light().call("is_lit")) and not bool(_gun_light().get("_light").enabled), "actual player death extinguishes the gun light immediately")
	return result


func _projectile_visible(projectile: Projectile) -> void:
	if projectile.active and projectile.visible and projectile.team == Combat.Team.PLAYER:
		_projectiles_spawned += 1


func _shot_sound(id: StringName) -> void:
	if id == _perf_sound:
		_accepted_shots += 1


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[ordered.size() / 2]


## One uninterrupted real-input SMG stream: real magazine, cooldown, recoil and automatic reload.
func _measure_performance() -> Dictionary:
	var smg := load("res://data/weapons/smg.tres") as WeaponData
	player.loadout.equip(smg)
	# Arranged infinite reserve only; magazine and automatic reload remain the actual weapon's.
	player.loadout.set_ammo(player.loadout.active_slot, smg.magazine_size, -1)
	_perf_sound = smg.fire_sound
	var container := ProjectilePool.container()
	for node in container.get_children():
		_watch_projectile(node)
	container.child_entered_tree.connect(_watch_projectile)
	Sfx.sound_played.connect(_shot_sound)
	var vsync_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.action_press(&"shoot")
	var result := {"scope": "same-version paired suppression controls, not a historical checkout", "pairs": TIMING_ROUNDS,
		"frames_per_window": FRAME_SAMPLES, "vsync": DisplayServer.window_get_vsync_mode(), "arranged_reserve": -1,
		"real_magazine_size": smg.magazine_size, "real_fire_interval": smg.fire_interval, "real_reload_time": smg.reload_time, "cases": {}}
	var cases := ["whole_feature", "fixed_body150"]
	if _phase == "perf-whole":
		cases = ["whole_feature"]
	elif _phase == "perf-fixed":
		cases = ["fixed_body150"]
	for variant: String in cases:
		_fixed_body_glow = variant == "fixed_body150"
		var pairs: Array[Dictionary] = []
		var ratios: Array[float] = []
		var totals := {"on": 0, "off": 0}
		var controls_valid := true
		for round in TIMING_ROUNDS:
			var pair := {}
			for key: String in (["on", "off"] if round % 2 == 0 else ["off", "on"]):
				_suppress(key == "off")
				await wait(0.35) # Fully settle original light fade and natural 84/150 body radius.
				pair[key] = await _timing_window()
				totals[key] += int(pair[key]["projectiles_spawned"])
				var expected_radius := 150.0 if _fixed_body_glow or key == "off" else 84.0
				controls_valid = controls_valid and bool(pair[key]["gun_enabled"]) == (key == "on") \
					and is_equal_approx(float(pair[key]["body_glow_radius_min"]), expected_radius) \
					and is_equal_approx(float(pair[key]["body_glow_radius_max"]), expected_radius) \
					and int(pair[key]["projectiles_spawned"]) == int(pair[key]["accepted_shots"]) \
					and (pair[key]["raw_frame_ms"] as Array).size() == FRAME_SAMPLES
			var ratio := float(pair["on"]["median_ms"]) / maxf(0.000001, float(pair["off"]["median_ms"]))
			pair["ratio"] = ratio
			pairs.append(pair)
			ratios.append(ratio)
			if round % 10 == 0:
				print("WEAPON_LIGHT_TIMING ", variant, " pair=", round, " ratio=", ratio)
		var ratio := _median(ratios)
		_gate(controls_valid and ratio <= 1.05 and totals["on"] > 0 and totals["off"] > 0 and result["vsync"] == DisplayServer.VSYNC_DISABLED,
			"natural sustained-fire paired median <=105%: " + variant)
		result["cases"][variant] = {"paired_median_ratio": ratio, "controls_valid": controls_valid, "total_projectiles": totals, "pairs": pairs}
	Input.action_release(&"shoot")
	_fixed_body_glow = false
	_suppress(false)
	Sfx.sound_played.disconnect(_shot_sound)
	container.child_entered_tree.disconnect(_watch_projectile)
	DisplayServer.window_set_vsync_mode(vsync_before)
	return result


func _timing_window() -> Dictionary:
	var values: Array[float] = []
	var physics_before := Engine.get_physics_frames()
	var shots_before := _projectiles_spawned
	var accepted_before := _accepted_shots
	var reload_frames := 0
	var glow_min := INF
	var glow_max := 0.0
	var last := Time.get_ticks_usec()
	for index in FRAME_SAMPLES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		values.append(float(now - last) / 1000.0)
		last = now
		reload_frames += int(player.loadout.is_reloading())
		glow_min = minf(glow_min, _render_glow_radius)
		glow_max = maxf(glow_max, _render_glow_radius)
	return {"raw_frame_ms": values, "median_ms": _median(values), "physics_frames": Engine.get_physics_frames() - physics_before,
		"projectiles_spawned": _projectiles_spawned - shots_before, "accepted_shots": _accepted_shots - accepted_before,
		"reload_render_frames": reload_frames, "body_glow_radius_min": glow_min, "body_glow_radius_max": glow_max,
		"gun_enabled": _has_light() and bool(_gun_light().get("_light").enabled), "gun_energy": float(_gun_light().get("_light").energy)}
