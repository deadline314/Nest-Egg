extends ScenarioBase
## NE-277: actual Player motion, arranged individual move selection and public held input.
## --out=absolute --weapon=blade|dagger|glaive|maul|whip --facing=-1|1|both
## --capture writes unscaled native crops of every observed physics step; no performance claim.
## --negative=missing-input deliberately omits the real hold press and must fail.
const WEAPONS := ["blade", "dagger", "glaive", "maul", "whip"]
const METRICS := ["bone_stretch", "elbow_hyper", "knee_hyper", "trunk_lean", "head_turn", "mesh_fold", "limb_pinch", "angle_pop"]
var _only := ""
var _sides := [-1, 1]
var _capture := false
var _negative := ""
var _checks := 0
var _failures: Array[String] = []
var _rows: Array[Dictionary] = []
var _camera: Camera2D
var _steps_before := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/")
		elif arg.begins_with("--weapon="):
			_only = arg.trim_prefix("--weapon=")
		elif arg.begins_with("--facing="):
			var side := arg.trim_prefix("--facing=")
			_sides = [-1, 1] if side == "both" else [int(side)]
		elif arg == "--capture":
			_capture = true
		elif arg.begins_with("--negative="):
			_negative = arg.trim_prefix("--negative=")
	_run.call_deferred()


func _run() -> void:
	if not out_dir.is_absolute_path() or (_only != "" and _only not in WEAPONS) or _negative not in ["", "missing-input"] or (_capture and DisplayServer.get_name() == "headless"):
		push_error("[NE277] invalid arguments/native capture required")
		get_tree().quit(2)
		return
	for side in _sides:
		if side not in [-1, 1]:
			get_tree().quit(2)
			return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.use_storage("user://ne277-settings.cfg")
	Story.auto_skip = true
	var data := NewEnemiesSuite.arena_data()
	data.chapter = &"ch1_kasa"
	await open_arena("res://data/lighting/warehouse_interior.tres", 12.0, data)
	_camera = get_viewport().get_camera_2d()
	_camera.set_physics_process(false)
	_camera.zoom = Vector2.ONE * 2.0
	_steps_before = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 1
	for id in WEAPONS:
		if _only != "" and id != _only:
			continue
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var moves: Array = set.combo()
		if not set.extension_attack().is_empty():
			moves.append(set.extension_attack())
		for side in _sides:
			if _negative == "":
				for move in moves:
					await _move(id, weapon, set, str(move), side, false)
			await _move(id, weapon, set, str(set.hold().get("attack", "")), side, true)
	var result := {"checks": _checks, "failures": _failures, "rows": _rows,
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"display": DisplayServer.get_name(), "capture": _capture, "native_size": str(get_viewport().get_texture().get_size()) if _capture else "headless",
		"limits": AnimAudit.LIMITS, "angle_pop_scale_applied_once": AnimAudit.ACTION_POP_SCALE,
		"scope": "arranged individual attacks and real action_press hold/release; not human play or a performance measurement"}
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		push_error("[NE277] cannot write result.json")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	Engine.max_physics_steps_per_frame = _steps_before
	Input.action_release(&"melee")
	await finish()
	await AudioRelease.settle(get_tree())
	print("NE277_DONE checks=%d failures=%d rows=%d" % [_checks, _failures.size(), _rows.size()])
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[NE277] " + message)


func _step() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	if _capture:
		await RenderingServer.frame_post_draw


