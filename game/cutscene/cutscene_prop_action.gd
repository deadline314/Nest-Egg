class_name CutscenePropAction
extends RefCounted
## 道具指令的有限資料契約；不接受任意節點路徑、屬性或回呼。

const FIELDS := {
	"prop_move": ["do", "id", "to", "angle", "time", "wait"],
	"prop_hold": ["do", "id", "actor", "hand", "point", "follow_rotation"],
	"prop_release": ["do", "id"],
	"prop_visible": ["do", "id", "visible"],
}
const DEFAULT_TIME := 0.35


static func problem(step: Dictionary) -> String:
	var kind := str(step.get("do", ""))
	if not FIELDS.has(kind):
		return "unknown prop action"
	for key: Variant in step:
		if not key is String or not FIELDS[kind].has(key):
			return "unexpected prop action field: %s" % str(key)
	if not identifier(step.get("id")):
		return "prop action requires a named stage prop"
	match kind:
		"prop_move":
			if not step.has("to") and not step.has("angle"):
				return "prop_move requires to or angle"
			if step.has("to") and not point(step["to"]):
				return "prop_move to requires two finite stage coordinates"
			if step.has("angle") and not angle(step["angle"]):
				return "prop angle must be finite and within eight turns"
			var duration: Variant = step.get("time", DEFAULT_TIME)
			if not number(duration) or float(duration) < 0.0 or float(duration) > 5.0:
				return "prop_move time must be within 0..5 seconds"
			if step.has("wait") and not step["wait"] is bool:
				return "prop_move wait must be boolean"
		"prop_hold":
			if step.has("follow_rotation") and not step["follow_rotation"] is bool:
				return "prop_hold follow_rotation must be boolean"
			if not identifier(step.get("actor")) or not step.get("hand") is String or not CutsceneReach.HANDS.has(step["hand"]):
				return "prop_hold requires a named actor and front or back hand"
			if not point(step.get("point"), true):
				return "prop_hold requires two finite prop-source pixels"
		"prop_visible":
			if not step.get("visible") is bool:
				return "prop_visible visible must be boolean"
	return ""


static func initial_problem(props: Variant) -> String:
	if not props is Dictionary or props.size() > 8:
		return "scene props must contain at most eight named records"
	for id: Variant in props:
		if not identifier(id):
			return "scene prop id must be a valid identifier"
		var record: Variant = props[id]
		if not record is Dictionary or record.is_empty():
			return "scene prop %s requires a nonempty record" % id
		for key: Variant in record:
			if key not in ["pos", "angle", "visible", "state"]:
				return "scene prop %s contains an unsupported field: %s" % [id, str(key)]
		if record.has("pos") and not point(record["pos"]):
			return "scene prop %s pos requires two finite coordinates" % id
		if record.has("angle") and not angle(record["angle"]):
			return "scene prop %s angle is invalid" % id
		if record.has("visible") and not record["visible"] is bool:
			return "scene prop %s visible must be boolean" % id
		if record.has("state") and not identifier(record["state"]):
			return "scene prop %s state requires a valid identifier" % id
	return ""


static func identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 64 and value.is_valid_identifier()


static func number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func angle(value: Variant) -> bool:
	return number(value) and absf(float(value)) <= TAU * 8.0


static func point(value: Variant, nonnegative := false) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for coordinate: Variant in value:
		if not number(coordinate) or absf(float(coordinate)) > 8192.0 or (nonnegative and float(coordinate) < 0.0):
			return false
	return true
