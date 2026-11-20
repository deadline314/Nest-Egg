extends "res://tools/melee_art_probe.gd"

var _current: Dictionary = {}

func _run() -> void:
	Story.auto_skip = true
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	await open_arena("res://data/lighting/warehouse_interior.tres", 12.0)
	var camera := get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 3.4
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	level.hud.visible = false
	for id: String in WEAPONS:
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % id) as WeaponData
		var records: Dictionary = {}
		for mode in [["normal",false,false],["motion",false,true],["flashes",true,false],["both",true,true]]:
			Settings.set_reduce_flashes(mode[1])
			Settings.set_reduce_ui_motion(mode[2])
			await _arm(weapon, camera)
			await settle(30)
			var result := await _sample_strike(id, mode[0])
			records[mode[0]] = result
		_current[id] = records
		var base: Dictionary = records["normal"]
		for mode: String in ["motion","flashes","both"]:
			var item: Dictionary = records[mode]
			if item["physics_samples"] != base["physics_samples"] or item["first_active"] != base["first_active"] or item["pose"] != base["pose"] or item["maximum_grip_error"] > 0.01 or not item["ok"]:
				push_error("[GripSettings] %s %s altered the active strike or failed the palm check" % [id, mode])
				_failures += 1
		if not base["ok"] or base["maximum_grip_error"] > 0.01 or absf(base["peak_light"] - records["motion"]["peak_light"]) > 0.01 or records["flashes"]["peak_light"] >= base["peak_light"] * 0.95 or records["both"]["peak_light"] >= base["peak_light"] * 0.95:
			push_error("[GripSettings] %s does not preserve the normal/reduced flash light response" % id)
			_failures += 1
	var result := {"weapons": _current, "adapter": RenderingServer.get_video_adapter_name(), "failures": _failures}
	FileAccess.open(out_dir.path_join("current-settings.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("NE275_CURRENT_SETTINGS tools failures=", _failures)
	await finish()
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if _failures == 0 else 1)

func _sample_strike(id: String, mode: String) -> Dictionary:
	var blade := player.find_child("BladeLight", true, false) as BladeLight
	var frames := 0
	var first := -1
	var maximum := 0.0
	var peak := 0.0
	var pose := ""
	var accepted := player._try_melee()
	if accepted and blade != null:
		for i in 240:
			await get_tree().physics_frame
			if player._melee_phase == Player.MeleePhase.NONE:
				break
			frames += 1
			var rig := player._visual.rig
			var palm := rig.bone(&"hand_front").global_transform * rig.hand_grip_offset(&"hand_front")
			maximum = maxf(maximum,palm.distance_to(player._visual.melee_hold().origin))
			if player._melee_phase == Player.MeleePhase.ACTIVE:
				peak = maxf(peak, blade.energy())
				if first < 0:
					first = i
					pose = player.melee_pose()
					await RenderingServer.frame_post_draw
					if mode in ["normal","both"]:
						capture("%s-%s" % [id,mode])
	return {"ok": accepted and first>=0 and frames<240 and not pose.is_empty() and peak>0.0,
		"physics_samples":frames,"first_active":first,"pose":pose,"maximum_grip_error":maximum,"peak_light":peak}
