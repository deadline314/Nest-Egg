extends Node2D
## Private Forward+ acceptance fixture for the unadopted seed-22308 support hand.
## It mounts an ImageTexture/CanvasTexture on the real Rin hand_back Sprite2D;
## no formal file is changed and no rig/weapon geometry is overridden.

const DEFAULT_OUT_DIR := ".godot/ne222-support-hand-review"
const VIEW_SIZE := Vector2i(1536, 1216)
const GAME_ZOOM := 3.4
const CLOSE_ZOOM := 23.78
const CLOSE_BASE := Vector2(768.0, 1600.0)
const CHARACTER_PATH := "res://art/characters/rin/character.json"
const WEAPON_DATA_PATH := "res://art/weapons/weapons.json"
const CANDIDATE_PATH := "res://art_src/characters/rin_support_grip_22308/overrides/hand_back.png"
const NORMAL_PATH := "res://art_src/characters/rin_support_grip_22308/overrides/hand_back_n.png"
const REGISTRATION_PATH := "res://pm/Nest-Egg/attachments/NE-222-native-support-hand/registration.json"
const CROP_SOURCE_PATH := "res://art_src/characters/rin_support_grip_22308/source/actual-rifle-back_human-crop-native.png"
const PAIR_METRIC_DELTA := 0.006

var _viewport: SubViewport
var _holder: Node2D
var _rig: CharacterRig
var _input := RigInput.new()
var _back_sprite: Sprite2D
var _back_grip_entry: Dictionary
var _candidate_canvas: CanvasTexture
var _candidate_diffuse: ImageTexture
var _candidate_normal: ImageTexture
var _base_scale := 0.0
var _candidate_scale := 0.0
var _candidate_pivot := Vector2.ZERO
var _errors: Array[String] = []
var _checks := 0
var _captures: Array[Dictionary] = []
var _pair_images: Dictionary = {}
var _source_hashes: Dictionary = {}
var _light_key: PointLight2D
var _normal_enabled := true
var _background: ColorRect
var _out_dir := DEFAULT_OUT_DIR
var _current_scenario := "stand"
var _current_weapon_id := "rifle"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _prepare_sources():
		_finish(false)
		return
	var cli_args := OS.get_cmdline_user_args()
	if "--cpu-only" in cli_args:
		if _setup_rig():
			_run_cpu_matrix()
		_finish(false)
		return
	if not _setup_viewport() or not _setup_rig():
		_finish(false)
		return
	await _run_capture_matrix()
	_finish(true)


func _prepare_sources() -> bool:
	var manifest_text := FileAccess.get_file_as_string(REGISTRATION_PATH)
	var parsed: Variant = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		_fail("private registration.json is missing/invalid")
		return false
	var candidate: Dictionary = parsed.get("candidate_registration", {})
	_candidate_scale = float(candidate.get("raw_texture_scale", 0.0))
	var pivot_values: Array = candidate.get("raw_texture_pivot_wrist_px", [])
	if pivot_values.size() != 2:
		_fail("candidate pivot is malformed")
		return false
	_candidate_pivot = Vector2(float(pivot_values[0]), float(pivot_values[1]))
	var character: Dictionary = _read_json(CHARACTER_PATH)
	_base_scale = float(character.get("texture_scale", 0.0))
	_check(is_finite(_candidate_scale) and _candidate_scale > 0.0 and _candidate_pivot.is_finite(), "candidate scale/pivot are finite")
	_check(absf(float(character.get("scale", 0.0)) - 1.15) < 1e-6, "current Rin body scale matches registration")
	_check(absf(_base_scale - 0.04205) < 1e-7, "current Rin texture scale matches registration")
	_check(_candidate_scale > 0.0 and _candidate_scale < _base_scale, "raw texture uses private scale to preserve native pixels")
	var image := Image.load_from_file(ProjectSettings.globalize_path(CANDIDATE_PATH))
	var normal_image := Image.load_from_file(ProjectSettings.globalize_path(NORMAL_PATH))
	_check(image != null and image.get_size() == Vector2i(226, 142), "candidate diffuse loads at source crop size")
	_check(normal_image != null and normal_image.get_size() == Vector2i(226, 142), "candidate normal companion matches diffuse dimensions")
	if image == null or normal_image == null:
		return false
	var used := image.get_used_rect()
	_check(used.position == Vector2i.ZERO and used.size == Vector2i(226, 142), "all candidate owner pixels remain inside the exact crop")
	_candidate_diffuse = ImageTexture.create_from_image(image)
	_candidate_normal = ImageTexture.create_from_image(normal_image)
	_candidate_canvas = CanvasTexture.new()
	_candidate_canvas.diffuse_texture = _candidate_diffuse
	_candidate_canvas.normal_texture = _candidate_normal
	_check(_candidate_canvas.diffuse_texture != null and _candidate_canvas.normal_texture != null, "candidate CanvasTexture retains diffuse and normal channels")
	for path in [CHARACTER_PATH, WEAPON_DATA_PATH, CANDIDATE_PATH, NORMAL_PATH, CROP_SOURCE_PATH, "res://art/weapons/rifle.png", "res://art/weapons/shotgun.png", "res://game/rig/character_rig.gd", "res://game/rig/humanoid_animator.gd", "res://core/lit_textures.gd", "res://core/light_kit.gd", "res://tools/viewport_capture.gd"]:
		_source_hashes[path] = _sha256_resource(path)
	return _errors.is_empty()


