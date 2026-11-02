extends MeleeCommandInput
## Only frame-script parity uses simulation time. Real-expiry/hitstop tests use
## the original wall clock; physical devices and wall-time latency remain separate.
func _now_msec() -> int:
	return int(Engine.get_physics_frames() * 1000.0 / Engine.physics_ticks_per_second)
