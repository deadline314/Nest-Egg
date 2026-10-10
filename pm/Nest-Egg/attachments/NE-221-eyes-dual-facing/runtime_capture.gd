extends Node2D
## Private NE-221 eye-state verification. Uses production CharacterRig.animate() and
## the configured EyeBlink timer; it never assigns eye textures or forces a state.

const SKINS: PackedStringArray = ["rin", "old_k", "nurse", "night_worker", "repairman_chen", "resident", "ah_po", "wataru", "mei"]
const EXPECTED_SKINS: PackedStringArray = ["ah_po", "mei", "night_worker", "nurse", "old_k", "repairman_chen", "resident", "rin", "wataru"]
const STATES: PackedStringArray = ["open", "half", "closed"]
const WINDOW_SIZE := Vector2i(1536, 1400)
const IDLE_SECONDS := 15.0
const TOTAL_SECONDS := 30.0
const STATE_ORDER: Array[StringName] = [&"half", &"closed", &"half", &"open"]
const ACTIVE_BLINK_STATES: Array[StringName] = [&"half", &"closed", &"half"]
const RIG_SCRIPT = preload("res://game/rig/character_rig.gd")

var _out_path := ""
var _cpu_check := false
var _rows: Array[Dictionary] = []
var _errors: Array[String] = []
var _pending_crops: Array[Dictionary] = []
var _stage_capture := ""
var _started_usec := 0
var _started_utc := ""
var _last_wall := 0.0
var _simulation_seconds := 0.0
var _frame_count := 0
var _finished := false
var _finish_after_draw := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
		elif arg == "--cpu-check":
			_cpu_check = true
	if _out_path.is_empty() or not _out_path.is_absolute_path() or not _out_path.to_lower().ends_with(".json"):
		_fail("--out must be an absolute .json path")
		_finish(1)
		return
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		_fail("cannot create output directory: " + error_string(mkdir_error))
		_finish(1)
		return
	if not _check_applicable_skin_scope():
		_finish(1)
		return
	if not _build_rigs():
		_finish(1)
		return
	if _cpu_check:
		_run_cpu_regression()
		_write_report("cpu_headless_only")
		_finish(0 if _errors.is_empty() else 1)
		return
	_setup_capture_viewport()
	RenderingServer.frame_post_draw.connect(_after_draw)
	call_deferred("_begin_capture")


func _check_applicable_skin_scope() -> bool:
	var root := DirAccess.open("res://art/characters")
	if root == null:
		return _fail("cannot enumerate res://art/characters")
	var actual: PackedStringArray = []
	for dir_name in root.get_directories():
		var path := "res://art/characters/%s/character.json" % dir_name
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			return _fail("character.json is invalid: " + path)
		if (parsed as Dictionary).has("eye_states"):
			actual.append(dir_name)
	actual.sort()
	if actual != EXPECTED_SKINS:
		return _fail("runtime eye_states skin inventory changed: %s" % [actual])
	if SKINS.duplicate() != actual:
		var sorted_skins := SKINS.duplicate()
		sorted_skins.sort()
		if sorted_skins != actual:
			return _fail("capture skin list does not cover every configured eye_states entry")
	return true


