class_name PoseMeshSuite
extends TestSuite
## Native Polygon2D/Skeleton2D pose binding and whole-set data validation.


func run() -> void:
	var lit_enabled := LitTextures.is_enabled()
	var rigid_limbs := CharacterRig.force_rigid_limbs
	LitTextures.set_enabled(true)
	CharacterRig.force_rigid_limbs = true
	_test_bind_switch_and_slots()
	_test_native_mesh_bounds_and_audit()
	_test_invalid_sets()
	CharacterRig.force_rigid_limbs = rigid_limbs
	LitTextures.set_enabled(lit_enabled)


func _test_bind_switch_and_slots() -> void:
	var skin := _fixture()
	var rig := _new_rig(skin)
	rig.scale = Vector2(-1.15, 0.92)
	rig.rotation = 0.07
	rig.bone(&"hip").rotation = 0.21
	rig.bone(&"chest").rotation = -0.09
	var original_rests := _rests(rig)
	var original_transforms := _transforms(rig)
	check(rig.bone_order().size() == 20, "pose-mesh fixture uses the canonical 20-bone Rin rig")
	check(rig._pose_sets.has(&"mesh_a") and rig._pose_sets.has(&"mesh_b") and rig._pose_sets.has(&"sprite"), "complete mesh and legacy sprite alternatives are cached at setup")
	check(rig.set_pose_parts(&"mesh_a"), "native mesh pose selects")
	check(rig._pose_rest_snapshot.size() == rig.bone_order().size(), "mesh pose snapshots every original rest transform")
	check(_rests(rig) == _bind_expected(skin, "mesh_a"), "first pose installs its nonzero canonical bind rotations")
	check(_transforms(rig) == original_transforms, "installing a mesh bind leaves current local bone transforms unchanged")
	var mesh := _alternative(rig, &"armor_pelvis", &"mesh_a") as Polygon2D
	var glow := mesh.get_node_or_null("Glow") as Polygon2D if mesh != null else null
	check(mesh != null and mesh.get_parent() == rig._skeleton and mesh.skeleton == mesh.get_path_to(rig._skeleton), "pose mesh is a child of the existing Skeleton2D")
	check(mesh != null and mesh.polygon.size() == 4 and mesh.polygons.size() == 2, "mesh retains explicit source geometry and topology")
	check(mesh != null and _bone_paths_resolve(rig, mesh), "pose-mesh bone paths resolve relative to Skeleton2D")
	var canvas := mesh.texture as CanvasTexture if mesh != null else null
	check(canvas != null and canvas.diffuse_texture != null and canvas.normal_texture != null, "mesh keeps the native diffuse and normal CanvasTexture")
	check(glow != null and glow.polygons == mesh.polygons and glow.uv == mesh.uv and glow.get_node(glow.skeleton) == rig._skeleton and _bone_paths_resolve(rig, glow), "glow companion reuses matching topology, UVs and Skeleton2D bone paths")
	check(_visible_slot_nodes(rig, &"armor_pelvis") == 1 and _visible_slot_nodes(rig, &"pelvis_dmg") == 0, "intact armor shows one logical mesh slot")
	rig.facing = -1
	check(_visible_slot_nodes(rig, &"armor_pelvis") == 1, "facing flip does not duplicate the mesh slot")
	rig.set_armor_ratio(0.5, false)
	check(_visible_slot_nodes(rig, &"armor_pelvis") == 1 and _visible_slot_nodes(rig, &"pelvis_dmg") == 1, "armor and damage mesh counterparts switch together")
	check(rig.set_pose_parts(&"mesh_b"), "switching to a different mesh bind succeeds")
	check(_rests(rig) == _bind_expected(skin, "mesh_b"), "second mesh pose replaces, rather than compounds, the first bind")
	check(rig.set_pose_parts(&"sprite"), "mesh-to-legacy-sprite transition succeeds")
	check(rig._pose_rest_snapshot.is_empty() and _rests(rig) == original_rests, "sprite pose restores every original rest transform")
	check(_alternative(rig, &"armor_pelvis", &"sprite") is Sprite2D, "legacy sprite alternative remains available")
	check(rig.set_pose_parts(&"mesh_a"), "mesh can be reselected after a sprite pose")
	check(not rig.set_pose_parts(&"missing") and rig.active_pose_parts() == &"mesh_a", "unknown pose leaves the current valid selection unchanged")
	check(rig.set_pose_parts(&""), "mesh pose can be cleared")
	check(_rests(rig) == original_rests and _transforms(rig) == original_transforms, "clear restores original rests and all current bone transforms")
	rig.free()


