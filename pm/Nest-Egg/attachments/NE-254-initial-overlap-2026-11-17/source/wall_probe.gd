extends "res://tests/smoke_test.gd"
func _run() -> void:
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	await ThrowablesSuite.new(self)._test_initial_overlap_wall()
	await _finish()
