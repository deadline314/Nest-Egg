extends "res://pm/Nest-Egg/attachments/NE-222-native-support-hand/capture_api.gd"
## Portable review capture: clone the archived original skin and compare it with the
## current candidate skin through CharacterRig.setup and its real grip-scale API.

const LEGACY_CHARACTER := "res://pm/Nest-Egg/attachments/NE-222-native-support-hand/legacy/character.json"
const LEGACY_HAND := "../../../pm/Nest-Egg/attachments/NE-222-native-support-hand/legacy/hand_left_grip.png"
const PORTABLE_CANDIDATE := "res://art/characters/rin/parts/hand_left_grip.png"
const PORTABLE_NORMAL := "res://art/characters/rin/parts/hand_left_grip_n.png"
const PORTABLE_CHARACTER := "res://art/characters/rin/character.json"

var _legacy_skin: Dictionary = {}
var _candidate_skin: Dictionary = {}


func _run() -> void:
	if "--cpu-only" not in OS.get_cmdline_user_args() and not Array(OS.get_cmdline_user_args()).any(func(arg: String) -> bool: return arg.begins_with("--out-dir=")):
		_fail("native capture requires --out-dir=<new absolute directory>")
		_finish(false)
		return
	if not _prepare_portable_sources():
		_finish(false)
		return
	if "--cpu-only" in OS.get_cmdline_user_args():
		if _setup_api_variant_rig("original"):
			_run_production_cpu_matrix()
		_finish(false)
		return
	if not _setup_viewport() or not _setup_api_variant_rig("original"):
		_finish(false)
		return
	await _run_capture_matrix()
	_finish(true)


func _prepare_portable_sources() -> bool:
	_legacy_skin = _read_json(LEGACY_CHARACTER)
	_candidate_skin = _read_json(PORTABLE_CHARACTER)
	_check(not _legacy_skin.is_empty(), "public attachment legacy character JSON loads")
	_check(not _candidate_skin.is_empty(), "current candidate Rin character JSON loads")
	if _legacy_skin.is_empty() or _candidate_skin.is_empty():
		return false
	_base_scale = 0.04205
	_candidate_scale = CANDIDATE_GRIP_SCALE
	_candidate_pivot = CANDIDATE_GRIP_PIVOT
	_base_skin = _legacy_skin.duplicate(true)
	_base_skin_hash = _sha256_resource(LEGACY_CHARACTER)
	var legacy_grip: Dictionary = (_legacy_skin.get("textures", {}) as Dictionary).get("hand_left_grip", {})
	var candidate_grip: Dictionary = (_candidate_skin.get("textures", {}) as Dictionary).get("hand_left_grip", {})
	_check(RigLibrary.vec2(legacy_grip.get("size")) == Vector2(90, 70), "legacy attachment is the original 90x70 hand")
	_check(RigLibrary.vec2(candidate_grip.get("size")) == Vector2(226, 142), "candidate skin declares 226x142 crop")
	_check(candidate_grip.get("pivot", []) == [26.0822, 25.9259], "candidate pivot matches reviewed source registration")
	_check(is_equal_approx(float(candidate_grip.get("texture_scale", 0.0)), CANDIDATE_GRIP_SCALE), "candidate density uses reviewed native scale")
	_check(ResourceLoader.exists(PORTABLE_CANDIDATE) and ResourceLoader.exists(PORTABLE_NORMAL), "formal WIP candidate diffuse and normal are imported resources")
	var candidate_canvas := LitTextures.load_texture(PORTABLE_CANDIDATE, CANDIDATE_GRIP_SIZE)
	_check(candidate_canvas is CanvasTexture, "candidate resolves through production LitTextures")
	if candidate_canvas is CanvasTexture:
		var canvas := candidate_canvas as CanvasTexture
		_check(canvas.diffuse_texture.get_size() == Vector2(CANDIDATE_GRIP_SIZE), "candidate diffuse is native-sized")
		_check(canvas.normal_texture != null and canvas.normal_texture.get_size() == Vector2(CANDIDATE_GRIP_SIZE), "candidate normal matches diffuse dimensions")
	var legacy_resource := ProjectSettings.globalize_path("res://pm/Nest-Egg/attachments/NE-222-native-support-hand/legacy/hand_left_grip.png")
	_check(FileAccess.file_exists(legacy_resource), "public attachment contains legacy original grip texture")
	for path in [LEGACY_CHARACTER, PORTABLE_CHARACTER, PORTABLE_CANDIDATE, PORTABLE_NORMAL, "res://game/rig/character_rig.gd", "res://core/lit_textures.gd", "res://tools/viewport_capture.gd"]:
		_source_hashes[path] = _sha256_resource(path)
	return _errors.is_empty()