func _build_rigs() -> bool:
	for skin_id in SKINS:
		var skin: Dictionary = RigLibrary.character(skin_id)
		var eye_config: Variant = skin.get("eye_states")
		if typeof(eye_config) != TYPE_DICTIONARY:
			return _fail("%s missing production eye_states" % skin_id)
		var eye_states: Dictionary = eye_config
		var part_name := str(eye_states.get("part", ""))
		var part_def := _head_part_definition(skin, part_name)
		if part_def.is_empty():
			return _fail("%s eye slot does not resolve to exactly one head part" % skin_id)
		var base_scale := float(skin.get("scale", 1.0))
		var texture_scale := float(skin.get("texture_scale", 0.25))
		if not is_finite(base_scale) or not is_finite(texture_scale) or base_scale <= 0.0 or texture_scale <= 0.0:
			return _fail("%s has invalid source density scales" % skin_id)
		for face in [1, -1]:
			var holder := Node2D.new()
			holder.name = "%s_face_%d" % [skin_id, face]
			# Cancel only the authored display scale so a screen pixel represents one
			# source texel. CharacterRig's bone/head local transforms stay untouched.
			holder.scale = Vector2.ONE / (base_scale * texture_scale)
			add_child(holder)
			var rig: CharacterRig = RIG_SCRIPT.new()
			holder.add_child(rig)
			if not rig.setup(skin_id, "npc"):
				return _fail("%s CharacterRig.setup failed" % skin_id)
			rig.facing = face
			var input := RigInput.new()
			input.two_handed = false
			input.facing = face
			rig.animate(0.0, input)
			var head_value: Variant = rig.get("_eye_part")
			var head: Sprite2D = head_value as Sprite2D
			var blink: EyeBlink = rig.get("_eye_blink") as EyeBlink
			if head == null or blink == null or head.name != part_name:
				return _fail("%s facing %d did not bind the runtime eye driver/head slot" % [skin_id, face])
			if head.get_parent() != rig.bone(&"head"):
				return _fail("%s head slot is not parented to head bone" % skin_id)
			var tex_map: Dictionary = {
				"open": rig.get("_eye_open_texture"),
				"half": rig.get("_eye_half_texture"),
				"closed": rig.get("_eye_closed_texture"),
			}
			var glow_map: Dictionary = {
				"open": rig.get("_eye_open_glow"),
				"half": rig.get("_eye_half_glow"),
				"closed": rig.get("_eye_closed_glow"),
			}
			for state in STATES:
				var tex: Texture2D = tex_map[state] as Texture2D
				if tex == null or tex.get_size() != head.texture.get_size():
					return _fail("%s %s texture missing or changed the head canvas" % [skin_id, state])
				if rig.get("_eye_glow") != null:
					var glow_tex: Texture2D = glow_map[state] as Texture2D
					if glow_tex == null or glow_tex.get_size() != head.texture.get_size():
						return _fail("%s %s glow missing or changed the head canvas" % [skin_id, state])
			var part_array: Array = rig.get("_parts")
			var part_ids: Array[int] = []
			for part: CanvasItem in part_array:
				part_ids.append(part.get_instance_id())
				if part != head:
					part.visible = false
			var rests: Dictionary = {}
			for bone_name: StringName in rig.bone_order():
				rests[String(bone_name)] = {"rest": rig.bone(bone_name).rest, "id": rig.bone(bone_name).get_instance_id(), "parent": rig.parent_of(bone_name)}
			var texture_defs: Dictionary = skin.get("textures", {})
			var open_key := str(eye_states.get("open_texture", part_def.get("texture", "")))
			var state_keys := {"open": open_key, "half": str(eye_states.get("half_texture", "")), "closed": str(eye_states.get("closed_texture", ""))}
			var files: Dictionary = {}
			for state in STATES:
				var state_key := str(state_keys[state])
				if not texture_defs.has(state_key):
					return _fail("%s %s texture key not present in character data" % [skin_id, state])
				var texture_def: Dictionary = texture_defs[state_key]
				var source_path := RigLibrary.character_dir(skin_id).path_join(str(texture_def.get("file", "")))
				if not FileAccess.file_exists(source_path):
					return _fail("%s %s source file missing: %s" % [skin_id, state, source_path])
				files[state] = _file_record(source_path)
				var normal_path := _normal_path(source_path)
				if FileAccess.file_exists(normal_path):
					files["%s_normal" % state] = _file_record(normal_path)
				var glow_value := str(texture_def.get("glow", ""))
				if not glow_value.is_empty():
					var glow_path := RigLibrary.character_dir(skin_id).path_join(glow_value)
					if not FileAccess.file_exists(glow_path):
						return _fail("%s %s glow file missing: %s" % [skin_id, state, glow_path])
					files["%s_glow" % state] = _file_record(glow_path)
				# Guard size and pivot data against declarations that merely happen to
				# load through the texture cache with a different source canvas.
				var size_data: Array = texture_def.get("size", [])
				if size_data.size() != 2 or Vector2i(int(size_data[0]), int(size_data[1])) != Vector2i(head.texture.get_size()):
					return _fail("%s %s declared size differs from runtime head canvas" % [skin_id, state])
				var pivot_data: Array = texture_def.get("pivot", [])
				if pivot_data.size() != 2:
					return _fail("%s %s pivot must contain two values" % [skin_id, state])
				var declared_pivot := Vector2(float(pivot_data[0]), float(pivot_data[1]))
				if not declared_pivot.is_equal_approx(-head.offset):
					return _fail("%s %s pivot differs from runtime head offset" % [skin_id, state])
			var row := {
				"skin_id": skin_id,
				"facing": face,
				"holder": holder,
				"holder_scale": holder.scale,
				"rig": rig,
				"input": input,
				"head": head,
				"head_id": head.get_instance_id(),
				"head_parent_id": head.get_parent().get_instance_id(),
				"head_parent_path": str(head.get_path_to(rig.bone(&"head"))),
				"head_local_transform": head.transform,
				"head_material": head.material,
				"texture_filter": head.texture_filter,
				"glow": rig.get("_eye_glow"),
				"glow_material": (rig.get("_eye_glow") as Sprite2D).material if rig.get("_eye_glow") != null else null,
				"textures": tex_map,
				"glows": glow_map,
				"part_ids": part_ids,
				"parts": part_array,
				"rests": rests,
				"size": head.texture.get_size(),
				"source_files": files,
				"timing_config": eye_states.get("timing", {}),
				"state": StringName(rig.get("_eye_state")),
				"seen": {"open": true, "half": false, "closed": false},
				"captures": {"open": false, "half": false, "closed": false},
				"transitions": [],
				"cycles": [],
				"interrupted_cycles": [],
				"active_cycle": {},
				"counts": {"idle": {"open": 0, "half": 0, "closed": 0}, "talking": {"open": 0, "half": 0, "closed": 0}},
				"target": Vector2.ZERO,
				"crop_rect": Rect2i(),
				"output_files": {},
				"crop_meta": {},
				"stage_frames": {},
			}
			_rows.append(row)
	if _rows.size() != SKINS.size() * 2:
		return _fail("expected two facing rigs for each configured eye-state character")
	return true


