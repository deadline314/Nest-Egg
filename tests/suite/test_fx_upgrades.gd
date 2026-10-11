class_name FxUpgradesSuite
extends EnemySuiteBase
## 特效升級收尾（NE-95）：彈道拖尾（固定容量、跟著子彈、重用乾淨）、格擋／完美反彈／衝刺／義體能力／重生的特效、
## 環境（雨的陣風與漣漪、排氣孔噴發、霓虹連閃）、以及所有光影設定下的亮度預算（不過曝）。

## 泛光超出量的預算：(發光倍率上限 - 該光影設定的泛光門檻) × 泛光強度。
const BLOOM_EXCESS_BUDGET := 3.0
const SOURCE_DIRS: Array[String] = ["res://game", "res://autoload", "res://core", "res://ui"]


func run() -> void:
	await _test_ring_surface()
	await _test_dual_team_explosion()
	await _test_blast_shape()
	_test_exposure_budget()
	_test_source_literals()
	await _test_projectile_trails()
	await _test_projectile_sweeps()
	await _test_player_fx()
	await _test_shield_presentation()
	await _test_dash_and_materialize()
	await DashSilhouetteChecks.run(self)
	await _test_environment()


# ---------------------------------------------------------------------------
# 光影設定下的亮度（不過曝）
# ---------------------------------------------------------------------------

func _test_exposure_budget() -> void:
	check(is_equal_approx(LightKit.glow(Color.WHITE, 99.0).r, LightKit.HDR_PEAK_MAX), "glow intensity is clamped to the peak cap")
	check(is_equal_approx(Fx.hdr(Color.WHITE, 99.0).r, LightKit.HDR_PEAK_MAX) and LightKit.glow(Color.WHITE, 1.5).r == 1.5, "Fx.hdr clamps and lower intensities are untouched")
	var checked := 0
	for file in DirAccess.get_files_at("res://data/lighting"):
		if not file.ends_with(".tres"):
			continue
		var profile := load("res://data/lighting/" + file) as LightingProfile
		if profile == null:
			continue
		checked += 1
		var excess := (LightKit.HDR_PEAK_MAX - profile.glow_threshold) * profile.glow_intensity
		check(excess <= BLOOM_EXCESS_BUDGET, "%s keeps the brightest effect within the bloom budget (%.2f of %.1f)" % [file, excess, BLOOM_EXCESS_BUDGET])
	check(checked >= 10, "every lighting profile was checked (%d)" % checked)


## 程式裡寫死的發光倍率不超過上限（算式裡 sin／cos 的參數不算）。
func _test_source_literals() -> void:
	var offenders: PackedStringArray = []
	for dir in SOURCE_DIRS:
		for path in _scripts_under(dir):
			var text := FileAccess.get_file_as_string(path)
			var from := 0
			while true:
				var at := text.find("glow(", from)
				if at < 0:
					break
				from = at + 5
				var args := _call_args(text, from)
				var comma := _top_level_comma(args)
				if comma < 0:
					continue
				var intensity := _strip_trig(args.substr(comma + 1))
				for number in _numbers(intensity):
					if number > LightKit.HDR_PEAK_MAX + 0.001:
						offenders.append("%s:%d (%s)" % [path, text.substr(0, at).count("\n") + 1, intensity.strip_edges().left(40)])
						break
	check(offenders.is_empty(), "no hard-coded glow intensity above %.1f: %s" % [LightKit.HDR_PEAK_MAX, ", ".join(offenders)])


func _scripts_under(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_scripts_under(dir.path_join(sub)))
	return result


