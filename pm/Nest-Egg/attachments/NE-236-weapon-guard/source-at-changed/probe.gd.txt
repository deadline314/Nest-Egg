extends "res://tests/smoke_test.gd"
## Uses the same strict assertions as the normal MeleeWeaponsSuite; no product
## replacement. All input is synthetic and the projectile runs in real physics.


func _run() -> void:
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	var high := OS.get_cmdline_user_args().has("--guard-quality=high")
	Settings.set_light_quality(LightQuality.Tier.HIGH if high else LightQuality.Tier.LOW)
	Settings.set_feel_scale("shake", 0.0)
	Settings.set_feel_scale("particles", 0.25)
	Settings.set_reduce_flashes(true)
	print("NE236_GUARD_SETTINGS ", JSON.stringify({"quality":"high" if high else "low", "particles":0.25, "shake":0.0,
		"reduce_flashes":true, "synthetic_input":true, "renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name()}))
	await MeleeWeaponsSuite.new(self)._test_weapon_guard_transition()
	AimInput.using_gamepad = false
	await _finish()
