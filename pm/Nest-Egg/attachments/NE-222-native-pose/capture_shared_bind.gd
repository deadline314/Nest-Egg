extends Node
## Private one-knee shared-bind grid prototype. CPU prepare-check by default; root owns GPU capture.

const CELL := 128
const STEPS := 120
const WAYPOINTS := [0.0, -5.0, 5.0, -15.0, 15.0, -30.0, 30.0, 0.0]
const FACINGS := [1, -1]
const ZOOMS := [1.0, 3.4]
const POSE := &"kneel_22297_registration_v3_fixture"
const SOURCE_SHA := "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed"
const REPORT_PATH := "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/registration-v3-report.json"
const POSE_PATH := "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/pose_parts.json"
const TEXTURES_PATH := "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/textures.json"
const BONES_PATH := "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/canonical_bone_pose.json"
const GRID_PATH := "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/shared_mesh/shared_grid.json"
const CAPTURE := preload("res://tools/viewport_capture.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _nonempty_cells := 0
var _registered: Array[Texture2D] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var mode := "baseline"
	var output_dir := ""
	var prepare_only := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--out="):
			output_dir = argument.trim_prefix("--out=")
		elif argument == "--prepare-check":
			prepare_only = true
	if mode not in ["baseline", "shared_bind", "native_bind"]:
		_fail_fast("unknown mode: " + mode)
		return
	if not prepare_only and output_dir.is_empty():
		_fail_fast("capture requires --out=<absolute directory>")
		return
	if not prepare_only and DirAccess.make_dir_recursive_absolute(output_dir) != OK and not DirAccess.dir_exists_absolute(output_dir):
		_fail_fast("cannot create output directory: " + output_dir)
		return

	var registration := _read_json(REPORT_PATH)
	var pose_data := _read_json(POSE_PATH)
	var texture_data := _read_json(TEXTURES_PATH)
	var bone_data := _read_json(BONES_PATH)
	var grid_data := _read_json(GRID_PATH)
	var grid: Dictionary = grid_data.get("grid", {})
	var points: Array = grid.get("points_source_xy", [])
	var lower_weights: Array = grid.get("lower_weights", [])
	var triangles: Array = grid.get("triangles", [])
	var columns := int(grid.get("columns", 0))
	var rows := int(grid.get("rows", 0))
	var source_record: Dictionary = registration.get("source", {})
	var pose_parts: Array = pose_data.get(str(POSE), {}).get("parts", [])
	var upper_meta := _find_owner(registration, "front_thigh")
	var lower_meta := _find_owner(registration, "front_calf")
	var source_map: Array = registration.get("guide", {}).get("source_to_skeleton", [])
	_check(source_record.get("sha256", "") == SOURCE_SHA, "pinned source hash unchanged")
	var source_size: Array = source_record.get("size", [])
	_check(source_size.size() == 2 and int(source_size[0]) == 1440 and int(source_size[1]) == 736 and str(source_record.get("mode", "")) == "RGBA", "native source is RGBA 1440x736")
	_check(points.size() == columns * rows and columns >= 5 and rows >= 5 and lower_weights.size() == points.size(), "common grid has matching UV/weight vertices and at least 5x5 coverage")
	_check(triangles.size() % 3 == 0 and triangles.size() == (columns - 1) * (rows - 1) * 6, "explicit common topology covers every grid cell")
	_check(pose_parts.size() == 12 and bone_data.size() == 20, "canonical 20-bone fixture retains all 12 source pose slots")
	_check(source_map.size() == 6 and not upper_meta.is_empty() and not lower_meta.is_empty(), "both registered owners and source affine are present")
	_check(_weights_valid(lower_weights), "all shared lower weights are finite and within [0,1], complementary upper weights sum to one")
	_check(_source_textures_valid(grid_data), "both common-bbox diffuse atlases preserve source RGBA under alpha-floor 40")
	_check(_topology_valid(triangles, points.size()), "all explicit triangle indices are in range and nondegenerate")
	if not _failures.is_empty():
		_finish(output_dir, mode, registration, [], false)
		return

	var rig: CharacterRig = _make_rig(1, bone_data)
	if rig == null:
		_finish(output_dir, mode, registration, [], false)
		return
	var original_rest := _bone_rest_snapshot(rig)
	if mode == "native_bind":
		add_child(rig)
		await get_tree().process_frame
	var upper_node := _make_owner_sprite(rig, registration, "front_thigh")
	var lower_node := _make_owner_sprite(rig, registration, "front_calf")
	var hinge := rig.bone(&"leg_front_lower")
	_check(upper_node != null and lower_node != null and hinge != null, "upper/lower active source slots and hinge resolve")
	if upper_node == null or lower_node == null or hinge == null:
		_finish(output_dir, mode, registration, [], false)
		return
	var upper_bone := rig.bone(&"leg_front_upper")
	var lower_bone := rig.bone(&"leg_front_lower")
	var rig_inverse := rig.global_transform.affine_inverse()
	var bind_upper := rig_inverse * upper_bone.global_transform
	var bind_lower := rig_inverse * lower_bone.global_transform
	var canonical_local := _source_points_to_rig_local(rig, points, source_map)
	_check(canonical_local.size() == points.size(), "source XY vertices map to canonical rig-local coordinates")
	_check(_bind_rest_error(rig, upper_node, lower_node, points, source_map) <= 1e-4, "registered source affine equals both owner Sprite transforms in bind pose within 1e-4")
	_check(_parented_projection_error(rig, upper_node, lower_node, points, source_map, canonical_local) <= 1e-4,
		"shared grid source points match the actual parented Sprite projection in rig-local space")
	_check(_canonical_guide_matches(rig, bone_data), "20 canonical local bone transforms/rest data match the pinned guide")
	if mode == "native_bind":
		_check(_set_native_bind_rest(rig), "native Polygon2D bind records all 20 canonical Bone2D transforms as rest")
	if mode in ["shared_bind", "native_bind"]:
		upper_node.visible = false
		lower_node.visible = false
		for part: CanvasItem in rig._parts:
			part.visible = false
			for child: Node in part.get_children():
				if child is CanvasItem:
					(child as CanvasItem).visible = false
	var shared_nodes: Array[Polygon2D] = []
	if mode in ["shared_bind", "native_bind"]:
		shared_nodes = _make_shared_polygons(rig, grid_data, canonical_local, source_map, mode == "native_bind")
		_check(shared_nodes.size() == 2, "two owner polygons use the same UV/template/weight array and distinct source masks")
		_check(_same_shared_geometry(shared_nodes), "upper/lower polygons have byte-identical grid UVs, topology and bind vertices")
		if mode == "native_bind":
			_check(_native_bindings_valid(rig, shared_nodes, lower_weights), "native Skeleton2D paths resolve and both bone-weight fields are finite, complementary and vertex-aligned")
	var snap := _bone_snapshot(rig)
	var baseline_error := _bind_rest_error(rig, upper_node, lower_node, points, source_map)
	_check(baseline_error <= 1e-4, "baseline initial bind placement matches source registration within 1e-4")
	var sweep_nodes: Array[Polygon2D] = []
	if mode == "shared_bind":
		sweep_nodes = shared_nodes
	var cpu_metrics := _cpu_sweep_checks(rig, hinge, upper_node, lower_node, sweep_nodes, points, lower_weights, canonical_local, source_map, bind_upper, bind_lower, snap)
	var parented_projection := _parented_projection_sweep(rig, upper_node, lower_node, points, source_map, canonical_local, hinge)
	cpu_metrics["parented_projection"] = parented_projection
	_check(float(parented_projection.get("max_error_rig_units", INF)) <= 1e-4,
		"parented source, shared-grid and Sprite knee points agree at both zooms/facings")
	_check(cpu_metrics.get("max_canonical_position_error", INF) <= 1e-4, "shared-bind source vertices remain exact at 0 degrees")
	_check(is_finite(float(cpu_metrics.get("max_deformed_vertex_displacement_rig_units", INF))), "shared vertices remain finite through canonical knee sweep")
	if prepare_only:
		if mode == "native_bind":
			_check(_restore_bone_rests(rig, original_rest), "CPU prepare restores all original Bone2D rest transforms before disposal")
		rig.free()
		_finish(output_dir, mode, registration, [], false, cpu_metrics)
		return

	if mode == "baseline":
		for part: CanvasItem in rig._parts:
			part.visible = false
			for child: Node in part.get_children():
				if child is CanvasItem:
					(child as CanvasItem).visible = false
		upper_node.visible = true
	lower_node.visible = true

	var frame_groups: Array[Dictionary] = []
	var rig_records: Array[Dictionary] = []
	rig.queue_free()
	await get_tree().process_frame
	for zoom: float in ZOOMS:
		for facing: int in FACINGS:
			var capture_rig := _make_rig(facing, bone_data)
			if capture_rig == null:
				continue
			var capture_original_rest := _bone_rest_snapshot(capture_rig)
			if mode == "native_bind":
				add_child(capture_rig)
				await get_tree().process_frame
			var capture_upper := _make_owner_sprite(capture_rig, registration, "front_thigh")
			var capture_lower := _make_owner_sprite(capture_rig, registration, "front_calf")
			var capture_hinge := capture_rig.bone(&"leg_front_lower")
			var capture_canonical := _source_points_to_rig_local(capture_rig, points, source_map)
			var capture_shared: Array[Polygon2D] = []
			if mode == "native_bind":
				_check(_set_native_bind_rest(capture_rig), "capture rig stores canonical rest before native bind")
			if mode in ["shared_bind", "native_bind"]:
				capture_upper.visible = false
				capture_lower.visible = false
				for part: CanvasItem in capture_rig._parts:
					part.visible = false
					for child: Node in part.get_children():
						if child is CanvasItem:
							(child as CanvasItem).visible = false
				capture_shared = _make_shared_polygons(capture_rig, grid_data, capture_canonical, source_map, mode == "native_bind")
				if mode == "native_bind":
					_check(_native_bindings_valid(capture_rig, capture_shared, lower_weights), "capture native bone paths and weights resolve before rendering")
			else:
				for part: CanvasItem in capture_rig._parts:
					part.visible = false
					for child: Node in part.get_children():
						if child is CanvasItem:
							(child as CanvasItem).visible = false
				capture_upper.visible = true
				capture_lower.visible = true
			var captured := await _capture_group(mode, zoom, facing, output_dir, capture_rig, capture_hinge, capture_upper, capture_lower, capture_shared, points, lower_weights, capture_canonical, source_map, bone_data, capture_original_rest)
			frame_groups.append(captured.get("group", {}))
			rig_records.append(captured.get("record", {}))
	_check(frame_groups.size() == 4 and rig_records.size() == 4, "four facing/zoom groups include 120 actual-frame samples each")
	_finish(output_dir, mode, registration, frame_groups, true, cpu_metrics, rig_records)


func _capture_group(mode: String, zoom: float, facing: int, output_dir: String, rig: CharacterRig, hinge: Bone2D,
		upper_node: Sprite2D, lower_node: Sprite2D, shared_nodes: Array[Polygon2D], points: Array,
		lower_weights: Array, canonical_local: PackedVector2Array, source_map: Array, bone_data: Dictionary, original_rest: Dictionary) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL, CELL)
	viewport.use_hdr_2d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var clip := Control.new()
	clip.size = Vector2(CELL, CELL)
	clip.clip_contents = true
	viewport.add_child(clip)
	var holder := Node2D.new()
	holder.scale = Vector2.ONE * zoom
	clip.add_child(holder)
	if rig.get_parent() == null:
		holder.add_child(rig)
	else:
		rig.reparent(holder)
	rig.facing = facing
	var projection_error := _parented_projection_error(rig, upper_node, lower_node, points, source_map, canonical_local)
	_check(projection_error <= 1e-4,
		"facing %d zoom %.1f: shared knee point matches each parented owner Sprite (error %.9f rig units)" % [facing, zoom, projection_error])
	print("KNEE_PROJECTION facing=%d zoom=%.1f rig_scale=%s holder_scale=%s hinge_global=%s hinge_rig_local=%s shared_joint_rig_local=%s shared_joint_global=%s" % [
		facing, zoom, str(rig.scale), str(holder.scale), str(hinge.global_position), str(rig.to_local(hinge.global_position)),
		str(canonical_local[_joint_grid_index(points)]), str(rig.to_global(canonical_local[_joint_grid_index(points)]))])
	var rig_inverse := rig.global_transform.affine_inverse()
	var bind_upper := rig_inverse * rig.bone(&"leg_front_upper").global_transform
	var bind_lower := rig_inverse * rig.bone(&"leg_front_lower").global_transform
	var native_bind_pose_snapshot := _bone_snapshot(rig)
	var delta_sequence: Array[Dictionary] = []
	var radius := ceili(8.0 * zoom * rig.body_scale())
	var record := {"char": "rin", "joint": "knee_front", "facing": facing, "zoom": zoom, "mode": mode,
		"hinge": "leg_front_lower", "source_sha256": SOURCE_SHA, "radius": radius,
		"canonical_bones": 20, "active_source_owners": ["front_thigh", "front_calf"]}
	for frame in STEPS:
		var delta := _frame_delta(frame)
		hinge.rotation = float(bone_data["leg_front_lower"]["local_rotation_radians"]) + deg_to_rad(delta)
		rig.refresh_limbs()
		if mode == "shared_bind":
			_update_shared_vertices(rig, shared_nodes, canonical_local, lower_weights, bind_upper, bind_lower)
		var relative_hinge := hinge.global_position - clip.global_position
		holder.position += Vector2(CELL, CELL) * 0.5 - relative_hinge
		var centered := hinge.global_position - clip.global_position
		_check(centered.distance_to(Vector2(CELL, CELL) * 0.5) <= 0.001 and is_finite(centered.x) and is_finite(centered.y), "hinge centered for %s frame %d" % [mode, frame])
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := CAPTURE.image(viewport)
		var file := "front_knee_%s_f%d_z%.1f_%03d.png" % [mode, facing, zoom, frame]
		_check(image.get_size() == Vector2i(CELL, CELL), "native sample dimensions for " + file)
		_check(_alpha_count(image) > 0, "cell alpha nonzero for " + file)
		_check(image.save_png(output_dir.path_join(file)) == OK, "sample saved: " + file)
		delta_sequence.append({"file": file, "frame": frame, "seconds": float(frame + 1) / 60.0, "delta_degrees": delta})
	var group := {"pose": "kneel_shared_bind_%s" % mode, "zoom": zoom, "facing": facing,
		"cells": [{"char": "rin", "joint": "knee_front", "facing": facing, "radius": radius, "rect": [0, 0, CELL, CELL]}],
		"samples": delta_sequence}
	if mode == "native_bind":
		hinge.rotation = float(bone_data["leg_front_lower"]["local_rotation_radians"])
		rig.refresh_limbs()
		_check(_bone_snapshot_matches(rig, native_bind_pose_snapshot, []), "native bind capture leaves all current canonical bone transforms/rests unchanged during sampling")
		_check(_restore_bone_rests(rig, original_rest), "native bind capture restores all original Bone2D.rest transforms after final readback")
	_check(_canonical_guide_matches(rig, bone_data), "%s ends with canonical bone transforms and original rest origins restored" % mode)
	viewport.queue_free()
	await get_tree().process_frame
	return {"group": group, "record": record}