func _test_native_mesh_bounds_and_audit() -> void:
	var rig := _new_rig(_fixture())
	check(rig.set_pose_parts(&"mesh_a"), "native mesh pose activates before bounds and audit checks")
	var active := _alternative(rig, &"armor_pelvis", &"mesh_a") as Polygon2D
	for bone_name: StringName in rig.bone_order():
		rig.bone(bone_name).transform = rig.bone(bone_name).rest
	var bind_geometry := _pose_geometry(rig)
	check(bind_geometry.size() == 1, "active geometry excludes hidden damage alternatives and glow children")
	if not bind_geometry.is_empty():
		var source_vertices: PackedVector2Array = bind_geometry[0]["source_vertices"]
		var bound_vertices: PackedVector2Array = bind_geometry[0]["vertices"]
		var bind_matches := source_vertices.size() == bound_vertices.size()
		for i in mini(source_vertices.size(), bound_vertices.size()):
			bind_matches = bind_matches and source_vertices[i].is_equal_approx(bound_vertices[i])
		check(bind_matches, "authored bind pose reproduces every native source vertex")
	var hip_skin := Transform2D(0.0, Vector2(10.0, 0.0))
	var chest_skin := Transform2D(PI * 0.5, Vector2.ZERO)
	var hip := rig.bone(&"hip")
	var chest := rig.bone(&"chest")
	hip.global_transform = rig._skeleton.global_transform * hip_skin * hip.get_skeleton_rest()
	chest.global_transform = rig._skeleton.global_transform * chest_skin * chest.get_skeleton_rest()
	var oracle_geometry := _pose_geometry(rig)
	var oracle_matches := not oracle_geometry.is_empty()
	if oracle_matches:
		var oracle_mesh := oracle_geometry[0]["mesh"] as Polygon2D
		var source_point := rig._skeleton.global_transform.affine_inverse() * oracle_mesh.global_transform * oracle_mesh.polygon[0]
		var expected_point := (hip_skin * source_point + chest_skin * source_point) * 0.5
		var actual_vertices: PackedVector2Array = oracle_geometry[0]["vertices"]
		oracle_matches = actual_vertices.size() > 0 and actual_vertices[0].is_equal_approx(expected_point)
	check(oracle_matches, "two-bone 50/50 skinning matches an independent translation-plus-rotation oracle")
	for bone_name: StringName in rig.bone_order():
		rig.bone(bone_name).transform = rig.bone(bone_name).rest
	var was_visible := rig.visible
	rig.visible = false
	check(_pose_geometry(rig).is_empty(), "hidden rig returns no active native geometry")
	rig.visible = was_visible
	for part: CanvasItem in rig._parts:
		part.visible = part == active
	rig.position = Vector2(31.0, -17.0)
	rig.scale = Vector2(-1.2, 0.85)
	rig.rotation = 0.2
	var bounds := rig.visual_bounds()
	check(bounds.has_area(), "pose-only native mesh contributes visible bounds when all legacy parts are hidden")
	var expected_bounds := _world_bounds(rig, bind_geometry[0]["vertices"] if not bind_geometry.is_empty() else PackedVector2Array())
	check(_rects_match(bounds, expected_bounds), "native skeleton-local bounds apply root translation, rotation and reflection once")
	var first_center := bounds.get_center()
	rig.bone(&"hip").rotation += 0.35
	var moved_bounds := rig.visual_bounds()
	check(moved_bounds.has_area() and not moved_bounds.get_center().is_equal_approx(first_center), "native pose bounds follow current weighted bone deformation")
	var ctx := {"rig": rig, "where": "pose-only", "frame": 0, "results": {}, "prev": {}}
	AnimAudit._measure(ctx, false)
	check((ctx["results"] as Dictionary).has("mesh_fold"), "pose-only native mesh contributes to mesh-fold audit without legacy limb meshes")
	check(rig.limb_meshes().is_empty(), "native mesh audit fixture has no legacy limb-mesh fallback")
	rig.set_armor_ratio(0.5, false)
	var damage_geometry := _pose_geometry(rig)
	var damage_is_included := false
	for geometry: Dictionary in damage_geometry:
		var mesh := geometry.get("mesh") as Polygon2D
		damage_is_included = damage_is_included or (mesh != null and str(mesh.name).ends_with("__pelvis_dmg"))
	var active_names: Array[String] = []
	for geometry: Dictionary in damage_geometry:
		active_names.append(str((geometry.get("mesh") as Polygon2D).name))
	check(damage_is_included and damage_geometry.size() == 2, "visible damage counterpart joins intact geometry without counting glow children: %s" % ",".join(active_names))
	check(rig.set_pose_parts(&"sprite") and _pose_geometry(rig).is_empty() and rig.visual_bounds().has_area(), "sprite-pose transition restores legacy bounds and clears native mesh geometry")
	check(rig.set_pose_parts(&"") and _pose_geometry(rig).is_empty() and rig.visual_bounds().has_area(), "clearing native pose restores base-sprite bounds")
	rig.free()
	_test_native_pose_fold_negative_control()


