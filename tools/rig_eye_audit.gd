extends Node2D
## NE-221 realtime audit of production CharacterRig eye slots; never forces a state.

const SKINS := ["rin", "old_k", "nurse", "night_worker", "repairman_chen", "resident", "ah_po", "wataru", "mei"]
const SIZE := Vector2i(1280, 720)
const ZOOM := 3.4
const TALK_AT := 15.0
const DURATION := 30.0
const RIG := preload("res://game/rig/character_rig.gd")

var _out := ""
var _rows: Array[Dictionary] = []
var _errors: Array[String] = []
var _head_queue: Array[Dictionary] = []
var _stage_queue := ""
var _finish_draw := false
var _finished := false
var _start_usec := 0
var _end_usec := 0
var _start_utc := ""
var _end_utc := ""
var _sim := 0.0
var _previous_wall := 0.0
var _frames := 0
var _dropped := 0
var _max_delta := 0.0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	if not _out.is_absolute_path() or not _out.to_lower().ends_with(".json"):
		_fail("--out must be an absolute .json path"); _finish(); return
	var directory_error := DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("output directory error: " + error_string(directory_error)); _finish(); return
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = SIZE; get_viewport().size = SIZE
	add_child(LightKit.create_environment())
	var bg := ColorRect.new(); bg.color = Color("17202c"); bg.size = SIZE; bg.z_index = -100; add_child(bg)
	for i in 3:
		var light := LightKit.create_point_light(Color("f0f4ff"), 900.0, 0.75)
		light.position = Vector2((i + 0.5) * SIZE.x / 3.0, SIZE.y * 0.5); add_child(light)
	for i in SKINS.size():
		if not _add_rig(i, SKINS[i]): _finish(); return
	RenderingServer.frame_post_draw.connect(_after_draw)
	call_deferred("_start")

func _add_rig(i: int, skin_id: String) -> bool:
	var skin := RigLibrary.character(skin_id); var eyes: Variant = skin.get("eye_states")
	if skin.is_empty() or typeof(eyes) != TYPE_DICTIONARY: return _fail("%s: missing production eye_states" % skin_id)
	var holder := Node2D.new(); holder.scale = Vector2.ONE * ZOOM; add_child(holder)
	var rig: CharacterRig = RIG.new(); holder.add_child(rig)
	if not rig.setup(skin_id, "npc"): return _fail("%s: CharacterRig.setup failed" % skin_id)
	var head: Sprite2D = rig.get("_eye_part"); var glow: Sprite2D = rig.get("_eye_glow")
	var part_name := str(eyes.get("part", ""))
	if not _check(rig.get("_eye_blink") != null and head != null and head.name == part_name and head.get_parent() == rig.bone(&"head"), "%s: eye binding fell back or left authored head bone" % skin_id): return false
	if not _check(head.material == rig.get("_light_material"), "%s: head lost shared light material" % skin_id): return false
	var tex := {"open": rig.get("_eye_open_texture"), "half": rig.get("_eye_half_texture"), "closed": rig.get("_eye_closed_texture")}
	var glows := {"open": rig.get("_eye_open_glow"), "half": rig.get("_eye_half_glow"), "closed": rig.get("_eye_closed_glow")}
	for state in ["open", "half", "closed"]:
		if not _check(tex[state] != null and tex[state].get_size() == head.texture.get_size(), "%s: %s state missing/fallback or changed canvas" % [skin_id, state]): return false
		if glow != null and not _check(glows[state] != null and glows[state].get_size() == head.texture.get_size(), "%s: %s glow missing/wrong size" % [skin_id, state]): return false
	if glow != null and not _check(glow.material == RIG._glow_material() and glow.light_mask == 0, "%s: glow lost shared unlit material" % skin_id): return false
	var heads := rig.find_children(part_name, "Sprite2D", true, false)
	if not _check(heads.size() == 1 and heads[0] == head, "%s: expected exactly one head slot" % skin_id): return false
	var parts: Array = rig.get("_parts"); var part_ids: Array[int] = []; var rests := {}
	for part: CanvasItem in parts:
		part_ids.append(part.get_instance_id())
		if part != head: part.visible = false
	for bone: StringName in rig.bone_order():
		rests[String(bone)] = [rig.rest(bone), rig.bone(bone).rest, rig.bone(bone).get_instance_id(), rig.parent_of(bone)]
	var col := i % 3; var row := floori(float(i) / 3.0)
	var label := Label.new(); label.text = skin_id; label.position = Vector2(col * SIZE.x / 3.0 + 12, row * SIZE.y / 3.0 + 10); add_child(label)
	var npc_input := RigInput.new(); npc_input.two_handed = false
	_rows.append({"id": skin_id, "rig": rig, "holder": holder, "head": head, "head_id": head.get_instance_id(), "glow": glow,
		"parts": parts, "part_ids": part_ids, "rests": rests, "textures": tex, "glows": glows, "input": npc_input,
		"target": Vector2((col + 0.5) * SIZE.x / 3.0, (row + 0.5) * SIZE.y / 3.0),
		"size": head.texture.get_size(), "offset": head.offset, "position": head.position, "rotation": head.rotation,
		"scale": head.scale, "centered": head.centered, "material": head.material, "state": StringName(rig.get("_eye_state")),
		"seen": {"open": false, "half": false, "closed": false},
		"counts": {"idle": {"open": 0, "half": 0, "closed": 0}, "talking": {"open": 0, "half": 0, "closed": 0}},
		"transitions": [], "cycles": [], "active": {}, "captures": {}, "files": {}, "timing": eyes.get("timing", {})})
	return true