func _head_part_definition(skin: Dictionary, part_name: String) -> Dictionary:
	var matches: Array[Dictionary] = []
	for entry: Variant in skin.get("parts", []):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", entry.get("texture", ""))) == part_name:
			matches.append(entry)
	return matches[0] if matches.size() == 1 else {}


func _setup_capture_viewport() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = WINDOW_SIZE
	get_viewport().size = WINDOW_SIZE
	var background := ColorRect.new()
	background.color = Color("777d84")
	background.size = WINDOW_SIZE
	background.z_index = -4096
	add_child(background)
	add_child(LightKit.create_environment())
	for i in 3:
		var light := LightKit.create_point_light(Color("f0f4ff"), 900.0, 0.75)
		light.position = Vector2((i + 0.5) * WINDOW_SIZE.x / 3.0, WINDOW_SIZE.y * 0.5)
		add_child(light)
	for i in _rows.size():
		var row := _rows[i]
		var col := i % 6
		var row_index := floori(float(i) / 6.0)
		row["target"] = Vector2((float(col) + 0.5) * WINDOW_SIZE.x / 6.0, (float(row_index) + 0.52) * WINDOW_SIZE.y / 3.0)
		var label := Label.new()
		label.text = "%s face %d" % [row["skin_id"], row["facing"]]
		label.position = Vector2(col * WINDOW_SIZE.x / 6.0 + 6, row_index * WINDOW_SIZE.y / 3.0 + 6)
		label.z_index = 20
		add_child(label)


func _begin_capture() -> void:
	await get_tree().process_frame
	for row in _rows:
		var rect := _head_screen_rect(row["head"] as Sprite2D)
		if rect.size.x <= 0 or rect.size.y <= 0:
			_fail("%s facing %d has an empty head canvas rect" % [row["skin_id"], row["facing"]])
			_finish(1)
			return
		row["holder"].position += row["target"] - rect.get_center()
		var positioned := _head_screen_rect(row["head"] as Sprite2D)
		var cell := Rect2(Vector2((row["target"] as Vector2).x - WINDOW_SIZE.x / 12.0 + 4, floorf((row["target"] as Vector2).y / (WINDOW_SIZE.y / 3.0)) * (WINDOW_SIZE.y / 3.0) + 32), Vector2(WINDOW_SIZE.x / 6.0 - 8, WINDOW_SIZE.y / 3.0 - 36))
		if not cell.encloses(positioned):
			_fail("%s facing %d full head canvas falls outside its capture cell" % [row["skin_id"], row["facing"]])
			_finish(1)
			return
		var basis := (row["head"] as Sprite2D).get_global_transform_with_canvas()
		var density_x := basis.x.length()
		var density_y := basis.y.length()
		if absf(density_x - 1.0) > 0.001 or absf(density_y - 1.0) > 0.001:
			_fail("%s facing %d source-pixel-density scale is not 1:1 (%f,%f)" % [row["skin_id"], row["facing"], density_x, density_y])
			_finish(1)
			return
		row["crop_rect"] = _head_crop_rect(row["head"] as Sprite2D)
		row["output_files"]["open"] = _output_for(row, "open")
		row["captures"]["open"] = true
		_pending_crops.append({"row": row, "state": "open", "phase": "initial_open", "wall": 0.0, "rect": row["crop_rect"]})
	if not _errors.is_empty():
		_finish(1)
		return
	if get_viewport().get_visible_rect().size != Vector2(WINDOW_SIZE):
		_fail("actual viewport size differs from native source-density target: %s" % get_viewport().get_visible_rect().size)
		_finish(1)
		return
	_started_usec = Time.get_ticks_usec()
	_started_utc = Time.get_datetime_string_from_system(true, true)
	_stage_capture = "stage-00"


