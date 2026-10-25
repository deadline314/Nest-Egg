class_name CutsceneReach
extends RefCounted
## 一隻手的舞台接觸；每個演員重用兩份，沒有接觸指令時不執行 IK。

const HANDS: PackedStringArray = ["front", "back"]
const DEFAULT_TIME := 0.35
const MAX_TIME := 5.0
const MAX_COORDINATE := 8192.0

var hand: StringName
var target := Vector2.ZERO
var angle := 0.0
var weight := 0.0
var _wanted := 0.0
var _duration := DEFAULT_TIME
var _reported := false
var _from_target := Vector2.ZERO
var _to_target := Vector2.ZERO
var _from_angle := 0.0
var _to_angle := 0.0
var _elapsed := 0.0
var _actor_space := false
var _binding: StagePropBinding
var _binding_angle := 0.0
var _contact_offset: Variant = null
var _follow_rotation := false


func _init(which: StringName) -> void:
	hand = which


static func problem(step: Dictionary) -> String:
	if not step.get("hand") is String or not HANDS.has(step["hand"]):
		return "reach hand must be front or back"
	if step.has("release") and not step["release"] is bool:
		return "reach release must be boolean"
	if step.has("wait") and not step["wait"] is bool:
		return "reach wait must be boolean"
	if step.get("space", "stage") not in ["stage", "actor", "prop"]:
		return "reach space must be stage, actor or prop"
	if step.get("space", "stage") == "prop" and (not step.get("prop") is String or not String(step["prop"]).is_valid_identifier()):
		return "reach prop space requires a named stage prop"
	if step.has("follow_rotation") and not step["follow_rotation"] is bool:
		return "reach follow_rotation must be boolean"
	if step.get("follow_rotation", false) and step.get("space", "stage") != "prop":
		return "reach follow_rotation requires prop space"
	if step.has("contact"):
		var point: Variant = step["contact"]
		if not point is Array or point.size() != 2:
			return "reach contact must be a two-number hand-source point"
		for value: Variant in point:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) > MAX_COORDINATE:
				return "reach contact must contain finite hand-source pixels within 0..8192"
	for key: String in ["time", "angle"]:
		if step.has(key) and (typeof(step[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(step[key]))):
			return "reach %s must be finite" % key
	var duration := float(step.get("time", DEFAULT_TIME))
	if duration < 0.0 or duration > MAX_TIME:
		return "reach time must be 0..5 seconds"
	if not step.get("release", false):
		var point: Variant = step.get("to")
		if not point is Array or point.size() != 2:
			return "reach to must be a two-number stage point"
		for value: Variant in point:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > MAX_COORDINATE:
				return "reach to must contain finite stage coordinates within ±8192"
	return ""


func configure(step: Dictionary, actor_position := Vector2.ZERO) -> void:
	_binding = null
	_duration = float(step.get("time", DEFAULT_TIME))
	_wanted = 0.0 if step.get("release", false) else 1.0
	if _wanted > 0.0:
		var previous_stage_point := target + actor_position if _actor_space else target
		_actor_space = step.get("space", "stage") == "actor"
		_to_target = Vector2(step["to"][0], step["to"][1])
		_to_angle = float(step.get("angle", 0.0))
		_from_target = (previous_stage_point - actor_position if _actor_space else previous_stage_point) if weight > 0.0 else _to_target
		_from_angle = angle if weight > 0.0 else _to_angle
		_elapsed = 0.0
		target = _from_target
		angle = _from_angle
	else:
		# 路徑走到一半就收手時，從當下接觸點放開，不能繼續追尚未到達的目標。
		_from_target = target
		_to_target = target
		_from_angle = angle
		_to_angle = angle
		_elapsed = 0.0
	_reported = false
	if _duration == 0.0:
		weight = _wanted
		target = _to_target
		angle = _to_angle


func apply(actor: CutsceneActor, delta: float) -> void:
	var parent := actor.get_parent() as Node2D
	if _binding != null:
		var point := _binding.stage_point(parent)
		var direction := _binding.stage_angle(parent)
		if point.is_finite() and is_finite(direction):
			_to_target = point
			_to_angle = direction + _binding_angle if _follow_rotation else _binding_angle
		else:
			_binding = null
			configure({"release": true, "time": DEFAULT_TIME})
			if not _reported:
				push_warning("[CutsceneReach] %s/%s lost its prop contact; returning to original animation" % [actor.actor_id, hand])
				_reported = true
	_elapsed = minf(_duration, _elapsed + delta)
	var progress := smoothstep(0.0, 1.0, _elapsed / maxf(_duration, 0.0001)) if _duration > 0.0 else 1.0
	target = _from_target.lerp(_to_target, progress)
	angle = lerp_angle(_from_angle, _to_angle, progress)
	weight = move_toward(weight, _wanted, delta / maxf(_duration, 0.0001))
	if weight <= 0.0:
		return
	if parent == null or actor.rig == null:
		return
	var direction := parent.global_transform.basis_xform(Vector2.from_angle(angle))
	var stage_point := actor.position + target if _actor_space else target
	if not actor.rig.place_hand(hand, parent.to_global(stage_point), direction.angle(), smoothstep(0.0, 1.0, weight), _contact_offset) and not _reported:
		push_warning("[CutsceneReach] %s/%s cannot reach stage point %s; keeping original arm pose" % [actor.actor_id, hand, stage_point])
		_reported = true


func bind_to(binding: StagePropBinding, angle_offset: float, follow_rotation := false) -> void:
	_binding = binding
	_binding_angle = angle_offset
	_follow_rotation = follow_rotation


func set_contact_offset(value: Variant) -> void:
	_contact_offset = value


func contact_offset() -> Variant:
	return _contact_offset


func active() -> bool:
	return weight > 0.0 or _wanted > 0.0


func settled() -> bool:
	return _wanted == 1.0 and weight >= 1.0 and _elapsed >= _duration


func keep_with_body(actor_position: Vector2) -> void:
	if not _actor_space:
		target -= actor_position
	_actor_space = true
	_binding = null
	_from_target = target
	_to_target = target
	_from_angle = angle
	_to_angle = angle
	_elapsed = _duration