func _start() -> void:
	await get_tree().process_frame
	for row in _rows:
		var bounds := _head_bounds(row["head"])
		if bounds.size == Vector2.ZERO: _fail("%s: no visible source head pixels" % row["id"]); _finish(); return
		row["holder"].position += row["target"] - bounds.get_center()
	_start_usec = Time.get_ticks_usec(); _start_utc = Time.get_datetime_string_from_system(true, true); _stage_queue = "stage-00"

func _process(delta: float) -> void:
	if _start_usec == 0 or _finished: return
	_frames += 1; _sim += delta; _max_delta = maxf(_max_delta, delta); _dropped += maxi(0, roundi(delta * 60.0) - 1)
	var wall := float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0; var talking := wall >= TALK_AT
	if _previous_wall < TALK_AT and talking: _stage_queue = "stage-15"
	for row in _rows:
		var rig: CharacterRig = row["rig"]; var input: RigInput = row["input"]
		input.talking = talking; var old: StringName = row["state"]; rig.animate(delta, input)
		var state: StringName = rig.get("_eye_state"); var phase := "talking" if talking else "idle"
		row["counts"][phase][String(state)] += 1
		if state != old: _transition(row, old, state, phase, wall, delta)
		row["state"] = state
		if not _invariants(row): _finish_draw = true
	_previous_wall = wall
	if wall >= DURATION: _stage_queue = "stage-30"; _finish_draw = true

func _transition(row: Dictionary, old: StringName, state: StringName, phase: String, wall: float, delta: float) -> void:
	row["transitions"].append({"from": String(old), "to": String(state), "wall_seconds": wall, "simulation_seconds": _sim, "phase": phase})
	var key := String(state); if row["seen"].has(key): row["seen"][key] = true
	if state == &"half" and old == &"open" and row["active"].is_empty():
		var blink = row["rig"].get("_eye_blink")
		row["active"] = {"start_wall": wall, "start_sim": _sim, "start_delta": delta, "duration": float(blink.get("_blink_duration")), "sequence": ["half"]}
		_queue(row, "half", wall)
	elif state == &"closed" and not row["active"].is_empty(): row["active"]["sequence"].append("closed"); _queue(row, "closed", wall)
	elif state == &"half" and old == &"closed" and not row["active"].is_empty(): row["active"]["sequence"].append("half")
	elif state == &"open" and old == &"half" and not row["active"].is_empty():
		var a: Dictionary = row["active"]; var elapsed := _sim - float(a["start_sim"]); var eps := maxf(float(a["start_delta"]), delta)
		var sequence_ok: bool = a["sequence"] == ["half", "closed", "half"]
		var duration_ok: bool = absf(elapsed - float(a["duration"])) <= eps + 0.000001
		row["cycles"].append({"start_wall_seconds": a["start_wall"], "end_wall_seconds": wall, "duration_expected_seconds": a["duration"], "duration_measured_simulation_seconds": elapsed, "frame_epsilon_seconds": eps, "sequence_ok": sequence_ok, "duration_ok": duration_ok})
		if not sequence_ok or not duration_ok: _fail("%s: invalid blink sequence or one-frame duration" % row["id"])
		_queue(row, "open", wall); row["active"] = {}

