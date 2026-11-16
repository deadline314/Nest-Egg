extends Node2D
## Isolated source-preserving diagnostic; never loaded by a campaign scene.
const SKIN := "harbor_lamplighter_demo"
var _out := ""
var _pose := "stand"
var _region := "knee"
var _audit := false
var _frame := 59

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--pose="): _pose = arg.trim_prefix("--pose=")
		elif arg.begins_with("--region="): _region = arg.trim_prefix("--region=")
		elif arg == "--audit": _audit = true
		elif arg.begins_with("--frame="): _frame = int(arg.trim_prefix("--frame="))
	assert(not _out.is_empty() and _pose in ["stand", "sit", "wave", "aim_up", "dead"] and _region in ["knee", "neck"])
	_run.call_deferred()

func _run() -> void:
	if _audit:
		_run_anim_audit()
		return
	add_child(LightKit.create_environment())
	var background := ColorRect.new()
	background.color = Color("5b6577")
	background.size = Vector2(640, 360)
	background.z_index = -10
	add_child(background)
	var cases: Array = []
	var holders: Array[Node2D] = []
	for index in 4:
		var rigid := index < 2
		var normals := index % 2 == 0
		CharacterRig.force_rigid_limbs = rigid
		var holder := Node2D.new()
		holder.position = Vector2(320, 330 if _region == "knee" else 630)
		holder.scale = Vector2.ONE * 10.0
		add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		assert(rig.setup(SKIN, "" if _pose in ["aim_up", "dead"] else "npc"))
		rig.set_weapon("")
		var input := RigInput.new()
		input.on_floor = true
		input.two_handed = false
		input.aim_dir = Vector2(1, -1).normalized() if _pose == "aim_up" else Vector2.RIGHT
		input.npc_pose = &"sit" if _pose == "sit" else &"stand"
		for tick in (180 + _frame + 1 if _pose in ["wave", "dead"] else 240):
			input.waving = _pose == "wave" and tick >= 180
			input.dead = _pose == "dead" and tick >= 180
			rig.animate(1.0 / 60.0, input)
		if _pose == "dead":
			holder.position += Vector2(320, 180) - rig.bone(&"head").global_position
		var changed := 0
		if not normals:
			for node in rig.find_children("*", "CanvasItem", true, false):
				if not (node is Sprite2D or node is Polygon2D): continue
				if not node.texture is CanvasTexture: continue
				var texture: CanvasTexture = node.texture.duplicate()
				texture.normal_texture = null
				node.texture = texture
				changed += 1
			assert(changed > 0)
		holders.append(holder)
		holder.visible = false
		var meshes := rig.find_children("*", "RigPartMesh", true, false).size()
		assert(meshes == 0 if rigid else meshes > 0)
		var bones := {}
		for bone_name in rig.bone_order():
			var bone := rig.bone(bone_name)
			bones[str(bone_name)] = [bone.position.x, bone.position.y, bone.rotation]
		if not cases.is_empty(): assert(bones == cases[0]["bones"])
		cases.append({"rigid": rigid, "normals": normals, "changed_textures": changed, "bones": bones,
			"knee_world": [rig.bone(&"leg_front_lower").global_position.x, rig.bone(&"leg_front_lower").global_position.y]})
	CharacterRig.force_rigid_limbs = false
	for spot in [Vector2(160, 40), Vector2(480, 40), Vector2(320, 220)]:
		var light := LightKit.create_point_light(Color("f0f4ff"), 900.0, 0.75)
		light.position = spot
		add_child(light)
	var label := Label.new()
	label.position = Vector2(8, 8)
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)
	var size := Vector2i.ZERO
	for index in 4:
		if index > 0: holders[index - 1].visible = false
		holders[index].visible = true
		var tag := "%s-normal-%s" % ["rigid" if index < 2 else "mesh", "on" if index % 2 == 0 else "off"]
		label.text = tag + " / same source, pose, position, light, time"
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var captured := preload("res://tools/viewport_capture.gd").image(get_viewport())
		var path := _out + "-" + tag + ".png"
		assert(captured.save_png(path) == OK)
		size = captured.get_size()
		cases[index]["file"] = path
	var file := FileAccess.open(_out + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"pose": _pose, "frame": _frame, "region": _region, "native_size": [size.x, size.y], "cases": cases}, "\t"))
	print("DIAGNOSTIC %s: fixed source/pose/bones; only rigid and normal texture factors differ" % _out)
	get_tree().quit()


func _run_anim_audit() -> void:
	var reports := {}
	var failures: Array = []
	var inapplicable: Array = []
	for mode in ["combat", "stand", "sit", "lean", "crouch", "hammer"]:
		var rig := CharacterRig.new()
		add_child(rig)
		assert(rig.setup(SKIN, "" if mode == "combat" else "npc"))
		rig.set_weapon("")
		var report: Dictionary
		if mode == "combat":
			report = AnimAudit.audit(rig, SKIN, [])
		else:
			report = AnimAudit.audit_npc(rig, &"stand" if mode == "hammer" else StringName(mode), &"hammer" if mode == "hammer" else &"")
		reports[mode] = report
		var metrics: Array = AnimAudit.LIMITS.keys() if mode == "combat" else ["bone_stretch", "elbow_hyper", "knee_hyper", "trunk_lean", "head_turn", "angle_pop", "foot_below_ground", "foot_floating"]
		for metric in metrics:
			if not report.has(metric):
				if (mode == "combat" and metric == "grip_gap") or (mode == "sit" and metric in ["foot_below_ground", "foot_floating"]):
					inapplicable.append({"mode": mode, "metric": metric, "reason": "Not measured by original audit for this empty-hand/seated state"})
					continue  # Existing audit does not measure an empty-hand grip or seated floor support.
				failures.append({"mode": mode, "metric": metric, "missing": true})
				continue
			var value := float(report[metric]["value"])
			var limit := float(report[metric]["limit"]) * (1.6 if mode != "combat" and metric == "foot_floating" else 1.0)
			if not is_finite(value) or value > limit:
				failures.append({"mode": mode, "metric": metric, "entry": report[metric], "suite_limit": limit})
		rig.free()
	var file := FileAccess.open(_out + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"reports": reports, "failures": failures, "inapplicable": inapplicable, "policy": "Unchanged AnimAuditSuite limits, including its existing NPC foot-floating multiplier"}, "\t"))
	print("ANIM_AUDIT %d failures: %s" % [failures.size(), JSON.stringify(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