func _setup_api_variant_rig(variant: String) -> bool:
	var errors_before := _errors.size()
	if _rig != null and is_instance_valid(_rig):
		if _rig.get_parent() != null:
			_rig.get_parent().remove_child(_rig)
		_rig.free()
	_rig = CharacterRig.new()
	_rig.name = "Rin_%s_PortableProductionAPI" % variant
	if _holder == null:
		_holder = Node2D.new()
		_holder.name = "PortableCaptureHolder"
		add_child(_holder)
	_holder.add_child(_rig)
	var character_path := RigLibrary.CHARACTER_PATH % "rin"
	var variant_skin: Dictionary = _legacy_skin.duplicate(true)
	var textures: Dictionary = variant_skin.get("textures", {})
	var grip: Dictionary = (textures.get("hand_left_grip", {}) as Dictionary).duplicate(true)
	if variant == "candidate":
		var candidate_grip: Dictionary = (_candidate_skin.get("textures", {}) as Dictionary).get("hand_left_grip", {})
		grip = candidate_grip.duplicate(true)
	else:
		grip["file"] = LEGACY_HAND
	textures["hand_left_grip"] = grip
	variant_skin["textures"] = textures
	RigLibrary._json_cache[character_path] = variant_skin
	var setup_ok := _rig.setup("rin")
	RigLibrary._json_cache[character_path] = _legacy_skin
	_check(setup_ok, "%s public-skin clone loads through CharacterRig.setup" % variant)
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
	_check(not _back_grip_entry.is_empty(), "%s real production grip entry is configured" % variant)
	if _back_grip_entry.is_empty():
		return false
	var texture: Texture2D = _back_grip_entry["grip_texture"]
	if variant == "candidate":
		_check(texture is CanvasTexture and texture.get_size() == Vector2(CANDIDATE_GRIP_SIZE), "candidate uses loaded formal-WIP crop")
		_check((_back_grip_entry["grip_scale"] as Vector2).is_equal_approx(Vector2.ONE * CANDIDATE_GRIP_SCALE), "candidate scale comes from data")
	else:
		_check(texture.get_size() == Vector2(ORIGINAL_GRIP_SIZE), "original uses archived 90x70 crop")
		_check((_back_grip_entry["grip_scale"] as Vector2).is_equal_approx(Vector2.ONE * 0.04205), "original scale remains archived body density")
	_rig.facing = 1
	_input.facing = 1
	_input.on_floor = true
	_input.two_handed = true
	_input.action = &""
	_input.aim_dir = Vector2.RIGHT
	_rig.set_weapon("rifle")
	_current_api_variant = variant
	return _errors.size() == errors_before


func _run_capture_matrix() -> void:
	await super._run_capture_matrix()
	# The inherited 100-image matrix only includes horizontal shotgun. Add up/down
	# for both facings, preserving paired original/candidate production API setup.
	for facing in [1, -1]:
		var side := "right" if facing == 1 else "left"
		for aim_name in ["up", "down"]:
			var aim := _aim_vector(aim_name, facing)
			var pair := "portable_shotgun_%s_f%s_z23p78" % [aim_name, side]
			await _capture_one(pair + "_original", "original", "stand", facing, aim, "shotgun", CLOSE_ZOOM, "lit")
			await _capture_one(pair + "_candidate", "candidate", "stand", facing, aim, "shotgun", CLOSE_ZOOM, "lit")
	_compare_pairs()
	_check(_captures.size() == 108, "portable matrix adds eight shotgun up/down images to the 100-image matrix")


func _write_manifest() -> void:
	super._write_manifest()
	var path := _out_dir.path_join("manifest.json")
	var manifest := _read_json(path)
	manifest["status"] = "PORTABLE_NATIVE_SOURCE_REVIEW_NOT_ART_ACCEPTANCE"
	manifest["portable_review"] = {
		"legacy_json": LEGACY_CHARACTER, "legacy_diffuse": "res://pm/Nest-Egg/attachments/NE-222-native-support-hand/legacy/hand_left_grip.png",
		"candidate_diffuse": PORTABLE_CANDIDATE, "candidate_normal": PORTABLE_NORMAL,
		"api": "Both variants are cloned from the same archived legacy skin; candidate variant swaps only the grip texture record before CharacterRig.setup. No per-frame Sprite2D mutation.",
		"expected_capture_count": 108, "fixture_script_sha256": _sha256_resource("res://pm/Nest-Egg/attachments/NE-222-native-support-hand/portable_support_capture.gd"),
		"source_sha256": _source_hashes,
		"limitations": ["source join metrics do not prove silhouette or full-body visual acceptance", "all seven weapon visual IDs have horizontal/up/down for both facings except shotgun was just extended in this 108-image replay", "Partial support-hand delivery; whole-character and complete animation acceptance remain separate"],
	}
	_write_json(path, manifest)
