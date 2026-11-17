extends Node
var checks := 0
var failures := 0
func _ready() -> void:
	_run.call_deferred()
func _check(value: bool, message: String) -> void:
	checks += 1
	failures += int(not value)
	print("NE259_ANCHOR:", "PASS" if value else "FAIL", ":", message)
func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
func _end_level(level: Level) -> void:
	level.queue_free()
	await _frames(6)
func _run() -> void:
	Enemy.activation_culling_enabled = false
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var suite := EnvironmentSuite.new(self)
	await suite._test_enemy_glow()
	suite = null
	await AudioRelease.settle(get_tree())
	print("NE259_ANCHOR_RESULT:", checks, "/", failures)
	get_tree().quit(1 if failures else 0)