func _setup_viewport() -> bool:
	_viewport = SubViewport.new()
	_viewport.name = "NativeForwardPlusHandViewport"
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = false
	_viewport.use_hdr_2d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.add_child(LightKit.create_environment())
	var background := ColorRect.new()
	background.name = "NeutralGrayDiagnosticBackdrop"
	background.position = Vector2.ZERO
	background.size = VIEW_SIZE
	background.color = Color(0.27, 0.27, 0.27, 1.0)
	_background = background
	var background_material := CanvasItemMaterial.new()
	background_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	background.material = background_material
	background.z_index = -100
	_viewport.add_child(background)
	_light_key = LightKit.create_point_light(Color.WHITE, 720.0, 0.85, false, false)
	_light_key.name = "WhiteKeyLight_0p85"
	_light_key.position = Vector2(590, 385)
	_viewport.add_child(_light_key)
	_holder = Node2D.new()
	_holder.name = "CapturedRinRig"
	_holder.position = CLOSE_BASE
	_holder.scale = Vector2.ONE * CLOSE_ZOOM
	_viewport.add_child(_holder)
	_check(_viewport.use_hdr_2d, "capture viewport has HDR 2D enabled")
	return _errors.is_empty()


func _setup_rig() -> bool:
	if _holder == null:
		_holder = Node2D.new()
		add_child(_holder)
	_rig = CharacterRig.new()
	_holder.add_child(_rig)
	_check(_rig.setup("rin"), "production CharacterRig setup for Rin succeeds")
	if _rig.animator == null:
		_fail("production HumanoidAnimator is missing")
		return false
	for part: CanvasItem in _rig._parts:
		if str(part.name) == "hand_back":
			_back_sprite = part as Sprite2D
			break
	_check(_back_sprite != null, "real hand_back slot resolves to Sprite2D")
	if _back_sprite == null:
		return false
	for entry: Dictionary in _rig._hand_grips:
		if entry.get("bone") == &"hand_back" and entry.get("sprite") == _back_sprite:
			_back_grip_entry = entry
			break
	_check(not _back_grip_entry.is_empty(), "real hand_back grip metadata is retained for exact original control")
	if _back_grip_entry.is_empty():
		return false
	_check(_back_sprite.z_index == -6 and _rig.weapon_root().z_index == 7, "capture retains production back-hand / weapon z ordering")
	_input.on_floor = true
	_input.two_handed = true
	_input.action = &""
	_input.aim_dir = Vector2.RIGHT
	_rig.set_weapon("rifle")
	return _errors.is_empty()


