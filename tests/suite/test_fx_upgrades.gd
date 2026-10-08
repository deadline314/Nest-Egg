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
	_test_exposure_budget()
	_test_source_literals()
	await _test_projectile_trails()
	await _test_player_fx()
	await _test_dash_and_materialize()
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
	check(visual._ghosts.size() > 0 and visual._ghosts.size() <= PlayerVisual.MAX_GHOSTS, "dash leaves a capped number of afterimages (%d)" % visual._ghosts.size())
	check(visual._ghosts.is_empty() or visual._ghosts[0].w == 1.0, "afterimages remember the dash direction")
	await physics_frames(60)
	check(visual._ghosts.is_empty(), "afterimages fade out")
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
