extends "res://pm/Nest-Egg/attachments/NE-222-native-support-hand/capture_base.gd"
## Private integration fixture for CharacterRig's production grip texture_scale API.
## The only runtime variation is the cloned skin JSON loaded before CharacterRig.setup().

const STAGED_CANDIDATE := "parts/hand_left_grip.png"
const STAGED_NORMAL := "parts/hand_left_grip_n.png"
const STAGED_RESOURCE := "res://art/characters/rin/parts/hand_left_grip.png"
const STAGED_NORMAL_RESOURCE := "res://art/characters/rin/parts/hand_left_grip_n.png"
const ORIGINAL_GRIP_SIZE := Vector2i(90, 70)
const CANDIDATE_GRIP_SIZE := Vector2i(226, 142)
const CANDIDATE_GRIP_PIVOT := Vector2(26.0822, 25.9259)
const CANDIDATE_GRIP_SCALE := 0.018283541156251144

var _base_skin: Dictionary = {}
var _base_skin_hash := ""
var _current_api_variant := ""


func _run() -> void:
	if not _prepare_sources():
		_finish(false)
		return
	_base_skin = RigLibrary.character("rin").duplicate(true)
	_base_skin_hash = _sha256_resource(CHARACTER_PATH)
	if not _validate_imported_candidate():
		_finish(false)
		return
	if "--cpu-only" in OS.get_cmdline_user_args():
		_run_production_cpu_matrix()
		_finish(false)
		return
	if not _setup_viewport() or not _setup_rig():
		_finish(false)
		return
	await _run_capture_matrix()
	_finish(true)


func _validate_imported_candidate() -> bool:
	_check(ResourceLoader.exists(STAGED_RESOURCE), "staged candidate diffuse is an imported ResourceLoader path")
	_check(ResourceLoader.exists(STAGED_NORMAL_RESOURCE), "staged candidate normal is an imported ResourceLoader path")
	if not ResourceLoader.exists(STAGED_RESOURCE) or not ResourceLoader.exists(STAGED_NORMAL_RESOURCE):
		return false
	var candidate_texture := LitTextures.load_texture(STAGED_RESOURCE, CANDIDATE_GRIP_SIZE)
	_check(candidate_texture is CanvasTexture, "production LitTextures returns CanvasTexture for candidate grip")
	if candidate_texture is CanvasTexture:
		var canvas := candidate_texture as CanvasTexture
		_check(canvas.diffuse_texture != null and canvas.diffuse_texture.get_size() == Vector2(CANDIDATE_GRIP_SIZE), "production CanvasTexture has exact native diffuse size")
		_check(canvas.normal_texture != null and canvas.normal_texture.get_size() == Vector2(CANDIDATE_GRIP_SIZE), "production CanvasTexture has exact paired normal")
	_source_hashes[STAGED_RESOURCE] = _sha256_resource(STAGED_RESOURCE)
	_source_hashes[STAGED_NORMAL_RESOURCE] = _sha256_resource(STAGED_NORMAL_RESOURCE)
	_source_hashes["res://game/rig/character_rig.gd"] = _sha256_resource("res://game/rig/character_rig.gd")
	_source_hashes["res://core/lit_textures.gd"] = _sha256_resource("res://core/lit_textures.gd")
	return _errors.is_empty()


func _setup_rig() -> bool:
	return _setup_api_variant_rig("original")