## text 從 start（左括號之後）到配對右括號之前的內容。
func _call_args(text: String, start: int) -> String:
	var depth := 1
	var i := start
	while i < text.length() and depth > 0:
		var c := text[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
		i += 1
	return text.substr(start, maxi(0, i - 1 - start))


func _top_level_comma(args: String) -> int:
	var depth := 0
	for i in args.length():
		var c := args[i]
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth -= 1
		elif c == "," and depth == 0:
			return i
	return -1


func _strip_trig(expression: String) -> String:
	var regex := RegEx.create_from_string("(sin|cos|fmod|randf_range|lerpf)\\([^()]*(\\([^()]*\\)[^()]*)*\\)")
	return regex.sub(expression, "0", true)


func _numbers(expression: String) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for m in RegEx.create_from_string("(?<![\\w.])\\d+\\.?\\d*").search_all(expression):
		result.append(float(m.get_string()))
	return result


# ---------------------------------------------------------------------------
# 彈道拖尾
# ---------------------------------------------------------------------------

func _test_projectile_trails() -> void:
	for file in DirAccess.get_files_at("res://data/projectiles"):
		if file.ends_with(".tres"):
			var spec := load("res://data/projectiles/" + file) as ProjectileSpec
			check(spec != null and spec.trail_points >= 0 and spec.trail_points <= Projectile.MAX_TRAIL_POINTS, "%s trail length is within the fixed capacity" % file)
	var rocket := load("res://data/projectiles/grenade.tres") as ProjectileSpec
	check(rocket.smoke_trail and rocket.trail_points > 0, "the launcher shell leaves a smoke trail")
	check(not (load("res://data/projectiles/laser_beam.tres") as ProjectileSpec).trail_points > 1, "the laser beam has no extra trail")
	await open_level(10.0)
	var rifle := load("res://data/projectiles/rifle_shot.tres") as ProjectileSpec
	var bullet := ProjectilePool.spawn(rifle, level.player.global_position + Vector2(0, -60), Vector2.RIGHT, Combat.Team.PLAYER)
	check(bullet != null and bullet._trail_len == 0, "a fresh bullet starts without a trail")
	var capacity: int = bullet._trail.size()
	await physics_frames(4)
	check(bullet._trail_len == 4 and bullet._trail_at(0).distance_to(bullet.global_position) < 0.01, "the trail follows the bullet (%d points)" % bullet._trail_len)
	check(bullet._trail_at(0).x > bullet._trail_at(3).x, "older trail points are behind the bullet")
	await physics_frames(20)
	check(bullet._trail.size() == capacity and bullet._trail_len <= Projectile.MAX_TRAIL_POINTS, "the trail never grows past its fixed capacity")
	bullet.deactivate()
	var again := ProjectilePool.spawn(rifle, level.player.global_position + Vector2(0, -60), Vector2.RIGHT, Combat.Team.PLAYER)
	check(again != null and again._trail_len == 0, "a pooled bullet starts clean (no old trail)")
	again.deactivate()
	await physics_frames(2)
	await end_level(level)


# ---------------------------------------------------------------------------
# 玩家特效
# ---------------------------------------------------------------------------

func _test_shield_presentation() -> void:
	var surface := ShieldSurface.new()
	surface.update(0.04, true, false, Vector2.RIGHT, 120.0)
	check(surface.extension > 0.0 and surface.extension < 1.0, "shield raises progressively without delaying guard")
	check(is_equal_approx(surface._rim[0].angle(), -PI / 3.0) and is_equal_approx(surface._rim[-1].angle(), PI / 3.0), "shield endpoints match the real 120 degree defence cone")
	var front_only := true
	for point in surface._rim:
		front_only = front_only and point.x > 0.0 and is_equal_approx(point.length(), ShieldSurface.RADIUS)
	check(front_only, "the field has body-sized reach and never depicts rear protection")
	surface.update(0.04, true, false, Vector2.UP, 120.0)
	check(is_equal_approx(surface.extension, 1.0) and surface.direction == Vector2.UP, "raised shield follows vertical aim")
	surface.notify_impact(Vector2(-1, 0))
	check(surface.impact_direction == Vector2.LEFT, "impact feedback records the incoming direction")
	surface.update(0.04, false, true, Vector2.LEFT, 120.0)
	check(surface.break_left > 0.0 and surface.extension < 1.0 and surface.direction == Vector2.UP, "guard break fragments retain their direction while lowering")
	surface.update(0.09, false, true, Vector2.LEFT, 120.0)
	check(surface.extension == 0.0 and surface.break_left > 0.0 and surface.direction == Vector2.UP, "break fragments keep the old direction after the base field disappears")
	surface.update(1.0, false, true, Vector2.RIGHT, 120.0)
	check(surface.break_left == 0.0 and surface.extension == 0.0, "lower and break presentation expire without lingering particles")
	var center := Vector2(10, -22)
	check(ShieldSurface.contact(center, Vector2(1, 1), Vector2.RIGHT).is_equal_approx(center + Vector2(1, 1).normalized() * ShieldSurface.RADIUS), "shield contact mark follows the source angle")
	check(ShieldSurface.contact(center, Vector2.ZERO, Vector2.ZERO).is_equal_approx(center + Vector2.RIGHT * ShieldSurface.RADIUS), "missing contact direction has a finite safe fallback")
	await open_level(10.0)
	var player := level.player
	player.set_physics_process(false)
	player.aim_dir = Vector2.RIGHT
	player.is_blocking = true
	player._block_time = player.parry_window_length() + 0.01
	var energy := player.guard
	var info := DamageInfo.create(1, Combat.Team.ENEMY, &"test_shield", Vector2.LEFT * 100.0)
	info.is_projectile = true
	check(player._guard(info) == Hurtbox.Guard.BLOCK and player.guard < energy, "larger shield still consumes normal guard energy")
	energy = player.guard
	info.knockback = Vector2.RIGHT * 100.0
	check(player._guard(info) == Hurtbox.Guard.NONE and player.guard == energy, "rear projectile passes through without spending guard")
	info.knockback = -Vector2.RIGHT.rotated(deg_to_rad(61.0)) * 100.0
	check(player._guard(info) == Hurtbox.Guard.NONE, "one degree beyond visible shield remains undefended")
	info.knockback = -Vector2.RIGHT.rotated(deg_to_rad(59.0)) * 100.0
	player._block_time = 0.0
	check(player._guard(info) == Hurtbox.Guard.REFLECT, "inside the visible cone the original perfect window reflects once")
	check(player._visual._shield.impact_direction.is_equal_approx(Vector2.RIGHT.rotated(deg_to_rad(59.0))), "off-centre reflection marks its own shield segment")
	await end_level(level)


func _test_player_fx() -> void:
	await open_level(10.0)
	var player := level.player
	var at := player.global_position + Vector2(20, -24)
	var recipes := {
		"parry": func() -> void: PlayerFx.parry(at, Vector2.RIGHT),
		"block": func() -> void: PlayerFx.block(at, Vector2(-1, 0)),
		"dash": func() -> void: PlayerFx.dash(player.global_position, Vector2.RIGHT),
		"ability": func() -> void: PlayerFx.ability(at, Palette.CYAN, 150.0),
		"respawn": func() -> void: PlayerFx.respawn(player.global_position),
	}
	for name: String in recipes.keys():
		await physics_frames(60)  # 讓上一個配方的粒子散掉
		var before := Fx.particle_count()
		(recipes[name] as Callable).call()
		var added := Fx.particle_count() - before
		check(added >= 1 and added <= 40, "%s fx emits a bounded number of particles (%d)" % [name, added])
	# 呼叫端確實觸發：完美反彈與格擋。
	await physics_frames(60)
	var base := Fx.particle_count()
	player._on_parry(DamageInfo.create(1, Combat.Team.ENEMY, &"test"), at)
	check(Fx.particle_count() - base >= 10, "a perfect parry plays the new burst on top of the old effect (%d)" % (Fx.particle_count() - base))
	await physics_frames(3)
	await end_level(level)


func _test_dash_and_materialize() -> void:
	await open_level(10.0)
	var player := level.player
	var visual: PlayerVisual = player._visual
	player._dash_cooldown_left = 0.0
	player._try_dash(1.0)
	await physics_frames(12)
	check(is_instance_valid(visual._ghost_pool) and visual._ghost_pool.active_count() > 0 and visual._ghost_pool.active_count() <= PlayerVisual.MAX_GHOSTS, "real dash leaves bounded actual-pose silhouettes")
	if is_instance_valid(visual._ghost_pool):
		for slot in visual._ghost_pool.slots:
			if slot.visible:
				check(absf(slot.facing) == 1.0 and slot.used > 0, "actual-pose snapshot stores a valid captured rig facing and geometry")
	await physics_frames(60)
	check(is_instance_valid(visual._ghost_pool) and visual._ghost_pool.active_count() == 0, "afterimages fade out and release source texture leases")
	visual.notify_parry()
	await frames(2)
	check(visual._parry_flash > 0.0, "the parry starburst is playing")
	player.play_respawn_fx()
	await frames(2)
	check(visual._materialize_left > 0.0 and visual.modulate.a < 1.0, "a respawn fades the body in")
	await physics_frames(int(PlayerVisual.MATERIALIZE_TIME * 60.0) + 12)
	await frames(2)
	check(visual._materialize_left == 0.0 and visual.modulate.a >= 0.99, "the fade-in ends fully visible")
	await end_level(level)


# ---------------------------------------------------------------------------
# 環境
# ---------------------------------------------------------------------------

func _test_environment() -> void:
	await open_level(10.0)
	var rain := RainLayer.new()
	level.add_child(rain)
	var winds: Array[float] = []
	for t in [0.0, 3.0, 7.0, 11.0, 19.0]:
		rain._time = t
		winds.append(rain._wind())
	check(winds.max() - winds.min() > 0.02 and winds.min() > 0.0 and winds.max() < RainLayer.WIND * 2.0, "the wind gusts but stays in range (%.3f..%.3f)" % [winds.min(), winds.max()])
	rain._time = 0.0
	var drift := rain._drift
	rain._process(0.5)
	check(rain._drift > drift, "rain drift accumulates with the wind")
	await frames(3)
	rain.queue_free()
	var vent := SteamVent.new()
	level.add_child(vent)
	vent.position = level.player.global_position + Vector2(200, 0)
	var bursts := 0
	var was := false
	vent._burst_in = 0.1
	for i in 600:
		vent._process(1.0 / 30.0)
		var now := vent._burst_left > 0.0
		if now and not was:
			bursts += 1
		was = now
	check(bursts >= 2, "the vent bursts periodically (%d bursts in 20 s)" % bursts)
	vent.queue_free()
	var sign_node := NeonSign.new()
	sign_node.text = "拉麵"
	level.add_child(sign_node)
	await frames(2)
	sign_node._burst_flicks = 2
	sign_node._off_left = 0.05
	var offs := 0
	var was_off := false
	for i in 120:
		sign_node._process(1.0 / 60.0)
		var off_now := sign_node._off_left > 0.0
		if off_now and not was_off:
			offs += 1
		was_off = off_now
		if offs >= 3:
			break
	check(offs >= 2, "a neon flicker can come in a quick burst of several blinks (%d)" % offs)
	check(sign_node._restrike_left >= 0.0, "the sign re-strikes after a blink")
	sign_node.queue_free()
	await physics_frames(3)
	await end_level(level)


func _test_ring_surface() -> void:
	var first := ShockRing.new()
	var second := ShockRing.new()
	runner.add_child(first)
	runner.add_child(second)
	check(first.texture is ImageTexture and first.texture == second.texture, "pooled shock rings share one real UV surface")
	var image := first.texture.get_image()
	check(image.get_size() == Vector2i(2, 2) and not image.has_mipmaps(), "shock carrier is a tiny unmipped surface")
	var texture := first.texture
	first.play(Vector2(123, 87), 46.0, 0.02, Palette.CYAN, 0.1)
	check(first.global_position == Vector2(123, 87) and first.get_rect().get_center() == Vector2.ZERO, "shock geometry stays centered on its world contact")
	first.play(Vector2(50, 70), 64.0, 0.02, Palette.WARNING, 0.1)
	check(first.texture == texture and first.get_child_count() == 0, "replaying a ring reuses its texture and creates no child nodes")
	first.queue_free()
	second.queue_free()
	await frames(2)


func _test_dual_team_explosion() -> void:
	await open_level(10.0)
	var enemy := spawn(GRUNT_PATH, 12.0)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.health.setup(999, 0.0)
	level.player.health.setup(999, 0.0)
	await physics_frames(2)
	var flashes: Array[int] = [0]
	var on_flash := func(_color: Color, _strength: float, _duration: float) -> void: flashes[0] += 1
	EventBus.ambient_flash_requested.connect(on_flash)
	var at := level.player.global_position + Vector2(16, -20)
	Fx.explosion(at, 64.0, 2, Combat.Team.PLAYER, &"test_barrel_dual")
	Fx.explosion(at, 64.0, 2, Combat.Team.ENEMY, &"test_barrel_dual")
	await physics_frames(4)
	EventBus.ambient_flash_requested.disconnect(on_flash)
	check(flashes[0] == 1, "dual-team barrel emits one ambient flash")
	check(level.player.health.current < 999 and enemy.health.current < 999, "deduplicating blast visuals preserves damage to both teams")
	await end_level(level)


## 貼地的爆炸只往上炸開、火球不沉到地板底下；半空中的爆炸四面炸開。
func _test_blast_shape() -> void:
	await open_level(10.0)
	level.player.health.setup(999, 0.0)
	await physics_frames(2)
	var feet := level.player.global_position
	var soft: ParticleField = Fx._soft
	var before := soft.alive_count()
	var floor_y := Fx._floor_below(feet + Vector2(60, -8), 48.0)
	check(not is_nan(floor_y) and absf(floor_y - feet.y) < 4.0, "the ground under a blast is found (%.1f vs feet %.1f)" % [floor_y, feet.y])
	check(is_nan(Fx._floor_below(feet + Vector2(60, -160), 48.0)), "a blast high in the air has no ground under it")
	Fx.explosion(feet + Vector2(60, -8), 64.0, 0, Combat.Team.PLAYER, &"test_blast_ground")
	var blobs := _blast_blobs(soft)
	check(soft.alive_count() - before >= 6 and blobs.size() >= 6, "a blast is built from flat cloud layers (%d blobs)" % blobs.size())
	var sunk := 0
	var downward := 0
	for index: int in blobs:
		if soft._pos[index].y > floor_y + 0.5:
			sunk += 1
		if soft._vel[index].y > 0.5:
			downward += 1
	check(sunk == 0 and downward == 0, "a grounded blast opens upward only (%d below the floor, %d heading down)" % [sunk, downward])
	await frames(90)
	check(_blast_blobs(soft).is_empty(), "the fireball and its smoke are gone within 1.5 seconds")
	Fx.explosion(feet + Vector2(60, -160), 40.0, 0, Combat.Team.PLAYER, &"test_blast_air", Palette.CYAN)
	downward = 0
	for index: int in _blast_blobs(soft):
		if soft._vel[index].y > 0.5:
			downward += 1
	check(downward > 0, "a blast in the air opens in every direction")
	await frames(4)
	await end_level(level)


func _blast_blobs(field: ParticleField) -> PackedInt32Array:
	var result := PackedInt32Array()
	for index in ParticleField.CAPACITY:
		if field._life[index] > 0.0 and (field._cell[index] == VfxAtlas.Cell.BLOB_A or field._cell[index] == VfxAtlas.Cell.BLOB_B):
			result.append(index)
	return result


## NE-238: a fast head must hit a thin target before its visible tail crosses it.
func _test_projectile_sweeps() -> void:
	var container := Node2D.new()
	runner.add_child(container)
	ProjectilePool.bind_container(container)
	var target := _projectile_target(container, Vector2(100, 0), Combat.Team.ENEMY)
	await physics_frames(2)
	for id in ["pistol", "rifle", "smg", "spread", "laser", "railgun", "launcher", "mech_cannon"]:
		var weapon := load("res://data/weapons/%s.tres" % id) as WeaponData
		var projectile_spec := weapon.projectile.duplicate() as ProjectileSpec
		projectile_spec.gravity = 0.0 # A straight lane isolates collision from ballistic aim.
		projectile_spec.explosion_radius = 0.0
		target.health.setup(100, 0.0)
		var bullet := ProjectilePool.spawn(projectile_spec, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER)
		bullet.set_physics_process(false)
		bullet._physics_process(0.5)
		check(target.health.current == 100 - projectile_spec.damage, "%s does not tunnel through a thin target on a long frame" % id)
		check(bullet.global_position.x < 108.0 or projectile_spec.pierce > 0, "%s impact stays at the head rather than the far end of its frame" % id)
		bullet.deactivate()
		await physics_frames(1)
	var rail := (load("res://data/projectiles/rail_slug.tres") as ProjectileSpec).duplicate() as ProjectileSpec
	var second := _projectile_target(container, Vector2(150, 0), Combat.Team.ENEMY)
	await physics_frames(2)
	target.health.setup(100, 0.0)
	var piercing := ProjectilePool.spawn(rail, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER)
	piercing.set_physics_process(false)
	piercing._physics_process(0.2)
	check(target.health.current == 94 and second.health.current == 94, "rail sweep pierces two separate targets once each within one frame")
	piercing.deactivate()
	target.guard = func(_info: DamageInfo) -> Hurtbox.Guard: return Hurtbox.Guard.REFLECT
	target.reflect_direction = Vector2.LEFT
	var friendly := _projectile_target(container, Vector2(30, 0), Combat.Team.PLAYER)
	await physics_frames(2)
	var reflected := ProjectilePool.spawn(rail, Vector2(50, 0), Vector2.RIGHT, Combat.Team.PLAYER)
	reflected.set_physics_process(false)
	reflected._physics_process(0.15)
	check(reflected.team == Combat.Team.ENEMY and friendly.health.current == 88, "reflection changes the swept mask and hits the new opposing team in the remaining frame")
	check(reflected.spec == rail and reflected._trail_len <= 1, "reflection keeps its original projectile type without a trail across the reflector")
	reflected.deactivate()
	target.guard = Callable()
	var wall := StaticBody2D.new()
	wall.position = Vector2(100, 80)
	wall.collision_layer = Layers.WORLD
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2, 50)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	container.add_child(wall)
	await physics_frames(2)
	var blocked := ProjectilePool.spawn(rail, Vector2(0, 80), Vector2.RIGHT, Combat.Team.PLAYER)
	blocked.set_physics_process(false)
	blocked._physics_process(0.2)
	check(not blocked.active and blocked.position.x < 103, "fast piercing heads stop at thin solid walls")
	rail.passes_walls = true
	var bypass := ProjectilePool.spawn(rail, Vector2(0, 80), Vector2.RIGHT, Combat.Team.PLAYER)
	bypass.set_physics_process(false)
	bypass._physics_process(0.2)
	check(bypass.active and bypass.position.x > 200, "wall-passing projectiles preserve their actual collision rule")
	bypass.deactivate()
	var reuse := ProjectilePool.spawn(load("res://data/projectiles/spread_pellet.tres"), Vector2(0, 160), Vector2.RIGHT, Combat.Team.PLAYER)
	check(reuse == bypass and reuse._damage_scale == 1.0 and reuse.team == Combat.Team.PLAYER and reuse._trail_len == 0, "reused projectile clears reflection, team and old trajectory when the gun changes")
	reuse.deactivate()
	# An invulnerable foreground hurtbox cannot eat a round aimed at a valid target.
	target.health.setup(100, 0.0)
	second.health.setup(100, 0.0)
	target.health.grant_invulnerability(60.0)
	var pistol := load("res://data/projectiles/pistol_shot.tres") as ProjectileSpec
	var through_immune := ProjectilePool.spawn(pistol, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER)
	through_immune.set_physics_process(false)
	through_immune._physics_process(0.4)
	check(target.health.current == 100 and second.health.current == 99, "an invulnerable foreground hurtbox does not hide a valid target behind it")
	through_immune.deactivate()
	target.health._physics_process(60.0) # Expire the temporary immunity through the real timer.
	var overlap := ProjectilePool.spawn(pistol, target.global_position, Vector2.RIGHT, Combat.Team.PLAYER)
	overlap.set_physics_process(false)
	overlap._physics_process(1.0 / 60.0)
	check(target.health.current == 99 and not overlap.active, "initial overlap health=%d active=%s position=%s can_receive=%s" % [target.health.current, overlap.active, overlap.position, target.can_receive()])
	# Reuse and reflect every shipped player gun, not only the fastest rail slug.
	target.position.x = 300.0
	friendly.position.x = 200.0
	target.guard = func(_info: DamageInfo) -> Hurtbox.Guard: return Hurtbox.Guard.REFLECT
	await physics_frames(2)
	var gun_names := ["pistol", "rifle", "smg", "spread", "laser", "railgun", "launcher", "mech_cannon"]
	var doubled_damage := [2, 2, 2, 2, 6, 12, 2, 6]
	for i in gun_names.size():
		var weapon := load("res://data/weapons/%s.tres" % gun_names[i]) as WeaponData
		var gun_spec := weapon.projectile.duplicate() as ProjectileSpec
		gun_spec.gravity = 0.0
		gun_spec.explosion_radius = 0.0
		friendly.health.setup(100, 0.0)
		var round_trip := ProjectilePool.spawn(gun_spec, Vector2(250, 0), Vector2.RIGHT, Combat.Team.PLAYER)
		round_trip.set_physics_process(false)
		round_trip._physics_process(0.6)
		check(round_trip.team == Combat.Team.ENEMY and friendly.health.current == 100 - doubled_damage[i], "%s reflection team=%d health=%d position=%s target_receives=%s" % [gun_names[i], round_trip.team, friendly.health.current, round_trip.position, target.can_receive()])
		check(round_trip.spec == gun_spec, "%s reflection retains its gun-specific head" % gun_names[i])
		round_trip.deactivate()
		await physics_frames(1)
	target.guard = Callable()
	# Damage is counted by shared health, even when a head and body overlap.
	target.add_part(&"overlap", Vector2(4, 40), Vector2.ZERO, 1.0)
	second.position.x = 350.0
	target.health.setup(100, 0.0)
	second.health.setup(100, 0.0)
	await physics_frames(2)
	var layered := ProjectilePool.spawn(rail, Vector2(250, 0), Vector2.RIGHT, Combat.Team.PLAYER)
	layered.set_physics_process(false)
	layered._physics_process(0.2)
	check(target.health.current == 94 and second.health.current == 94, "piercing overlapping parts damage once: %d/%d at %s" % [target.health.current, second.health.current, layered.position])
	layered.deactivate()
	# The physical radius, not the drawn tail, decides a near miss and a graze.
	target.health.setup(100, 0.0)
	var markers: Array[StringName] = []
	var listener := func(kind: StringName) -> void: markers.append(kind)
	EventBus.hit_marker.connect(listener)
	var miss := ProjectilePool.spawn(pistol, Vector2(250, 22.1), Vector2.RIGHT, Combat.Team.PLAYER)
	miss.set_physics_process(false)
	miss._physics_process(0.1)
	check(target.health.current == 100 and markers.is_empty(), "a round outside the physical head radius causes neither damage nor hit feedback")
	miss.deactivate()
	var graze := ProjectilePool.spawn(pistol, Vector2(250, 21.9), Vector2.RIGHT, Combat.Team.PLAYER)
	graze.set_physics_process(false)
	graze._physics_process(0.1)
	check(target.health.current == 99 and markers.size() == 1, "grazing physical head hits once: health=%d markers=%d at %s" % [target.health.current, markers.size(), graze.position])
	graze.deactivate()
	EventBus.hit_marker.disconnect(listener)
	container.queue_free()
	await physics_frames(2)


func _projectile_target(container: Node2D, at: Vector2, owner_team: Combat.Team) -> Hurtbox:
	var health := HealthComponent.new()
	container.add_child(health)
	health.setup(100, 0.0)
	var target := Hurtbox.new()
	target.position = at
	target.setup(owner_team, health, Vector2(4, 40))
	container.add_child(target)
	return target
