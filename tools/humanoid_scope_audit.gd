extends Node
## NE-90 scoped evidence: actual enemy skin/weapon, both facings, native walk/run frames.
## gpu_lock.py -- godot --path . --rendering-method forward_plus res://tools/humanoid_scope_audit.tscn -- --config=<absolute json> --out=<absolute directory>

const DT := 1.0 / 60.0
const CELL := Vector2i(280, 270)
const ZOOM := 3.4
const PHASES := 8

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var config := ""
	var out := ""
	var metrics_only := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--config="): config = arg.trim_prefix("--config=")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg == "--metrics": metrics_only = true
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(config))
	if typeof(rows) != TYPE_ARRAY or out.is_empty():
		push_error("[humanoid_scope_audit] requires config array and output directory")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	if metrics_only:
		var measurements: Array[Dictionary] = []
		for row: Dictionary in rows:
			for mode in 2:
				for facing: int in [1, -1]:
					measurements.append(_measure(row, mode, facing))
		var metric_file := FileAccess.open(out.path_join("locomotion-metrics.json"), FileAccess.WRITE)
		metric_file.store_string(JSON.stringify(measurements, "\t"))
		get_tree().quit(0)
		return
	var report: Array[Dictionary] = []
	for row: Dictionary in rows:
		var skin := str(row["skin"])
		var weapon := str(row["weapon"])
		var speed := float(row["speed"])
		var run_speed := maxf(40.0, speed * 2.0)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(CELL.x * PHASES, CELL.y * 4)
		viewport.use_hdr_2d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var stage := Node2D.new()
		viewport.add_child(stage)
		stage.add_child(LightKit.create_environment())
		var background := ColorRect.new()
		background.color = Color("5b6577")
		background.size = Vector2(viewport.size)
		background.z_index = -20
		stage.add_child(background)
		for mode in 2:
			for side in 2:
				var facing := 1 if side == 0 else -1
				var actual_speed := speed if mode == 0 else run_speed
				var cell_row := mode * 2 + side
				for phase in PHASES:
					var origin := Vector2(phase * CELL.x, cell_row * CELL.y)
					var holder := Node2D.new()
					holder.position = origin + Vector2(CELL.x * 0.5, 243)
					holder.scale = Vector2.ONE * ZOOM
					stage.add_child(holder)
					var rig := CharacterRig.new()
					holder.add_child(rig)
					if not rig.setup(skin):
						get_tree().quit(1)
						return
					rig.set_weapon(weapon)
					var input := RigInput.new()
					input.facing = facing
					input.aim_dir = Vector2(facing, 0)
					input.run_speed = run_speed
					input.on_floor = true
					input.two_handed = bool(row.get("two_handed", true))
					for frame in 60: rig.animate(DT, input)
					input.velocity = Vector2(actual_speed * facing, 0)
					for frame in 180: rig.animate(DT, input)
					var stride := float(rig.animator._motion["move"]["stride"])
					var exponent := float(rig.animator._motion["move"].get("stride_exp", 0.0))
					var min_stride := float(rig.animator._motion["move"].get("stride_floor", 0.45))
					if exponent > 0.0:
						stride *= clampf(pow(minf(actual_speed / run_speed, 1.0), exponent), min_stride, 1.0)
					for frame in int(round(stride / actual_speed / DT * phase / PHASES)):
						rig.animate(DT, input)
					var label := Label.new()
					label.position = origin + Vector2(5, 5)
					label.text = "%s %s %s p%d\n%.1f / %.1f px/s" % [skin, weapon, "R" if facing == 1 else "L", phase, actual_speed, run_speed]
					stage.add_child(label)
					var line := Line2D.new()
					line.points = PackedVector2Array([origin + Vector2(0, 243), origin + Vector2(CELL.x, 243)])
					line.width = 1
					line.default_color = Color("293344")
					stage.add_child(line)
					var light := LightKit.create_point_light(Color("f0f4ff"), 260, 0.75, false, false)
					light.position = origin + Vector2(140, 60)
					stage.add_child(light)
		var image_path := out.path_join("%s-%s-gait.png" % [skin, weapon if not weapon.is_empty() else "unarmed"])
		for frame in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := preload("res://tools/viewport_capture.gd").image(viewport)
		image.save_png(image_path)
		report.append({"skin": skin, "weapon": weapon, "speed": speed, "run_speed": run_speed, "zoom": ZOOM, "image": image_path, "width": image.get_width(), "height": image.get_height(), "facings": [1, -1], "phases_per_mode": PHASES})
		viewport.queue_free()
		await get_tree().process_frame
		print("saved ", image_path)
	var file := FileAccess.open(out.path_join("gait-capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0)

func _measure(row: Dictionary, mode: int, facing: int) -> Dictionary:
	var holder := Node2D.new()
	add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	var skin := str(row["skin"])
	if not rig.setup(skin):
		holder.free()
		return {"skin": skin, "setup_failed": true}
	rig.set_weapon(str(row["weapon"]))
	var run_speed := maxf(40.0, float(row["speed"]) * 2.0)
	var speed := float(row["speed"]) if mode == 0 else run_speed
	var input := RigInput.new()
	input.facing = facing
	input.on_floor = true
	input.aim_dir = Vector2(facing, 0)
	input.two_handed = bool(row.get("two_handed", true))
	input.run_speed = run_speed
	for frame in 60: rig.animate(DT, input)
	input.velocity = Vector2(speed * facing, 0)
	for frame in 180: rig.animate(DT, input)
	var hip := PackedFloat32Array()
	var contacts: Array[Dictionary] = [{"on": false, "min": 0.0, "max": 0.0, "frames": 0}, {"on": false, "min": 0.0, "max": 0.0, "frames": 0}]
	var slide := 0.0
	var world_x := 0.0
	var bone_length_error := 0.0
	var grip_error := 0.0
	var rest_lengths: Dictionary = {}
	for name: String in ["arm_front_lower", "hand_front", "arm_back_lower", "hand_back", "leg_front_lower", "foot_front", "leg_back_lower", "foot_back"]:
		var bone := rig.bone(StringName(name))
		rest_lengths[name] = bone.position.length()
	for frame in 360:
		rig.animate(DT, input)
		world_x += speed * facing * DT
		hip.append(rig.animator.bone_pos(&"hip").y)
		for foot_index in 2:
			var name: StringName = [&"foot_front", &"foot_back"][foot_index]
			var foot := rig.animator.bone_pos(name)
			var foot_world_x := world_x + foot.x * facing
			var contact := absf(foot.y - rig.animator.ground_level()) <= 0.2
			var state := contacts[foot_index]
			if contact:
				state["frames"] += 1
				state["min"] = minf(float(state["min"]), foot_world_x) if state["on"] else foot_world_x
				state["max"] = maxf(float(state["max"]), foot_world_x) if state["on"] else foot_world_x
				slide = maxf(slide, float(state["max"]) - float(state["min"]))
			state["on"] = contact
		for name: String in rest_lengths:
			bone_length_error = maxf(bone_length_error, absf(rig.bone(StringName(name)).position.length() - float(rest_lengths[name])))
		if not str(row["weapon"]).is_empty():
			var sprite := rig._weapon_sprite
			var definition := rig.weapon_def()
			for side in (2 if input.two_handed else 1):
				var hand: StringName = &"hand_front" if side == 0 else &"hand_back"
				var key := "grip" if side == 0 else "foregrip"
				var target := sprite.to_global(RigLibrary.vec2(definition.get(key, definition.get("grip"))) + sprite.offset)
				var palm := rig.bone(hand).to_global(rig.hand_grip_offset(hand))
				grip_error = maxf(grip_error, palm.distance_to(target) / rig.body_scale())
	var result := LocomotionAudit._analyse(hip, speed)
	var leg := absf(rig.rest(&"hip").y)
	result.merge({"skin": skin, "weapon": row["weapon"], "facing": facing, "mode": "walk" if mode == 0 else "run", "run_speed": run_speed, "speed": speed, "pp_l": float(result["pp"]) / leg, "slide_l": slide / leg, "contact_frames": [contacts[0]["frames"], contacts[1]["frames"]], "max_bone_length_error": bone_length_error, "max_grip_error": grip_error, "samples": hip.size()})
	print("METRIC ", JSON.stringify(result))
	holder.free()
	return result