func _process(delta: float) -> void:
	if _started_usec == 0 or _finished:
		return
	_frame_count += 1
	_simulation_seconds += delta
	var wall := float(Time.get_ticks_usec() - _started_usec) / 1_000_000.0
	var talking := wall >= IDLE_SECONDS
	if _last_wall < IDLE_SECONDS and talking:
		_stage_capture = "stage-15"
	for row in _rows:
		var rig: CharacterRig = row["rig"]
		var input: RigInput = row["input"]
		input.talking = talking
		rig.animate(delta, input)
		var new_state := StringName(rig.get("_eye_state"))
		var phase := "talking" if talking else "idle"
		row["counts"][phase][String(new_state)] += 1
		if new_state != row["state"]:
			_record_transition(row, row["state"], new_state, phase, wall, delta)
			row["state"] = new_state
		if not _runtime_invariants(row):
			_finish(1)
			return
	_last_wall = wall
	if wall >= TOTAL_SECONDS:
		_stage_capture = "stage-30"
		_finish_after_draw = true


func _record_transition(row: Dictionary, old_state: StringName, new_state: StringName, phase: String, wall: float, delta: float) -> void:
	var now_sim := wall if _cpu_check else _simulation_seconds
	row["transitions"].append({"from": String(old_state), "to": String(new_state), "phase": phase, "wall_seconds": wall, "simulation_seconds": now_sim, "delta_seconds": delta})
	row["seen"][String(new_state)] = true
	if old_state == &"open" and new_state == &"half" and row["active_cycle"].is_empty():
		var blink: EyeBlink = row["rig"].get("_eye_blink") as EyeBlink
		row["active_cycle"] = {"start_simulation_seconds": now_sim, "start_wall_seconds": wall, "expected_duration_seconds": blink.get("_blink_duration"), "start_delta_seconds": delta, "sequence": [&"half"]}
	elif new_state == &"closed" and not row["active_cycle"].is_empty():
		row["active_cycle"]["sequence"].append(&"closed")
	elif new_state == &"half" and old_state == &"closed" and not row["active_cycle"].is_empty():
		row["active_cycle"]["sequence"].append(&"half")
	elif new_state == &"open" and not row["active_cycle"].is_empty():
		var active: Dictionary = row["active_cycle"]
		var measured := now_sim - float(active["start_simulation_seconds"])
		var epsilon := maxf(float(active["start_delta_seconds"]), delta)
		var sequence_ok: bool = active["sequence"] == ACTIVE_BLINK_STATES
		var interruption := ""
		if delta > EyeBlink.MAX_DELTA:
			interruption = "driver_spike_abort"
		elif not sequence_ok:
			interruption = "lid_phase_skipped"
		if not interruption.is_empty():
			row["interrupted_cycles"].append({"start_wall_seconds": active["start_wall_seconds"], "end_wall_seconds": wall, "expected_duration_seconds": active["expected_duration_seconds"], "elapsed_seconds": measured, "delta_seconds": delta, "state_before_open": String(old_state), "observed_sequence": active["sequence"], "reason": interruption})
		else:
			var duration_ok: bool = absf(measured - float(active["expected_duration_seconds"])) <= epsilon + 0.000001
			row["cycles"].append({"start_wall_seconds": active["start_wall_seconds"], "end_wall_seconds": wall, "expected_duration_seconds": active["expected_duration_seconds"], "measured_duration_seconds": measured, "frame_epsilon_seconds": epsilon, "sequence_ok": sequence_ok, "duration_ok": duration_ok})
			if not duration_ok:
				_fail("%s face %d completed natural blink duration invalid" % [row["skin_id"], row["facing"]])
		row["active_cycle"] = {}
	if not _cpu_check and not row["captures"][String(new_state)]:
		row["captures"][String(new_state)] = true
		row["output_files"][String(new_state)] = _output_for(row, String(new_state))
		_pending_crops.append({"row": row, "state": String(new_state), "phase": phase, "wall": wall})


