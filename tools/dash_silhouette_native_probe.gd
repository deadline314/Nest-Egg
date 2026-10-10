extends Node
## Isolated authored Level visual/mechanics probe. Not a Main/Story walkthrough.
## Root must adopt the separately frozen NE247 source before running this tool.

const Capture := preload("res://tools/viewport_capture.gd")
const PoseFixture := preload("res://tests/suite/test_pose_mesh.gd")
const MAP := "res://data/levels/ch1_pawnshop.tres"
const LETHAL_MAP := "res://data/levels/ch1_booth_alley.tres"
const ACTIONS: Array[StringName] = [&"dash", &"jump", &"move_left", &"move_right", &"aim_left", &"aim_right"]
const NORMAL_SHOT_LIMIT := 12
const SETTINGS_SHOT_LIMIT := 1
const ALIGNMENT_SIZE := Vector2i(512, 512)
const REPEATED_DASHES := 20
const SAMPLE_LIMIT := 8192

class VisualLevel extends Level:
	func _begin_intro() -> void:
		pass # Explicit tool-only suppression: no Story flags/completion are written.

	func _begin_death_reactions() -> void:
		pass

	func _spawn_cinematic_entries() -> void:
		pass

	func _physics_process(_delta: float) -> void:
		_update_lighting_events() # Keep actual authored lighting, suppress story/boss entry.

var out := ""
var baseline := ""
var manifest_path := ""
var manifest: Dictionary = {}
var level: VisualLevel
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var shots := 0
var settings_shots := 0
var checks := 0
var frame_samples := PackedFloat64Array()
var frame_count := 0
var elapsed_sum := 0.0
var elapsed_max := 0.0
var started_usec := 0
var saved_settings: Dictionary = {}
var alignment_view: SubViewport
var alignment_root: Node2D
var alpha_buffer := PackedByteArray()
var lifecycle_shots := 0
var death_retry_done := false
var death_restart_in_progress := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	frame_samples.resize(SAMPLE_LIMIT)
	alpha_buffer.resize(ALIGNMENT_SIZE.x * ALIGNMENT_SIZE.y)
	started_usec = Time.get_ticks_usec()
	_run.call_deferred()


