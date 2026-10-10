extends "res://pm/Nest-Egg/attachments/NE-222-native-pose/formal_pose_native.gd"
## Replay the published source control while checking the active native audit geometry.

func _make_shared_polygons(rig: CharacterRig, grid_data: Dictionary, canonical_local: PackedVector2Array,
		source_map: Array, native_bind := false) -> Array[Polygon2D]:
	var nodes := super._make_shared_polygons(rig, grid_data, canonical_local, source_map, native_bind)
	var geometry := rig.active_pose_mesh_geometries()
	_check(geometry.size() == 2, "both visible native owners enter the audit without hidden alternatives or glow")
	_check(rig.visual_bounds().has_area(), "native-only source control contributes visible world bounds")
	var ctx := {"rig": rig, "where": "native-source-control", "frame": 0, "results": {}, "prev": {}}
	AnimAudit._measure(ctx, false)
	_check((ctx["results"] as Dictionary).has("mesh_fold"), "native source control records the existing mesh-fold metric")
	return nodes
