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


func _init(which: StringName) -> void:
	hand = which


static func problem(step: Dictionary) -> String:
	if not step.get("hand") is String or not HANDS.has(step["hand"]):
		return "reach hand must be front or back"
	if step.has("release") and not step["release"] is bool:
		return "reach release must be boolean"
	if step.has("wait") and not step["wait"] is bool:
		return "reach wait must be boolean"
	if step.get("space", "stage") not in ["stage", "actor"]:
		return "reach space must be stage or actor"
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
	_reported = false
	if _duration == 0.0:
		weight = _wanted
		target = _to_target
		angle = _to_angle


func apply(actor: CutsceneActor, delta: float) -> void:
	_elapsed = minf(_duration, _elapsed + delta)
	var progress := smoothstep(0.0, 1.0, _elapsed / maxf(_duration, 0.0001)) if _duration > 0.0 else 1.0
	target = _from_target.lerp(_to_target, progress)
	angle = lerp_angle(_from_angle, _to_angle, progress)
	weight = move_toward(weight, _wanted, delta / maxf(_duration, 0.0001))
	if weight <= 0.0:
		return
	var parent := actor.get_parent() as Node2D
	if parent == null or actor.rig == null:
		return
	var direction := parent.global_transform.basis_xform(Vector2.from_angle(angle))
	var stage_point := actor.position + target if _actor_space else target
	if not actor.rig.place_hand(hand, parent.to_global(stage_point), direction.angle(), smoothstep(0.0, 1.0, weight)) and not _reported:
		push_warning("[CutsceneReach] %s/%s cannot reach stage point %s; keeping original arm pose" % [actor.actor_id, hand, target])
		_reported = true