func _test_native_pose_fold_negative_control() -> void:
	var skin := _fixture()
	for pose_data: Dictionary in (skin["pose_parts"] as Dictionary).values():
		for part_data: Dictionary in pose_data["parts"]:
			if not part_data.has("mesh"):
				continue
			var mesh_data: Dictionary = part_data["mesh"]
			var values: Array = []
			values.resize(mesh_data["vertices"].size())
			values.fill(1.0)
			mesh_data["weights"] = [{"bone": "hip", "values": values}]
	var rig := _new_rig(skin)
	rig.set_pose_parts(&"mesh_a")
	for part: CanvasItem in rig._parts:
		part.visible = part is Polygon2D and str(part.name).ends_with("__armor_pelvis")
	var hip := rig.bone(&"hip")
	hip.transform = Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2.ZERO) * hip.rest
	var ctx := {"rig": rig, "where": "native-fold-negative", "frame": 0, "results": {}, "prev": {}}
	AnimAudit._measure(ctx, false)
	var results: Dictionary = ctx["results"]
	var fold_result: Dictionary = results.get("mesh_fold", {})
	check(rig.limb_meshes().is_empty(), "native fold negative control has no legacy limb meshes")
	check(results.has("mesh_fold"), "native fold negative control records a mesh-fold result")
	check(float(fold_result.get("value", 0.0)) > AnimAudit.LIMITS["mesh_fold"], "deliberately reflected native triangles exceed the unchanged fold limit: %s" % str(fold_result))
	rig.free()


func _world_bounds(rig: CharacterRig, vertices: PackedVector2Array) -> Rect2:
	if vertices.is_empty():
		return Rect2()
	var skeleton_xf := rig._skeleton.global_transform
	var result := Rect2(skeleton_xf * vertices[0], Vector2.ZERO)
	for vertex in vertices:
		result = result.expand(skeleton_xf * vertex)
	return result


func _pose_geometry(rig: CharacterRig) -> Array[Dictionary]:
	if not rig.has_method("active_pose_mesh_geometries"):
		return []
	return rig.call("active_pose_mesh_geometries")


func _rects_match(a: Rect2, b: Rect2) -> bool:
	return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)


func _test_invalid_sets() -> void:
	for case_name in ["partial_bind", "unknown_bone", "nan_bind", "overflow_bind", "singular_bind", "unknown_weight_bone", "duplicate_weight", "nan_weight", "negative_weight", "bad_weight_sum", "bad_weight_count", "overflow_vertex", "overflow_uv", "bad_uv", "degenerate", "bad_index", "fractional_index", "near_integral_index", "nan_index", "overflow_index", "unused_vertex", "five_influences", "over_budget", "bad_late_slot"]:
		var rig := _new_rig(_fixture(case_name))
		check(not rig._pose_sets.has(&"mesh_a") and rig._pose_slots.is_empty(), "%s rejects the whole malformed mesh set before adding nodes" % case_name)
		check(_base(rig, &"armor_pelvis").visible and not _base(rig, &"pelvis_dmg").visible, "%s leaves original armor/damage visibility intact" % case_name)
		rig.free()