func _make_rig(facing: int, bone_data: Dictionary) -> CharacterRig:
	var rig := CharacterRig.new()
	var ok := rig.setup("rin")
	_check(ok, "private canonical Rin rig sets up")
	if not ok:
		rig.free()
		return null
	rig.facing = facing
	_apply_canonical_pose(rig, bone_data)
	rig.set_armor_ratio(1.0, false)
	rig.refresh_limbs()
	for part: CanvasItem in rig._parts:
		part.visible = false
		for child: Node in part.get_children():
			if child is CanvasItem:
				(child as CanvasItem).visible = false
	return rig


func _make_shared_polygons(rig: CharacterRig, grid_data: Dictionary, canonical_local: PackedVector2Array, source_map: Array, native_bind := false) -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	var grid: Dictionary = grid_data["grid"]
	var bbox: Array = grid_data["common_bbox_xyxy_half_open"]
	var source_points: Array = grid["points_source_xy"]
	var uv := PackedVector2Array()
	var weights := PackedFloat32Array()
	var triangles := PackedInt32Array()
	for point: Array in source_points:
		uv.append(Vector2(float(point[0]) - float(bbox[0]), float(point[1]) - float(bbox[1])))
	for weight: float in grid["lower_weights"]:
		weights.append(weight)
	for index: int in grid["triangles"]:
		triangles.append(index)
	var topology := _split_triangles(triangles)
	for owner in ["front_thigh", "front_calf"]:
		var image := Image.new()
		var png_path := "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/shared_mesh/" + str(grid_data["textures"][owner]["file"])
		if image.load(ProjectSettings.globalize_path(png_path)) != OK:
			_fail("failed to load owner atlas: " + png_path)
			continue
		var polygon := Polygon2D.new()
		polygon.name = "SharedBind_%s" % owner
		polygon.texture = ImageTexture.create_from_image(image)
		polygon.uv = uv
		polygon.polygons = topology
		polygon.polygon = canonical_local
		polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var material := CanvasItemMaterial.new()
		material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		polygon.material = material
		polygon.z_index = 0
		rig.add_child(polygon)
		if native_bind:
			var skeleton := rig.get_node_or_null("Skeleton") as Skeleton2D
			var upper_bone := rig.bone(&"leg_front_upper")
			var lower_bone := rig.bone(&"leg_front_lower")
			if skeleton == null or upper_bone == null or lower_bone == null:
				_fail("native Polygon2D fixture missing Skeleton2D or canonical leg bones")
			else:
				polygon.skeleton = polygon.get_path_to(skeleton)
				var upper_weights := PackedFloat32Array()
				for weight: float in grid["lower_weights"]:
					upper_weights.append(1.0 - weight)
				polygon.add_bone(polygon.get_path_to(upper_bone), upper_weights)
				polygon.add_bone(polygon.get_path_to(lower_bone), weights)
		result.append(polygon)
	return result