func _runtime_invariants(row: Dictionary) -> bool:
	var rig: CharacterRig = row["rig"]
	var head: Sprite2D = row["head"]
	var state := String(rig.get("_eye_state"))
	if not _require(rig.get("_eye_blink") != null and head.texture == row["textures"].get(state), "%s face %d: active texture does not follow EyeBlink state" % [row["skin_id"], row["facing"]]):
		return false
	if not _require(head.get_instance_id() == row["head_id"] and head.get_parent().get_instance_id() == row["head_parent_id"] and head.get_parent() == rig.bone(&"head"), "%s face %d: head slot/parent changed" % [row["skin_id"], row["facing"]]):
		return false
	if not _require(head.transform == row["head_local_transform"] and head.material == row["head_material"] and head.texture.get_size() == row["size"], "%s face %d: head local pose/material/canvas changed" % [row["skin_id"], row["facing"]]):
		return false
	if row["glow"] != null and not _require((row["glow"] as Sprite2D).texture == row["glows"].get(state) and (row["glow"] as Sprite2D).material == row["glow_material"], "%s face %d: glow state/material does not follow eye state" % [row["skin_id"], row["facing"]]):
		return false
	if not _require(rig.animator.get("_use_npc") == true, "%s face %d: NPC animation branch is not active" % [row["skin_id"], row["facing"]]):
		return false
	var parts: Array = row["parts"]
	if not _require(parts.size() == row["part_ids"].size(), "%s face %d: head-state updates changed part count" % [row["skin_id"], row["facing"]]):
		return false
	for i in parts.size():
		if not _require((parts[i] as CanvasItem).get_instance_id() == row["part_ids"][i], "%s face %d: part node was replaced" % [row["skin_id"], row["facing"]]):
			return false
	for bone_name: StringName in rig.bone_order():
		var before: Dictionary = row["rests"][String(bone_name)]
		var bone: Bone2D = rig.bone(bone_name)
		if not _require(bone.rest == before["rest"] and bone.get_instance_id() == before["id"] and rig.parent_of(bone_name) == before["parent"], "%s face %d bone %s: rest/identity/parent changed" % [row["skin_id"], row["facing"], bone_name]):
			return false
	return true


func _run_cpu_regression() -> void:
	if not _check_hdr_png_conversion():
		return
	if not _check_cycle_abort_recorder():
		return
	var reports: Array[Dictionary] = []
	for hz in [60, 120]:
		for row in _rows:
			var blink: EyeBlink = row["rig"].get("_eye_blink") as EyeBlink
			blink.reset()
			row["rig"]._eye_state = &"open"
			(row["head"] as Sprite2D).texture = row["textures"]["open"]
			if row["glow"] != null:
				(row["glow"] as Sprite2D).texture = row["glows"]["open"]
			row["state"] = &"open"
			row["transitions"] = []
			row["cycles"] = []
			row["interrupted_cycles"] = []
			row["active_cycle"] = {}
			row["seen"] = {"open": true, "half": false, "closed": false}
		var step := 1.0 / float(hz)
		var previous_states: Array[StringName] = []
		for row in _rows:
			previous_states.append(&"open")
		for frame in int(TOTAL_SECONDS * float(hz)):
			var sim_time := float(frame + 1) * step
			for index in _rows.size():
				var row: Dictionary = _rows[index]
				var input: RigInput = row["input"]
				input.talking = sim_time >= IDLE_SECONDS
				(row["rig"] as CharacterRig).animate(step, input)
				var state := StringName((row["rig"] as CharacterRig).get("_eye_state"))
				if state != previous_states[index]:
					_record_transition(row, previous_states[index], state, "talking" if sim_time >= IDLE_SECONDS else "idle", sim_time, step)
					row["state"] = state
					previous_states[index] = state
				if not _runtime_invariants(row):
					return
		for row in _rows:
			if not row["active_cycle"].is_empty():
				_close_open_cycle_as_interrupted(row, TOTAL_SECONDS, TOTAL_SECONDS, "simulation_end")
			var seq: Array[StringName] = []
			for transition: Dictionary in row["transitions"]:
				seq.append(StringName(transition["to"]))
			var valid_cycle := false
			for i in maxi(0, seq.size() - 3):
				if seq.slice(i, i + 4) == STATE_ORDER:
					valid_cycle = true
					break
			var cycles: Array = row["cycles"]
			if not valid_cycle or cycles.is_empty():
				_fail("%s face %d did not complete a natural cycle at %dHz" % [row["skin_id"], row["facing"], hz])
			for cycle: Dictionary in cycles:
				if not cycle["sequence_ok"] or not cycle["duration_ok"]:
					_fail("%s face %d duration/sequence failed at %dHz" % [row["skin_id"], row["facing"], hz])
			reports.append({"skin_id": row["skin_id"], "facing": row["facing"], "hz": hz, "transitions": row["transitions"].size(), "cycles": cycles.size(), "interrupted_cycles": row["interrupted_cycles"].size(), "states_seen": row["seen"], "valid_cycle": valid_cycle})
	_write_cpu_report(reports)


