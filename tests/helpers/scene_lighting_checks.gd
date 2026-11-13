extends RefCounted
## BG-57: real factories, texture states and quality lifecycle, without claiming GPU pixels.


static func run(suite: TestSuite) -> void:
	var pickup := HealthPickup.new()
	suite.runner.add_child(pickup)
	pickup.set_process(false)
	_check_surfaces(suite, pickup, "pickup")
	suite.check(pickup.get_child(1) is WorldPrompt, "pickup material split preserves the existing prompt child")
	pickup.free()
	for path: String in ["res://data/throwables/pipe.tres", "res://data/throwables/concrete_chunk.tres", "res://data/throwables/crate_small.tres", "res://data/throwables/fuel_barrel.tres"]:
		var prop := Throwable.new()
		prop.configure(load(path) as ThrowableData)
		suite.runner.add_child(prop)
		prop.set_physics_process(false)
		_check_surfaces(suite, prop, path)
		var destructible := prop.data.max_health > 0
		var expected_destructible := path in ["res://data/throwables/crate_small.tres", "res://data/throwables/fuel_barrel.tres"]
		suite.check(prop.state == Throwable.State.REST and destructible == expected_destructible and (prop.health != null) == destructible and (prop.hurtbox != null) == destructible, "throwable lighting preserves data-defined gameplay components: " + path)
		if prop._body_art != null:
			suite.check(prop._body_art.material == null and not prop._body_art.use_parent_material, "fixture art remains a separate lit body: " + path)
		prop.free()
	var vehicle := Vehicle.new()
	vehicle.configure(load("res://data/vehicles/bulwark.tres") as VehicleData)
	suite.runner.add_child(vehicle)
	vehicle.set_physics_process(false)
	_check_surfaces(suite, vehicle, "legacy vehicle")
	suite.check(vehicle.can_mount() and vehicle.health != null and vehicle.hurtbox != null, "legacy vehicle retains mounting, health and hurtbox")
	vehicle.free()
	_test_stage_textures(suite)
	await _test_quality(suite)
	await _test_stage_canvas(suite)
	await _test_stage_ui(suite)


static func _check_surfaces(suite: TestSuite, body: Node2D, label: String) -> void:
	suite.check(body.material == null and not body.use_parent_material, label + " reflective body uses ordinary canvas lighting")
	var emission := body.get_node_or_null("Emission") as CanvasItem
	suite.check(emission != null and emission.material == LightKit.emissive_material() and not emission.use_parent_material, label + " warnings and glow use a distinct unshaded canvas")


static func _test_stage_textures(suite: TestSuite) -> void:
	var quality := Settings.get_light_quality()
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	var base := "res://art/environment/scene_props/dawn_noodle_stall/dawn_noodle_stall__noodle_bowls_table.png"
	var empty := "res://art/environment/scene_props/dawn_noodle_stall/dawn_noodle_stall__noodle_table_empty.png"
	var definition := {"kind": "sprite", "id": "table", "path": base, "pos": [0, 0], "source_width": 304, "scale": 0.5, "states": {"eaten": {"path": empty}}}
	var prop := StageLayers.create(definition, "BG57 table") as StageLayers._Sprite
	suite.check(prop != null and prop.texture is CanvasTexture and (prop.texture as CanvasTexture).normal_texture != null, "stage physical base loads the existing normal")
	if prop != null:
		var width := prop.texture.get_width() * prop.scale.x
		var changed := prop.set_prop_state("eaten")
		suite.check(changed and prop.texture is CanvasTexture and (prop.texture as CanvasTexture).normal_texture.resource_path == empty.get_basename() + "_n.png", "stage state swaps diffuse and its matching normal together")
		suite.check(is_equal_approx(prop.texture.get_width() * prop.scale.x, width) and prop.material == null, "stage state preserves source width and reflective material")
		prop.free()
	var backdrop := StageLayers.create({"kind": "sprite", "path": "res://art/environment/scenes/pawnshop_kitchen_contacts.png", "pos": [0, 0]}, "BG57 baked") as Sprite2D
	suite.check(backdrop != null and not backdrop.texture is CanvasTexture and backdrop.material == LightKit.emissive_material(), "complete baked backplate keeps its original appearance even when a normal file exists")
	if backdrop != null:
		backdrop.free()
	suite.check(not StageLayers.prop_state_problem({"kind": "sprite", "path": base, "lighting": "unknown"}).is_empty(), "unknown stage lighting role is rejected")
	suite.check(not StageLayers.prop_state_problem({"kind": "sprite", "path": base, "life": true}).is_empty(), "physical stage body cannot become an unshaded window-life layer")
	Settings.set_light_quality(quality)