func _set_native_bind_rest(rig: CharacterRig) -> bool:
	var skeleton := rig.get_node_or_null("Skeleton") as Skeleton2D
	if skeleton == null or rig.bone_order().size() != 20:
		return false
	if rig.is_inside_tree() and skeleton.get_bone_count() != 20:
		return false
	for name: StringName in rig.bone_order():
		var bone := rig.bone(name)
		bone.rest = bone.transform
	for name: StringName in rig.bone_order():
		var bone := rig.bone(name)
		if not bone.rest.is_equal_approx(bone.transform):
			return false
	return true


func _bone_rest_snapshot(rig: CharacterRig) -> Dictionary:
	var result := {}
	for name: StringName in rig.bone_order():
		result[str(name)] = rig.bone(name).rest
	return result


func _restore_bone_rests(rig: CharacterRig, snapshot: Dictionary) -> bool:
	if snapshot.size() != rig.bone_order().size():
		return false
	for name: StringName in rig.bone_order():
		if not snapshot.has(str(name)):
			return false
		rig.bone(name).rest = snapshot[str(name)]
	for name: StringName in rig.bone_order():
		if rig.bone(name).rest != snapshot[str(name)]:
			return false
	return true


func _native_bindings_valid(rig: CharacterRig, nodes: Array[Polygon2D], lower_weights: Array) -> bool:
	var skeleton := rig.get_node_or_null("Skeleton") as Skeleton2D
	if skeleton == null or nodes.size() != 2 or lower_weights.size() != int(_read_json(GRID_PATH).get("grid", {}).get("columns", 0)) * int(_read_json(GRID_PATH).get("grid", {}).get("rows", 0)):
		return false
	for polygon: Polygon2D in nodes:
		if polygon.skeleton != polygon.get_path_to(skeleton) or polygon.get_bone_count() != 2 or polygon.polygon.size() != lower_weights.size():
			return false
		var upper_path := polygon.get_bone_path(0)
		var lower_path := polygon.get_bone_path(1)
		if polygon.get_node_or_null(upper_path) != rig.bone(&"leg_front_upper") or polygon.get_node_or_null(lower_path) != rig.bone(&"leg_front_lower"):
			return false
		var upper: PackedFloat32Array = polygon.get_bone_weights(0)
		var lower: PackedFloat32Array = polygon.get_bone_weights(1)
		if upper.size() != lower_weights.size() or lower.size() != lower_weights.size():
			return false
		for index in lower_weights.size():
			if not is_finite(upper[index]) or not is_finite(lower[index]) or absf(upper[index] - (1.0 - float(lower_weights[index]))) > 1e-6 or absf(upper[index] + lower[index] - 1.0) > 1e-6:
				return false
	return true