func _setup_api_variant_rig(variant: String) -> bool:
	var errors_before := _errors.size()
	if _rig != null and is_instance_valid(_rig):
		if _rig.get_parent() != null:
			_rig.get_parent().remove_child(_rig)
		_rig.free()
	_rig = CharacterRig.new()
	_rig.name = "Rin_%s_ProductionAPI" % variant
	if _holder == null:
		_holder = Node2D.new()
		_holder.name = "NativeAPICaptureHolder"
		add_child(_holder)
	_holder.add_child(_rig)
	var character_path := RigLibrary.CHARACTER_PATH % "rin"
	var variant_skin: Dictionary = _base_skin.duplicate(true)
	if variant == "candidate":
		var textures: Dictionary = variant_skin.get("textures", {})
		var grip: Dictionary = (textures.get("hand_left_grip", {}) as Dictionary).duplicate(true)
		grip["file"] = STAGED_CANDIDATE
		grip["size"] = [CANDIDATE_GRIP_SIZE.x, CANDIDATE_GRIP_SIZE.y]
		grip["pivot"] = [CANDIDATE_GRIP_PIVOT.x, CANDIDATE_GRIP_PIVOT.y]
		grip["texture_scale"] = CANDIDATE_GRIP_SCALE
		textures["hand_left_grip"] = grip
		variant_skin["textures"] = textures
	RigLibrary._json_cache[character_path] = variant_skin
	var setup_ok := _rig.setup("rin")
	RigLibrary._json_cache[character_path] = _base_skin
	_check(setup_ok, "%s cloned skin loads through production CharacterRig.setup" % variant)
	if not setup_ok:
		return false
	_back_sprite = null
	_back_grip_entry.clear()
	for part: CanvasItem in _rig._parts:
		if str(part.name) == "hand_back":
			_back_sprite = part as Sprite2D
			break
	_check(_back_sprite != null, "%s logical hand_back is a production Sprite2D" % variant)
	if _back_sprite == null:
		return false
	for entry: Dictionary in _rig._hand_grips:
		if entry.get("bone") == &"hand_back" and entry.get("sprite") == _back_sprite:
			_back_grip_entry = entry
			break
	_check(not _back_grip_entry.is_empty(), "%s production grip entry is created" % variant)
	if _back_grip_entry.is_empty():
		return false
	_check(_back_sprite.z_index == -6 and _rig.weapon_root().z_index == 7, "%s retains original production layer order" % variant)
	var grip_texture: Texture2D = _back_grip_entry["grip_texture"]
	if variant == "candidate":
		_check(grip_texture is CanvasTexture and grip_texture.get_size() == Vector2(CANDIDATE_GRIP_SIZE), "candidate source is the production-loaded native crop")
		_check((_back_grip_entry["grip_scale"] as Vector2).is_equal_approx(Vector2.ONE * CANDIDATE_GRIP_SCALE), "production entry retains candidate texture_scale")
	else:
		_check(grip_texture.get_size() == Vector2(ORIGINAL_GRIP_SIZE), "original control retains 90x70 authored grip source")
		_check((_back_grip_entry["grip_scale"] as Vector2).is_equal_approx(Vector2.ONE * 0.04205), "original control uses existing character scale")
	_input.on_floor = true
	_input.two_handed = true
	_input.action = &""
	_input.aim_dir = Vector2.RIGHT
	_rig.set_weapon("rifle")
	_current_api_variant = variant
	return setup_ok and _errors.size() == errors_before


func _apply_hand_variant(_use_candidate: bool) -> void:
	# Intentionally empty: the production CharacterRig animator owns texture, pivot, and scale.
	pass


func _capture_one(label: String, variant: String, scenario: String, facing: int, aim: Vector2, weapon_id: String, zoom: float, normal_mode: String) -> void:
	if variant != _current_api_variant and not _setup_api_variant_rig(variant):
		_fail("cannot prepare production API rig for " + variant)
		return
	await super._capture_one(label, variant, scenario, facing, aim, weapon_id, zoom, normal_mode)


func _run_capture_matrix() -> void:
	await super._run_capture_matrix()
	# The inherited matrix already covers rifle and shotgun. Extend to every other current
	# Player ranged visual ID; each pair uses the same actual setup/animate path and camera.
	for weapon_id in ["smg", "railgun", "launcher", "laser", "pistol"]:
		for facing in [1, -1]:
			var side := "right" if facing == 1 else "left"
			for aim_name in ["level", "up", "down"]:
				var aim := _aim_vector(aim_name, facing)
				var pair := "all_visuals_%s_%s_f%s_z23p78" % [weapon_id, aim_name, side]
				await _capture_one(pair + "_original", "original", "stand", facing, aim, weapon_id, CLOSE_ZOOM, "lit")
				await _capture_one(pair + "_candidate", "candidate", "stand", facing, aim, weapon_id, CLOSE_ZOOM, "lit")
	_compare_pairs()
	_check(_captures.size() == 100, "native API matrix includes 40 inherited states and 60 additional ranged visual captures")


