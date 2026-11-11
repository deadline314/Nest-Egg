extends Node
## CPU checks for the fixture's real stale-rig failure and one-field interventions.
const Probe := preload("res://tools/bg55_enemy_readability_probe.gd")
const Held := preload("res://tools/held_lighting_state.gd")
var _checks := 0
var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[BG55 CPU] FAIL ", message)


func _run() -> void:
	var source := load("res://data/lighting/market.tres") as LightingProfile
	var original := var_to_bytes([source.fog_density, source.enemy_fill_scale, source.ambient_color,
		source.lamp_style.energy, source.rim_energy])
	for factor in ["source", "fill-min", "fill-max", "fog-half", "fog-quarter"]:
		var changed := Probe.variant_profile(source, factor)
		_check(changed != source, factor + " uses a distinct profile")
		_check(changed.ambient_color == source.ambient_color and changed.lamp_style == source.lamp_style
			and changed.rim_energy == source.rim_energy, factor + " preserves ambient, lamps and rim")
		_check(changed.enemy_fill_scale == source.enemy_fill_scale if factor.begins_with("fog-") else changed.fog_density == source.fog_density,
			factor + " changes only its declared factor")
	_check(Probe.variant_profile(source, "unknown") == null, "unknown intervention is rejected")
	_check(original == var_to_bytes([source.fog_density, source.enemy_fill_scale, source.ambient_color,
		source.lamp_style.energy, source.rim_energy]), "original cached market data is unchanged")
	if ResourceLoader.exists("res://data/lighting/market_gate.tres"):
		var local := load("res://data/lighting/market_gate.tres") as LightingProfile
		_check(local.validate().is_empty() and local.id == &"market_gate", "authored local profile validates")
		for name in LightingProfile.BLENDED:
			_check(is_equal_approx(local.enemy_fill_scale, 1.0) if name == &"enemy_fill_scale" else local.get(name) == source.get(name),
				"local profile changes only enemy fill: " + str(name))
		for property in source.lamp_style.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				_check(local.lamp_style.get(property.name) == source.lamp_style.get(property.name), "lamp style unchanged: " + str(property.name))
		_check(Ambience.layers_for(&"market_gate") == Ambience.layers_for(&"market"), "real ambience owner preserves all layers and volumes")
		var audio_alias: Array = Ambience._profiles["market_gate"]
		Ambience._profiles.erase("market_gate")
		_check(Ambience.layers_for(&"market_gate") != Ambience.layers_for(&"market"), "negative control: missing ambience alias loses the soundscape")
		Ambience._profiles["market_gate"] = audio_alias
		var music_alias: Dictionary = Music._map["zones"]["market_gate"]
		for state in Music.STATES:
			_check(Music.resolve_cue(&"ch2_market_gate", &"market_gate", state) == Music.resolve_cue(&"ch2_market_gate", &"market", state), "real music owner preserves " + str(state))
			_check(Music.resolve_cue(&"", &"market_gate", state) == Music.resolve_cue(&"", &"market", state), "zone-only music owner preserves " + str(state))
		Music._map["zones"].erase("market_gate")
		_check(Music.resolve_cue(&"", &"market_gate", &"calm") != Music.resolve_cue(&"", &"market", &"calm"), "negative control: missing zone alias changes cue without a level override")
		Music._map["zones"]["market_gate"] = music_alias
	_check(Probe.bytes_sha("abc".to_utf8_buffer()) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "raw SHA has an independent known answer")
	var layout := LevelLayout.new()
	layout.width = 1
	layout.height = 24
	for row in 24: layout.rows.append("=" if row == 14 else ("#" if row >= 20 else "."))
	_check(is_equal_approx(layout.floor_below(0, 13), 224.0), "negative control: legacy search stops at an unusably high platform")
	_check(is_equal_approx(Probe.visible_floor(layout, 0, Rect2(0, 172.5, 333.333, 187.5)), 320.0), "continue to the visible ground below that platform")
	_check(not is_finite(Probe.visible_floor(layout, 0, Rect2(0, 0, 333.333, 187.5))), "sky-only view has no invented standable actor")
	var old_fill := LightKit.enemy_fill
	var old_cap := LightKit.enemy_light_cap
	var rig := CharacterRig.new()
	rig.use_enemy_fill = true
	add_child(rig)
	_check(rig.setup("collector_gunner"), "actual market enemy skin loads")
	LightKit.enemy_fill = 1.0
	LightKit.enemy_light_cap = 0.25
	Probe.sync_rig(rig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var pose: Array[String] = []
	for part in rig._parts: pose.append(str(part.global_transform))
	LightKit.enemy_fill = 2.0
	LightKit.enemy_light_cap = 0.6
	_check(is_equal_approx(rig._fill, 1.0) and is_equal_approx(rig._light_cap, 0.25), "negative control: frozen rig retains stale fill and cap")
	Probe.sync_rig(rig)
	_check(is_equal_approx(rig._fill, 2.0) and is_equal_approx(rig._light_cap, 0.6), "sync applies actual fill and cap to frozen rig")
	_check(is_equal_approx(float(rig._light_material.get_shader_parameter("fill")), 2.0), "actual lighting material receives fill")
	var after_pose: Array[String] = []
	for part in rig._parts: after_pose.append(str(part.global_transform))
	_check(pose == after_pose, "lighting sync preserves the actual drawable pose")
	var beam := WeaponLight.new()
	beam.top_level = true
	add_child(beam)
	beam.configure(load("res://data/weapons/pistol.tres") as WeaponData)
	beam.set_active(true)
	beam.aim(Vector2(40, 100), Vector2.RIGHT, 1.0, 1.0)
	_check(beam.is_lit(), "actual pistol weapon light is on")
	var moved_origin := Vector2(472, 290)
	_check(beam.global_position.distance_to(moved_origin) > 400.0, "negative control: top-level beam stays at the old origin")
	beam.aim(moved_origin, Vector2.RIGHT, 1.0, 0.0)
	_check(beam.global_position == moved_origin and is_equal_approx(beam._level, 1.0), "zero-time real owner aim synchronizes beam without advancing fade")
	beam.queue_free()
	var quality_before := Settings.get_light_quality()
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	add_child(viewport)
	var stage := Node2D.new()
	viewport.add_child(stage)
	var budget := LightBudget.new()
	stage.add_child(budget)
	var lamps: Array[PointLight2D] = []
	for x in [50.0, 2000.0]:
		var lamp := PointLight2D.new()
		lamp.position = Vector2(x, 90)
		lamp.texture_scale = 0.1
		lamp.add_to_group(LightKit.SCENE_LIGHTS)
		stage.add_child(lamp)
		lamps.append(lamp)
	var wall := WallShadows.new()
	wall.setup([Rect2(0, 0, 2400, 180)])
	stage.add_child(wall)
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	Held.sync_owners(budget, [wall])
	_check(lamps[0].visible and not lamps[1].visible, "budget selects the initial real viewport")
	var old_caster_transform := wall._viewport.canvas_transform
	viewport.canvas_transform = Transform2D(0.0, Vector2(-1900, 0))
	_check(lamps[0].visible and not lamps[1].visible, "negative control: frozen budget retains off-camera lights")
	_check(wall._viewport.canvas_transform == old_caster_transform, "negative control: frozen silhouette retains the old camera")
	Held.sync_owners(budget, [wall])
	_check(not lamps[0].visible and lamps[1].visible and budget.active_lights == 1, "owner sync selects lights at the new camera")
	var expected := Transform2D(0.0, Vector2.ONE * WallShadows.RESOLUTION, 0.0, Vector2.ZERO) * viewport.get_final_transform() * viewport.canvas_transform
	_check(wall._viewport.canvas_transform.is_equal_approx(expected), "actual silhouette owner adopts the new camera transform")
	_check(wall._since_scan == 0.0 and wall._frame == WallShadows.REDRAW_EVERY, "real owner rescan and redraw execute without advancing time")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	_check(not wall.is_enabled(), "authored low quality disables wall silhouettes")
	Held.sync_owners(budget, [wall])
	_check(not wall.is_enabled(), "held sync preserves low-quality wall-shadow policy")
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = Layers.SOLID
	var floor_shape := CollisionShape2D.new()
	var support_box := RectangleShape2D.new()
	support_box.size = Vector2(320, 16)
	floor_shape.shape = support_box
	floor_shape.position = Vector2(160, 188)
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	var body := CharacterBody2D.new()
	body.collision_layer = Layers.PLAYER
	body.collision_mask = Layers.SOLID
	var body_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Player.BODY_SIZE
	body_shape.shape = shape
	body_shape.position = Vector2(0, -Player.BODY_SIZE.y * 0.5)
	body.add_child(body_shape)
	body.position = Vector2(50, 178)
	stage.add_child(body)
	_check(not PhysicsServer2D.body_get_space(body.get_rid()).is_valid(), "negative control: disabled parent removes default body from physics space")
	Held.preserve_physics_bodies(stage)
	for _tick in 2: await get_tree().physics_frame
	var floating := Probe.ground_support(body)
	_check(floating.found and is_equal_approx(floating.gap, 2.0), "negative control: floor-minus-two held actor really floats two pixels")
	var contact := body.move_and_collide(Vector2.DOWN * 4, false, body.safe_margin)
	var grounded := Probe.ground_support(body)
	_check(contact != null and contact.get_normal().dot(Vector2.UP) > 0.99, "actual collision solver reaches the support top")
	_check(grounded.found and absf(grounded.gap) <= body.safe_margin + 0.001, "actual feet stop within authored collision safe margin")
	_check(grounded.found and is_equal_approx(grounded.get("floor", [0, 0])[1], 180.0), "independent support ray hits the known 180-pixel floor")
	var shadow := ContactShadow.attach(body, 10.0)
	shadow.process_mode = Node.PROCESS_MODE_ALWAYS
	lamps[0].position = Vector2(10, 100)
	lamps[0].visible = true
	for ray in shadow._rays: ray.force_raycast_update()
	shadow._light_timer = 100.0
	shadow._physics_process(0.0)
	_check(shadow.is_cast() and absf(shadow.world_rect().position.y - 178.0) < 0.001, "actual contact shadow still finds the preserved support")
	_check(is_zero_approx(shadow._shift), "negative control: held nearest-light cache retains its old shift")
	Held.sync_contact_shadows(stage)
	_check(shadow._shift > 0.0 and is_equal_approx(shadow._light_timer, ContactShadow.LIGHT_REFRESH), "actual contact-shadow owner refreshes the correct light without time advancement")
	viewport.queue_free()
	Settings.set_light_quality(quality_before)
	LightKit.enemy_fill = old_fill
	LightKit.enemy_light_cap = old_cap
	rig.queue_free()
	await get_tree().process_frame
	await AudioRelease.settle(get_tree())
	print("BG55_CPU checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