func _update_shared_vertices(rig: CharacterRig, nodes: Array[Polygon2D], source_points_local: PackedVector2Array,
		lower_weights: Array, bind_upper: Transform2D, bind_lower: Transform2D) -> void:
	var upper := rig.bone(&"leg_front_upper")
	var lower := rig.bone(&"leg_front_lower")
	var rig_inverse := rig.global_transform.affine_inverse()
	var upper_relative := rig_inverse * upper.global_transform
	var lower_relative := rig_inverse * lower.global_transform
	var upper_delta := upper_relative * bind_upper.affine_inverse()
	var lower_delta := lower_relative * bind_lower.affine_inverse()
	var deformed := PackedVector2Array()
	for index in source_points_local.size():
		var source_local := source_points_local[index]
		var upper_world := upper_delta * source_local
		var lower_world := lower_delta * source_local
		var weight := float(lower_weights[index])
		deformed.append(upper_world.lerp(lower_world, weight))
	for node: Polygon2D in nodes:
		node.polygon = deformed


func _source_points_to_rig_local(rig: CharacterRig, source_points: Array, affine: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p: Array in source_points:
		# The report affine is already expressed in rig-local skeleton coordinates.
		var registered_world := Vector2(float(affine[0]) * float(p[0]) + float(affine[2]) * float(p[1]) + float(affine[4]),
			float(affine[1]) * float(p[0]) + float(affine[3]) * float(p[1]) + float(affine[5]))
		# The rig's root scale applies once through the node hierarchy.
		result.append(registered_world)
	return result


func _parented_projection_error(rig: CharacterRig, upper_node: Sprite2D, lower_node: Sprite2D,
		points: Array, affine: Array, shared_points: PackedVector2Array) -> float:
	# Compare one exact registered source coordinate after the actual rig->holder
	# hierarchy exists. Use both sprites and a shared-grid vertex at the canonical knee.
	var target := Vector2(986.5470282502092, 196.32953522798385)
	var target_index := -1
	for index in points.size():
		var source_point: Array = points[index]
		if Vector2(float(source_point[0]), float(source_point[1])).distance_to(target) < 1e-5:
			target_index = index
			break
	if target_index < 0:
		_fail("canonical knee source coordinate is absent from shared grid")
		return INF
	var expected_rig_local := Vector2(float(affine[0]) * target.x + float(affine[2]) * target.y + float(affine[4]),
		float(affine[1]) * target.x + float(affine[3]) * target.y + float(affine[5]))
	var error := shared_points[target_index].distance_to(expected_rig_local)
	var metas := [_find_owner(_read_json(REPORT_PATH), "front_thigh"), _find_owner(_read_json(REPORT_PATH), "front_calf")]
	var sprites := [upper_node, lower_node]
	for owner_index in 2:
		var meta: Dictionary = metas[owner_index]
		var bbox: Array = meta["crop_bbox_xyxy_half_open"]
		var pivot := Vector2(float(meta["pivot_local_xy"][0]), float(meta["pivot_local_xy"][1]))
		var local_texture := Vector2(target.x - float(bbox[0]), target.y - float(bbox[1])) - pivot
		# A Sprite2D's local texture point is in source pixels; its own node transform
		# applies offset, rotation, scale and position exactly once.
		var actual_rig_local := rig.to_local((sprites[owner_index] as Sprite2D).to_global(local_texture))
		print("OWNER_POINT owner=%d source=%s affine_rig_local=%s shared_rig_local=%s sprite_rig_local=%s sprite_global=%s" % [owner_index,
			str(target), str(expected_rig_local), str(shared_points[target_index]), str(actual_rig_local),
			str((sprites[owner_index] as Sprite2D).to_global(local_texture))])
		error = maxf(error, actual_rig_local.distance_to(expected_rig_local))
	# Include the current holder transform so this catches errors hidden by a rootless rig.
	var shared_global := rig.to_global(shared_points[target_index])
	var actual_global := rig.to_global(expected_rig_local)
	error = maxf(error, shared_global.distance_to(actual_global) / maxf(rig.scale.length(), 1e-6))
	return error


func _joint_grid_index(points: Array) -> int:
	var target := Vector2(986.5470282502092, 196.32953522798385)
	for index in points.size():
		var p: Array = points[index]
		if Vector2(float(p[0]), float(p[1])).distance_to(target) < 1e-5:
			return index
	return -1


func _parented_projection_sweep(rig: CharacterRig, upper_node: Sprite2D, lower_node: Sprite2D,
		points: Array, affine: Array, shared_points: PackedVector2Array, hinge: Bone2D) -> Dictionary:
	var holder := Node2D.new()
	add_child(holder)
	var previous_parent := rig.get_parent()
	var previous_transform := rig.transform
	if previous_parent != null:
		previous_parent.remove_child(rig)
	holder.add_child(rig)
	var samples: Array[Dictionary] = []
	var maximum := 0.0
	var index := _joint_grid_index(points)
	var source_xy: Array = points[index]
	var expected := Vector2(float(affine[0]) * float(source_xy[0]) + float(affine[2]) * float(source_xy[1]) + float(affine[4]),
		float(affine[1]) * float(source_xy[0]) + float(affine[3]) * float(source_xy[1]) + float(affine[5]))
	for zoom: float in ZOOMS:
		holder.scale = Vector2.ONE * zoom
		for facing: int in FACINGS:
			rig.facing = facing
			var error := _parented_projection_error(rig, upper_node, lower_node, points, affine, shared_points)
			maximum = maxf(maximum, error)
			var global_grid := rig.to_global(shared_points[index])
			var global_hinge := hinge.global_position
			samples.append({"zoom": zoom, "facing": facing, "source_xy": source_xy,
				"affine_rig_local": _xy(expected), "shared_rig_local": _xy(shared_points[index]),
				"shared_global": _xy(global_grid), "hinge_global": _xy(global_hinge),
				"hinge_rig_local": _xy(rig.to_local(global_hinge)), "projection_error_rig_units": error,
				"holder_global_transform": _transform_values(holder.global_transform), "rig_global_transform": _transform_values(rig.global_transform)})
	rig.facing = 1
	holder.remove_child(rig)
	if previous_parent != null:
		previous_parent.add_child(rig)
	rig.transform = previous_transform
	holder.free()
	return {"source_point_xy": source_xy, "max_error_rig_units": maximum, "samples": samples}


func _xy(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _transform_values(value: Transform2D) -> Array[float]:
	return [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]


func _bind_rest_error(rig: CharacterRig, upper_node: Sprite2D, lower_node: Sprite2D, points: Array, affine: Array) -> float:
	var maximum := 0.0
	var metas := [_find_owner(_read_json(REPORT_PATH), "front_thigh"), _find_owner(_read_json(REPORT_PATH), "front_calf")]
	var nodes := [upper_node, lower_node]
	for owner_index in 2:
		var meta: Dictionary = metas[owner_index]
		var bbox: Array = meta["crop_bbox_xyxy_half_open"]
		var pivot := Vector2(float(meta["pivot_local_xy"][0]), float(meta["pivot_local_xy"][1]))
		var offset := Vector2(float(meta["bone_local_offset"][0]), float(meta["bone_local_offset"][1]))
		var rotation := float(meta["bone_local_rotation_radians"])
		var bone := rig.bone(StringName(meta["bone"]))
		var last_source := Vector2.ZERO
		var last_sprite := Vector2.ZERO
		for p: Array in points:
			if float(p[0]) < float(bbox[0]) or float(p[0]) > float(bbox[2]) or float(p[1]) < float(bbox[1]) or float(p[1]) > float(bbox[3]):
				continue
			var source_global := Vector2(float(affine[0]) * float(p[0]) + float(affine[2]) * float(p[1]) + float(affine[4]),
				float(affine[1]) * float(p[0]) + float(affine[3]) * float(p[1]) + float(affine[5])) * rig.body_scale()
			var local_texture := Vector2(float(p[0]) - float(bbox[0]), float(p[1]) - float(bbox[1])) - pivot
			var sprite_local := offset + Vector2(local_texture.x * cos(rotation) - local_texture.y * sin(rotation), local_texture.x * sin(rotation) + local_texture.y * cos(rotation)) * float(meta["texture_scale_world_per_pixel"])
			var sprite_global := bone.global_transform * sprite_local
			last_source = rig.to_local(source_global)
			last_sprite = rig.to_local(sprite_global)
			maximum = maxf(maximum, last_source.distance_to(last_sprite))
	return maximum


func _cpu_sweep_checks(rig: CharacterRig, hinge: Bone2D, upper_node: Sprite2D, lower_node: Sprite2D,
		shared_nodes: Array[Polygon2D], source_points: Array, weights: Array, canonical_local: PackedVector2Array,
		source_map: Array, bind_upper: Transform2D, bind_lower: Transform2D, initial_snapshot: Dictionary) -> Dictionary:
	var max_canonical := 0.0
	var max_deformed_displacement := 0.0
	var motion := [-30.0, -15.0, -5.0, 0.0, 5.0, 15.0, 30.0]
	var base := float(_read_json(BONES_PATH)["leg_front_lower"]["local_rotation_radians"])
	for degrees: float in motion:
		hinge.rotation = base + deg_to_rad(degrees)
		rig.refresh_limbs()
		if not shared_nodes.is_empty():
			_update_shared_vertices(rig, shared_nodes, canonical_local, weights, bind_upper, bind_lower)
		for local_point in canonical_local:
			if not is_finite(local_point.x) or not is_finite(local_point.y):
				max_deformed_displacement = INF
		for node: Polygon2D in shared_nodes:
			for index in node.polygon.size():
				var vertex := node.polygon[index]
				if not is_finite(vertex.x) or not is_finite(vertex.y):
					max_deformed_displacement = INF
				else:
					max_deformed_displacement = maxf(max_deformed_displacement, vertex.distance_to(canonical_local[index]))
		if absf(degrees) < 0.00001:
			for index in canonical_local.size():
				var expected := canonical_local[index]
				for node: Polygon2D in shared_nodes:
					max_canonical = maxf(max_canonical, node.polygon[index].distance_to(expected))
	var transforms_unchanged := _bone_snapshot_matches(rig, initial_snapshot, [&"leg_front_lower"])
	_check(transforms_unchanged, "CPU prototype restores canonical non-hinge local transforms; only the test hinge is swept")
	return {"angles_degrees": motion, "max_canonical_position_error": max_canonical,
		"max_deformed_vertex_displacement_rig_units": max_deformed_displacement, "bone_snapshot_nonhinge_unchanged": transforms_unchanged,
		"note": "finite displacement is descriptive only; it is not a source/visual acceptance metric"}


func _weights_valid(weights: Array) -> bool:
	for w: float in weights:
		if not is_finite(w) or w < 0.0 or w > 1.0 or absf((1.0 - w) + w - 1.0) > 1e-6:
			return false
	return true


func _source_textures_valid(data: Dictionary) -> bool:
	var bbox: Array = data.get("common_bbox_xyxy_half_open", [])
	if bbox.size() != 4:
		return false
	var expected_size := Vector2i(int(bbox[2]) - int(bbox[0]), int(bbox[3]) - int(bbox[1]))
	for owner in ["front_thigh", "front_calf"]:
		var path := ProjectSettings.globalize_path("res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/shared_mesh/" + str(data.get("textures", {}).get(owner, {}).get("file", "")))
		var image := Image.new()
		if image.load(path) != OK or image.get_size() != expected_size or image.get_format() != Image.FORMAT_RGBA8:
			return false
	return true


func _topology_valid(triangles: Array, vertex_count: int) -> bool:
	for index: int in range(0, triangles.size(), 3):
		var a := int(triangles[index])
		var b := int(triangles[index + 1])
		var c := int(triangles[index + 2])
		if a < 0 or b < 0 or c < 0 or a >= vertex_count or b >= vertex_count or c >= vertex_count or a == b or b == c or a == c:
			return false
	return true


func _same_shared_geometry(nodes: Array[Polygon2D]) -> bool:
	return nodes.size() == 2 and nodes[0].uv == nodes[1].uv and nodes[0].polygons == nodes[1].polygons and nodes[0].polygon == nodes[1].polygon


func _split_triangles(triangles: PackedInt32Array) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for i in range(0, triangles.size(), 3):
		result.append(PackedInt32Array([triangles[i], triangles[i + 1], triangles[i + 2]]))
	return result


func _find_owner(report: Dictionary, owner: String) -> Dictionary:
	return report.get("owners", {}).get(owner, {})


func _make_owner_sprite(rig: CharacterRig, registration: Dictionary, owner: String) -> Sprite2D:
	var meta: Dictionary = _find_owner(registration, owner)
	var texture_key := "front_thigh" if owner == "front_thigh" else "front_calf"
	var image := Image.new()
	var path := ProjectSettings.globalize_path("res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/textures/%s.png" % texture_key)
	if image.load(path) != OK:
		_fail("could not load original masked owner source " + path)
		return null
	var sprite := Sprite2D.new()
	sprite.name = "OriginalOwner_%s" % owner
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.offset = -Vector2(float(meta["pivot_local_xy"][0]), float(meta["pivot_local_xy"][1]))
	sprite.scale = Vector2.ONE * float(meta["texture_scale_world_per_pixel"])
	sprite.position = Vector2(float(meta["bone_local_offset"][0]), float(meta["bone_local_offset"][1]))
	sprite.rotation = float(meta["bone_local_rotation_radians"])
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	sprite.material = material
	rig.bone(StringName(meta["bone"])).add_child(sprite)
	return sprite


func _apply_canonical_pose(rig: CharacterRig, data: Dictionary) -> void:
	for name: String in data:
		var bone := rig.bone(StringName(name))
		var item: Dictionary = data[name]
		bone.position = Vector2(float(item["local_position"][0]), float(item["local_position"][1]))
		bone.rotation = float(item["local_rotation_radians"])


func _canonical_guide_matches(rig: CharacterRig, data: Dictionary) -> bool:
	if rig.bone_order().size() != 20:
		return false
	for name: StringName in rig.bone_order():
		var bone := rig.bone(name)
		var item: Dictionary = data[str(name)]
		if bone.position.distance_to(Vector2(float(item["local_position"][0]), float(item["local_position"][1]))) > 1e-6:
			return false
		if bone.rest.origin.distance_to(Vector2(float(item["rest_position"][0]), float(item["rest_position"][1]))) > 1e-6:
			return false
		if name != &"hip" and absf(bone.rotation - float(item["local_rotation_radians"])) > 1e-6:
			return false
	return true


func _bone_snapshot(rig: CharacterRig) -> Dictionary:
	var result := {}
	for name: StringName in rig.bone_order():
		var b := rig.bone(name)
		result[str(name)] = [b.position, b.rotation, b.scale, b.rest, b.get_parent().get_instance_id()]
	return result


func _bone_snapshot_matches(rig: CharacterRig, snapshot: Dictionary, excluded: Array[StringName]) -> bool:
	for name: StringName in rig.bone_order():
		if name in excluded:
			continue
		var now := rig.bone(name)
		var prior: Array = snapshot[str(name)]
		if now.position != prior[0] or now.rotation != prior[1] or now.scale != prior[2] or now.rest != prior[3] or now.get_parent().get_instance_id() != int(prior[4]):
			return false
	return true


func _frame_delta(frame: int) -> float:
	if frame == 0:
		return float(WAYPOINTS[0])
	var intervals := (STEPS - 1) / (WAYPOINTS.size() - 1)
	var segment := mini((frame - 1) / intervals, WAYPOINTS.size() - 2)
	var t := float(frame - segment * intervals) / float(intervals)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(float(WAYPOINTS[segment]), float(WAYPOINTS[segment + 1]), t)


func _alpha_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("missing JSON: " + ProjectSettings.globalize_path(path))
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("invalid JSON: " + path)
		return {}
	return parsed


func _finish(output_dir: String, mode: String, registration: Dictionary, groups: Array, viewport_used: bool,
		cpu_metrics: Dictionary = {}, records: Array = []) -> void:
	if not output_dir.is_empty():
		var frames_file := FileAccess.open(output_dir.path_join("frames.json"), FileAccess.WRITE)
		if frames_file != null:
			frames_file.store_string(JSON.stringify(groups, "\t"))
			frames_file.close()
	var result := {"status": "PRIVATE_SHARED_BIND_CAPTURED_NOT_ACCEPTED" if viewport_used else "PRIVATE_SHARED_BIND_CPU_PREPARED_NOT_ACCEPTED",
		"mode": mode, "source_sha256": registration.get("source", {}).get("sha256", ""), "canonical_bones": 20,
		"shared_bind": true, "grid": "res://pm/Nest-Egg/attachments/NE-222-native-pose/generated/shared_mesh/shared_grid.json", "rig_records": records,
		"cpu_metrics": cpu_metrics, "frame_groups": groups.size(), "samples_per_group": STEPS if viewport_used else 0,
		"checks": _checks, "failures": _failures, "viewport_used": viewport_used,
		"rendering_method": RenderingServer.get_current_rendering_method() if viewport_used else "not_rendered",
		"viewport_use_hdr_2d": true if viewport_used else false, "capture_adapter": "tools/viewport_capture.gd" if viewport_used else "none",
		"acceptance": false,
		"limitations": ["CPU geometry and viewport fixture only; this is not visual, runtime, transition, armor-underlayer, source-anatomy, or acceptance evidence.",
		"Both owner polygons use the same grid, UVs and weights; source ownership/masks remain exclusive and RGBA is copied from 22297 only.",
		"The bind transform is sampled from the existing canonical 20-bone pose before knee rotation changes; it is not the standing zero-angle mesh bind."]}
	if not output_dir.is_empty():
		var file := FileAccess.open(output_dir.path_join("capture-report.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "\t"))
			file.close()
	print("NE222_SHARED_BIND mode=%s checks=%d failures=%d viewport=%s status=%s" % [mode, _checks, _failures.size(), str(viewport_used), result["status"]])
	for failure in _failures:
		printerr("FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("FAIL: " + message)


func _fail_fast(message: String) -> void:
	_fail(message)
	get_tree().quit(2)