func _compare_pairs() -> void:
	for key: String in _pair_images:
		var pair: Dictionary = _pair_images[key]
		if not pair.has("original") or not pair.has("candidate"):
			continue
		var before_record: Dictionary = pair["original"]
		var after_record: Dictionary = pair["candidate"]
		var before: Image = before_record["image"]
		var after: Image = after_record["image"]
		var r1: Array = before_record["hand_rect"]
		var r2: Array = after_record["hand_rect"]
		var x0 := maxi(0, mini(int(r1[0]), int(r2[0])))
		var y0 := maxi(0, mini(int(r1[1]), int(r2[1])))
		var x1 := mini(VIEW_SIZE.x, maxi(int(r1[0]) + int(r1[2]), int(r2[0]) + int(r2[2])))
		var y1 := mini(VIEW_SIZE.y, maxi(int(r1[1]) + int(r1[3]), int(r2[1]) + int(r2[3])))
		var changed := 0
		var total := 0.0
		var maximum := 0.0
		for y in range(y0, y1):
			for x in range(x0, x1):
				var a := before.get_pixel(x, y)
				var b := after.get_pixel(x, y)
				var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
				if delta > 0.01:
					changed += 1
				total += delta
				maximum = maxf(maximum, delta)
		var roi_area := maxi(1, (x1 - x0) * (y1 - y0))
		var stats := {"pair": key, "hand_roi_xywh": [x0, y0, x1 - x0, y1 - y0], "changed_pixels_over_0p01": changed,
			"mean_max_channel_delta": total / float(roi_area), "max_channel_delta": maximum}
		_write_json(_out_dir.path_join(key + "_pairdiff.json"), stats)
		_check(changed >= 100, "candidate visibly changes paired image %s (%d/100 pixels)" % [key, changed])