func _check_hdr_png_conversion() -> bool:
	# Match tools/viewport_capture.gd's Forward+/HDR readback path: convert
	# linear RGBAH to RGBA8, then encode linear RGB as sRGB while preserving alpha.
	var linear_pixel := Color(0.2, 0.4, 0.8, 0.37)
	var raw := Image.create(2, 2, false, Image.FORMAT_RGBAH)
	if raw == null or raw.is_empty():
		return _fail("cannot create RGBAH conversion self-check image")
	raw.fill(linear_pixel)
	var encoded := raw.duplicate()
	encoded.convert(Image.FORMAT_RGBA8)
	encoded.linear_to_srgb()
	if not _require(encoded.get_format() == Image.FORMAT_RGBA8 and encoded.get_size() == Vector2i(2, 2), "HDR readback conversion must preserve dimensions and produce RGBA8"):
		return false
	var sample: Color = encoded.get_pixel(0, 0)
	if not _require(absf(sample.a - linear_pixel.a) <= 0.01, "HDR readback conversion must preserve alpha"):
		return false
	if not _require(absf(sample.r - linear_pixel.r) >= 0.05 and absf(sample.g - linear_pixel.g) >= 0.05, "HDR readback conversion must encode RGB from linear to sRGB"):
		return false
	return true


func _check_cycle_abort_recorder() -> bool:
	var subthreshold_deltas: Array[float] = [0.055057, 0.0666667, 0.0597183]
	for delta in subthreshold_deltas:
		var blink := _configured_delta_probe()
		blink._blink_elapsed = 0.095
		blink._state = EyeBlink.CLOSED
		var state := blink.update(delta, false)
		if not _require(state == EyeBlink.OPEN and not blink._blinking and blink._blink_elapsed > 0.0, "sub-MAX_DELTA probe must complete naturally to open without spike reset"):
			return false
		var row := _cycle_probe_row([EyeBlink.HALF, EyeBlink.CLOSED])
		_record_transition(row, EyeBlink.CLOSED, EyeBlink.OPEN, "idle", 0.095 + delta, delta)
		if not _require(row["cycles"].is_empty() and row["interrupted_cycles"].size() == 1 and row["interrupted_cycles"][0]["reason"] == "lid_phase_skipped" and row["active_cycle"].is_empty(), "closed-to-open sub-MAX_DELTA path must be logged as interrupted and reset tracker"):
			return false
	var spike_delta := 0.1430267
	var spike_probe := _configured_delta_probe()
	spike_probe._blink_elapsed = 0.095
	spike_probe._state = EyeBlink.HALF
	var spike_state := spike_probe.update(spike_delta, false)
	if not _require(spike_state == EyeBlink.OPEN and not spike_probe._blinking and is_zero_approx(spike_probe._blink_elapsed), "over-MAX_DELTA probe must follow the driver's spike-abort reset"):
		return false
	var spike_row := _cycle_probe_row([EyeBlink.HALF])
	_record_transition(spike_row, EyeBlink.HALF, EyeBlink.OPEN, "talking", 0.1430267, spike_delta)
	if not _require(spike_row["cycles"].is_empty() and spike_row["interrupted_cycles"].size() == 1 and spike_row["interrupted_cycles"][0]["reason"] == "driver_spike_abort" and spike_row["active_cycle"].is_empty(), "over-MAX_DELTA transition must be logged as a driver abort and reset tracker"):
		return false
	var complete_row := _cycle_probe_row([EyeBlink.HALF, EyeBlink.CLOSED, EyeBlink.HALF])
	_record_transition(complete_row, EyeBlink.HALF, EyeBlink.OPEN, "idle", 0.14, 0.01)
	if not _require(complete_row["cycles"].size() == 1 and complete_row["cycles"][0]["sequence_ok"] and complete_row["cycles"][0]["duration_ok"] and complete_row["interrupted_cycles"].is_empty(), "valid completed sequence must remain subject to strict sequence/duration checks"):
		return false
	return true


func _configured_delta_probe() -> EyeBlink:
	var blink := EyeBlink.new()
	blink.setup("ne221_recorder_probe", {"seed": 1})
	blink._blinking = true
	blink._blink_elapsed = 0.0
	blink._blink_duration = 0.14
	blink._state = EyeBlink.CLOSED
	return blink


func _cycle_probe_row(sequence: Array[StringName]) -> Dictionary:
	return {
		"skin_id": "probe", "facing": 1, "state": EyeBlink.HALF,
		"seen": {"open": true, "half": true, "closed": true},
		"transitions": [], "cycles": [], "interrupted_cycles": [],
		"active_cycle": {"start_simulation_seconds": 0.0, "start_wall_seconds": 0.0, "expected_duration_seconds": 0.14, "start_delta_seconds": 0.01, "sequence": sequence.duplicate()},
	}


func _close_open_cycle_as_interrupted(row: Dictionary, wall_seconds: float, simulation_seconds: float, reason: String) -> void:
	var active: Dictionary = row["active_cycle"]
	if active.is_empty():
		return
	row["interrupted_cycles"].append({
		"start_wall_seconds": active["start_wall_seconds"],
		"end_wall_seconds": wall_seconds,
		"expected_duration_seconds": active["expected_duration_seconds"],
		"elapsed_seconds": simulation_seconds - float(active["start_simulation_seconds"]),
		"delta_seconds": 0.0,
		"state_at_end": String(row["state"]),
		"observed_sequence": active["sequence"],
		"reason": reason,
	})
	row["active_cycle"] = {}