func _run_cpu_matrix() -> void:
	for scenario in ["stand", "crouch", "shield", "recoil", "dead", "unequipped"]:
		_set_state(scenario, 1, Vector2.RIGHT, "rifle")
		var okay := true
		for frame in 120:
			_rig.animate(1.0 / 60.0, _input)
			_apply_hand_variant(true)
			var expects_candidate := _grip_should_be_closed(scenario, _current_weapon_id)
			okay = okay and _assert_runtime_anchors("cpu_%s" % scenario, expects_candidate)
		_check(okay, "headless rig scenario %s stays finite through settled animation" % scenario)


func _run_capture_matrix() -> void:
	var args := OS.get_cmdline_user_args()
	var has_out_dir := false
	for arg in args:
		if arg.begins_with("--out-dir="):
			_out_dir = arg.trim_prefix("--out-dir=")
			has_out_dir = true
	if "--white-edge-only" in args and not has_out_dir:
		_out_dir = ".godot/ne222-support-hand-review-white-edge"
	if DirAccess.dir_exists_absolute(_out_dir):
		_fail("refusing to overwrite prior native capture folder: " + _out_dir)
		return
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create native capture folder: " + _out_dir)
		return
	if "--white-edge-only" in OS.get_cmdline_user_args():
		_background.color = Color.WHITE
		await _capture_one("white_edge_level_right_original", "original", "stand", 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "lit")
		await _capture_one("white_edge_level_right_candidate", "candidate", "stand", 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "lit")
		_compare_pairs()
		_write_manifest()
		if _captures.size() != 2:
			_fail("expected 2 white-edge captures, got %d" % _captures.size())
		return
	# Standing and crouching, both facings, three actual aim directions, original and candidate at native upper-body zoom.
	for posture in ["stand", "crouch"]:
		for facing in [1, -1]:
			for aim_name in ["level", "up", "down"]:
				var aim := _aim_vector(aim_name, int(facing))
				var pair := "%s_%s_f%s_%s_rifle_z23p78" % [posture, aim_name, "right" if facing == 1 else "left", str(facing)]
				await _capture_one(pair + "_original", "original", posture, int(facing), aim, "rifle", CLOSE_ZOOM, "lit")
				await _capture_one(pair + "_candidate", "candidate", posture, int(facing), aim, "rifle", CLOSE_ZOOM, "lit")
	# The actual 3.4 game zoom gets full-body controls in both facings.
	for facing in [1, -1]:
		var side := "right" if facing == 1 else "left"
		await _capture_one("game_stand_level_%s_rifle_original" % side, "original", "stand", int(facing), _aim_vector("level", int(facing)), "rifle", GAME_ZOOM, "lit")
		await _capture_one("game_stand_level_%s_rifle_candidate" % side, "candidate", "stand", int(facing), _aim_vector("level", int(facing)), "rifle", GAME_ZOOM, "lit")
	# A second real two-handed weapon tests transfer without changing the rifle-authored registration.
	for facing in [1, -1]:
		var side := "right" if facing == 1 else "left"
		await _capture_one("stand_level_%s_shotgun_original" % side, "original", "stand", int(facing), _aim_vector("level", int(facing)), "shotgun", CLOSE_ZOOM, "lit")
		await _capture_one("stand_level_%s_shotgun_candidate" % side, "candidate", "stand", int(facing), _aim_vector("level", int(facing)), "shotgun", CLOSE_ZOOM, "lit")
	# Visibility/toggle states use the same actual rig; candidate must yield to the authored open hand when grip is inactive.
	for transition in ["shield", "recoil", "dead", "unequipped"]:
		await _capture_one("transition_%s_candidate" % transition, "candidate", transition, 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "lit")
	# Normal-off control is diagnostic only. Keep matching same-state baseline/candidate images.
	await _capture_one("normal_off_level_right_original", "original", "stand", 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "normal_off")
	await _capture_one("normal_off_level_right_candidate", "candidate", "stand", 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "normal_off")
	_background.color = Color.WHITE
	await _capture_one("white_edge_level_right_original", "original", "stand", 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "lit")
	await _capture_one("white_edge_level_right_candidate", "candidate", "stand", 1, Vector2.RIGHT, "rifle", CLOSE_ZOOM, "lit")
	_compare_pairs()
	_write_manifest()
	if _captures.size() != 40:
		_fail("expected 40 native captures, got %d" % _captures.size())


