extends ScenarioBase
## NE-67: real chapter map and PropNode integration, preview only; permanent placement belongs to Session 3.
func run() -> void:
	var quality := Settings.get_light_quality()
	Settings.set_light_quality(LightQuality.Tier.LOW)
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load("res://data/levels/level_01.tres") as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	await clear_enemies()
	player.global_position = Vector2(115 * 16.0 + 8.0, level._layout.floor_below(115, 4) - 2.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	capture("asset_before")
	var data := PropLibrary.find(&"kenney_sedge")
	assert(data != null and data.validate().is_empty())
	for index in 3:
		var prop := PropNode.new()
		prop.setup(data, Vector2(player.global_position.x + (2 + index * 2) * 16.0 - data.size.x / 2.0, player.global_position.y - data.size.y))
		level._entities.add_child(prop)
	await wait(0.8)
	capture("asset_after_low")
	Settings.set_light_quality(LightQuality.Tier.MEDIUM)
	await wait(0.8)
	capture("asset_after_medium")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	await wait(0.8)
	capture("asset_after_high")
	var image := (load(data.texture) as Texture2D).get_image()
	print("ASSET_IN_GAME id=%s logical=%s imported=%s mipmaps=%s bytes=%d instances=3" % [data.id, data.size, image.get_size(), image.has_mipmaps(), image.get_data_size()])
	Settings.set_light_quality(quality)
	await finish()