func _run_production_cpu_matrix() -> void:
	var cases := [
		{"name": "two_handed", "weapon": "rifle", "two_handed": true, "shield": false, "dead": false, "action": &""},
		{"name": "shield", "weapon": "rifle", "two_handed": false, "shield": true, "dead": false, "action": &""},
		{"name": "recoil", "weapon": "rifle", "two_handed": true, "shield": false, "dead": false, "action": &"", "recoil": true},
		{"name": "dead", "weapon": "rifle", "two_handed": true, "shield": false, "dead": true, "action": &""},
		{"name": "unequipped", "weapon": "", "two_handed": false, "shield": false, "dead": false, "action": &""},
	]
	for variant in ["original", "candidate"]:
		if not _setup_api_variant_rig(variant):
			return
		for facing in [1, -1]:
			for aim in [Vector2(float(facing), 0.0), Vector2(float(facing), -0.55).normalized(), Vector2(float(facing), 0.55).normalized()]:
				for case: Dictionary in cases:
					_rig.facing = facing
					_input.facing = facing
					_input.aim_dir = aim
					_input.two_handed = bool(case["two_handed"])
					_input.shield_forward = bool(case["shield"])
					_input.dead = bool(case["dead"])
					_input.action = case["action"]
					_input.recoil = 1.0 if bool(case.get("recoil", false)) else 0.0
					_rig.set_weapon(str(case["weapon"]))
					for frame in 120:
						_rig.animate(1.0 / 60.0, _input)
					var closed: bool = not str(case["weapon"]).is_empty() and not bool(case["dead"]) and bool(case["two_handed"]) and not bool(case["shield"]) and case["action"] == &""
					var should_be_candidate_scale: bool = variant == "candidate" and closed
					var expected_scale := CANDIDATE_GRIP_SCALE if should_be_candidate_scale else 0.04205
					_check(bool(_back_grip_entry["closed"]) == closed, "%s/%s/f%s grip closed state follows production update" % [variant, case["name"], facing])
					_check(_back_sprite.scale.is_equal_approx(Vector2.ONE * expected_scale), "%s/%s/f%s uses production open/closed texture scale" % [variant, case["name"], facing])
					var expected_size := CANDIDATE_GRIP_SIZE if should_be_candidate_scale else (ORIGINAL_GRIP_SIZE if closed else Vector2i(134, 65))
					_check(_back_sprite.texture.get_size() == Vector2(expected_size), "%s/%s/f%s uses actual expected grip/open texture" % [variant, case["name"], facing])
					if should_be_candidate_scale:
						_check(_back_sprite.offset.is_equal_approx(-CANDIDATE_GRIP_PIVOT), "%s/%s/f%s uses candidate authored wrist pivot" % [variant, case["name"], facing])
						_check(_back_sprite.global_position.distance_to(_rig.bone(&"hand_back").global_position) <= 0.001, "%s/%s/f%s preserves wrist-bone anchor" % [variant, case["name"], facing])
					_check(_back_sprite.scale.is_finite() and _back_sprite.global_position.is_finite(), "%s/%s/f%s attachment transform stays finite" % [variant, case["name"], facing])
		for weapon_id in ["rifle", "shotgun", "smg", "railgun", "launcher", "laser", "pistol"]:
			for facing in [1, -1]:
				for aim_name in ["level", "up", "down"]:
					_input.facing = facing
					_input.aim_dir = _aim_vector(aim_name, facing)
					_input.two_handed = true
					_input.dead = false
					_input.shield_forward = false
					_input.action = &""
					_rig.facing = facing
					_rig.set_weapon(weapon_id)
					for frame in 3:
						_rig.animate(1.0 / 60.0, _input)
					var expected_native_scale := CANDIDATE_GRIP_SCALE if variant == "candidate" else 0.04205
					_check(_rig.weapon_root().visible and not _rig._weapon_def.is_empty(), "%s/%s/%s/f%s resolves a real ranged visual" % [variant, weapon_id, aim_name, facing])
					_check(bool(_back_grip_entry["closed"]) and _back_sprite.scale.is_equal_approx(Vector2.ONE * expected_native_scale), "%s/%s/%s/f%s uses production closed-grip scale" % [variant, weapon_id, aim_name, facing])
	print("NE222_SUPPORT_HAND_PRODUCTION_API_CPU checks=%d errors=%d" % [_checks, _errors.size()])


func _write_manifest() -> void:
	super._write_manifest()
	var path := _out_dir.path_join("manifest.json")
	var manifest := _read_json(path)
	manifest["status"] = "NATIVE_PRODUCTION_API_REVIEW_REQUIRED_NOT_ACCEPTED"
	manifest["production_api"] = {
		"setup": "cloned Rin character JSON is injected into RigLibrary cache before CharacterRig.setup; actual CharacterRig._update_hand_grips changes texture, pivot, and scale",
		"candidate_resource": STAGED_RESOURCE,
		"candidate_normal_resource": STAGED_NORMAL_RESOURCE,
		"candidate_scale": CANDIDATE_GRIP_SCALE,
		"candidate_pivot": [CANDIDATE_GRIP_PIVOT.x, CANDIDATE_GRIP_PIVOT.y],
		"no_manual_sprite_variant_override": true,
		"character_json_sha256": _base_skin_hash,
		"fixture_script_sha256": _sha256_resource("res://.godot/ne222-support-hand-registration-v3/native/production_api_capture.gd"),
		"source_file_sha256": _source_hashes,
	}
	manifest["limitations"] = [
		"synthetic cloned skin JSON only; candidate remains unadopted and no formal character JSON changed",
		"native appearance is a limited source review, not all gameplay, all weapon, full-body, or NE222 acceptance",
		"the single back-hand sprite remains behind the weapon, so this does not prove visible thumb/fingers over the fore-end",
	]
	_write_json(path, manifest)