func _capture_one(label: String, variant: String, scenario: String, facing: int, aim: Vector2, weapon_id: String, zoom: float, normal_mode: String) -> void:
	_set_state(scenario, facing, aim, weapon_id)
	_holder.scale = Vector2.ONE * zoom
	_normal_enabled = normal_mode != "normal_off"
	LitTextures.set_enabled(_normal_enabled)
	for frame in 120:
		_rig.animate(1.0 / 60.0, _input)
		_apply_hand_variant(variant == "candidate")
	if zoom <= GAME_ZOOM + 0.001:
		_recenter_subject(true)
	else:
		_recenter_subject(false)
	for frame in 3:
		await RenderingServer.frame_post_draw
	var actual_weapon_visible := _rig.weapon_root().visible
	var wants_weapon := not weapon_id.is_empty() and scenario != "unequipped" and scenario != "dead"
	_check(actual_weapon_visible == wants_weapon, "%s weapon visibility is correct" % label)
	var expects_candidate := variant == "candidate" and _grip_should_be_closed(scenario, _current_weapon_id)
	_check(_assert_runtime_anchors(label, expects_candidate), "%s rig/weapon/grip geometry is finite and on contract" % label)
	var image: Image = preload("res://tools/viewport_capture.gd").image(_viewport)
	if image == null or image.get_size() != VIEW_SIZE:
		_fail(label + " viewport readback missing or wrong size")
		return
	var bounds := _subject_bounds(false)
	var image_path := _out_dir.path_join(label + ".png")
	if image.save_png(image_path) != OK:
		_fail(label + " failed to save native output")
		return
	var measurement := _measure_image(image)
	var closed := _grip_should_be_closed(scenario, weapon_id)
	var hand_texture: Texture2D = _back_sprite.texture
	var normal_present := hand_texture is CanvasTexture and (hand_texture as CanvasTexture).normal_texture != null
	var record := {
		"name": label, "variant": variant, "scenario": scenario, "facing": "right" if facing > 0 else "left",
		"aim_dir": [aim.x, aim.y], "weapon": weapon_id, "zoom": zoom, "normal_mode": normal_mode,
		"two_handed": _input.two_handed, "shield_forward": _input.shield_forward, "dead": _input.dead, "crouching": _input.crouching,
		"grip_expected_closed": closed, "candidate_mounted": variant == "candidate" and closed,
		"backdrop_srgb": [_background.color.r, _background.color.g, _background.color.b],
		"back_hand_texture_size": [hand_texture.get_width(), hand_texture.get_height()] if hand_texture != null else [],
		"back_hand_node_scale": [_back_sprite.scale.x, _back_sprite.scale.y], "back_hand_has_normal": normal_present,
		"hand_anchor_to_back_bone_world_px": _back_sprite.global_position.distance_to(_rig.bone(&"hand_back").global_position),
		"runtime_geometry": measurement, "rig_bounds_screen": _rect_to_json(bounds),
		"image": image_path, "image_sha256": _sha256_file(image_path),
	}
	_captures.append(record)
	var key := _pair_key(label)
	if not _pair_images.has(key):
		_pair_images[key] = {}
	_pair_images[key][variant] = {"image": image.duplicate(), "hand_rect": _rect_to_json(_canvas_rect(_back_sprite))}


func _set_state(scenario: String, facing: int, aim: Vector2, weapon_id: String) -> void:
	_current_scenario = scenario
	_current_weapon_id = weapon_id
	_input.facing = facing
	_input.aim_dir = aim
	_input.on_floor = true
	_input.velocity = Vector2.ZERO
	_input.run_speed = 150.0
	_input.crouching = scenario == "crouch"
	_input.shield_forward = scenario == "shield"
	_input.dead = scenario == "dead"
	_input.two_handed = weapon_id != "" and scenario != "shield" and scenario != "unequipped"
	_input.recoil = 1.0 if scenario == "recoil" else 0.0
	_input.action = &""
	_input.hurt = false
	_input.relaxed = false
	_input.on_floor = true
	if weapon_id == "":
		_rig.set_weapon("")
	else:
		_rig.set_weapon(weapon_id)
	if scenario == "unequipped":
		_rig.set_weapon("")
	_input.two_handed = false if scenario == "unequipped" else _input.two_handed
	_rig.facing = facing