func _queue(row: Dictionary, state: String, wall: float) -> void:
	if row["captures"].has(state): return
	row["captures"][state] = true; _head_queue.append({"row": row, "state": state, "wall": wall})

func _invariants(row: Dictionary) -> bool:
	var rig: CharacterRig = row["rig"]; var head: Sprite2D = row["head"]; var state := String(rig.get("_eye_state"))
	if not _check(rig.animator.get("_use_npc") == true, "%s: expected actual NPC animation branch" % row["id"]): return false
	if not _check(row["textures"].has(state) and head.texture == row["textures"][state] and head.texture.get_size() == row["size"], "%s: state texture/canvas changed" % row["id"]): return false
	if not _check(head.get_instance_id() == row["head_id"] and head.material == row["material"] and head.offset == row["offset"] and head.position == row["position"] and head.rotation == row["rotation"] and head.scale == row["scale"] and head.centered == row["centered"], "%s: head node/material/pivot/transform changed" % row["id"]): return false
	if not _check(row["parts"].size() == row["part_ids"].size(), "%s: part count changed" % row["id"]): return false
	for i in row["parts"].size():
		if not _check(row["parts"][i].get_instance_id() == row["part_ids"][i], "%s: part replaced" % row["id"]): return false
	if row["glow"] != null and not _check(row["glow"].texture == row["glows"][state] and row["glow"].material == RIG._glow_material(), "%s: glow does not match active state" % row["id"]): return false
	for bone: StringName in rig.bone_order():
		var initial: Array = row["rests"][String(bone)]
		if not _check(rig.rest(bone) == initial[0] and rig.bone(bone).rest == initial[1] and rig.bone(bone).get_instance_id() == initial[2] and rig.parent_of(bone) == initial[3], "%s: bone %s identity/rest changed" % [row["id"], bone]): return false
	return true

func _after_draw() -> void:
	if _start_usec == 0 or _finished or (_stage_queue.is_empty() and _head_queue.is_empty() and not _finish_draw): return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_size() != SIZE: _fail("rendered viewport is not 1280x720"); _finish(); return
	if not _stage_queue.is_empty():
		var key := _stage_queue; _stage_queue = ""; var path := _sibling(key + ".png")
		if image.save_png(path) != OK: _fail("cannot write " + path)
		for row in _rows: row["files"][key] = path
	for item in _head_queue:
		var row: Dictionary = item["row"]; var rect := _head_bounds(row["head"])
		var crop := Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.size.ceil()))
		if crop.size.x <= 0 or crop.size.y <= 0 or crop.intersection(Rect2i(Vector2i.ZERO, SIZE)) != crop: _fail("%s head crop outside stage" % row["id"]); continue
		var key := String(item["state"]); var path := _sibling("%s-%s-rendered-crop.png" % [row["id"], key])
		var head_image := image.get_region(crop)
		var nonuniform := false
		for y in head_image.get_height():
			for x in head_image.get_width():
				if head_image.get_pixel(x, y) != head_image.get_pixel(0, 0): nonuniform = true; break
			if nonuniform: break
		if not nonuniform: _fail("%s %s crop contains only background" % [row["id"], key]); continue
		if head_image.save_png(path) != OK: _fail("cannot write " + path)
		else: row["files"][key] = path
	_head_queue.clear()
	if _finish_draw: _finish()

