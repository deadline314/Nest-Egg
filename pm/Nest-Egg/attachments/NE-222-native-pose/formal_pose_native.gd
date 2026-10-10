extends "res://pm/Nest-Egg/attachments/NE-222-native-pose/capture_shared_bind.gd"
## Private geometry comparison through the production pose-parts API.

func _make_rig(face: int, bone_data: Dictionary) -> CharacterRig:
	var original := RigLibrary.character("rin")
	var skin := original.duplicate(true)
	var data := _read_json("res://pm/Nest-Egg/attachments/NE-222-native-pose/formal_pose_data.json")
	for key: String in data["textures"]:
		var definition: Dictionary = data["textures"][key]
		skin["textures"][key] = definition
		var path := ("res://art/characters/rin/" + str(definition["file"])).simplify_path()
		for resource: String in [path, path.get_basename() + "_n.png"]:
			var raw := Image.new()
			_check(raw.load(ProjectSettings.globalize_path(resource)) == OK, "native source/normal texture exists")
			var texture := ImageTexture.create_from_image(raw)
			texture.take_over_path(resource)
			_registered.append(texture)
	skin["pose_parts"] = data["pose_parts"]
	RigLibrary._json_cache[RigLibrary.CHARACTER_PATH % "rin"] = skin
	var rig := super._make_rig(face, bone_data)
	RigLibrary._json_cache[RigLibrary.CHARACTER_PATH % "rin"] = original
	_check(rig != null and rig._pose_sets.has(POSE), "production API validates the complete authored mesh pose")
	if rig != null and not rig._pose_sets.has(POSE):
		rig.free()
		return null
	return rig

func _set_native_bind_rest(rig: CharacterRig) -> bool:
	return rig.set_pose_parts(POSE)

func _make_shared_polygons(rig: CharacterRig, _grid: Dictionary, _vertices: PackedVector2Array, _affine: Array, _native := false) -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	for slot: StringName in [&"armor_thigh", &"armor_calf"]:
		if not rig._pose_slots.has(slot):
			_fail("production pose mesh is missing slot " + str(slot))
			return result
		var polygon := rig._pose_slots[slot]["alternatives"][POSE] as Polygon2D
		_check(polygon != null and polygon.get_parent() == rig._skeleton, "cached production mesh is attached to the neutral skeleton")
		var canvas := polygon.texture as CanvasTexture
		_check(canvas != null and canvas.normal_texture != null, "production mesh retains its matching normal channel")
		polygon.visible = true
		var unshaded := CanvasItemMaterial.new()
		unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		polygon.material = unshaded
		result.append(polygon)
	return result

func _restore_bone_rests(rig: CharacterRig, snapshot: Dictionary) -> bool:
	if not rig.set_pose_parts(&""):
		return false
	for name: StringName in rig.bone_order():
		if rig.bone(name).rest != snapshot[str(name)]:
			return false
	return true

func _native_bindings_valid(rig: CharacterRig, nodes: Array[Polygon2D], lower_weights: Array) -> bool:
	if nodes.size() != 2:
		return false
	for polygon: Polygon2D in nodes:
		if polygon.skeleton != polygon.get_path_to(rig._skeleton) or polygon.get_bone_count() != 2:
			return false
		for index in 2:
			var expected := rig.bone(&"leg_front_upper" if index == 0 else &"leg_front_lower")
			if rig._skeleton.get_node_or_null(polygon.get_bone_path(index)) != expected:
				return false
			var weights := polygon.get_bone_weights(index)
			if weights.size() != lower_weights.size():
				return false
			for vertex in weights.size():
				var want := 1.0-float(lower_weights[vertex]) if index == 0 else float(lower_weights[vertex])
				if not is_finite(weights[vertex]) or absf(weights[vertex]-want) > 1e-6:
					return false
	return true
