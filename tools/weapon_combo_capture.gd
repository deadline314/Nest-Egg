extends ScenarioBase
## 真實 Level／Player／Forward+；不手設 action_t，按實際三階段各捕獲一格。
const WEAPONS := ["dagger", "blade", "maul", "glaive", "whip"]
const LEGACY := {"dagger": "thrust", "blade": "slash", "maul": "overhead", "glaive": "thrust", "whip": "sweep"}


func _ready() -> void:
	out_dir = "res://pm/Nest-Egg/images"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	print("NE236_RENDERER ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	Story.auto_skip = true
	await open_arena("res://data/lighting/neutral.tres", 12.0)
	var camera := get_viewport().get_camera_2d()
	# LevelCamera 每 physics step 重設 ZOOM，拍摄用镜头先停自動更新。
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE * 3.4
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.position = Vector2(16, 16)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	overlay.add_child(label)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	for quality in [LightQuality.Tier.HIGH, LightQuality.Tier.LOW]:
		Settings.set_light_quality(quality)
		for weapon_id in WEAPONS:
			var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
			for legacy in [true, false]:
				if legacy and quality == LightQuality.Tier.LOW:
					continue
				player._interrupt_melee()
				player.loadout.reset(weapon)
				player._melee_cooldown_left = 0.0
				place_player(12.0)
				camera.global_position = player.global_position + Vector2(30, -32)
				player.facing = 1
				player.aim_dir = Vector2.RIGHT
				await settle(3)
				player._try_melee()
				if legacy:
					# 同一招／時序；僅回放原動作，以直接比較接觸姿勢。
					player._melee_attack["pose"] = LEGACY[weapon_id]
				for phase in [Player.MeleePhase.WINDUP, Player.MeleePhase.ACTIVE, Player.MeleePhase.RECOVERY]:
					var limit := 180
					while player._melee_phase != phase and limit > 0:
						await get_tree().physics_frame
						limit -= 1
					if limit == 0:
						push_error("capture missed phase %s" % phase)
						get_tree().quit(1)
						return
					player.set_physics_process(false)
					label.text = "%s / %s / %s / %s" % [weapon_id, "legacy" if legacy else "weapon pose", ["idle", "windup", "active", "recovery"][phase], LightQuality.NAMES[quality]]
					await settle(3)
					await RenderingServer.frame_post_draw
					capture("NE-236-%s-%s-%s-%s" % [weapon_id, "before" if legacy else "after", phase, "high" if quality == LightQuality.Tier.HIGH else "low"])
					print("NE236_PHASE ", weapon_id, " ", phase, " pose_t=", player.melee_pose_progress(), " hit=", player._melee_landed, " zoom=", camera.zoom)
					player.set_physics_process(true)
				player._interrupt_melee()
	await finish()
	get_tree().quit()