func _head_screen_rect(head: Sprite2D) -> Rect2:
	var local_rect := head.get_rect()
	var transform := head.get_global_transform_with_canvas()
	var corners := [transform * local_rect.position, transform * Vector2(local_rect.end.x, local_rect.position.y), transform * local_rect.end, transform * Vector2(local_rect.position.x, local_rect.end.y)]
	var result := Rect2(corners[0], Vector2.ZERO)
	for point: Vector2 in corners:
		result = result.expand(point)
	return result


func _head_crop_rect(head: Sprite2D) -> Rect2i:
	var bounds := _head_screen_rect(head)
	var rect := Rect2i(Vector2i(bounds.position.floor()) - Vector2i(4, 4), Vector2i(bounds.size.ceil()) + Vector2i(8, 8))
	return rect


func _after_draw() -> void:
	if _finished or (_stage_capture.is_empty() and _pending_crops.is_empty()):
		return
	# Use the same shared readback conversion as other Forward+/HDR captures.
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	if image == null or image.get_size() != WINDOW_SIZE:
		_fail("rendered viewport does not match requested native output size %s" % WINDOW_SIZE)
		_finish(1)
		return
	if image.get_format() not in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8]:
		_fail("unexpected screenshot format: %s" % image.get_format())
		_finish(1)
		return
	if not _stage_capture.is_empty():
		var stage_name := _stage_capture
		_stage_capture = ""
		var stage_path := _out_path.get_base_dir().path_join("eye-%s.png" % stage_name)
		if image.save_png(stage_path) != OK:
			_fail("cannot save stage frame: " + stage_path)
		for row in _rows:
			row["stage_frames"][stage_name] = stage_path
	for item: Dictionary in _pending_crops:
		var row: Dictionary = item["row"]
		var head: Sprite2D = row["head"]
		var rect := _head_crop_rect(head)
		var screen := Rect2i(Vector2i.ZERO, WINDOW_SIZE)
		if rect.size.x <= 0 or rect.size.y <= 0 or rect.intersection(screen) != rect:
			_fail("%s face %d head crop is outside viewport" % [row["skin_id"], row["facing"]])
			continue
		var crop := image.get_region(rect)
		if crop.get_size() != rect.size:
			_fail("%s face %d crop was resized" % [row["skin_id"], row["facing"]])
			continue
		var out_path: String = row["output_files"][item["state"]]
		if crop.save_png(out_path) != OK:
			_fail("cannot write rendered state: " + out_path)
			continue
		item["row"]["crop_meta"][item["state"]] = {"path": out_path, "size": [crop.get_width(), crop.get_height()], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "sha256": _file_sha(out_path), "phase": item["phase"], "wall_seconds": item["wall"], "head_canvas_transform": _transform_array(head.get_global_transform_with_canvas()), "screen_pixel_per_source_pixel": [head.get_global_transform_with_canvas().x.length(), head.get_global_transform_with_canvas().y.length()], "alpha": _alpha_summary(crop)}
	_pending_crops.clear()
	if _finish_after_draw:
		_finish_after_draw = false
		_finish(0)