func _fixture(invalid_case := "") -> Dictionary:
	var skin: Dictionary = RigLibrary.character("rin").duplicate(true)
	var probe := CharacterRig.new()
	runner.add_child(probe)
	check(probe.setup("rin"), "probe rig initializes before source mesh fixture creation")
	var intact_mesh := _mesh_for(probe, &"armor_pelvis", 2, 2)
	var damage_mesh := _mesh_for(probe, &"pelvis_dmg", 2, 2)
	if invalid_case == "over_budget":
		intact_mesh = _mesh_for(probe, &"armor_pelvis", 26, 20)
	var bind_a := _bind_data(probe, 0.08)
	var bind_b := _bind_data(probe, -0.13)
	probe.free()
	var poses := {
		"mesh_a": {"bind_pose": bind_a, "parts": [
			{"slot": "armor_pelvis", "texture": "pelvis", "mesh": intact_mesh},
			{"slot": "pelvis_dmg", "texture": "pelvis_dmg", "mesh": damage_mesh},
		]},
		"mesh_b": {"bind_pose": bind_b, "parts": [
			{"slot": "armor_pelvis", "texture": "pelvis", "mesh": intact_mesh.duplicate(true)},
			{"slot": "pelvis_dmg", "texture": "pelvis_dmg", "mesh": damage_mesh.duplicate(true)},
		]},
		"sprite": {"parts": [
			{"slot": "armor_pelvis", "texture": "pelvis", "bone": "hip"},
			{"slot": "pelvis_dmg", "texture": "pelvis_dmg", "bone": "hip"},
		]},
	}
	# Round-trip as an actual character.json payload: Godot's JSON parser returns every numeric
	# array member (including whole triangle indices) as TYPE_FLOAT.
	poses = JSON.parse_string(JSON.stringify(poses))
	bind_a = poses["mesh_a"]["bind_pose"]
	intact_mesh = poses["mesh_a"]["parts"][0]["mesh"]
	damage_mesh = poses["mesh_a"]["parts"][1]["mesh"]
	match invalid_case:
		"partial_bind": bind_a.erase("hand_back")
		"unknown_bone": bind_a["not_a_bone"] = [1, 0, 0, 1, 0, 0]
		"nan_bind": bind_a["hip"] = [NAN, 0, 0, 1, 0, 0]
		"overflow_bind": bind_a["hip"] = [1e99, 0, 0, 1, 0, 0]
		"singular_bind": bind_a["hip"] = [1, 0, 2, 0, 0, 0]
		"unknown_weight_bone": intact_mesh["weights"][0]["bone"] = "missing_bone"
		"duplicate_weight": intact_mesh["weights"].append(intact_mesh["weights"][0].duplicate(true))
		"nan_weight": intact_mesh["weights"][0]["values"][0] = NAN
		"negative_weight": intact_mesh["weights"][0]["values"][0] = -0.1
		"bad_weight_sum": intact_mesh["weights"][0]["values"][0] = 0.4
		"bad_weight_count": intact_mesh["weights"][0]["values"].pop_back()
		"overflow_vertex": intact_mesh["vertices"][0] = [1e99, 0]
		"overflow_uv": intact_mesh["uvs"][0] = [1e99, 0]
		"bad_uv": intact_mesh["uvs"][0] = [-1, 0]
		"degenerate": intact_mesh["triangles"] = [0, 1, 1, 0, 2, 3]
		"bad_index": intact_mesh["triangles"][0] = 99
		"fractional_index": intact_mesh["triangles"][0] = 0.25
		"near_integral_index": intact_mesh["triangles"][0] = 0.000001
		"nan_index": intact_mesh["triangles"][0] = NAN
		"overflow_index": intact_mesh["triangles"][0] = 1e99
		"unused_vertex": intact_mesh["vertices"].append(intact_mesh["vertices"][0].duplicate())
		"five_influences": intact_mesh["weights"] = _weights(["hip", "chest", "leg_front_upper", "leg_front_lower", "foot_front"], intact_mesh["vertices"].size())
		"over_budget": pass
		"bad_late_slot": damage_mesh["triangles"] = [0, 1, 1, 0, 2, 3]
	if invalid_case == "bad_late_slot":
		poses["mesh_a"]["parts"][1]["mesh"] = damage_mesh
	if not invalid_case.is_empty():
		poses.erase("mesh_b")
		poses.erase("sprite")
	skin["pose_parts"] = poses
	return skin