static func _test_quality(suite: TestSuite) -> void:
	var previous := Settings.get_light_quality()
	var storage := Settings.storage_path()
	var path := "res://art/environment/scene_props/dawn_noodle_stall/dawn_noodle_stall__noodle_bowls_table.png"
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	var texture := LitTextures.load_texture(path) as CanvasTexture
	suite.check(texture != null and texture.normal_texture != null, "normal quality control starts with a real cached normal")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	suite.check(not LitTextures.is_enabled() and texture != null and texture.normal_texture == null, "LOW applies to cached textures without any live Level")
	var controller := LightingController.new()
	controller._on_exiting()
	controller.free()
	suite.check(not LitTextures.is_enabled() and texture.normal_texture == null, "leaving LOW Level cannot silently restore HIGH normals")
	var cold := LitTextures.load_texture("res://art/environment/scene_props/pawnshop_kitchen_contacts/kettle_atlas.png") as CanvasTexture
	suite.check(cold != null and cold.normal_texture == null, "textures loaded after LOW Level exit stay LOW")
	var fixture := "user://bg57-light-quality.cfg"
	var config := ConfigFile.new()
	config.set_value("display", "light_quality", LightQuality.Tier.LOW)
	suite.check(config.save(fixture) == OK, "quality reload fixture is written")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Settings.use_storage(fixture)
	suite.check(Settings.get_light_quality() == LightQuality.Tier.LOW and not LitTextures.is_enabled() and texture.normal_texture == null, "loading stored LOW synchronizes normals before a Level is built")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	suite.check(LitTextures.load_texture(path) == texture and texture.normal_texture != null and cold.normal_texture != null, "HIGH restores the same cached textures and both normals")
	Settings.use_storage(storage)
	Settings.set_light_quality(previous)
	DirAccess.remove_absolute(fixture)
	await suite.frames(1)


static func _test_stage_canvas(suite: TestSuite) -> void:
	suite.check(not StageLibrary.lighting_problems({"lights": [{"pos": [0, 0], "color": "#ffffff", "radius": 100, "energy": 4.0}]}).is_empty(), "stage local light rejects an excessive energy")
	suite.check(not StageLibrary.lighting_problems({"ambient": 1.0}).is_empty(), "stage local lighting rejects a malformed ambient")
	var layer := CanvasLayer.new()
	layer.layer = UiLayers.CUTSCENE
	suite.runner.add_child(layer)
	var stage := StageLibrary.Stage.new()
	stage.configure_lighting({"ambient": "#666666", "lights": [{"pos": [50, 40], "radius": 100, "energy": 0.2, "color": "#ffe0bc"}]})
	layer.add_child(stage)
	await suite.frames(1)
	suite.check(stage._ambient != null and stage._ambient.color == Color("666666"), "stage uses its explicit local ambient")
	suite.check(stage._local_lights.size() == 1 and stage._local_lights[0].range_layer_min == UiLayers.CUTSCENE and stage._local_lights[0].range_layer_max == UiLayers.CUTSCENE, "stage point light is restricted to its actual independent canvas layer")
	suite.check(not stage._local_lights[0].is_in_group(LightKit.SCENE_LIGHTS), "stage light never joins the gameplay light budget")
	var old_fill := LightKit.character_fill
	var old_cap := LightKit.character_light_cap
	LightKit.character_fill = 4.0
	LightKit.character_light_cap = 0.3
	for setup_first in [true, false]:
		var actor := CutsceneActor.new()
		if setup_first:
			actor.setup(&"stage_light_control", "rin", "", 1.0, "")
		stage.actors.add_child(actor)
		if not setup_first:
			actor.setup(&"stage_light_control", "rin", "", 1.0, "")
		actor.set_process(false)
		actor._process(1.0 / 60.0)
		suite.check(is_equal_approx(actor.rig._fill, 1.0) and is_equal_approx(actor.rig._light_cap, LightKit.character_light_cap_for(LightKit.luminance(stage._ambient.color), 1.0)), "stage actor shares its own canvas ambient whether setup occurs before or after entering")
		suite.check(is_equal_approx(LightKit.character_fill, 4.0) and is_equal_approx(LightKit.character_light_cap, 0.3), "stage context never changes global world fill/cap")
		actor.free()
	LightKit.character_fill = old_fill
	LightKit.character_light_cap = old_cap
	layer.free()
	var plain := StageLibrary.build(&"ch1_pawnshop_kitchen")
	suite.check(plain._local_lights.is_empty() and plain._ambient == null, "decorative stage glow does not silently become a light or change ambient")
	plain.free()