func _apply_hand_variant(use_candidate: bool) -> void:
	# animate() owns the current open/closed texture. Only the private candidate's native scale/pivot are injected here.
	var active := use_candidate and _grip_should_be_closed(_current_scenario, _current_weapon_id)
	if active:
		_back_sprite.texture = _candidate_canvas
		_back_sprite.offset = -_candidate_pivot
		_back_sprite.scale = Vector2.ONE * _candidate_scale
	else:
		var closed := bool(_back_grip_entry.get("closed", false))
		_back_sprite.texture = _back_grip_entry["grip_texture"] if closed else _back_grip_entry["open_texture"]
		_back_sprite.offset = -_back_grip_entry["grip_pivot"] if closed else -_back_grip_entry["open_pivot"]
		_back_sprite.scale = Vector2.ONE * _base_scale


func _grip_should_be_closed(scenario: String, weapon_id: String) -> bool:
	return not weapon_id.is_empty() and scenario != "dead" and scenario != "shield" and scenario != "unequipped"


func _assert_runtime_anchors(label: String, candidate_expected: bool) -> bool:
	var okay := true
	var weapon_root := _rig.weapon_root()
	if weapon_root == null:
		_fail(label + " has no weapon root")
		return false
	if not weapon_root.visible:
		return true
	var weapon_def := _rig.weapon_def()
	var foregrip_local := (RigLibrary.vec2(weapon_def.get("foregrip")) - RigLibrary.vec2(weapon_def.get("grip"))) * _rig.weapon_scale()
	var foregrip_world := weapon_root.to_global(foregrip_local)
	var foregrip_finite := foregrip_world.is_finite() and _rig.muzzle_global().is_finite()
	_check(foregrip_finite, label + " real weapon foregrip/muzzle are finite")
	okay = okay and foregrip_finite
	var hand_bone := _rig.bone(&"hand_back")
	var offset := _rig.hand_grip_offset(&"hand_back").rotated(_rig.animator._global_angle[&"hand_back"])
	var target := _rig._skeleton.to_global(_rig.animator._global_pos[&"hand_back"] + offset)
	var residual := target.distance_to(foregrip_world)
	_check(is_finite(residual), label + " actual foregrip residual is finite (%.6f)" % residual)
	okay = okay and is_finite(residual)
	if _current_weapon_id == "rifle" and _grip_should_be_closed(_current_scenario, _current_weapon_id):
		_check(residual <= 0.05, label + " rifle IK foregrip target residual is within existing registration (%.6f)" % residual)
		okay = okay and residual <= 0.05
	if candidate_expected:
		var anchor_delta := _back_sprite.global_position.distance_to(hand_bone.global_position)
		_check(is_finite(anchor_delta) and anchor_delta <= 0.01, label + " candidate wrist pivot remains at the real back-hand bone")
		okay = okay and is_finite(anchor_delta) and anchor_delta <= 0.01
	return okay


