class_name StagePropBinding
extends RefCounted
## 接觸點追著具名道具的實際變換；只保留弱參照，不延長舞台／道具生命。

var _target: WeakRef
var _point := Vector2.ZERO
var _offset := Vector2.ZERO
var _mesh_requested := false
var _mesh_valid := false
var _mesh_indices := PackedInt32Array()
var _mesh_uv := PackedVector2Array()
var _mesh_weights := Vector3.ZERO
var _mesh_u := Vector2.ZERO
var _mesh_triangle := -1
var _mesh_vertices := 0
var _mesh_polygons := 0
var _mesh_texture: WeakRef


func _init(target: Node2D, point: Vector2, stage_offset := Vector2.ZERO) -> void:
	_target = weakref(target)
	_point = point
	_offset = stage_offset


## 一次解析來源三角與重心權重；逐格只讀現有變形頂點，不遍歷或重建網格。
static func mesh_part(mesh: RigPartMesh, source: Vector2, stage_offset := Vector2.ZERO) -> StagePropBinding:
	var binding := StagePropBinding.new(mesh, source, stage_offset)
	binding._mesh_requested = true
	binding._mesh_valid = binding._prepare_mesh(mesh, source)
	return binding


func _prepare_mesh(mesh: RigPartMesh, source: Vector2) -> bool:
	if not is_instance_valid(mesh) or not mesh.visible or mesh.texture == null or not source.is_finite():
		return false
	var size := Vector2(mesh.texture.get_size())
	if source.x < 0.0 or source.y < 0.0 or source.x > size.x or source.y > size.y:
		return false
	var uvs := mesh.uv
	var vertices := mesh.deformed_vertices()
	if uvs.size() != vertices.size() or uvs.size() < 3 or mesh.polygons.is_empty():
		return false
	var chosen := -1
	for index in mesh.polygons.size():
		var raw: Variant = mesh.polygons[index]
		if not raw is PackedInt32Array:
			return false
		var triangle: PackedInt32Array = raw
		if triangle.size() != 3:
			return false
		for vertex in triangle:
			if vertex < 0 or vertex >= uvs.size() or not uvs[vertex].is_finite() or not vertices[vertex].is_finite() or uvs[vertex].x < 0.0 or uvs[vertex].y < 0.0 or uvs[vertex].x > size.x or uvs[vertex].y > size.y:
				return false
		var basis := Transform2D(uvs[triangle[1]] - uvs[triangle[0]], uvs[triangle[2]] - uvs[triangle[0]], uvs[triangle[0]])
		if absf(basis.determinant()) < 0.000001:
			continue
		var inverse := basis.affine_inverse()
		var weights := inverse * source
		if chosen < 0 and weights.x >= -0.000001 and weights.y >= -0.000001 and weights.x + weights.y <= 1.000001:
			chosen = index
			_mesh_indices = triangle
			_mesh_uv = PackedVector2Array([uvs[triangle[0]], uvs[triangle[1]], uvs[triangle[2]]])
			_mesh_weights = Vector3(1.0 - weights.x - weights.y, weights.x, weights.y)
			_mesh_u = inverse.x
	if chosen < 0:
		return false
	_mesh_triangle = chosen
	_mesh_vertices = vertices.size()
	_mesh_polygons = mesh.polygons.size()
	_mesh_texture = weakref(mesh.texture)
	return true


func _mesh_current(mesh: RigPartMesh) -> bool:
	if not _mesh_valid or mesh == null or not mesh.is_visible_in_tree() or mesh.texture != _mesh_texture.get_ref():
		return false
	var vertices := mesh.deformed_vertices()
	if vertices.size() != _mesh_vertices or mesh.uv.size() != _mesh_vertices or mesh.polygons.size() != _mesh_polygons or mesh.polygons[_mesh_triangle] != _mesh_indices:
		return false
	for index in 3:
		if mesh.uv[_mesh_indices[index]] != _mesh_uv[index] or not vertices[_mesh_indices[index]].is_finite():
			return false
	return true


func stage_point(parent: Node2D) -> Vector2:
	var node := _node()
	if node == null or not _parent_valid(parent) or not _offset.is_finite() or absf(_offset.x) > 8192.0 or absf(_offset.y) > 8192.0:
		return Vector2.INF
	var local: Vector2
	if _mesh_requested:
		var mesh := node as RigPartMesh
		if not _mesh_current(mesh):
			return Vector2.INF
		var vertices := mesh.deformed_vertices()
		local = vertices[_mesh_indices[0]] * _mesh_weights.x + vertices[_mesh_indices[1]] * _mesh_weights.y + vertices[_mesh_indices[2]] * _mesh_weights.z
	else:
		local = (node as StageLayers._Sprite).source_point(_point) if node is StageLayers._Sprite else _point
	if not local.is_finite():
		return Vector2.INF
	var point := parent.to_local(node.to_global(local)) + _offset
	return point if point.is_finite() else Vector2.INF


func stage_angle(parent: Node2D) -> float:
	var node := _node()
	if node == null or not _parent_valid(parent):
		return NAN
	var local_axis := Vector2.RIGHT
	if _mesh_requested:
		var mesh := node as RigPartMesh
		if not _mesh_current(mesh):
			return NAN
		var vertices := mesh.deformed_vertices()
		local_axis = (vertices[_mesh_indices[1]] - vertices[_mesh_indices[0]]) * _mesh_u.x + (vertices[_mesh_indices[2]] - vertices[_mesh_indices[0]]) * _mesh_u.y
	var direction := parent.global_transform.affine_inverse().basis_xform(node.global_transform.basis_xform(local_axis))
	return direction.angle() if direction.is_finite() and direction.length_squared() > 0.000001 else NAN


func _node() -> Node2D:
	var node := _target.get_ref() as Node2D if _target != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null


func _parent_valid(parent: Node2D) -> bool:
	return is_instance_valid(parent) and parent.global_transform.is_finite() and absf(parent.global_transform.determinant()) > 0.000001