static func _test_stage_ui(suite: TestSuite) -> void:
	var movie := CutscenePlayer.new()
	suite.runner.add_child(movie)
	movie._overlay_mode = true
	movie._build_ui()
	var text := movie._dialogue._text
	var original_color := text.get_theme_color(&"font_color")
	var noise_material := movie._noise.material
	var physical := StageLibrary.Stage.new()
	physical.configure_lighting({"ambient": "#666666"})
	movie._stage_holder.add_child(physical)
	var body := StageLayers.create({"kind": "sprite", "path": "res://art/environment/scene_props/pawnshop_kitchen_contacts/kettle_atlas.png", "pos": [100, 100]}, "UI isolation physical control") as Sprite2D
	physical.add_layer(body)
	movie._isolate_ui_lighting(movie._root)
	suite.check(text.material == LightKit.emissive_material() and movie._dialogue._portrait.material == LightKit.emissive_material(), "dark stage keeps dialogue text and portrait independent of scene lighting")
	suite.check(movie._center_text.material == LightKit.emissive_material() and movie._skip_hint.material == LightKit.emissive_material() and movie._fade.material == LightKit.emissive_material(), "title, skip hint and screen overlay retain their UI light context")
	suite.check(body.material == null and movie._stage_holder.material == null and physical.actors.material == null, "UI isolation never marks the stage holder or physical branch emissive")
	suite.check(movie._noise.material == noise_material, "UI isolation preserves the existing foreign FX shader")
	# Undo only this UI material as the explicit old-route negative, then restore it.
	text.material = null
	suite.check(text.material == null and physical._ambient.color == Color("666666"), "negative retains an ordinary dialogue surface under the same dark canvas")
	movie._isolate_ui_lighting(movie._root)
	physical._ambient.color = Color.WHITE
	suite.check(text.material == LightKit.emissive_material() and text.get_theme_color(&"font_color") == original_color, "white ambient preserves authored UI color and the same unshaded contract")
	physical._ambient.color = Color("666666")
	var mouse_mode := Input.mouse_mode
	movie._running = true
	movie._do_choice({"text": "請選擇材質對照。", "default": "stay", "options": [{"id": "stay", "text": "保留原場景。", "explanation": "這個樣本不提交任何結果。"}]})
	await suite.frames(2)
	var isolated := movie._choice != null and movie._choice.material == LightKit.emissive_material()
	if movie._choice != null:
		for node: Node in movie._choice.get_children():
			isolated = isolated and (node is CanvasItem and node.material == LightKit.emissive_material())
	suite.check(isolated, "late choice prompt, button and explanation receive UI isolation when actually built")
	movie._running = false
	await suite.frames(2)
	Input.mouse_mode = mouse_mode
	movie.free()