func _move(id: String, weapon: WeaponData, set: MeleeSet, move: String, side: int, held: bool) -> void:
	Input.action_release(&"melee")
	player._interrupt_melee()
	player.loadout.reset(weapon)
	player._melee_cooldown_left = 0.0
	player._melee_combo_left = 0.0
	place_player(12.0)
	player.facing = side
	player.aim_dir = Vector2(side, 0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2(side, 0)
	# The whip's overhead arc needs the full stroke/glow margin above the viewport.
	# Publish a real fixed view: changing the node alone leaves Camera2D's smoothed view stale.
	_camera.global_position = player.global_position + Vector2(side * 38, -48 if id == "whip" else -30)
	if id == "whip":
		_camera.position_smoothing_enabled = false
		_camera.reset_smoothing()
		_camera.force_update_scroll()
	for i in 30:
		await _step()
	var def := set.attack(move, move == set.extension_attack())
	var name := "%s/%d/%s%s" % [id, side, move, "-held" if held else ""]
	var row := {"weapon": id, "move": move, "side": side, "held": held, "name": name, "frames": [], "phases": {}, "results": {}, "released": false, "palm_max": 0.0, "second_max": 0.0, "second_missed": 0, "path_samples": 0}
	var ctx := {"rig": player._visual.rig, "results": {}, "where": name, "frame": 0, "prev": {}, "grounded": false, "pop_scale": AnimAudit.ACTION_POP_SCALE, "skip_pop": 1}
	var entered := false
	if held:
		if _negative != "missing-input":
			Input.action_press(&"melee")
	else:
		entered = player._start_melee_attack(false)
		if entered:
			# This selects each authored move in isolation; it is not a combo-input test.
			player._melee_attack = def
			player.melee.swing_direction = player.melee.aim_direction(def)
	var release_next := false
	var active_frames := 0
	var hold_ticks := 0
	var ended := false
	var rest_frames := 0
	for tick in 360:
		await _step()
		if held and not entered and player.melee.hold_mode != "":
			entered = true
		if entered and player.melee.phase == MeleeModule.Phase.NONE:
			ended = true
			rest_frames += 1
			if rest_frames > 15:
				break
		if not entered:
			if tick >= 180:
				break
			continue
		if held:
			hold_ticks += 1
			if player.melee.phase == MeleeModule.Phase.ACTIVE:
				active_frames += 1
			var mode := str(set.hold().get("mode", ""))
			release_next = (mode == "charge" and player.melee.charged) or (mode == "sustain" and active_frames > _sustain_sample_frames(def, set)) or (mode == "repeat" and player.melee.phase == MeleeModule.Phase.RECOVERY)
		ctx["frame"] = (row["frames"] as Array).size()
		AnimAudit._measure(ctx, false)
		var phase: int = player.melee.phase
		row["phases"][str(phase)] = int(row["phases"].get(str(phase), 0)) + 1
		var frame := {"tick": Engine.get_physics_frames(), "phase": phase, "progress": player.melee.pose_progress(), "held_input": Input.is_action_pressed(&"melee"), "hold_mode": player.melee.hold_mode, "charged": player.melee.charged}
		var animator := player._visual.rig.animator
		frame["on_floor"] = player.is_on_floor()
		frame["camera_position"] = [_camera.global_position.x, _camera.global_position.y]
		frame["camera_zoom"] = [_camera.zoom.x, _camera.zoom.y]
		frame["velocity"] = [player.velocity.x, player.velocity.y]
		frame["gait_weight"] = animator._gait_w
		frame["idle_pin_weight"] = animator._idle_pin_w
		frame["foot_ground_error"] = [animator.bone_pos(&"foot_front").y - animator.ground_level(), animator.bone_pos(&"foot_back").y - animator.ground_level()]
		var angles := {}
		for bone in player._visual.rig.bone_order():
			angles[str(bone)] = player._visual.rig.bone(bone).rotation
		frame["angles"] = angles
		_measure_grips(row, frame)
		if _capture:
			_capture_frame(name, (row["frames"] as Array).size(), frame)
		(row["frames"] as Array).append(frame)
		if held and release_next and not row["released"]:
			Input.action_release(&"melee")
			row["released"] = true
	row["results"] = ctx["results"]
	row["ended"] = ended
	row["hold_ticks"] = hold_ticks
	_check(entered and ended and (row["frames"] as Array).size() >= 3, name + " enters and finishes a measured attack")
	for phase in [1, 2, 3]:
		_check(int(row["phases"].get(str(phase), 0)) > 0, name + " observed phase %d" % phase)
	for metric in METRICS:
		var entry: Dictionary = ctx["results"].get(metric, {})
		_check(not entry.is_empty() and is_finite(float(entry.get("value", INF))) and float(entry.get("value", INF)) <= float(entry.get("limit", -INF)), name + " metric " + metric)
	_check(int(row["path_samples"]) > 0 and float(row["palm_max"]) <= 1.0 and float(row["second_max"]) <= 1.5 and int(row["second_missed"]) == 0, name + " actual hand grips")
	if held:
		_check(row["released"] and hold_ticks > 0, name + " public held input and release")
		_check(player.melee.hold_mode == "" and not Input.is_action_pressed(&"melee"), name + " clean hold ownership release")
	_rows.append(row)
	print("NE277_MOVE ", JSON.stringify({"name": name, "frames": (row["frames"] as Array).size(), "ended": ended, "grip": row["palm_max"], "second": row["second_max"]}))
	Input.action_release(&"melee")
	player._interrupt_melee()


func _sustain_sample_frames(def: Dictionary, _set: MeleeSet) -> int:
	return int(float(def["active"]) * 60) + 24


func _measure_grips(row: Dictionary, frame: Dictionary) -> void:
	var rig := player._visual.rig
	var held := player._visual.melee_held()
	frame["front_hand"] = str(rig.bone(&"hand_front").global_position)
	frame["back_hand"] = str(rig.bone(&"hand_back").global_position)
	frame["body_bounds"] = str(rig.visual_bounds())
	var actual_back := rig.bone(&"hand_back").global_transform * rig.hand_grip_offset(&"hand_back")
	frame["second_along"] = (actual_back - held.hold().origin).dot(held.hold().x)
	frame["shaft_origin"] = [held.hold().origin.x, held.hold().origin.y]
	frame["shaft_dir"] = [held.hold().x.x, held.hold().x.y]
	frame["rear_shoulder"] = [rig.bone(&"arm_back_upper").global_position.x, rig.bone(&"arm_back_upper").global_position.y]
	frame["reach"] = player._visual.second_hand_reach()
	frame["shaft_tail"] = held._butt - MeleeHeld.SECOND_TAIL_MARGIN
	frame["shaft_front"] = float(held._spec["second"])
	var path := player.melee.path_now()
	if path.is_empty() or player._visual._input.melee_path_w < 0.999:
		return
	row["path_samples"] = int(row["path_samples"]) + 1
	var shoulder := rig.to_local(rig.bone(&"arm_front_upper").global_position)
	var want := rig.to_global(shoulder + Vector2.from_angle(path[0]) * path[1])
	var gap := held.hold().origin.distance_to(want)
	frame["palm_gap"] = gap
	row["palm_max"] = maxf(float(row["palm_max"]), gap)
	if MeleeMove.hands(player.melee.attack) == 2:
		if not rig.second_hand_on_weapon:
			row["second_missed"] = int(row["second_missed"]) + 1
		else:
			var grip := rig.bone(&"hand_back").global_transform * rig.hand_grip_offset(&"hand_back")
			var near := player._visual.second_grip(rig.bone(&"arm_back_upper").global_position)
			frame["second_gap"] = grip.distance_to(near)
			row["second_max"] = maxf(float(row["second_max"]), grip.distance_to(near))


func _capture_frame(name: String, index: int, frame: Dictionary) -> void:
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var xf := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	frame["capture_canvas_transform"] = [xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y]
	var rig := player._visual.rig
	var box := rig.visual_bounds().grow(4)
	var held := player._visual.melee_held()
	box = box.expand(held.hold().origin).expand(held.tip_point()).grow(8)
	var rope := held.whip()
	if rope != null and rope.is_laid():
		# node() is world-space; _points is only the renderer's transformed local cache.
		var points: Array = []
		for i in SoftWhip.NODES:
			var point := rope.node(i)
			box = box.expand(point)
			var screen_point := xf * point
			points.append([screen_point.x, screen_point.y])
		frame["rope_screen_points"] = points
		box = box.grow(8)  # Include line width, ink and glow, not just its centerline.
	var region := _screen_rect(box, xf)
	var screen := Rect2i(Vector2i.ZERO, image.get_size())
	_check(screen.encloses(region), "%s frame %d whole body/weapon inside viewport" % [name, index])
	region = region.intersection(screen)
	if region.size.x <= 0 or region.size.y <= 0:
		_check(false, name + " empty capture")
		return
	var directory := out_dir.path_join("frames").path_join(name)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("%04d.png" % index)
	_check(image.get_region(region).save_png(path) == OK, name + " writes native frame")
	var arms := Rect2(rig.bone(&"arm_front_upper").global_position, Vector2.ZERO)
	for bone in [&"arm_front_lower", &"hand_front", &"arm_back_upper", &"arm_back_lower", &"hand_back"]:
		arms = arms.expand(rig.bone(bone).global_position)
	var hand_region := _screen_rect(arms.grow(8), xf).intersection(screen)
	_check(image.get_region(hand_region).save_png(directory.path_join("%04d-hands.png" % index)) == OK, name + " writes native hands")
	frame["image"] = path.trim_prefix(out_dir + "/")
	frame["crop"] = [region.position.x, region.position.y, region.size.x, region.size.y]
	frame["hands_crop"] = [hand_region.position.x, hand_region.position.y, hand_region.size.x, hand_region.size.y]
	if index == 0:
		_check(image.save_png(directory.path_join("full.png")) == OK, name + " writes full native context")


func _screen_rect(box: Rect2, xf: Transform2D) -> Rect2i:
	var a := xf * box.position
	var b := xf * box.end
	return Rect2i(Vector2i(a.floor()), Vector2i(b.ceil() - a.floor()))