func _new_rig(skin: Dictionary) -> CharacterRig:
	var rig := CharacterRig.new()
	runner.add_child(rig)
	check(rig.setup("rin"), "production Rin character sets up for pose-mesh validation")
	rig._build_pose_parts(skin)
	return rig


func _mesh_for(rig: CharacterRig, slot: StringName, columns: int, rows: int) -> Dictionary:
	var sprite := _base(rig, slot) as Sprite2D
	if sprite == null:
		return {}
	var rect := sprite.get_rect()
	var tex_size := sprite.texture.get_size()
	var to_skeleton := rig._skeleton.global_transform.affine_inverse() * sprite.global_transform
	var vertices: Array = []
	var uvs: Array = []
	for y in rows:
		for x in columns:
			var uv := Vector2(tex_size.x * float(x) / float(columns - 1), tex_size.y * float(y) / float(rows - 1))
			var point := to_skeleton * (uv + rect.position)
			vertices.append([point.x, point.y])
			uvs.append([uv.x, uv.y])
	var triangles: Array = []
	for y in rows - 1:
		for x in columns - 1:
			var a := y * columns + x
			var b := a + 1
			var c := a + columns
			var d := c + 1
			triangles.append_array([a, b, d, a, d, c])
	var count := vertices.size()
	return {"vertices": vertices, "uvs": uvs, "triangles": triangles, "weights": _weights(["hip", "chest"], count)}


func _weights(names: Array, count: int) -> Array:
	var result: Array = []
	for i in names.size():
		var values: Array = []
		for j in count:
			values.append(1.0 / float(names.size()))
		result.append({"bone": names[i], "values": values})
	return result


func _bind_data(rig: CharacterRig, hip_angle: float) -> Dictionary:
	var result := {}
	for bone_name in rig.bone_order():
		var transform: Transform2D = rig.bone(bone_name).rest
		if bone_name == &"hip":
			transform = Transform2D(hip_angle, transform.origin)
		result[str(bone_name)] = [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y]
	return result


func _bind_expected(skin: Dictionary, pose: String) -> Dictionary:
	var bind: Dictionary = skin["pose_parts"][pose]["bind_pose"]
	var result := {}
	for key in bind:
		result[StringName(key)] = Transform2D(Vector2(bind[key][0], bind[key][1]), Vector2(bind[key][2], bind[key][3]), Vector2(bind[key][4], bind[key][5]))
	return result


func _base(rig: CharacterRig, slot: StringName) -> CanvasItem:
	for part in rig._parts:
		if str(part.name) == str(slot):
			return part
	return null


func _alternative(rig: CharacterRig, slot: StringName, pose: StringName) -> CanvasItem:
	return (rig._pose_slots[slot]["alternatives"] as Dictionary).get(pose) if rig._pose_slots.has(slot) else null


func _visible_slot_nodes(rig: CharacterRig, slot: StringName) -> int:
	var base := _base(rig, slot)
	var count := 1 if base != null and base.visible else 0
	if rig._pose_slots.has(slot):
		for alternative: CanvasItem in (rig._pose_slots[slot]["alternatives"] as Dictionary).values():
			if alternative.visible:
				count += 1
	return count


func _bone_paths_resolve(rig: CharacterRig, polygon: Polygon2D) -> bool:
	if polygon.get_bone_count() != 2:
		return false
	for i in polygon.get_bone_count():
		var bone := rig._skeleton.get_node_or_null(polygon.get_bone_path(i)) as Bone2D
		if bone == null or not rig._bones.values().has(bone):
			return false
	return true


func _rests(rig: CharacterRig) -> Dictionary:
	var result := {}
	for bone_name in rig.bone_order():
		result[bone_name] = rig.bone(bone_name).rest
	return result


func _transforms(rig: CharacterRig) -> Dictionary:
	var result := {}
	for bone_name in rig.bone_order():
		result[bone_name] = rig.bone(bone_name).transform
	return result
