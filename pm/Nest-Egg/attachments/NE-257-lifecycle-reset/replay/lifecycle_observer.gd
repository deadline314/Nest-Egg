extends "res://tests/suite/test_protagonist_motion.gd"
## Observe the actual lifecycle regression; do not duplicate or replace its actions.
var captured_states: Array[Dictionary] = []
var last_animator: HumanoidAnimator

func snapshot_springs(animator: HumanoidAnimator, kind: String) -> Dictionary:
	var max_velocity := 0.0
	var max_deviation := 0.0
	var states := {}
	for spring in animator._springs:
		var key := animator._spring_key(spring)
		var neutral := clampf(float(spring.get("rest", 0.0)), float(spring.get("min", HumanoidAnimator.SPRING_MIN)), float(spring.get("max", HumanoidAnimator.SPRING_MAX)))
		var velocity := float(animator._spring_velocity[key])
		var angle := float(animator._spring_angle[key])
		max_velocity = maxf(max_velocity, absf(velocity))
		max_deviation = maxf(max_deviation, absf(angle - neutral))
		states[str(key)] = {"angle": angle, "neutral": neutral, "velocity": velocity}
	return {"kind": kind, "milliseconds": Time.get_ticks_msec(), "max_velocity_rad_s": max_velocity, "max_deviation_rad": max_deviation, "states": states}

func _prime_secondary_motion(rig: CharacterRig) -> HumanoidAnimator:
	last_animator = super._prime_secondary_motion(rig)
	captured_states.append(snapshot_springs(last_animator, "before"))
	return last_animator

func _secondary_is_rest(animator: HumanoidAnimator) -> bool:
	captured_states.append(snapshot_springs(animator, "after"))
	return super._secondary_is_rest(animator)