func _finish(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	if _started_usec != 0:
		var elapsed_ms := int((Time.get_ticks_usec() - _started_usec) / 1000)
		if not _cpu_check and elapsed_ms < int(TOTAL_SECONDS * 1000.0):
			_fail("native wall runtime shorter than required %d ms: %d" % [int(TOTAL_SECONDS * 1000.0), elapsed_ms])
		if not _cpu_check:
			var wall_seconds := float(Time.get_ticks_usec() - _started_usec) / 1_000_000.0
			for row in _rows:
				if not row["active_cycle"].is_empty():
					_close_open_cycle_as_interrupted(row, wall_seconds, _simulation_seconds, "capture_ended")
	for row in _rows:
		if not _cpu_check:
			for state in STATES:
				if not row["seen"][state] or not row["crop_meta"].has(state):
					_fail("%s face %d missing natural rendered %s state" % [row["skin_id"], row["facing"], state])
			if row["cycles"].is_empty():
				_fail("%s face %d had no complete natural blink cycle" % [row["skin_id"], row["facing"]])
		for key: Variant in row["source_files"]:
			var record: Dictionary = row["source_files"][key]
			var current := _file_record(record["res_path"])
			if current.get("sha256") != record.get("sha256") or current.get("size_bytes") != record.get("size_bytes"):
				_fail("source changed during audit: %s" % record["res_path"])
	_write_report("captured_not_accepted" if not _cpu_check else "cpu_headless_only")
	if get_tree() != null:
		get_tree().quit(exit_code if _errors.is_empty() else 1)


func _write_cpu_report(rows: Array[Dictionary]) -> void:
	var path := _out_path.get_base_dir().path_join("cpu-regression.json")
	var report := {"status": "passed" if _errors.is_empty() else "failed", "checks": rows.size(), "errors": _errors, "target_hz": [60, 120], "seconds_per_simulation": TOTAL_SECONDS, "cycle_recorder_cases": {"subthreshold_deltas_seconds": [0.055057, 0.0666667, 0.0597183], "driver_spike_delta_seconds": 0.1430267, "complete_cycle_control": true}, "roles": rows, "evidence_type": "manual delta stepping through production CharacterRig.animate with real EyeBlink state machine; no rendering"}
	_write_json(path, report)


func _write_report(status: String) -> void:
	var character_rows: Array[Dictionary] = []
	for row in _rows:
		character_rows.append({
			"skin_id": row["skin_id"], "facing": row["facing"], "state": String(row["state"]),
			"part_count": row["parts"].size(), "eye_node_id": row["head_id"], "eye_parent_id": row["head_parent_id"], "eye_parent_bone": "head",
			"eye_local_transform": _transform_array(row["head_local_transform"]), "eye_offset": [row["head"].offset.x, row["head"].offset.y],
			"eye_canvas": [row["size"].x, row["size"].y], "eye_material_class": row["head_material"].get_class(),
			"source_density_holder_scale": [row["holder_scale"].x, row["holder_scale"].y], "texture_filter": row["texture_filter"],
			"timing_config": row["timing_config"], "transitions": row["transitions"], "blink_cycles": row["cycles"], "interrupted_cycles": row["interrupted_cycles"],
			"state_frame_counts": row["counts"], "source_files": row["source_files"], "rendered_crops": row["crop_meta"], "stage_frames": row["stage_frames"],
		})
	var report := {
		"status": status if _errors.is_empty() else "failed", "errors": _errors, "capture_states_are_natural": true,
		"forced_states": false, "native_density_definition": "viewport output crop; one screen pixel per source texel by holder-scale compensation, no post-capture resampling",
		"full_character_or_clothing_acceptance": false, "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"hdr_2d": ProjectSettings.get_setting("rendering/viewport/hdr_2d", false), "readback_helper": "res://tools/viewport_capture.gd", "encoded_image_format": "RGBA8 after HDR linear-to-sRGB conversion", "adapter": RenderingServer.get_video_adapter_name(), "window_size": [WINDOW_SIZE.x, WINDOW_SIZE.y],
		"eye_state_configured_characters": SKINS, "characters": character_rows,
		"wall_elapsed_ms": int((Time.get_ticks_usec() - _started_usec) / 1000) if _started_usec != 0 else 0,
		"processed_frames": _frame_count, "simulation_delta_sum_seconds": _simulation_seconds, "start_utc": _started_utc,
	}
	_write_json(_out_path, report)


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open report: " + path)
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()


func _output_for(row: Dictionary, state: String) -> String:
	return _out_path.get_base_dir().path_join("%s_face_%d_%s.png" % [row["skin_id"], row["facing"], state])


func _file_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"res_path": path, "sha256": "missing", "size_bytes": -1}
	var bytes := FileAccess.get_file_as_bytes(path)
	return {"res_path": path, "sha256": _bytes_sha(bytes), "size_bytes": bytes.size()}


func _file_sha(path: String) -> String:
	return _bytes_sha(FileAccess.get_file_as_bytes(path))


func _alpha_summary(image: Image) -> Dictionary:
	if image.get_format() == Image.FORMAT_RGB8:
		return {"format": "RGB8", "pixels": image.get_width() * image.get_height(), "alpha_not_present": true}
	var zero := 0
	var partial := 0
	var full := 0
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.0:
				zero += 1
			elif alpha >= 1.0:
				full += 1
			else:
				partial += 1
	return {"format": image.get_format(), "pixels": image.get_width() * image.get_height(), "transparent": zero, "partial": partial, "opaque": full}


func _bytes_sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _normal_path(path: String) -> String:
	var ext := path.get_extension()
	return path.get_basename() + "_n." + ext


func _transform_array(xform: Transform2D) -> Array[float]:
	return [xform.x.x, xform.x.y, xform.y.x, xform.y.y, xform.origin.x, xform.origin.y]


func _require(condition: bool, message: String) -> bool:
	return condition if condition else _fail(message)


func _fail(message: String) -> bool:
	if not _errors.has(message):
		_errors.append(message)
		push_error("[NE221EyeCurrentDelivery] " + message)
	return false