func _head_bounds(head: Sprite2D) -> Rect2:
	var texture: Texture2D = head.texture
	var diffuse := (texture as CanvasTexture).diffuse_texture if texture is CanvasTexture else texture
	var image: Image = diffuse.get_image() if diffuse != null else null
	if image == null: return Rect2()
	var used := image.get_used_rect(); if used.size == Vector2i.ZERO: return Rect2()
	var r := Rect2(head.offset + Vector2(used.position), Vector2(used.size)); var xf := head.get_global_transform_with_canvas()
	var points := [xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)]
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points: bounds = bounds.expand(p)
	return bounds

func _finish() -> void:
	if _finished: return
	_finished = true; _end_usec = Time.get_ticks_usec() if _start_usec > 0 else 0
	_end_utc = Time.get_datetime_string_from_system(true, true) if _start_usec > 0 else ""
	var wall_ms := maxi(0, _end_usec - _start_usec) / 1000 if _start_usec > 0 else 0
	if _start_usec > 0 and wall_ms < 30000: _fail("real wall elapsed %dms; need 30000ms" % wall_ms)
	var results: Array[Dictionary] = []
	for row in _rows:
		for state in ["open", "half", "closed"]:
			if not row["seen"][state] or not row["files"].has(state): _fail("%s missing observed/captured %s" % [row["id"], state])
		if row["cycles"].is_empty(): _fail("%s no complete blink cycle" % row["id"])
		for cycle in row["cycles"]:
			if not cycle["sequence_ok"] or not cycle["duration_ok"]: _fail("%s invalid blink cycle" % row["id"])
		if not row["files"].has("stage-15") or not row["files"].has("stage-30"): _fail("%s missing stage-15/30 capture" % row["id"])
		results.append({"skin_id": row["id"], "npc_mode": true, "npc_branch_required_each_frame": true, "stage_zoom": ZOOM, "timing_config": row["timing"], "part_count": row["parts"].size(), "state_frame_counts": row["counts"], "transitions": row["transitions"], "blink_cycles": row["cycles"], "capture_files": row["files"]})
	var report := {"status": "passed" if _errors.is_empty() else "failed", "errors": _errors, "godot": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "hdr_2d": ProjectSettings.get_setting("rendering/viewport/hdr_2d", false),
		"gpu_adapter": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(), "cpu": OS.get_processor_name(),
		"resolution": [SIZE.x, SIZE.y], "wall_elapsed_ms": wall_ms, "wall_elapsed_seconds": float(wall_ms) / 1000.0, "start_utc": _start_utc, "end_utc": _end_utc,
		"wall_at_least_30_seconds": wall_ms >= 30000, "simulation_delta_sum_seconds": _sim, "simulation_equals_wall_claimed": false,
		"processed_frames": _frames, "estimated_dropped_frames_at_60fps": _dropped, "max_delta_seconds": _max_delta,
		"idle_seconds": TALK_AT, "talking_seconds": DURATION - TALK_AT, "head_crops": "rendered viewport pixel crops at 3.4x; no resampling", "out": _out, "characters": results}
	_write(report); get_tree().quit(0 if _errors.is_empty() else 1)

func _sibling(name: String) -> String:
	return _out.get_base_dir().path_join(_out.get_file().get_basename() + "-" + name)

func _write(report: Dictionary) -> void:
	if _out.is_empty(): return
	var error := DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	if error != OK and error != ERR_ALREADY_EXISTS: _fail("output directory error: " + error_string(error)); return
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null: _fail("report file error: " + error_string(FileAccess.get_open_error())); return
	file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()

func _fail(message: String) -> bool:
	if not _errors.has(message): _errors.append(message); push_error("[rig_eye_audit] " + message)
	return false

func _check(condition: bool, message: String) -> bool:
	return condition if condition else _fail(message)
