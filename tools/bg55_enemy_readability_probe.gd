extends "res://tools/readability_phase_probe.gd"
## Held-scene A/A and A/B/A. Product actors, scenery and drawing remain intact.
## --diagnose varies one profile field at a time in memory, never on disk.
## --reference-profile=res://... compares the original profile with authored data.

const Capture55 := preload("res://tools/viewport_capture.gd")
const HeldLighting55 := preload("res://tools/held_lighting_state.gd")
var _diagnose55 := false
var _reference55 := ""
var _held55: Level
var _cell55 := 0
var _active_cell55 := 0
var _files55: Dictionary = {}
var _time_scale55 := 1.0
var _environment55: WorldEnvironment
var _contact55: Dictionary = {}


func _ready() -> void:
	# SceneTour does not install Main's WorldEnvironment. This leaf must use
	# the real game's HDR bloom owner, rather than merely an HDR viewport.
	_environment55 = LightKit.create_environment()
	add_child(_environment55)
	for arg in OS.get_cmdline_user_args():
		if arg == "--diagnose":
			_diagnose55 = true
		elif arg.begins_with("--reference-profile="):
			_reference55 = arg.trim_prefix("--reference-profile=")
	if not _reference55.is_empty() and not ResourceLoader.exists(_reference55):
		push_error("[BG55] Missing reference profile: %s" % _reference55)
		get_tree().quit(2)
		return
	super._ready()
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var caption := Label.new()
	caption.position = Vector2(12, 33)
	caption.text = "BG55 / HELD SIMULATION / %s / SCRIPTED AIM" % ("DIAGNOSTIC FACTORS" if _diagnose55 else "AUTHORED ACCEPTANCE")
	caption.add_theme_font_size_override("font_size", 13)
	overlay.add_child(caption)


static func bytes_sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func variant_profile(source: LightingProfile, factor: String) -> LightingProfile:
	var result := source.duplicate() as LightingProfile
	match factor:
		"source": pass
		"fill-min": result.enemy_fill_scale = 0.5
		"fill-max": result.enemy_fill_scale = 1.0
		"fog-half": result.fog_density *= 0.5
		"fog-quarter": result.fog_density *= 0.25
		_: return null
	return result


static func sync_rig(rig: CharacterRig) -> void:
	if rig != null:
		rig._apply_fill(LightKit.enemy_fill)
		rig._apply_light_cap(LightKit.enemy_light_cap)


static func rect_values(rect: Rect2i) -> Array[int]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func visible_floor(layout: LevelLayout, column: int, world: Rect2) -> float:
	# A higher one-way platform may be above the usable part of this view.
	# Continue looking for a real visible floor instead of hiding the actor.
	for row in range(layout.height):
		var y := float(row * layout.tile_size)
		if y <= world.position.y + 60.0 or y >= world.end.y:
			continue
		if layout.cell(column, row) not in ["#", "="] or layout.cell(column, row - 1) in ["#", "="]:
			continue
		var clear := true
		for above in range(maxi(0, row - 4), row):
			if layout.cell(column, above) == "#": clear = false
		if clear: return y
	return INF


static func ground_support(body: CharacterBody2D) -> Dictionary:
	var feet := body.global_position
	var query := PhysicsRayQueryParameters2D.create(feet - Vector2(0, 4), feet + Vector2(0, 6), Layers.SOLID)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"found": false, "feet": [feet.x, feet.y]}
	var at: Vector2 = hit.position
	var normal: Vector2 = hit.normal
	return {"found": true, "feet": [feet.x, feet.y], "floor": [at.x, at.y], "safe_margin": body.safe_margin,
		"gap": at.y - feet.y, "normal": [normal.x, normal.y],
		"on_floor_cache": body.is_on_floor()}


