extends ScenarioBase
## Native Forward+ pickup readability in implemented chapter environments.
## --out=<absolute directory> --label=before|after

var label := "after"
var ticket := "NE-226"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
		elif arg.begins_with("--ticket="):
			ticket = arg.trim_prefix("--ticket=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _run() -> void:
	var original_quality := Settings.get_light_quality()
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	for scene in ["ch1_street", "ch1_street_bright", "level_02"]:
		for quality in [LightQuality.Tier.LOW, LightQuality.Tier.HIGH]:
			Settings.set_light_quality(quality)
			GameState.start_new_run(GameState.difficulties[1])
			for id: String in Story.scene_ids():
				Story._seen[StringName(id)] = true
			var source: String = "ch1_street" if scene == "ch1_street_bright" else scene
			var data: LevelData = (load("res://data/levels/%s.tres" % source) as LevelData).duplicate()
			if scene == "ch1_street_bright":
				var zone := LightingZone.new()
				zone.start_tile = 0
				zone.profile = load("res://data/lighting/neutral.tres")
				var zones: Array[LightingZone] = [zone]
				data.lighting_zones = zones
			data.show_chapter_card = false
			data.intro_scene = &""
			data.complete_after_intro = false
			data.after_intro_portal = &""
			level = Level.new()
			level.configure(data)
			add_child(level)
			await settle(25)
			player = level.player
			player.health.setup(999, 0.0)
			level.hud.visible = false
			for entity in level._entities.get_children():
				if entity is HintSign:
					entity.queue_free()
			await clear_enemies()
			var tile := 52 if source == "ch1_street" else 12
			var floor_y := level._layout.floor_below(tile, 16)
			player.global_position = Vector2(tile * 16.0, floor_y)
			player.velocity = Vector2.ZERO
			player.set_physics_process(false)
			player.facing = 1
			player.aim_dir = Vector2.RIGHT
			AimInput.using_gamepad = true
			AimInput._last_stick_dir = Vector2.RIGHT
			snap_camera()
			var credit := CreditPickup.new()
			var injector := ConsumablePickup.new()
			injector.configure(load("res://data/consumables/med_injector.tres"))
			var doc := CollectiblePickup.new()
			doc.configure(load("res://data/story_items/doc_shaft_memo.tres"))
			var recording := CollectiblePickup.new()
			recording.configure(load("res://data/story_items/rec_wataru_1.tres"))
			var health := HealthPickup.new()
			var gun := WeaponPickup.new()
			gun.configure(load("res://data/weapons/rifle.tres"))
			var glaive := WeaponPickup.new()
			glaive.configure(load("res://data/weapons/melee/melee_glaive.tres"))
			var items: Array[Pickup] = [credit, injector, doc, recording, health, gun, glaive]
			for i in items.size():
				var item := items[i]
				item.position = Vector2((tile + 2 + i * 2) * 16.0, floor_y)
				level._entities.add_child(item)
				item._glint_offset = 1.0
			await settle(40)
			for entity in level._entities.get_children():
				if entity is HintSign:
					entity.queue_free()
			for item in items:
				item.set_process(false)
				item._time = 0.0
				item.queue_redraw()
			await settle(2)
			capture("%s-%s-%s-%s" % [ticket, label, scene, "low" if quality == LightQuality.Tier.LOW else "high"])
			await finish()
	Settings.set_light_quality(original_quality)
	AimInput.using_gamepad = false
	get_tree().quit()