func _process(delta: float) -> void:
	if frame_count < SAMPLE_LIMIT:
		frame_samples[frame_count] = delta * 1000.0
	frame_count += 1
	elapsed_sum += delta * 1000.0
	elapsed_max = maxf(elapsed_max, delta * 1000.0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("[NE247 probe] " + message)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--manifest="):
			manifest_path = arg.trim_prefix("--manifest=")
	baseline = OS.get_environment("DASH_PROBE_BASELINE")
	var hex := RegEx.new()
	hex.compile("^[0-9a-fA-F]{40}$")
	_check(hex.search(baseline) != null, "DASH_PROBE_BASELINE must be an explicit 40-hex actual HEAD")
	_check(out.is_absolute_path() and manifest_path.is_absolute_path(), "out and manifest must be absolute")
	_check(OS.get_environment("DASH_PROBE_PRIVATE_PROFILE") == "1", "private APPDATA launch wrapper required")
	if not failures.is_empty():
		get_tree().quit(1)
		return
	_check(DirAccess.make_dir_recursive_absolute(out) == OK, "create output directory")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_check(parsed is Dictionary, "load protected runtime source manifest")
	if not parsed is Dictionary:
		get_tree().quit(1)
		return
	manifest = parsed
	_check(manifest.get("baseline_head", "") == baseline, "manifest baseline matches explicit baseline")
	_verify_sources()
	_check(RenderingServer.get_current_rendering_method() == "forward_plus", "native Forward+ required; headless is not visual proof")
	if not failures.is_empty():
		_finish()
		return
	GameState.story_autosave = false
	# Private tool process: keep action APIs while preventing physical key/device
	# events from starting nearby NPC interaction during the controlled route.
	for action: StringName in InputMap.get_actions():
		InputMap.action_erase_events(action)
	saved_settings = {"quality": Settings.get_light_quality(), "reduce": Settings.get_reduce_flashes(), "particles": Settings.get_feel_scale("particles"), "trails": Settings.get_dash_silhouettes()}
	Settings.set_feel_scale("particles", 1.0)
	Settings.set_dash_silhouettes(true)
	await _create_level()
	if not is_instance_valid(level) or not is_instance_valid(level.player):
		_finish()
		return
	# Controlled teleport to genuine support cells; no fake grounded/state/cooldown.
	# Both corridors are in the unchanged authored map, floor at row 20.
	var cases: Array[Dictionary] = [
		{"id": "pistol-dark-right-ground", "weapon": "pistol", "cell": 19, "direction": 1, "air": false, "quality": 2, "reduce": false},
		{"id": "pistol-lit-left-air", "weapon": "pistol", "cell": 58, "direction": -1, "air": true, "quality": 2, "reduce": false},
		{"id": "blade-lit-right-ground", "weapon": "melee_blade", "cell": 58, "direction": 1, "air": false, "quality": 2, "reduce": false},
		{"id": "maul-dark-left-ground", "weapon": "melee_maul", "cell": 19, "direction": -1, "air": false, "quality": 2, "reduce": false},
		{"id": "glaive-lit-left-air", "weapon": "melee_glaive", "cell": 58, "direction": -1, "air": true, "quality": 2, "reduce": false},
		{"id": "whip-dark-right-ground", "weapon": "melee_whip", "cell": 19, "direction": 1, "air": false, "quality": 2, "reduce": false},
		{"id": "pistol-low-lit-right-ground", "weapon": "pistol", "cell": 58, "direction": 1, "air": false, "quality": 0, "reduce": false},
		{"id": "pistol-low-reduced-dark-left-air", "weapon": "pistol", "cell": 19, "direction": -1, "air": true, "quality": 0, "reduce": true},
		{"id": "pistol-high-reduced-lit-left-ground", "weapon": "pistol", "cell": 58, "direction": -1, "air": false, "quality": 2, "reduce": true},
	]
	for scenario: Dictionary in cases:
		await _dash_case(scenario, true)
		if not failures.is_empty():
			break
	if failures.is_empty():
		Settings.set_light_quality(2)
		Settings.set_reduce_flashes(false)
		await _place(58)
		var player := level.player
		var before := player.health.current
		var damage := DamageInfo.create(1, Combat.Team.ENEMY, &"ne247_probe_damage")
		damage.ignore_invulnerability = true
		_check(before > 1 and player.health.take_damage(damage), "actual nonlethal HealthComponent damage accepted")
		_check(player.health.current == before - 1, "real health decreased without fabricated armor visibility")
		await _wait_seconds(player.tuning.hurt_invulnerability + 0.4)
		await _dash_case({"id": "damaged-pistol-lit-right-ground", "weapon": "pistol", "cell": 58, "direction": 1, "air": false, "quality": 2, "reduce": false}, true)
		await _alignment("formal-rin-current-dash", false)
		await _alignment("synthetic-native-pose-mesh", true)
		await _trail_toggle()
		await _unsupported()
		await _repeated()
		await _pause_clear_exit()
		if failures.is_empty():
			await _lethal_restart()
	_release_actions()
	_verify_sources()
	_finish()


func _verify_sources() -> void:
	var sources: Variant = manifest.get("sources", {})
	_check(sources is Dictionary and not sources.is_empty(), "nonempty protected source set")
	if sources is Dictionary:
		for path: String in sources:
			_check(FileAccess.get_sha256(path) == sources[path], "source hash unchanged: " + path)


func _create_level(resume: Dictionary = {}, map_path := MAP, support_cell := 58) -> void:
	level = VisualLevel.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.configure(load(map_path) as LevelData)
	if not resume.is_empty():
		level.configure_resume(resume)
	add_child(level)
	await _frames(5)
	_check(is_instance_valid(level.player), "genuine authored Level Player spawned")
	if is_instance_valid(level.player):
		AimInput.set_virtual_gamepad(level.player, true)
		await _place(support_cell)
		_check(is_instance_valid(level.player._visual._ghost_pool), "adopted pool attached to actual Entities sibling")


func _place(cell: int) -> void:
	_release_actions()
	var player := level.player
	var floor_y := level._layout.floor_below(cell, 18)
	_check(is_finite(floor_y), "authored floor support at cell " + str(cell))
	player.global_position = Vector2((cell + 0.5) * level._layout.tile_size, floor_y - 2.0)
	# Tool relocation only: retain real velocity/timers and let physics settle.
	await _wait_seconds(player.tuning.dash_cooldown + 0.65)
	_check(player.is_on_floor() and player.state == Player.State.NORMAL, "real physics settled before controlled dash")
	level.camera.snap_to_target()
	await _frames(3)


func _dash_case(scenario: Dictionary, screenshot: bool) -> void:
	Settings.set_light_quality(int(scenario.quality))
	Settings.set_reduce_flashes(bool(scenario.reduce))
	await _place(int(scenario.cell))
	var player := level.player
	var path := "res://data/weapons/" + str(scenario.weapon) + ".tres"
	if str(scenario.weapon).begins_with("melee_"):
		path = "res://data/weapons/melee/" + str(scenario.weapon) + ".tres"
	var weapon := load(path) as WeaponData
	_check(weapon != null and weapon.is_valid(), "formal weapon resource: " + path)
	if weapon == null:
		return
	if weapon.id == &"pistol":
		player.loadout.select(Loadout.PRIMARY)
	else:
		player.loadout.equip(weapon) # Tool equipment fixture via actual loadout; no inventory grant.
	_check(player.loadout.active_weapon().id == weapon.id, "actual active loadout matches scenario")
	var direction := int(scenario.direction)
	Input.action_press(&"aim_right" if direction > 0 else &"aim_left")
	Input.action_press(&"move_right" if direction > 0 else &"move_left")
	await _frames(2)
	if bool(scenario.air):
		Input.action_press(&"jump")
		await _frames(4)
		_check(not player.is_on_floor(), "actual jump airborne before dash")
	var pool := player._visual._ghost_pool
	pool.clear()
	var health_before := player.health.current
	Input.action_press(&"dash")
	var seen_dash := false
	var captured := false
	var recorded := false
	var required_samples := mini(2, DashSilhouettePool.slot_budget())
	var minimum_age := maxf(DashSilhouettePool.sample_interval(), player.tuning.dash_time * 0.5)
	var minimum_distance := player.tuning.dash_speed * minimum_age
	var t0 := Time.get_ticks_usec()
	var peak_speed := 0.0
	for frame in 15:
		await get_tree().physics_frame
		await get_tree().process_frame
		if frame == 1:
			Input.action_release(&"dash")
		peak_speed = maxf(peak_speed, absf(player.velocity.x))
		if player.state == Player.State.DASH:
			seen_dash = true
			_check(player.health.is_invulnerable(), "dash actual invulnerability retained")
		if not captured and pool.active_count() > 0 and player.state == Player.State.DASH:
			captured = true
			_check(player.facing == direction, "actual aim input establishes requested facing")
			_check(pool.active_count() <= DashSilhouettePool.slot_budget(), "actual active slots respect quality/accessibility budget")
		# Preserve first-sample control checks above, but record a world image only
		# after real samples trail their current source drawing frame in world space.
		var oldest: DashSilhouettePool.Snapshot = null
		for slot: DashSilhouettePool.Snapshot in pool.slots:
			if slot.visible and slot.used > 0 and (oldest == null or slot.age > oldest.age):
				oldest = slot
		var world_distance := 0.0
		var draw_frame_valid := false
		if oldest != null:
			var command: DashSilhouettePool.Command = oldest.commands[0]
			var source := instance_from_id(command.source_id) as Node2D
			if is_instance_valid(source):
				var live_frame := source.global_transform
				draw_frame_valid = true
				# Native Polygon2D vertices are captured in Skeleton2D space;
				# Sprite2D / RigPartMesh vertices use their own source draw frame.
				if source is Polygon2D and not (source is RigPartMesh):
					draw_frame_valid = is_instance_valid(player._visual.rig._skeleton)
					if draw_frame_valid:
						live_frame = player._visual.rig._skeleton.global_transform
				var frozen_frame := oldest.global_transform * command.transform
				world_distance = (live_frame.origin.x - frozen_frame.origin.x) * direction
		var trail_ready := oldest != null and draw_frame_valid and oldest.age >= minimum_age and world_distance >= minimum_distance \
			and pool.active_count() >= required_samples and pool.active_count() <= DashSilhouettePool.slot_budget()
		if not recorded and captured and player.state == Player.State.DASH and (not screenshot or trail_ready):
			recorded = true
			var row := _pool_row(str(scenario.id), pool)
			row.merge({"weapon": path, "scenario": scenario.duplicate(), "health_before": health_before, "health_after": player.health.current, "player_position": _v(player.global_position), "player_velocity": _v(player.velocity), "actual_facing": player.facing, "actual_floor": player.is_on_floor(), "state": player.state, "alpha": DashSilhouettePool.opacity(), "actual_light_profile": str(level._lighting.zone_id_at(player.global_position.x)), "ambient": str((level.get_node("Ambient") as CanvasModulate).color)}, true)
			row["visible_parts"] = _visible_parts(player._visual)
			row["worldshot_timing"] = {"required_samples": required_samples, "minimum_oldest_age": minimum_age, "actual_oldest_age": oldest.age if oldest != null else 0.0, "minimum_signed_world_x_distance": minimum_distance, "actual_signed_world_x_distance": world_distance, "draw_frame_valid": draw_frame_valid, "oldest_source_id": oldest.commands[0].source_id if oldest != null else 0, "criterion_met": trail_ready, "scope": "captured draw-frame origin versus current corresponding source draw-frame origin; world units, not camera/screen pixels"}
			row["image"] = out.path_join("NE247-%02d-%s.png" % [shots, str(scenario.id)]) if screenshot else ""
			rows.append(row)
			if screenshot:
				get_tree().paused = true
				await _shot(str(scenario.id))
				get_tree().paused = false
	_release_actions()
	_check(seen_dash and captured, "actual input produced dash and snapshot: " + str(scenario.id))
	_check(not screenshot or recorded, "actual DASH provides separated aged world samples for image: " + str(scenario.id))
	_check(peak_speed >= player.tuning.dash_speed * 0.99, "unchanged actual dash speed reached")
	_check(player.health.current == health_before, "isolated dash did not change health")
	rows.append({"event": "dash_elapsed", "case": scenario.id, "wall_msec": (Time.get_ticks_usec() - t0) / 1000.0, "peak_speed": peak_speed, "tuning_speed": player.tuning.dash_speed, "tuning_time": player.tuning.dash_time, "tuning_cooldown": player.tuning.dash_cooldown})
	await _wait_seconds(0.4)
	_check(pool.active_count() == 0 and _texture_leases(pool) == 0, "expired samples release texture leases")


func _pool_row(label: String, pool: DashSilhouettePool) -> Dictionary:
	var commands := 0
	var vertices := 0
	var ids: Array[int] = []
	var slots: Array[Dictionary] = []
	for slot: DashSilhouettePool.Snapshot in pool.slots:
		ids.append(slot.get_instance_id())
		commands += slot.used
		vertices += slot.vertices
		slots.append({"visible": slot.visible, "used": slot.used, "vertices": slot.vertices, "indices": slot.index_count, "serial": slot.serial, "age": slot.age, "facing": slot.facing, "geometry_sha256": _geometry_sha(slot) if slot.used > 0 else ""})
	return {"event": label, "pool_id": pool.get_instance_id(), "slot_count": pool.slots.size(), "active": pool.active_count(), "commands": commands, "vertices": vertices, "slots": slots, "slot_ids": ids, "slot_budget": DashSilhouettePool.slot_budget(), "quality": LightQuality.tier(), "reduce_flashes": Settings.get_reduce_flashes(), "dash_silhouettes": Settings.get_dash_silhouettes(), "engine_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}


func _texture_leases(pool: DashSilhouettePool) -> int:
	var count := 0
	for slot: DashSilhouettePool.Snapshot in pool.slots:
		for command: DashSilhouettePool.Command in slot.commands:
			count += int(command.texture != null)
	return count


func _geometry_sha(slot: DashSilhouettePool.Snapshot) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	# Versioned framing distinguishes empty fields, commands and packed-array types.
	hash.update(("NE247.geometry.v2\ncommands:%d\n" % slot.used).to_utf8_buffer())
	for i in slot.used:
		var command: DashSilhouettePool.Command = slot.commands[i]
		hash.update(("command:%d:%s\n" % [i, "line" if command.line_width > 0.0 else "triangles"]).to_utf8_buffer())
		_hash_geometry_field(hash, "points/PackedVector2Array", command.points.size(), command.points.to_byte_array())
		_hash_geometry_field(hash, "uv/PackedVector2Array", command.uv.size(), command.uv.to_byte_array())
		_hash_geometry_field(hash, "indices/PackedInt32Array", command.indices.size(), command.indices.to_byte_array())
		_hash_geometry_field(hash, "colors/PackedColorArray", command.colors.size(), command.colors.to_byte_array())
		var xf := command.transform
		_hash_geometry_field(hash, "transform/PackedFloat64Array", 6,
			PackedFloat64Array([xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y]).to_byte_array())
		_hash_geometry_field(hash, "line_width/PackedFloat64Array", 1, PackedFloat64Array([command.line_width]).to_byte_array())
	return hash.finish().hex_encode()


func _hash_geometry_field(hash: HashingContext, field: String, count: int, payload: PackedByteArray) -> void:
	# Empty UV/index arrays are valid for line commands. Their typed length header
	# is still hashed, while HashingContext.update never receives an empty buffer.
	hash.update(("%s:%d:%d\n" % [field, count, payload.size()]).to_utf8_buffer())
	if not payload.is_empty():
		hash.update(payload)


func _xf_values(xf: Transform2D) -> Array[float]:
	return [xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y]


func _visible_parts(visual: PlayerVisual) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parts: Array = visual.rig._parts.duplicate()
	if is_instance_valid(visual.rig._weapon_sprite):
		parts.append(visual.rig._weapon_sprite)
	for part_value: Variant in parts:
		if not is_instance_valid(part_value) or not part_value is CanvasItem:
			continue
		var part := part_value as CanvasItem
		if not part.is_visible_in_tree():
			continue
		var texture: Texture2D
		if part is Sprite2D:
			texture = (part as Sprite2D).texture
		elif part is Polygon2D:
			texture = (part as Polygon2D).texture
		var diffuse := (texture as CanvasTexture).diffuse_texture if texture is CanvasTexture else texture
		result.append({"name": str(part.name), "node_id": part.get_instance_id(), "class": part.get_class(), "script": (part.get_script() as Script).resource_path if part.get_script() != null else "", "visible_in_tree": part.is_visible_in_tree(), "effective_source_alpha": visual._ghost_pool._source_alpha(part), "modulate": str(part.modulate), "self_modulate": str(part.self_modulate), "world_transform": _xf_values((part as Node2D).global_transform), "texture": diffuse.resource_path if diffuse != null else "", "texture_size": str(texture.get_size()) if texture != null else "", "vertices": (part as Polygon2D).polygon.size() if part is Polygon2D else 4})
	return result


func _repeated() -> void:
	var pool := level.player._visual._ghost_pool
	var ids := _identity(pool)
	await _wait_seconds(0.7) # Actual dash dust recipe max 0.6 s; compare drained endpoints.
	rows.append(_pool_row("stress-warm-baseline", pool))
	print("NE247_PHASE stress-warm-baseline utc_ms=%.0f" % (Time.get_unix_time_from_system() * 1000.0))
	for i in REPEATED_DASHES:
		await _dash_case({"id": "stress-%02d" % i, "weapon": "pistol", "cell": 58, "direction": 1 if i % 2 == 0 else -1, "air": false, "quality": 2, "reduce": false}, false)
		_check(_identity(pool) == ids, "bounded pool and command identities unchanged after repeat " + str(i))
	await _wait_seconds(0.7)
	rows.append(_pool_row("stress-final-drained", pool))
	print("NE247_PHASE stress-final-drained utc_ms=%.0f" % (Time.get_unix_time_from_system() * 1000.0))
	_check(pool.slots.size() == DashSilhouettePool.CAPACITY and _texture_leases(pool) == 0, "twenty repeats leave fixed slots and no live texture leases")
	# OS memory is wrapper evidence, never mislabeled as VRAM or a strict RAM cap.


func _identity(pool: DashSilhouettePool) -> PackedInt64Array:
	var result := PackedInt64Array()
	for slot: DashSilhouettePool.Snapshot in pool.slots:
		result.append(slot.get_instance_id())
		for command: DashSilhouettePool.Command in slot.commands:
			result.append(command.get_instance_id())
	return result


func _unsupported() -> void:
	var visual := level.player._visual
	var pool := visual._ghost_pool
	pool.clear()
	var unknown := Node2D.new()
	visual.rig.add_child(unknown)
	visual.rig._parts.append(unknown)
	_check(not pool.capture(visual), "unsupported actual visible part refuses complete sample")
	_check(pool.active_count() == 0 and _texture_leases(pool) == 0 and not pool.failure_reason.is_empty(), "unsupported source leaves no partial ghost or texture lease")
	visual.rig._parts.erase(unknown)
	unknown.free()


func _trail_toggle() -> void:
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Settings.set_reduce_flashes(false)
	await _place(58)
	var player := level.player
	var pool := player._visual._ghost_pool
	Input.action_press(&"aim_right")
	Input.action_press(&"move_right")
	Input.action_press(&"dash")
	for i in 12:
		await _frames(1)
		if player.state == Player.State.DASH and pool.active_count() > 0:
			break
	_check(player.state == Player.State.DASH and pool.active_count() > 0 and _texture_leases(pool) > 0, "toggle route begins in actual input dash with leased silhouettes")
	get_tree().paused = true
	_release_actions()
	var frozen_velocity := player.velocity
	var health_before := player.health.current
	var pool_id := pool.get_instance_id()
	# Use the existing formal pause CanvasLayer/UiOverlay route, so Camera2D
	# never translates the real SettingsScreen out of the captured viewport.
	var pause_menu := level._pause_menu
	_check(is_instance_valid(pause_menu) and not GameplayLock.is_locked(), "actual pause settings host is available without a modal lock")
	if not is_instance_valid(pause_menu) or GameplayLock.is_locked():
		get_tree().paused = false
		return
	pause_menu.open()
	pause_menu._open_settings()
	var screen := pause_menu._settings
	var first_screen_ref: WeakRef = weakref(screen)
	screen._tabs.current_tab = 2
	await _render_frames(2)
	var button := screen._dash_silhouettes
	button.grab_focus()
	_check(button.is_visible_in_tree() and button.focus_mode == Control.FOCUS_ALL and get_viewport().gui_get_focus_owner() == button, "actual settings dash CheckButton accepts keyboard/gamepad focus while paused")
	_check(screen._status.text == "關閉衝刺殘影，角色動作照常", "actual focused dash toggle shows its precise hint")
	# Exercise native CheckButton's normal property/handler path; no signal emission.
	button.button_pressed = false
	_check(not Settings.get_dash_silhouettes() and DashSilhouettePool.slot_budget() == 0 and pool.active_count() == 0 and _texture_leases(pool) == 0, "actual CheckButton off clears every lease immediately while gameplay is paused")
	_check(player.state == Player.State.DASH and player.velocity == frozen_velocity and player.health.current == health_before, "dash option leaves paused real state velocity and health intact")
	rows.append(_pool_row("settings-dash-off-paused", pool))
	await _settings_shot(screen)
	screen.close()
	pause_menu.close()
	get_tree().paused = false
	var disabled_dash_seen := false
	var peak_speed := 0.0
	for i in 20:
		await _frames(1)
		_check(pool.active_count() == 0 and _texture_leases(pool) == 0, "disabled trail never recaptures during actual dash and expiry")
		if player.state == Player.State.DASH:
			disabled_dash_seen = true
			peak_speed = maxf(peak_speed, absf(player.velocity.x))
			_check(player.health.is_invulnerable(), "trail disabled retains real dash invulnerability")
	_check(disabled_dash_seen and peak_speed >= player.tuning.dash_speed * 0.99 and player.health.current == health_before, "trail disabled continues actual dash at unchanged tuning speed and health")
	_check(first_screen_ref.get_ref() == null and pause_menu._settings == null and not pause_menu._root.visible, "formal first settings close frees screen and retires the pause overlay")
	get_tree().paused = true
	pause_menu.open()
	pause_menu._open_settings()
	var reopen := pause_menu._settings
	var reopen_ref: WeakRef = weakref(reopen)
	reopen._tabs.current_tab = 2
	await _render_frames(2)
	_check(not reopen._dash_silhouettes.button_pressed, "reopened real settings screen retains off choice")
	reopen._dash_silhouettes.button_pressed = true
	_check(Settings.get_dash_silhouettes() and pool.get_instance_id() == pool_id, "actual CheckButton on retains the same fixed pool")
	reopen.close()
	pause_menu.close()
	get_tree().paused = false
	await _dash_case({"id": "settings-toggle-restored", "weapon": "pistol", "cell": 58, "direction": 1, "air": false, "quality": 2, "reduce": false}, false)
	_check(reopen_ref.get_ref() == null and pause_menu._settings == null and not pause_menu._root.visible, "formal reopened settings close frees screen and leaves no active pause overlay")
	rows.append({"event": "actual-settings-toggle", "scope": "real Control property and native handler/focus; tool-driven, no physical keyboard/controller evidence", "peak_speed_disabled": peak_speed, "normal_pngs_added": 0})


func _pause_clear_exit() -> void:
	await _place(58)
	Input.action_press(&"aim_right")
	Input.action_press(&"move_right")
	Input.action_press(&"dash")
	var pool := level.player._visual._ghost_pool
	for i in 12:
		await _frames(1)
		if pool.active_count() > 0:
			break
	_check(pool.active_count() > 0, "actual dash snapshot available for pause")
	get_tree().paused = true
	var frozen := _pool_row("paused-before", pool)
	await _wait_seconds(0.3)
	_check(_pool_row("paused-after", pool).slots == frozen.slots, "paused gameplay does not age/allocate snapshots")
	await _shot("paused-real-dash")
	pool.clear()
	_check(pool.active_count() == 0 and _texture_leases(pool) == 0, "explicit paused clear releases complete samples")
	await _shot("paused-cleared")
	get_tree().paused = false
	_release_actions()
	AimInput.set_virtual_gamepad(level.player, false)
	var old_pool: WeakRef = weakref(pool)
	level.queue_free()
	await _frames(4)
	_check(old_pool.get_ref() == null, "real Level exit frees sibling pool")
	await _create_level()
	_check(is_instance_valid(level.player._visual._ghost_pool) and level.player._visual._ghost_pool.active_count() == 0, "new genuine Level starts empty fixed pool")
	rows.append(_pool_row("recreated-Level", level.player._visual._ghost_pool))
	AimInput.set_virtual_gamepad(level.player, false)
	level.queue_free()
	await _frames(4)


func _alignment(label: String, synthetic: bool) -> void:
	await _place(58)
	level.player.loadout.select(Loadout.PRIMARY)
	Input.action_press(&"aim_left")
	Input.action_press(&"move_left")
	Input.action_press(&"dash")
	await _frames(3)
	get_tree().paused = true
	_release_actions()
	var visual := level.player._visual
	var original_rig := visual.rig
	var original_visible := original_rig.visible
	var original_components := _alignment_components(original_rig)
	var player_before := _alignment_components(level.player)
	var visual_before := _alignment_components(visual)
	var original_state_before := _alignment_state(original_rig)
	var fixture_globals := {}
	var fixture: CharacterRig
	if synthetic:
		fixture_globals = {"lit": LitTextures.is_enabled(), "rigid": CharacterRig.force_rigid_limbs}
		LitTextures.set_enabled(true)
		CharacterRig.force_rigid_limbs = true
		var suite := PoseFixture.new(self)
		fixture = suite._new_rig(suite._fixture())
		fixture.reparent(visual, false)
		# A negative-X matrix assignment would decompose into PI rotation / -Y
		# scale; the later real facing setter would then invert the fixture too.
		_restore_alignment_components(fixture, original_components)
		_check(fixture.set_pose_parts(&"mesh_a"), "clearly synthetic native PoseMesh fixture activates")
		_check(not fixture.active_pose_mesh_geometries().is_empty(), "synthetic native alignment uses actual weighted Polygon2D geometry")
		fixture.bone(&"hip").rotation += 0.21
		fixture.bone(&"chest").rotation -= 0.17
		fixture.facing = -1
		fixture.set_weapon("pistol")
		original_rig.visible = false
		visual.rig = fixture
	var rig := visual.rig
	var pool := visual._ghost_pool
	var visible_parts := _visible_parts(visual)
	pool.clear()
	var captured := pool.capture(visual)
	_check(captured, "alignment exact current source captures: " + label)
	if not captured:
		_restore_alignment_fixture(visual, original_rig, original_visible, fixture, fixture_globals)
		get_tree().paused = false
		return
	var snapshot: DashSilhouettePool.Snapshot
	for slot: DashSilhouettePool.Snapshot in pool.slots:
		if slot.visible:
			snapshot = slot
	_check(snapshot != null, "one real captured snapshot for alignment")
	if snapshot == null:
		pool.clear()
		_restore_alignment_fixture(visual, original_rig, original_visible, fixture, fixture_globals)
		get_tree().paused = false
		return
	if alignment_view == null:
		alignment_view = SubViewport.new()
		alignment_view.world_2d = World2D.new()
		alignment_view.size = ALIGNMENT_SIZE
		alignment_view.transparent_bg = true
		alignment_view.use_hdr_2d = true
		alignment_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(alignment_view)
		alignment_root = Node2D.new()
		alignment_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		alignment_view.add_child(alignment_root)
	var xf := Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(256, 400) - level.player.global_position * 2.0)
	alignment_view.canvas_transform = xf
	var source_parent := rig.get_parent()
	var source_index := rig.get_index()
	var source_transform := rig.transform
	var source_components := _alignment_components(rig)
	var source_state_before := _alignment_state(rig)
	var source_process_mode := rig.process_mode
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var world_transform := rig.global_transform
	var parent_alpha := 1.0
	var ancestor: Node = source_parent
	while ancestor != pool.get_parent() and ancestor is CanvasItem:
		parent_alpha *= (ancestor as CanvasItem).modulate.a
		ancestor = ancestor.get_parent()
	var exact_ids := {}
	for i in snapshot.used:
		exact_ids[snapshot.commands[i].source_id] = true
	var material := ShaderMaterial.new()
	material.shader = DashSilhouettePool.SILHOUETTE_SHADER
	var restore: Array[Dictionary] = []
	var stack: Array[Node] = [rig]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node is Sprite2D or node is Polygon2D:
			var item := node as CanvasItem
			restore.append({"item": item, "visible": item.visible, "material": item.material, "parent_material": item.use_parent_material})
			# Glow companions are not silhouette body geometry. No pose/alpha/texture edits.
			item.visible = item.visible and exact_ids.has(item.get_instance_id())
			item.material = material
			item.use_parent_material = false
	rig.reparent(alignment_root, false)
	rig.transform = world_transform
	alignment_root.modulate.a = parent_alpha
	await _render_frames(3)
	var source_image := Capture.image(alignment_view)
	_check(source_image != null and not source_image.is_empty(), "native source readback")
	if source_image != null and not source_image.is_empty():
		_check(source_image.save_png(out.path_join(label + "-source.png")) == OK, "save real source geometry")
		for y in ALIGNMENT_SIZE.y:
			for x in ALIGNMENT_SIZE.x:
				alpha_buffer[y * ALIGNMENT_SIZE.x + x] = int(round(source_image.get_pixel(x, y).a * 255.0))
	source_image = null # One source alpha fixed buffer, no retained Image collection.
	rig.reparent(source_parent, false)
	source_parent.move_child(rig, source_index)
	# Restore the exact captured representation as well as its matrix. Facing
	# animates scale, so matrix-equivalent PI/-Y decomposition is not equivalent.
	_restore_alignment_components(rig, source_components)
	_check(rig.transform == source_transform and _alignment_components_match(rig, source_components), "alignment restores exact actual source matrix and position rotation scale skew components")
	_check(_alignment_components_match(level.player, player_before) and _alignment_components_match(visual, visual_before), "alignment staging never mutates actual Player or Visual matrix/components")
	var source_state_restored := _alignment_state(rig)
	rig.process_mode = source_process_mode
	for entry: Dictionary in restore:
		var item := entry.item as CanvasItem
		item.visible = bool(entry.visible)
		item.material = entry.material as Material
		item.use_parent_material = bool(entry.parent_material)
	alignment_root.modulate.a = 1.0
	var replay := DashSilhouettePool.Snapshot.new()
	replay.commands = snapshot.commands # Borrow exact captured immutable commands, no Rig clone.
	replay.used = snapshot.used
	replay.material = material
	replay.transform = pool.global_transform
	replay.visible = true
	alignment_root.add_child(replay)
	replay.queue_redraw()
	await _render_frames(3)
	var image := Capture.image(alignment_view)
	_check(image != null and not image.is_empty(), "native exact snapshot readback")
	var changed := 0
	var abs_sum := 0
	var alpha_union := 0
	var clipped := false
	if image != null and not image.is_empty():
		_check(image.save_png(out.path_join(label + "-snapshot.png")) == OK, "save exact native snapshot")
		for y in ALIGNMENT_SIZE.y:
			for x in ALIGNMENT_SIZE.x:
				var source_a := int(alpha_buffer[y * ALIGNMENT_SIZE.x + x])
				var snapshot_a := int(round(image.get_pixel(x, y).a * 255.0))
				var difference := absi(source_a - snapshot_a)
				changed += int(difference > 2)
				abs_sum += difference
				alpha_union += int(maxi(source_a, snapshot_a) > 2)
				if maxi(source_a, snapshot_a) > 2 and (x == 0 or y == 0 or x == ALIGNMENT_SIZE.x - 1 or y == ALIGNMENT_SIZE.y - 1):
					clipped = true
	image = null
	_check(alpha_union > 0 and not clipped, "nonempty unclipped alpha comparison")
	rows.append({"event": "native-alpha-alignment", "classification": "synthetic native PoseMesh fixture" if synthetic else "formal Rin current real input dash", "label": label, "source_image": out.path_join(label + "-source.png"), "snapshot_image": out.path_join(label + "-snapshot.png"), "actual_weapon": level.player.loadout.active_weapon().resource_path, "visible_parts": visible_parts, "actual_pose_parts": str(rig.active_pose_parts()), "source_world_transform": _xf_values(world_transform), "canvas_transform": _xf_values(xf), "source_ancestor_alpha": parent_alpha, "captured_commands": snapshot.used, "captured_serial": snapshot.serial, "geometry_sha256": _geometry_sha(snapshot), "alpha_union_pixels": alpha_union, "pixels_difference_gt_2": changed, "sum_absolute_alpha_difference": abs_sum, "clipped": clipped, "accepted": false, "acceptance_note": "Root must inspect actual source/snapshot PNGs; numeric differences recorded without a fabricated GPU tolerance", "scope": "current base body/coat/damage/weapon geometry; unlit black shader, texture alpha retained, glow companions excluded; normal level screenshots separately prove dark/lit appearance"})
	replay.used = 0 # Do not clear borrowed source commands.
	replay.free()
	pool.clear()
	_restore_alignment_fixture(visual, original_rig, original_visible, fixture, fixture_globals)
	_check(visual.rig == original_rig and _alignment_components_match(original_rig, original_components), "alignment returns the identical formal Rig with exact pre-diagnostic components")
	var original_state_restored := _alignment_state(original_rig)
	get_tree().paused = false
	await _frames(2)
	# Observe actual resumed animation; never write a pose or reset live transforms.
	_check(original_rig.rotation == float(original_components.rotation) and original_rig.skew == float(original_components.skew) and original_rig.position == original_components.position,
		"two real resumed frames retain original rig rotation skew and local origin")
	_check(original_rig.scale == Vector2(original_rig._base_scale * original_rig.facing, original_rig._base_scale) and original_rig.transform.y.dot((original_components.transform as Transform2D).y) > 0.0,
		"actual resumed facing updates scale without vertical inversion after alignment")
	rows.append({"event": "alignment-staging-restore", "label": label, "classification": "probe-only negative-X decomposition regression", "source_before": source_state_before, "source_restored": source_state_restored, "formal_before": original_state_before, "formal_restored": original_state_restored, "formal_after_two_actual_frames": _alignment_state(original_rig), "player_before": _alignment_json_components(player_before), "player_after_two_actual_frames": _alignment_state(level.player), "visual_before": _alignment_json_components(visual_before), "visual_after_two_actual_frames": _alignment_state(visual), "scope": "saved exact pre-staging components restored only on moved diagnostic Rig; actual resumed animation observed, no manual Player/Visual/pose reset"})


func _alignment_components(node: Node2D) -> Dictionary:
	return {"transform": node.transform, "position": node.position, "rotation": node.rotation, "scale": node.scale, "skew": node.skew}


func _restore_alignment_components(node: Node2D, components: Dictionary) -> void:
	node.position = components.position
	node.rotation = float(components.rotation)
	node.scale = components.scale
	node.skew = float(components.skew)


func _alignment_components_match(node: Node2D, components: Dictionary) -> bool:
	return node.transform == components.transform and node.position == components.position and node.rotation == float(components.rotation) \
		and node.scale == components.scale and node.skew == float(components.skew)


func _alignment_json_components(components: Dictionary) -> Dictionary:
	return {"local_transform": _xf_values(components.transform), "position": _v(components.position), "rotation": components.rotation, "scale": _v(components.scale), "skew": components.skew}


func _alignment_state(node: Node2D) -> Dictionary:
	var state := _alignment_json_components(_alignment_components(node))
	state["global_transform"] = _xf_values(node.global_transform)
	state["node_id"] = node.get_instance_id()
	state["parent_id"] = node.get_parent().get_instance_id()
	if node is CharacterRig:
		state["actual_facing"] = (node as CharacterRig).facing
		state["actual_pose_parts"] = str((node as CharacterRig).active_pose_parts())
	return state


func _restore_alignment_fixture(visual: PlayerVisual, original: CharacterRig, original_visible: bool,
		fixture: CharacterRig, globals: Dictionary) -> void:
	if globals.is_empty():
		return
	visual.rig = original
	original.visible = original_visible
	if is_instance_valid(fixture):
		fixture.free()
	CharacterRig.force_rigid_limbs = bool(globals.rigid)
	LitTextures.set_enabled(bool(globals.lit))
	_check(CharacterRig.force_rigid_limbs == bool(globals.rigid) and LitTextures.is_enabled() == bool(globals.lit), "native fixture restores exact prior global rendering controls")


func _lethal_restart() -> void:
	# Separate authored safe map: pawnshop has no checkpoint for first-death retry.
	# Actual Health -> Player -> Level -> clinic -> Level.retry_requested; no
	# written DEAD/seen/flags, emitted fake death signal, or fabricated receipt.
	await _create_level({}, LETHAL_MAP, 25)
	if not is_instance_valid(level) or not is_instance_valid(level.player):
		return
	var old := level
	var player := old.player
	var pool := player._visual._ghost_pool
	var old_pool: WeakRef = weakref(pool)
	var old_player: WeakRef = weakref(player)
	var old_level: WeakRef = weakref(old)
	var old_pool_id := pool.get_instance_id()
	var death_count := GameState.deaths
	var credits_before := Progression.credits
	death_retry_done = false
	death_restart_in_progress = false
	old.retry_requested.connect(_restart_after_lethal.bind(old), CONNECT_DEFERRED)
	Input.action_press(&"aim_right")
	Input.action_press(&"move_right")
	Input.action_press(&"dash")
	for i in 12:
		await _frames(1)
		if pool.active_count() > 0 and player.state == Player.State.DASH:
			break
	_release_actions()
	_check(player.state == Player.State.DASH and pool.active_count() > 0 and _texture_leases(pool) > 0, "real dash owns active silhouettes immediately before lethal hit")
	rows.append(_pool_row("lethal-before-real-health-hit", pool))
	var observed_death: Array[Dictionary] = []
	var death_observer: Callable = func(cause: StringName) -> void:
		var all_empty := true
		for slot: DashSilhouettePool.Snapshot in pool.slots:
			all_empty = all_empty and slot.used == 0 and not slot.visible
		observed_death.append({"cause": String(cause), "active": pool.active_count(),
			"texture_leases": _texture_leases(pool), "all_slots_empty": all_empty,
			"player_dead": player.is_dead(), "ghost_timer": player._visual._ghost_timer,
			"process_frame": Engine.get_process_frames(), "tree_paused": get_tree().paused,
			"player_process_mode": player.process_mode, "visual_can_process": player._visual.can_process()})
	EventBus.player_died.connect(death_observer)
	var frame_before := Engine.get_process_frames()
	var damage := DamageInfo.create(player.health.current, Combat.Team.ENEMY, &"ne247_probe_lethal")
	damage.ignore_invulnerability = true
	_check(player.health.take_damage(damage), "real lethal HealthComponent hit accepted during dash")
	EventBus.player_died.disconnect(death_observer)
	_check(Engine.get_process_frames() == frame_before and pool.active_count() == 0 and _texture_leases(pool) == 0,
		"real lethal signal clears samples synchronously before any next process frame")
	_check(observed_death.size() == 1 and bool(observed_death[0]["player_dead"]) \
		and bool(observed_death[0]["all_slots_empty"]) and observed_death[0]["active"] == 0 \
		and observed_death[0]["texture_leases"] == 0 and observed_death[0]["ghost_timer"] == 0.0,
		"actual EventBus death observer sees no old sample or texture lease")
	rows.append({"event": "lethal-synchronous-death-observation", "observations": observed_death})
	_check(player.health.is_dead and player.health.current == 0 and player.is_dead(), "actual Health signal puts actual Player in DEAD")
	_check(old.died and GameState.deaths == death_count + 1, "actual Level handles one genuine death and canonical counter")
	_check(old._death_entry.get("scene") == "ch1_c09_wake" and bool(old._death_entry.get("free", false)) and Progression.credits == credits_before, "real first-clinic route preserves its authored free-death fee rule")
	await _frames(2)
	_check(pool.active_count() == 0 and _texture_leases(pool) == 0, "actual player death clears all silhouette samples and texture leases")
	for slot: DashSilhouettePool.Snapshot in pool.slots:
		_check(slot.used == 0 and not slot.visible, "actual dead player leaves every snapshot empty and hidden")
	var after_death := _pool_row("lethal-after-real-player-death", pool)
	after_death["tree_paused"] = get_tree().paused
	after_death["player_process_mode"] = player.process_mode
	after_death["visual_can_process"] = player._visual.can_process()
	after_death["player_dead"] = player.is_dead()
	after_death["ghost_timer"] = player._visual._ghost_timer
	rows.append(after_death)
	await _lifecycle_shot("actual-lethal-cleared")
	# Use the actual non-choice movie's public skip API. Do not forge a completed
	# clinic, checkpoint, death flag or retry signal. If its contract changes,
	# refuse instead of applying default choices or bypassing the scene.
	var skipped_request := false
	for i in 900:
		if death_retry_done:
			break
		if not skipped_request and is_instance_valid(Story._player):
			var movie: CutscenePlayer = Story._player
			var actual: Dictionary = Story._scenes.get(String(movie.scene_id), {})
			var safe: bool = movie.scene_id == &"ch1_c09_wake" and actual.get("mode") == "animated" and actual.get("steps") is Array and not actual.get("steps", []).is_empty() and not movie.choice_active()
			for raw: Variant in actual.get("steps", []):
				if raw is Dictionary and raw.get("do") == "choice":
					safe = false
			_check(safe, "genuine first-death movie has no choice; public skip cannot default-select")
			if not safe:
				break
			movie.skip()
			skipped_request = true
		await _frames(1)
	_check(death_retry_done, "actual first-death continuation reaches natural same-level retry")
	_check(old_pool.get_ref() == null and old_player.get_ref() == null and old_level.get_ref() == null, "natural retry frees old Level, Player and sibling silhouette pool")
	if death_retry_done and is_instance_valid(level) and is_instance_valid(level.player):
		var new_pool := level.player._visual._ghost_pool
		_check(level.data.resource_path == LETHAL_MAP and level.is_initialized() and not level.died and not level.player.is_dead(), "new same authored Level installs a genuinely alive player")
		_check(GameState.deaths == death_count + 1 and GameState.checkpoint_applies(LETHAL_MAP) and level._from_checkpoint, "same-level retry uses real first-death checkpoint without extra death")
		_check(Progression.credits == credits_before, "first-clinic retry does not charge or reimburse a second fee")
		_check(new_pool.get_instance_id() != old_pool_id and new_pool.slots.size() == DashSilhouettePool.CAPACITY and new_pool.active_count() == 0 and _texture_leases(new_pool) == 0, "replacement fixed pool starts empty with no old texture lease")
		rows.append(_pool_row("lethal-natural-same-level-retry", new_pool))
		await _lifecycle_shot("actual-same-level-retry")
	_release_actions()
	Story.reset_active_presentation(&"ne247_probe_cleanup")
	if is_instance_valid(level):
		AimInput.set_virtual_gamepad(level.player, false)
		level.queue_free()
	await _frames(4)


func _restart_after_lethal(old: Level) -> void:
	# Tool host owns routing, as the existing VisualLevel probe does. The only
	# trigger is Level's real retry_requested. Reset fields match Main's retry;
	# this is not evidence of Main/RunSave persistence or the clinic story release.
	if death_restart_in_progress:
		_check(false, "same death must not request retry twice")
		return
	death_restart_in_progress = true
	if not is_instance_valid(old) or old != level or not old.died or not old.player.is_dead():
		_check(false, "retry source must be current genuinely dead Level")
		return
	_check(GameState.checkpoint_applies(LETHAL_MAP), "actual clinic continuation registered a checkpoint in same authored map")
	if not GameState.checkpoint_applies(LETHAL_MAP):
		return
	Story.reset_active_presentation(&"retry")
	var runtime := old.run_snapshot()
	GameState.pending_portal = &""
	GameState.carried_health = -1
	runtime["loadout"] = GameState.checkpoint_loadout.duplicate(true)
	runtime["dead"] = false
	runtime["ending"] = false
	runtime["health"] = GameState.difficulty.player_max_health
	runtime["position"] = [-1, -1]
	runtime["velocity"] = [0, 0]
	runtime["crouching"] = false
	AimInput.set_virtual_gamepad(old.player, false)
	remove_child(old)
	old.queue_free()
	GameplayLock.set_base_paused(false)
	Fx.reset_time()
	await _frames(4)
	await _create_level(runtime, LETHAL_MAP, 25)
	death_retry_done = is_instance_valid(level) and level.is_initialized()


func _lifecycle_shot(label: String) -> void:
	_check(lifecycle_shots < 2, "actual death/retry screenshots bounded to two")
	if lifecycle_shots >= 2:
		return
	await _render_frames(2)
	var image := Capture.image(get_viewport())
	_check(image != null and not image.is_empty(), "native lifecycle viewport readback " + label)
	if image != null and not image.is_empty():
		_check(image.save_png(out.path_join("NE247-lifecycle-%s.png" % label)) == OK, "save native lifecycle " + label)
	lifecycle_shots += 1


func _shot(label: String) -> void:
	_check(shots < NORMAL_SHOT_LIMIT, "normal screenshots bounded to twelve")
	if shots >= NORMAL_SHOT_LIMIT:
		return
	await _render_frames(2)
	var image := Capture.image(get_viewport())
	_check(image != null and not image.is_empty(), "native viewport readback " + label)
	if image != null and not image.is_empty():
		_check(image.save_png(out.path_join("NE247-%02d-%s.png" % [shots, label])) == OK, "save normal scene " + label)
	image = null
	shots += 1


func _settings_shot(screen: SettingsScreen) -> void:
	_check(settings_shots < SETTINGS_SHOT_LIMIT, "independent actual settings screenshot bounded to one")
	if settings_shots >= SETTINGS_SHOT_LIMIT:
		return
	# Wait for actual opaque, fully clipped-in reading geometry and any relevant
	# UiMotion ancestry tween to finish; a frame count alone is not GUI proof.
	await _render_frames(2)
	var deadline := Time.get_ticks_msec() + 2000
	while not _settings_reading_settled(screen) and Time.get_ticks_msec() < deadline:
		await _render_frames(1)
	_check(_settings_reading_settled(screen), "actual settings focus hint opacity clip and ancestry motion settle before image")
	if not _settings_reading_settled(screen):
		return
	var button := screen._dash_silhouettes
	_check(get_tree().paused and screen.is_visible_in_tree() and button.is_visible_in_tree() and get_viewport().gui_get_focus_owner() == button and not button.button_pressed and screen._status.text == "關閉衝刺殘影，角色動作照常", "settings image retains actual focused off control and precise hint after layout")
	_check(_settings_reading_in_viewport(screen), "settings image uses the formal pause canvas and fully visible viewport/scroll control and hint")
	var image_path := out.path_join("NE247-settings-dash-toggle.png")
	var image := Capture.image(get_viewport())
	_check(image != null and not image.is_empty(), "native actual settings main viewport readback")
	var saved := false
	if image != null and not image.is_empty():
		saved = image.save_png(image_path) == OK
		_check(saved, "save independent actual settings reading image")
	image = null
	settings_shots += 1
	rows.append({"event": "actual-settings-reading-image", "image": image_path, "saved": saved, "settings_image_attempt": settings_shots, "settings_image_limit": SETTINGS_SHOT_LIMIT, "formal_canvas_layer": level._pause_menu.layer, "screen_viewport_rect": str(_settings_viewport_rect(screen)), "button_viewport_rect": str(_settings_viewport_rect(button)), "hint_viewport_rect": str(_settings_viewport_rect(screen._status)), "scroll_viewport_rect": str(_settings_viewport_rect(screen._tabs.get_current_tab_control())), "reading_in_viewport": _settings_reading_in_viewport(screen), "reading_settled": _settings_reading_settled(screen), "canvas_transform": str(level._pause_menu.transform), "settle_timeout_ms": 2000, "hint": screen._status.text, "normal_pngs_added": 0, "scope": "actual paused SettingsScreen, focused native CheckButton off and rendered precise hint; tool-driven focus/property, no physical keyboard/controller proof"})


func _settings_viewport_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _settings_reading_in_viewport(screen: SettingsScreen) -> bool:
	var pause_menu := level._pause_menu
	var scroll := screen._tabs.get_current_tab_control() as ScrollContainer
	if scroll == null or screen.get_parent() != pause_menu._root or pause_menu._root.get_parent() != pause_menu or pause_menu.layer != UiLayers.PAUSE or pause_menu.follow_viewport_enabled:
		return false
	var viewport_rect := get_viewport().get_visible_rect()
	var screen_rect := _settings_viewport_rect(screen)
	var button_rect := _settings_viewport_rect(screen._dash_silhouettes)
	var hint_rect := _settings_viewport_rect(screen._status)
	var scroll_rect := _settings_viewport_rect(scroll)
	# Scroll children clip inside the bar-free content viewport.
	if scroll.get_v_scroll_bar().visible:
		scroll_rect.size.x -= _settings_viewport_rect(scroll.get_v_scroll_bar()).size.x
	if scroll.get_h_scroll_bar().visible:
		scroll_rect.size.y -= _settings_viewport_rect(scroll.get_h_scroll_bar()).size.y
	return screen_rect.has_area() and button_rect.has_area() and hint_rect.has_area() and scroll_rect.has_area() \
		and viewport_rect.encloses(screen_rect) and viewport_rect.encloses(button_rect) and viewport_rect.encloses(hint_rect) \
		and scroll_rect.encloses(button_rect)


func _settings_ancestors_settled(item: CanvasItem) -> bool:
	var current: Node = item
	while current is CanvasItem:
		var canvas_item := current as CanvasItem
		if not canvas_item.is_visible_in_tree() or not is_equal_approx(canvas_item.modulate.a, 1.0) or not is_equal_approx(canvas_item.self_modulate.a, 1.0):
			return false
		var motion: Variant = current.get_meta(UiMotion.TWEEN_META) if current.has_meta(UiMotion.TWEEN_META) else null
		if motion is Tween and (motion as Tween).is_valid() and (motion as Tween).is_running():
			return false
		current = current.get_parent()
	return current == level._pause_menu


func _settings_reading_settled(screen: SettingsScreen) -> bool:
	return _settings_reading_in_viewport(screen) and _settings_ancestors_settled(screen._dash_silhouettes) \
		and _settings_ancestors_settled(screen._status) and get_viewport().gui_get_focus_owner() == screen._dash_silhouettes \
		and not screen._dash_silhouettes.button_pressed and screen._status.text == "關閉衝刺殘影，角色動作照常"


func _render_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _release_actions() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _v(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _frame_stats() -> Dictionary:
	var sorted := frame_samples.duplicate()
	sorted.resize(mini(frame_count, SAMPLE_LIMIT))
	sorted.sort()
	return {"scope": "whole probe process delta, includes paused rendering/readbacks; not gameplay-only GPU timing", "stored": sorted.size(), "omitted": maxi(0, frame_count - SAMPLE_LIMIT), "p50_ms": sorted[int((sorted.size() - 1) * 0.5)] if not sorted.is_empty() else 0.0, "p95_ms": sorted[int((sorted.size() - 1) * 0.95)] if not sorted.is_empty() else 0.0}


func _finish() -> void:
	_release_actions()
	get_tree().paused = false
	if not saved_settings.is_empty():
		Settings.set_light_quality(int(saved_settings.quality))
		Settings.set_reduce_flashes(bool(saved_settings.reduce))
		Settings.set_feel_scale("particles", float(saved_settings.particles))
		Settings.set_dash_silhouettes(bool(saved_settings.trails))
		_check(Settings.get_dash_silhouettes() == bool(saved_settings.trails), "native probe restores exact original dash preference")
	var report := {"classification": "isolated actual authored Level; story/intro/boss entrance suppressed by tool subclass; no Main chapter completion", "baseline": baseline, "manifest_sha256": FileAccess.get_sha256(manifest_path), "engine_version": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name(), "viewport_size": str(get_viewport().get_visible_rect().size), "hdr_2d": get_viewport().use_hdr_2d, "runtime_seconds": (Time.get_ticks_usec() - started_usec) / 1000000.0, "checks": checks, "failures": failures, "normal_screenshots": shots, "settings_screenshots": settings_shots, "settings_screenshots_max": SETTINGS_SHOT_LIMIT, "settings_screenshot_scope": "actual paused SettingsScreen and main viewport; tool-driven focus/property, no physical keyboard/controller proof", "death_retry_screenshots": lifecycle_shots, "death_retry_screenshots_max": 2, "death_retry_scope": "real Health/Player/Level plus natural clinic retry; isolated visual tool host, no Main save proof", "alignment_screenshots_max": 4, "repeat_dashes": REPEATED_DASHES, "frame_elapsed_count": frame_count, "frame_elapsed_stored": mini(frame_count, SAMPLE_LIMIT), "frame_elapsed_omitted": maxi(0, frame_count - SAMPLE_LIMIT), "frame_elapsed_mean_ms": elapsed_sum / maxi(1, frame_count), "frame_elapsed_max_ms": elapsed_max, "frame_elapsed_distribution": _frame_stats(), "rows": rows, "native_visual_accepted": false, "hardware_input_tested": false, "os_memory": "wrapper os-memory.csv: actual Windows WorkingSet/PrivateBytes; no VRAM measurement or strict physical memory cap", "sources": manifest.get("sources", {})}
	var file := FileAccess.open(out.path_join("NE247-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		push_error("[NE247 probe] report write failed")
		failures.append("report write failed")
	print("NE247_PROBE_FINAL checks=%d failures=%d normal_shots=%d accepted=false" % [checks, failures.size(), shots])
	get_tree().quit(0 if failures.is_empty() else 1)