func _measure_image(image: Image) -> Dictionary:
	var subject := _subject_bounds(false)
	var hand_rect := _canvas_rect(_back_sprite)
	var opaque_hand := 0
	var hand_min := Vector2i(99999, 99999)
	var hand_max := Vector2i(-1, -1)
	for y in range(maxi(0, hand_rect.position.y), mini(VIEW_SIZE.y, hand_rect.end.y)):
		for x in range(maxi(0, hand_rect.position.x), mini(VIEW_SIZE.x, hand_rect.end.x)):
			if image.get_pixel(x, y).a > 0.8:
				opaque_hand += 1
				hand_min.x = mini(hand_min.x, x); hand_min.y = mini(hand_min.y, y)
				hand_max.x = maxi(hand_max.x, x); hand_max.y = maxi(hand_max.y, y)
	return {
		"back_hand_sprite_bbox": _rect_to_json(hand_rect),
		"back_hand_opaque_sample_pixels": opaque_hand,
		"back_hand_opaque_sample_bbox": [hand_min.x, hand_min.y, hand_max.x + 1, hand_max.y + 1] if opaque_hand > 0 else [],
		"back_hand_world_anchor": [_back_sprite.global_position.x, _back_sprite.global_position.y],
		"hand_bone_world": [_rig.bone(&"hand_back").global_position.x, _rig.bone(&"hand_back").global_position.y],
		"back_ik_target_to_foregrip_error_world_px": _back_target_foregrip_error(),
		"weapon_foregrip_world": _foregrip_world_json(), "muzzle_world": [_rig.muzzle_global().x, _rig.muzzle_global().y],
		"weapon_visible": _rig.weapon_root().visible,
	}


func _foregrip_world_json() -> Array[float]:
	if not _rig.weapon_root().visible:
		return []
	var definition := _rig.weapon_def()
	var local := (RigLibrary.vec2(definition.get("foregrip")) - RigLibrary.vec2(definition.get("grip"))) * _rig.weapon_scale()
	var world := _rig.weapon_root().to_global(local)
	return [world.x, world.y]


func _back_target_foregrip_error() -> float:
	if not _rig.weapon_root().visible:
		return -1.0
	var offset := _rig.hand_grip_offset(&"hand_back").rotated(_rig.animator._global_angle[&"hand_back"])
	var target := _rig._skeleton.to_global(_rig.animator._global_pos[&"hand_back"] + offset)
	return target.distance_to(_rig.weapon_root().to_global((RigLibrary.vec2(_rig.weapon_def().get("foregrip")) - RigLibrary.vec2(_rig.weapon_def().get("grip"))) * _rig.weapon_scale()))


func _recenter_subject(full_body: bool) -> void:
	var bounds := _subject_bounds(full_body)
	if bounds.size == Vector2.ZERO:
		_fail("cannot calculate a visible subject bound")
		return
	_holder.position += Vector2(VIEW_SIZE.x * 0.5, VIEW_SIZE.y * 0.5) - bounds.get_center()
	var moved := _subject_bounds(full_body)
	_check(moved.position.x > 1.0 and moved.position.y > 1.0 and moved.end.x < VIEW_SIZE.x - 1.0 and moved.end.y < VIEW_SIZE.y - 1.0,
		"framed subject is inside the native viewport (" + str(_rect_to_json(moved)) + ")")


func _subject_bounds(full_body: bool) -> Rect2:
	var points: Array[Vector2] = []
	for part: CanvasItem in _rig._parts:
		if not part.visible:
			continue
		if not full_body and str(part.name) not in ["head", "armor_torso", "jacket_sleeve_front_upper", "jacket_sleeve_back_upper", "jacket_sleeve_front_lower", "jacket_sleeve_back_lower", "arm_back_upper", "arm_back_lower", "hand_back", "hand_front"]:
			continue
		_add_item_corners(part, points)
	if _rig.weapon_root().visible:
		_add_item_corners(_rig._weapon_sprite, points)
	if points.is_empty():
		return Rect2()
	var left := INF; var top := INF; var right := -INF; var bottom := -INF
	for point in points:
		left = minf(left, point.x); top = minf(top, point.y); right = maxf(right, point.x); bottom = maxf(bottom, point.y)
	return Rect2(left, top, right-left, bottom-top)


func _canvas_rect(item: CanvasItem) -> Rect2i:
	var points: Array[Vector2] = []
	_add_item_corners(item, points)
	if points.is_empty():
		return Rect2i()
	var left := INF; var top := INF; var right := -INF; var bottom := -INF
	for point in points:
		left = minf(left, point.x); top = minf(top, point.y); right = maxf(right, point.x); bottom = maxf(bottom, point.y)
	return Rect2i(Vector2i(floori(left), floori(top)), Vector2i(ceili(right-left), ceili(bottom-top))).intersection(Rect2i(Vector2i.ZERO, VIEW_SIZE))


