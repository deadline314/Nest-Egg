extends Node
const CAPTURE = preload("res://tools/viewport_capture.gd")
var source_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
const SCALE = 0.03387914691943128
const ORIGIN = Vector2(548, 1502)
var rows: Array = []

func _ready() -> void:
	var output := "user://NE-222-material-axis.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_root + "/art_src/characters/rin_walk_source_ig01/registration/rejected-bone-axis-bind.json"))
	var corrected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_root + "/art_src/characters/rin_walk_source_ig01/registration/candidate.json"))
	var view := SubViewport.new()
	view.size = Vector2i(1200, 700)
	view.use_hdr_2d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var background := ColorRect.new()
	background.color = Color(0.12, 0.12, 0.12)
	background.size = Vector2(view.size)
	view.add_child(background)
	_label(view, Vector2(25, 18), "NE-222 native material-axis control - one hand, not a walking rig", 23)
	_label(view, Vector2(25, 52), "Same source RGBA / four UV corners / production Skeleton2D paths / unlit", 19)
	for column in 3:
		var binds: Dictionary = corrected.bind_pose if column != 1 else old.bind_pose
		var rig := CharacterRig.new()
		assert(rig.setup("rin"))
		view.add_child(rig)
		for part: CanvasItem in rig._parts:
			part.hide()
		var parsed_binds: Dictionary[StringName, Transform2D] = {}
		for bone_name: StringName in rig.bone_order():
			parsed_binds[bone_name] = _transform(binds[String(bone_name)])
		assert(rig._apply_pose_bind_pose(parsed_binds))
		if column == 0:
			for bone_name: StringName in rig.bone_order():
				rig.bone(bone_name).transform = parsed_binds[bone_name]
		var bind_globals := _global_binds(rig, parsed_binds)
		var current_globals := _global_current(rig)
		var skin: Transform2D = current_globals[&"hand_front"] * (bind_globals[&"hand_front"] as Transform2D).affine_inverse()
		var native_corners := [Vector2(341,711), Vector2(436,711), Vector2(436,841), Vector2(341,841)]
		var vertices: Array = []
		for corner: Vector2 in native_corners:
			var vertex: Vector2 = (corner - ORIGIN) * SCALE
			vertices.append([vertex.x, vertex.y])
		var mesh_data: Dictionary = {}
		var error := rig._parse_pose_mesh({"vertices": vertices, "uvs": [[0,0],[95,0],[95,130],[0,130]], "triangles": [0,1,2,0,2,3], "weights": [{"bone": "hand_front", "values": [1,1,1,1]}]}, Vector2i(95,130), mesh_data)
		assert(error.is_empty(), error)
		var image := Image.load_from_file(source_root + "/art_src/characters/rin_walk_source_ig01/author_parts/metal_hand.png")
		assert(image.get_size() == Vector2i(95,130))
		var polygon := rig._make_pose_mesh(mesh_data, ImageTexture.create_from_image(image), null, 1.0)
		rig._skeleton.add_child(polygon)
		rig._configure_pose_mesh_bones(polygon, mesh_data)
		assert(polygon.get_node(polygon.skeleton) == rig._skeleton)
		assert(rig._skeleton.get_node(polygon.get_bone_path(0)) == rig.bone(&"hand_front"))
		var center: Vector2 = skin * ((Vector2(388.5,776) - ORIGIN) * SCALE)
		rig.scale = Vector2.ONE / SCALE
		rig.position = Vector2(200+400*column,340) - center / SCALE
		var source_axis := Vector2(373,817)-Vector2(386,711)
		var mapped_axis: Vector2 = skin.basis_xform(source_axis)
		var hand_pivot: Array = RigLibrary.character("rin")["textures"]["hand"]["pivot"]
		var formal_axis := Vector2(120,32)-Vector2(hand_pivot[0],hand_pivot[1])
		var expected_axis: Vector2 = mapped_axis if column == 0 else (current_globals[&"hand_front"] as Transform2D).basis_xform(formal_axis)
		var angular_error := absf(rad_to_deg(mapped_axis.angle_to(expected_axis)))
		rows.append({"panel": column, "material_error_degrees": angular_error, "source_size": [95,130], "native_bone_path_resolves": true})
		_label(view, Vector2(35+400*column,110), ["Authored source pose", "Rejected +Y hand assumption", "Corrected texture-axis bind"][column], 20)
		_label(view, Vector2(35+400*column,530), "Material axis error: %.3f deg" % angular_error, 19)
		_label(view, Vector2(35+400*column,562), "Native crop 95 x 130, rendered 1:1", 18)
	assert(float(rows[1].material_error_degrees) > 80.0)
	assert(float(rows[2].material_error_degrees) < 0.1)
	_label(view, Vector2(25,645), "No wrist/cuff seam, anatomy, normal/glow, walk or gameplay acceptance is implied.", 18)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var captured: Image = CAPTURE.image(view)
	assert(captured.get_size() == view.size)
	assert(captured.save_png(output) == OK)
	var report := FileAccess.open(output.get_basename()+".json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"hdr_2d":view.use_hdr_2d,"rows":rows},"\t"))
	print("MATERIAL_AXIS_NATIVE ",JSON.stringify(rows))
	get_tree().quit()

func _transform(value: Array) -> Transform2D:
	return Transform2D(Vector2(value[0],value[1]),Vector2(value[2],value[3]),Vector2(value[4],value[5]))

func _global_binds(rig: CharacterRig, binds: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for name: StringName in rig.bone_order():
		var parent: StringName = rig._parent[name]
		result[name] = binds[name] if parent == &"" else (result[parent] as Transform2D) * (binds[name] as Transform2D)
	return result

func _global_current(rig: CharacterRig) -> Dictionary:
	var result: Dictionary = {}
	for name: StringName in rig.bone_order():
		var parent: StringName = rig._parent[name]
		result[name] = rig.bone(name).transform if parent == &"" else (result[parent] as Transform2D) * rig.bone(name).transform
	return result

func _label(view: SubViewport, at: Vector2, text: String, size: int) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	view.add_child(label)