func _place_player(level: Level, center: Vector2, view: Vector2) -> void:
	var column := clampi(int(center.x / level._layout.tile_size), 0, level._layout.width - 1)
	var floor_y := visible_floor(level._layout, column, Rect2(center - view * 0.5, view))
	level.player.visible = is_finite(floor_y)
	_contact55 = {"visible": level.player.visible}
	if level.player.visible:
		level.player.global_position = Vector2(column * level._layout.tile_size + level._layout.tile_size * 0.5, floor_y - 2.0)
		# The actor is held, so it cannot naturally finish the final two pixels
		# of falling. Use its actual collision solver and authored safe margin.
		var collision := level.player.move_and_collide(Vector2.DOWN * 4.0, false, level.player.safe_margin)
		_contact55 = ground_support(level.player)
		_contact55["visible"] = true
		_contact55["layout_floor"] = floor_y
		_contact55["safe_margin"] = level.player.safe_margin
		_contact55["solver_contact"] = collision != null
		_contact55["solver_normal"] = [collision.get_normal().x, collision.get_normal().y] if collision != null else []
		var valid: bool = collision != null and bool(_contact55.found) and absf(_contact55.gap) <= level.player.safe_margin + 0.001
		valid = valid and collision.get_normal().dot(Vector2.UP) > 0.99 if collision != null else false
		_contact55["valid"] = valid
		if not valid:
			_contrast_failures += 1
			printerr("[BG55] Actual player support contact failed: ", _contact55)


func _settle(frames: int) -> void:
	# The first ordinary settling interval gives the authored actors their real
	# idle pose. All subsequent interventions share this exact live instance.
	for node in get_children():
		if node is Level and (not is_instance_valid(_held55) or node != _held55):
			await super._settle(frames)
			# Finish the real weapon-light fade before holding the scene. A fixed
			# frame count is not a fixed duration on a fast native renderer.
			var light: WeaponLight = node.player._weapon_light
			var deadline := Time.get_ticks_msec() + 1500
			while light._weapon != null and light._active and light._level < 0.999 and Time.get_ticks_msec() < deadline:
				await super._settle(1)
			if light._weapon != null and light._active and light._level < 0.999:
				push_error("[BG55] Actual weapon-light fade did not settle before holding")
				_contrast_failures += 1
			_held55 = node
			HeldLighting55.preserve_physics_bodies(_held55)
			_held55.process_mode = Node.PROCESS_MODE_DISABLED
			# Shader TIME is affected by time_scale, unlike SceneTree pause.
			# A/A below still verifies this on the actual renderer.
			_time_scale55 = Engine.time_scale
			Engine.time_scale = 0.0
			for item in _held55.find_children("*", "", true, false):
				if item is WorldPrompt:
					item.visible = false
					item.process_mode = Node.PROCESS_MODE_DISABLED
				elif item is FogLayer or item is RainLayer or item is PostProcess:
					item.set_process(false)
			return
	if is_instance_valid(_held55):
		_held55._lighting.snap()
		_sync55(_held55)
	await super._settle(frames)


func _sync55(level: Level) -> void:
	_sync_player_light(level.player)
	# WeaponLight is top_level. Merely moving Player leaves that beam behind.
	# Use the actual owner update, with zero animation-time advancement.
	level.player._update_weapon_light(0.0)
	for node in level._entities.get_children():
		if node is Enemy:
			sync_rig(node.rig)
	HeldLighting55.sync(level)
	# Camera and player light can move between grid cells. Refresh actual tint
	# sources without advancing fog time or hiding any atmosphere layer.
	level._fog._tint_refresh = 0.0
	level._fog._process(0.0)
	level._fog.queue_redraw()


func _held_state55(level: Level) -> Dictionary:
	var actors: Array[Dictionary] = []
	for node in level._entities.get_children():
		if not node is Enemy:
			continue
		var parts: Array[String] = []
		if node.rig != null:
			for part in node.rig._parts:
				parts.append(str(part.global_transform))
		actors.append({"instance": node.get_instance_id(), "id": str(node.data.id),
			"feet": str(node.global_position), "facing": node.facing, "parts": parts})
	var rains: Array[Dictionary] = []
	for node in level.find_children("*", "", true, false):
		if node is RainLayer:
			rains.append({"time": node._time, "drift": node._drift,
				"visible": node.is_visible_in_tree(),
				"points_sha256": bytes_sha(var_to_bytes(node._points))})
	return {"actors": actors, "rain": rains, "fog_time": level._fog._time, "shader_time_scale": Engine.time_scale,
		"fog_visible": level._fog.is_visible_in_tree(), "camera": str(get_viewport().get_canvas_transform()),
		"player": str(level.player.global_position), "aim": str(level.player.aim_dir), "player_support": _contact55,
		"weapon_light_position": str(level.player._weapon_light.global_position),
		"weapon_light_energy": level.player._weapon_light._light.energy,
		"lighting_owners": HeldLighting55.snapshot(level), "lamps": _lamp_observations(level)}