func _add_item_corners(item: CanvasItem, points: Array[Vector2]) -> void:
	if item == null:
		return
	var transform := item.get_global_transform_with_canvas()
	if item is Sprite2D:
		var local := (item as Sprite2D).get_rect()
		points.append(transform * local.position); points.append(transform * Vector2(local.end.x, local.position.y))
		points.append(transform * local.end); points.append(transform * Vector2(local.position.x, local.end.y))
	elif item is RigPartMesh:
		for vertex in (item as RigPartMesh).deformed_vertices():
			points.append(transform * vertex)


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
		var changed := 0; var total := 0.0; var maximum := 0.0
		for y in range(y0, y1):
			for x in range(x0, x1):
				var a := before.get_pixel(x, y); var b := after.get_pixel(x, y)
				var delta := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b)))
				if delta > 0.01:
					changed += 1
				total += delta; maximum = maxf(maximum, delta)
		var roi_area := maxi(1, (x1 - x0) * (y1 - y0))
		var stats := {"pair": key, "hand_roi_xywh": [x0, y0, x1-x0, y1-y0], "changed_pixels_over_0p01": changed, "mean_max_channel_delta": total / float(roi_area), "max_channel_delta": maximum}
		var path := _out_dir.path_join(key + "_pairdiff.json")
		_write_json(path, stats)
		_check(changed > 100, "candidate visibly changes paired image %s" % key)


func _pair_key(label: String) -> String:
	for suffix in ["_original", "_candidate"]:
		if label.ends_with(suffix):
			return label.trim_suffix(suffix)
	return label


func _write_manifest() -> void:
	var manifest := {
		"status": "NATIVE_CAPTURE_REVIEW_REQUIRED_NOT_ACCEPTED",
		"engine": Engine.get_version_info(), "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"driver": RenderingServer.get_video_adapter_name(), "viewport_px": [VIEW_SIZE.x, VIEW_SIZE.y],
		"capture_conversion": "tools/viewport_capture.gd HDR readback linear-to-sRGB", "use_hdr_2d": _viewport.use_hdr_2d,
		"lightkit": {"glow": true, "fill": LightKit.character_fill, "light_cap": LightKit.character_light_cap},
		"key": {"position": [590, 385], "energy": 0.85, "radius": 720},
		"candidate_scale": _candidate_scale, "candidate_pivot": [_candidate_pivot.x, _candidate_pivot.y],
		"formal_back_hand_z": -6, "weapon_z": 7, "candidate_digit_overwrap_possible_with_current_z": false,
		"source_hashes": _source_hashes, "native_checks": _checks, "errors": _errors, "captures": _captures,
		"limitations": ["private scale adjustment simulates a future set-level texture_scale; production CharacterRig was not changed",
			"hand is behind rifle under current z ordering, so visible finger-over-fore-end cannot occur with one sprite",
			"CPU/renderer screenshot does not prove gameplay, weapon firing, all two-handed weapons, or source-art acceptance"]
	}
	_write_json(_out_dir.path_join("manifest.json"), manifest)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write JSON: " + path)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _finish(captured: bool) -> void:
	if captured:
		_write_manifest()
	print("NE222_SUPPORT_HAND_NATIVE checks=%d captures=%d errors=%d" % [_checks, _captures.size(), _errors.size()])
	if not _errors.is_empty():
		for message in _errors:
			push_error("NE222 support-hand native fixture: " + message)
	get_tree().quit(1 if not _errors.is_empty() else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_fail(label)


func _fail(message: String) -> void:
	_errors.append(message)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _sha256_file(path: String) -> String:
	return FileAccess.get_sha256(path)


func _sha256_resource(path: String) -> String:
	return _sha256_file(ProjectSettings.globalize_path(path))


func _aim_vector(name: String, facing: int) -> Vector2:
	match name:
		"up": return Vector2(float(facing), -0.55).normalized()
		"down": return Vector2(float(facing), 0.55).normalized()
		_: return Vector2(float(facing), 0.0)


func _rect_to_json(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
