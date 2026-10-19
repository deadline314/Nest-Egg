extends "res://tools/screenshot.gd"
## BG-47: arranged props lab, actual projectiles/power interaction and original physics.
## Copies unchanged to the pre-fix checkout for the negative control.

var _checks := 0
var _failures := 0
var _shots: Array[Dictionary] = []
var _caption: Label


func _ready() -> void:
	Settings.use_storage("user://fixture_states_settings.cfg")
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(12, 12)
	_caption.add_theme_font_size_override("font_size", 13)
	layer.add_child(_caption)
	super._ready()


func _run() -> void:
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	var data := PropsSuite.level_data()
	var zone := LightingZone.new()
	zone.profile = load("res://data/lighting/facility.tres")
	data.lighting_zones = [zone]
	data.show_chapter_card = false
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _settle(20)
	level.player.health.setup(999, 0.0)
	level.hud.visible = false
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_set_scripted_aim(level.player, true)
	for spec: Array in [[10, "crate", "breakable_crate"], [30, "glass", "breakable_glass"], [20, "barrel", "breakable_barrel"]]:
		var body := _prop_at(level, Breakable, spec[0]) as Breakable
		level.player.global_position = body.global_position + Vector2(-60, -2)
		level_camera_snap()
		await _settle(4)
		_check(body.find_child("Art_" + spec[2], true, false) != null, "%s has a formal body" % spec[1])
		await _photo(spec[1] + "-intact", level)
		var hits := 2 if spec[1] == "glass" else 1
		for hit in hits:
			await _shoot(body, level)
		_check(not body.is_broken and body.health.ratio() < 0.7, "%s is actually damaged and still blocks" % spec[1])
		await _wait(0.18)
		await _photo(spec[1] + "-damaged", level)
		while not body.is_broken:
			if not await _shoot(body, level):
				break
		await get_tree().process_frame
		await _photo(spec[1] + "-broken", level)
		_check(body.is_broken and not body.visible and body.hurtbox.enabled == false, "%s stops blocking after real destruction" % spec[1])
		await _wait(0.8)
	var lift := _prop_at(level, Lift, 50) as Lift
	level.player.global_position = lift.global_position + Vector2(0, -2)
	var rail_position: Vector2 = lift._rails.global_position
	for frame in 180:
		await get_tree().physics_frame
		if lift._phase == Lift.Phase.UP and lift.position.y < lift._start_y - 10:
			break
	level_camera_snap()
	await _photo("lift-riding", level)
	_check(lift.find_child("Art_lift_deck", true, false) != null and lift._rails.find_child("Art_lift_rail", true, false) != null,
		"the moving deck and stationary rails have formal art")
	_check(lift._rails.global_position == rail_position, "rails remain fixed while the platform moves")
	var power := _prop_at(level, PowerSwitch, 56) as PowerSwitch
	level.player.global_position = power.global_position + Vector2(-20, -2)
	level_camera_snap()
	await _settle(4)
	await _photo("power-supplied", level)
	Input.action_press(&"interact")
	await get_tree().physics_frame
	Input.action_release(&"interact")
	await _settle(4)
	_check(power.active and not PowerGrid.is_powered(lift), "real interaction cuts power to the original lift")
	await _photo("power-cut", level)
	_check(power._art_on != null and power._art_on.texture.resource_path.ends_with("power_switch_on.png"), "power cutoff uses its own panel")
	# A throwable barrel has different gameplay: it burns the existing fuse first.
	var fuel := Throwable.new()
	fuel.configure(load("res://data/throwables/fuel_barrel.tres"))
	fuel.position = Vector2(14 * 16, 19 * 16 - 2)
	level._entities.add_child(fuel)
	level.player.global_position = Vector2(11 * 16, 19 * 16 - 2)
	level_camera_snap()
	await _settle(6)
	var bullet: ProjectileSpec = load("res://data/projectiles/pistol_shot.tres")
	for hit in 2:
		ProjectilePool.spawn(bullet, fuel.world_center() + Vector2(-30, 0), Vector2.RIGHT, Combat.Team.PLAYER)
		for frame in 12:
			await get_tree().physics_frame
			if fuel.health.current <= 1 - hit:
				break
	await get_tree().process_frame
	_check(fuel.is_fuse_lit() and fuel.state != Throwable.State.GONE, "real projectiles start the throwable fuse before explosion")
	await _photo("throwable-fuse", level)
	Settings.set_reduce_flashes(true)
	await _photo("throwable-reduced-flashes", level)
	_set_scripted_aim(level.player, false)
	level.queue_free()
	await _settle(4)
	GameState.start_new_run(GameState.difficulties[1])
	# Explicit visual fixture: silence story entrances, never claim a natural route.
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var campaign := Level.new()
	campaign.configure(load("res://data/levels/ch1_pawnshop.tres"))
	add_child(campaign)
	await _settle(16)
	campaign.hud.visible = false
	campaign.player.health.setup(999, 0.0)
	_set_scripted_aim(campaign.player, true)
	var crates: Array[Breakable] = []
	for node in campaign.find_children("*", "", true, false):
		if node is Breakable and node.data.look == BreakableData.Look.CRATE:
			crates.append(node)
	_check(crates.size() == 2, "the canonical pawnshop spawns its two actual crates")
	if not crates.is_empty():
		var crate := crates[0]
		campaign.player.global_position = crate.global_position + Vector2(-60, -2)
		level_camera_snap()
		await _settle(4)
		_check(crate.find_child("Art_breakable_crate", true, false) != null, "the canonical pawnshop uses the formal crate view")
		await _photo("campaign-pawnshop-intact", campaign)
		await _shoot(crate, campaign)
		await _wait(0.18)
		await _photo("campaign-pawnshop-damaged", campaign)
		while not crate.is_broken:
			if not await _shoot(crate, campaign):
				break
		await get_tree().process_frame
		await _photo("campaign-pawnshop-broken", campaign)
		_check(crate.is_broken and not crate.visible and not crate.hurtbox.enabled,
			"the canonical pawnshop crate breaks through actual projectile physics")
	_set_scripted_aim(campaign.player, false)
	var report := {"kind": "arranged props fixture, not campaign playthrough", "engine": Engine.get_version_info().string,
		"adapter": RenderingServer.get_video_adapter_name(), "quality": Settings.get_light_quality(),
		"brightness": Settings.get_brightness(), "checks": _checks, "failures": _failures, "shots": _shots}
	var file := FileAccess.open(_out_dir.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	campaign.queue_free()
	await _settle(4)
	await AudioRelease.settle(get_tree())
	print("EXIT_WORLD valid=", is_instance_valid(campaign), " fx=", is_instance_valid(Fx._container), " soft=", is_instance_valid(Fx._soft))
	var orphan_types: Dictionary = {}
	for id in Node.get_orphan_node_ids():
		var node := instance_from_id(id) as Node
		var key: String = node.get_script().resource_path if node.get_script() != null else node.get_class()
		orphan_types[key] = int(orphan_types.get(key, 0)) + 1
	print("EXIT_ORPHANS ", JSON.stringify(orphan_types))
	print("FIXTURE_STATES checks: %d, failures: %d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _shoot(body: Breakable, level: Level) -> bool:
	var before := body.health.current
	var bullet: ProjectileSpec = load("res://data/projectiles/pistol_shot.tres")
	ProjectilePool.spawn(bullet, body.world_center() + Vector2(-30, 0), Vector2.RIGHT, Combat.Team.PLAYER)
	for frame in 16:
		await get_tree().physics_frame
		if body.health.current < before:
			_check(true, "projectile damaged %s" % body.data.id)
			return true
	_check(false, "projectile did not reach %s" % body.data.id)
	return false


func _photo(id: String, level: Level) -> void:
	_caption.text = "SOFTWARE FORWARD+ / " + ("ARRANGED CAMPAIGN SPOT / " if id.begins_with("campaign-") else "ARRANGED PROPS LAB / ") + id
	await RenderingServer.frame_post_draw
	_capture(id)
	_shots.append({"file": id + ".png", "level": level.data.resource_path, "player_feet": [level.player.position.x, level.player.position.y],
		"camera": [get_viewport().get_camera_2d().global_position.x, get_viewport().get_camera_2d().global_position.y]})


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FIXTURE_STATES FAIL: " + message)