func _apply55(level: Level, profile: LightingProfile) -> void:
	LightingProfile.copy_into(level._lighting.current, profile)
	level._lighting._apply()
	_sync55(level)
	# Deliberately bypass this subclass's snap-to-authored _settle: the
	# intervention lives only in current, and must survive until capture.
	await super._settle(3)


func _capture55(level: Level, world: Rect2, label: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var active_environment := get_viewport().find_world_3d().environment
	var environment_valid: bool = active_environment == _environment55.environment and active_environment.glow_enabled
	if not environment_valid:
		printerr("[BG55] Main-equivalent HDR bloom environment is not active")
		_contrast_failures += 1
	var probe := ContrastProbe.capture(get_viewport())
	var bytes := probe._image.get_data()
	var sha := bytes_sha(bytes)
	var directory := _out.path_join(str(level.data.id))
	var key := "%s:%s" % [level.data.id, sha]
	if not _files55.has(key):
		var name := "bg55-cell%03d-%s" % [_active_cell55, label]
		var raw_path := directory.path_join(name + ".bin")
		var file := FileAccess.open(raw_path, FileAccess.WRITE)
		if file == null:
			push_error("[BG55] Cannot preserve raw viewport: %s" % raw_path)
			_contrast_failures += 1
		else:
			file.store_buffer(bytes)
			file.close()
		var error := Capture55.encode(probe._image, get_viewport().use_hdr_2d).save_png(directory.path_join(name + ".png"))
		if error != OK:
			push_error("[BG55] Cannot preserve PNG: %s" % error_string(error))
			_contrast_failures += 1
		_files55[key] = {"raw": name + ".bin", "png": name + ".png"}
	var enemies: Array[Dictionary] = []
	var contact_bounds: Rect2 = level.player._contact_shadow.world_rect()
	for node in level._entities.get_children():
		if not node is Enemy or not node.is_visible_in_tree() or not world.grow(-24.0).has_point(node.global_position):
			continue
		var parts := probe.character_parts(node.global_position)
		var bounds := probe._body_box(node.global_position, false)
		var full_bounds: Rect2 = node.rig.visual_bounds() if node.rig != null else bounds
		enemies.append({"instance": node.get_instance_id(), "id": str(node.data.id), "skin": node.data.rig_skin,
			"feet": [node.global_position.x, node.global_position.y], "facing": node.facing,
			"fill": node.rig._fill if node.rig != null else null,
			"light_cap": node.rig._light_cap if node.rig != null else null,
			"ground_support": ground_support(node),
			"uses_gravity": node.data.uses_gravity,
			"parts": parts, "contrast": maxf(parts.bright, parts.dark),
			"screen_rect": rect_values(probe._screen_rect(bounds)),
			"outer_screen_rect": rect_values(probe._screen_rect(bounds.grow(ContrastProbe.RING))),
			"visual_world_bounds": str(full_bounds),
			"visual_world_bounds_values": [full_bounds.position.x, full_bounds.position.y, full_bounds.size.x, full_bounds.size.y],
			"aux_full_visual_parts": probe.contrast_parts(full_bounds, ContrastProbe.RING),
			"passed": maxf(parts.bright, parts.dark) >= ContrastProbe.MIN_ENEMY_CONTRAST})
	return {"label": label, "raw_sha256": sha, "files": _files55[key],
		"world_environment": {"active": environment_valid, "glow_enabled": active_environment.glow_enabled,
			"threshold": active_environment.glow_hdr_threshold, "intensity": active_environment.glow_intensity,
			"cap": active_environment.glow_hdr_luminance_cap, "background_mode": active_environment.background_mode},
		"width": probe._image.get_width(), "height": probe._image.get_height(), "format": probe._image.get_format(),
		"density": probe._scale, "canvas_transform": str(probe._to_screen),
		"canvas_transform_values": HeldLighting55.transform_values(probe._to_screen),
		"fog_density": level._fog.density, "enemy_fill_scale": level._lighting.current.enemy_fill_scale,
		"player_visible": level.player.is_visible_in_tree(),
		"player_contact_shadow": {"cast": level.player._contact_shadow.is_cast(),
			"visible": level.player._contact_shadow.is_visible_in_tree(), "shift": level.player._contact_shadow._shift,
			"bounds": [contact_bounds.position.x, contact_bounds.position.y, contact_bounds.size.x, contact_bounds.size.y]},
		"player_light_visible": level.player._light.is_visible_in_tree(),
		"player_light_energy": level.player._light.energy,
		"weapon_light": {"position": [level.player._weapon_light.global_position.x, level.player._weapon_light.global_position.y],
			"expected_origin": str(level.player.aim_origin().lerp(level.player.muzzle_position(), Player.WEAPON_LIGHT_ORIGIN)),
			"origin_error": level.player._weapon_light.global_position.distance_to(level.player.aim_origin().lerp(level.player.muzzle_position(), Player.WEAPON_LIGHT_ORIGIN)),
			"visible": level.player._weapon_light._light.is_visible_in_tree(), "enabled": level.player._weapon_light._light.enabled,
			"energy": level.player._weapon_light._light.energy, "fade_level": level.player._weapon_light._level,
			"reach": level.player._weapon_light.reach()},
		"enemy_fill": LightKit.enemy_fill, "ambient": str(level._lighting.current.ambient_color),
		"enemies": enemies, "held": _held_state55(level)}


func _measure(level: Level, world: Rect2) -> Dictionary:
	_active_cell55 = _cell55
	_cell55 += 1
	var result := await super._measure(level, world)
	var authored := level._lighting.current.duplicate() as LightingProfile
	var baseline := load(_reference55) as LightingProfile if not _reference55.is_empty() else authored
	await _apply55(level, baseline)
	var first := await _capture55(level, world, "A0")
	await _apply55(level, baseline)
	var repeat := await _capture55(level, world, "A1")
	var valid: bool = first.held.lighting_owners.valid and first.raw_sha256 == repeat.raw_sha256 and first.held == repeat.held
	var records: Array[Dictionary] = [first, repeat]
	var factors: Array = ["fill-min", "fill-max", "fog-half", "fog-quarter"] if _diagnose55 else (["product"] if not _reference55.is_empty() else [])
	for factor in factors:
		var candidate := authored if factor == "product" else variant_profile(baseline, factor)
		await _apply55(level, candidate)
		var altered := await _capture55(level, world, factor)
		valid = valid and altered.held == first.held
		records.append(altered)
		await _apply55(level, baseline)
		var restored := await _capture55(level, world, "restore-" + factor)
		valid = valid and restored.raw_sha256 == first.raw_sha256 and restored.held == first.held
		records.append(restored)
	await _apply55(level, authored)
	var product := await _capture55(level, world, "authored-final")
	for record in records:
		if record.label == "product":
			valid = valid and product.raw_sha256 == record.raw_sha256 and product.held == record.held
	records.append(product)
	if not valid:
		printerr("[BG55] A/A, restoration, or held-state control failed in %s cell %d" % [level.data.id, _active_cell55])
		_contrast_failures += 1
	if not _diagnose55:
		for enemy in product.enemies:
			if not enemy.passed:
				printerr("[BG55] Enemy below unchanged threshold: %s %s %.6f" % [enemy.id, enemy.feet, enemy.contrast])
				_contrast_failures += 1
	var authored_enemy_passed := true
	for enemy in product.enemies:
		authored_enemy_passed = authored_enemy_passed and bool(enemy.passed)
	result["bg55"] = {"kind": "single held live scene; diagnostic factors" if _diagnose55 else "authored profile acceptance",
		"diagnostic_only": _diagnose55, "controls_valid": valid, "records": records,
		"authored_enemy_passed": authored_enemy_passed,
		"source_sha256": FileAccess.get_sha256("res://tools/bg55_enemy_readability_probe.gd"),
		"enemy_box_unchanged": true, "aux_full_visual_is_not_acceptance": true,
		"distinct_images_deduplicated_by_actual_raw_sha256": true}
	if not _diagnose55:
		result["passed"] = bool(result.get("passed", true)) and authored_enemy_passed and valid
	return result


func _tour(level_id: String) -> bool:
	var result := await super._tour(level_id)
	Engine.time_scale = _time_scale55
	_held55 = null
	return result

