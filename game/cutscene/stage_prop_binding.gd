class_name StagePropBinding
extends RefCounted
## 接觸點追著具名道具的實際變換；只保留弱參照，不延長舞台／道具生命。

var _target: WeakRef
var _point := Vector2.ZERO


func _init(target: Node2D, point: Vector2) -> void:
	_target = weakref(target)
	_point = point


func stage_point(parent: Node2D) -> Vector2:
	var node := _node()
	if node == null or not _parent_valid(parent):
		return Vector2.INF
	var local: Vector2 = (node as StageLayers._Sprite).source_point(_point) if node is StageLayers._Sprite else _point
	if not local.is_finite():
		return Vector2.INF
	return parent.to_local(node.to_global(local))


func stage_angle(parent: Node2D) -> float:
	var node := _node()
	if node == null or not _parent_valid(parent):
		return NAN
	var direction := parent.global_transform.affine_inverse().basis_xform(node.global_transform.x)
	return direction.angle() if direction.is_finite() and direction.length_squared() > 0.000001 else NAN


func _node() -> Node2D:
	var node := _target.get_ref() as Node2D if _target != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null


func _parent_valid(parent: Node2D) -> bool:
	return is_instance_valid(parent) and parent.global_transform.is_finite() and absf(parent.global_transform.determinant()) > 0.000001
