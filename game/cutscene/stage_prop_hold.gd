class_name StagePropHold
extends RefCounted
## 道具留在舞台，只追真實掌心；保留舞台基底，轉身不把壺鏡像翻成倒置。

const CONTACT_TOLERANCE := 0.25

var prop_id := ""
var _sprite: WeakRef
var _actor: WeakRef
var _hand: StringName
var _source_point := Vector2.ZERO
var _basis := Transform2D.IDENTITY
var _texture_width := 1.0
var _original_z := 0
var _original_relative := true
var _follow_rotation := false
var _hand_bone: WeakRef
var _hand_start_angle := 0.0


func setup(id: String, sprite: StageLayers._Sprite, actor: CutsceneActor, hand: StringName, point: Vector2, stage: Node2D, follow_rotation := false) -> String:
	if not is_instance_valid(sprite) or not is_instance_valid(actor) or actor.rig == null or not is_instance_valid(stage) or not stage.is_inside_tree():
		return "hold requires a live stage sprite and rigged actor"
	if not actor.hand_target_settled(hand):
		return "hold requires a settled hand contact"
	if not point.is_finite() or sprite.texture == null or sprite.texture.get_width() <= 0:
		return "hold requires a finite source point and texture"
	if not is_equal_approx(float(sprite.get_meta(&"parallax", 1.0)), 1.0):
		return "a parallax decoration cannot be held"
	var local := sprite.source_point(point)
	var palm := actor.hand_contact_global(hand)
	if not local.is_finite() or not palm.is_finite():
		return "hold point is outside the prop or hand geometry"
	if not stage.global_transform.is_finite() or absf(stage.global_transform.determinant()) < 0.000001:
		return "hold stage transform is singular"
	if stage.to_local(sprite.to_global(local)).distance_to(stage.to_local(palm)) > CONTACT_TOLERANCE:
		return "hand must physically touch the prop before holding it"
	_basis = stage.global_transform.affine_inverse() * sprite.global_transform
	_basis.origin = Vector2.ZERO
	if not _basis.is_finite() or absf(_basis.determinant()) < 0.000001:
		return "hold prop transform is singular"
	if follow_rotation:
		var wrist := actor.rig.bone(&"hand_front" if hand == &"front" else &"hand_back")
		if wrist == null:
			return "rotating hold requires a live hand bone"
		var direction := stage.global_transform.affine_inverse().basis_xform(wrist.global_transform.x)
		if not direction.is_finite() or direction.length_squared() < 0.000001:
			return "rotating hold hand transform is singular"
		_hand_bone = weakref(wrist)
		_hand_start_angle = direction.angle()
	_follow_rotation = follow_rotation
	prop_id = id
	_sprite = weakref(sprite)
	_actor = weakref(actor)
	_hand = hand
	_source_point = point
	_texture_width = float(sprite.texture.get_width())
	_original_z = sprite.z_index
	_original_relative = sprite.z_as_relative
	sprite.z_as_relative = false
	sprite.z_index = WorldLayers.stage_actor_z(actor.layer_slot) + actor.rig.hand_draw_z(hand) - 1
	actor.keep_hand_with_body(hand)
	return ""


func update(stage: Node2D) -> bool:
	var sprite := _sprite.get_ref() as StageLayers._Sprite if _sprite != null else null
	var actor := _actor.get_ref() as CutsceneActor if _actor != null else null
	if not is_instance_valid(sprite) or not is_instance_valid(actor) or actor.rig == null or sprite.texture == null or sprite.texture.get_width() <= 0 or not is_instance_valid(stage):
		release()
		return false
	if sprite.is_queued_for_deletion() or actor.is_queued_for_deletion() or not stage.is_inside_tree():
		release()
		return false
	var palm := actor.hand_contact_global(_hand)
	var local := sprite.source_point(_source_point)
	if not palm.is_finite() or not local.is_finite() or not stage.global_transform.is_finite() or absf(stage.global_transform.determinant()) < 0.000001:
		release()
		return false
	var ratio := _texture_width / float(sprite.texture.get_width())
	var stage_inverse := stage.global_transform.affine_inverse()
	var basis_x := _basis.x * ratio
	var basis_y := _basis.y * ratio
	if _follow_rotation:
		var wrist := _hand_bone.get_ref() as Node2D if _hand_bone != null else null
		if not is_instance_valid(wrist) or wrist.is_queued_for_deletion():
			release()
			return false
		var direction := stage_inverse.basis_xform(wrist.global_transform.x)
		if not direction.is_finite() or direction.length_squared() < 0.000001:
			release()
			return false
		var delta_angle := wrapf(direction.angle() - _hand_start_angle, -PI, PI)
		basis_x = basis_x.rotated(delta_angle)
		basis_y = basis_y.rotated(delta_angle)
	var transform := Transform2D(basis_x, basis_y, Vector2.ZERO)
	transform.origin = stage_inverse * palm - transform.basis_xform(local)
	sprite.global_transform = stage.global_transform * transform
	return true


func owns_actor(actor: CutsceneActor) -> bool:
	return _actor != null and _actor.get_ref() == actor


func owns_hand(actor: CutsceneActor, hand: StringName) -> bool:
	return owns_actor(actor) and _hand == hand


func release() -> void:
	var sprite := _sprite.get_ref() as StageLayers._Sprite if _sprite != null else null
	if is_instance_valid(sprite):
		sprite.z_index = _original_z
		sprite.z_as_relative = _original_relative
