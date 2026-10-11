class_name WeaponSystem
extends RefCounted
## 射擊共用邏輯：玩家、載具、敵人與頭目都透過這裡發射子彈，確保行為一致。


## 依武器資料開火，回傳實際生成的子彈數（子彈池滿載時可能少於預期）。
## extra_random_degrees：額外的隨機散佈（例如連射造成的準星擴散）。
static func fire(weapon: WeaponData, origin: Vector2, direction: Vector2, team: Combat.Team, speed_multiplier := 1.0,
		extra_random_degrees := 0.0) -> int:
	if weapon == null or weapon.is_melee():
		return 0
	if not can_fire(weapon, origin, direction, team, speed_multiplier, extra_random_degrees):
		return 0
	return fire_spread(weapon.projectile, origin, direction, weapon.pellets, weapon.spread_degrees,
			weapon.random_spread_degrees + maxf(0.0, extra_random_degrees), team, speed_multiplier)


## Acceptance is independent of pool capacity: callers use this before paying
## ammo/cooldown or emitting feedback; fire() repeats it for direct callers.
static func can_fire(weapon: WeaponData, origin: Vector2, direction: Vector2, team: Combat.Team,
		speed_multiplier := 1.0, extra_random_degrees := 0.0, fire_rate_scale := 1.0) -> bool:
	var problems := shot_problems(weapon, origin, direction, team, speed_multiplier, extra_random_degrees, fire_rate_scale)
	if problems.is_empty():
		return true
	var source := "missing weapon" if weapon == null else (weapon.resource_path if not weapon.resource_path.is_empty() else str(weapon.id))
	push_error("[WeaponSystem] %s/shot: %s; refusing before shot costs/feedback" % [source, problems])
	return false


static func shot_problems(weapon: WeaponData, origin: Vector2, direction: Vector2, team: Combat.Team,
		speed_multiplier := 1.0, extra_random_degrees := 0.0, fire_rate_scale := 1.0) -> PackedStringArray:
	if weapon == null:
		return PackedStringArray(["weapon missing"])
	if weapon.is_melee():
		return PackedStringArray(["melee weapon cannot fire projectiles"])
	var problems := weapon.validate()
	if weapon.projectile != null:
		for problem in weapon.projectile.spawn_problems(origin, direction, speed_multiplier):
			problems.append("projectile " + problem)
	if team not in [Combat.Team.PLAYER, Combat.Team.ENEMY]:
		problems.append("team unknown combat team")
	if not is_finite(extra_random_degrees) or absf(extra_random_degrees) > 360.0:
		problems.append("extra_random_degrees outside finite +/-360")
	elif weapon.random_spread_degrees + maxf(0.0, extra_random_degrees) > 360.0:
		problems.append("combined random_spread_degrees exceeds 360")
	# A bounded denominator prevents zero/overflow cooldown and unsafe sound speed.
	# These are corruption bounds, not a change to any shipped ability or weapon.
	if not is_finite(fire_rate_scale) or fire_rate_scale < 0.1 or fire_rate_scale > 8.0:
		problems.append("fire_rate_scale outside finite 0.1–8")
	return problems


## 槍口回饋（閃光、光、火花、鏡頭後座與震動）：數值全來自武器資料；連發武器依 muzzle_fx_interval 節流。
## 回傳這一發是否播了槍口特效。
static func muzzle_feedback(weapon: WeaponData, muzzle: Vector2, direction: Vector2) -> bool:
	if weapon == null:
		return false
	var problems := weapon.numeric_problems()
	for field: String in ["muzzle", "direction"]:
		var value: Vector2 = muzzle if field == "muzzle" else direction
		if not is_finite(value.x) or not is_finite(value.y) or absf(value.x) > ProjectileSpec.MAX_VECTOR_COMPONENT or absf(value.y) > ProjectileSpec.MAX_VECTOR_COMPONENT:
			problems.append(field + " exceeds finite vector component bound")
	if not problems.is_empty():
		push_error("[WeaponSystem] %s/muzzle_feedback: %s; refusing unsafe feedback" % [weapon.id, problems])
		return false
	Fx.kick(-direction, weapon.camera_kick)
	Feel.shake_strength(weapon.screen_shake, weapon.screen_shake_time, -direction, muzzle)
	var now := Time.get_ticks_msec()
	if float(now - int(_last_muzzle_fx.get(weapon.id, -100000))) < weapon.muzzle_fx_interval * 1000.0:
		return false
	_last_muzzle_fx[weapon.id] = now
	Fx.flash_light(muzzle, weapon.color, weapon.muzzle_light_radius, weapon.muzzle_light_energy * Settings.flash_scale(), 0.08)
	Fx.flare(muzzle, weapon.color, weapon.muzzle_flare_size, 0.05)
	if weapon.muzzle_spark_count > 0:
		Fx.sparks(muzzle, weapon.color, weapon.muzzle_spark_count, 280.0, 0.14, direction, 0.7, 240.0)
	return true


static var _last_muzzle_fx: Dictionary = {}


## 以扇形發射多顆子彈。count = 1 時即為單發。
static func fire_spread(spec: ProjectileSpec, origin: Vector2, direction: Vector2, count: int,
		spread_degrees: float, random_degrees: float, team: Combat.Team, speed_multiplier := 1.0) -> int:
	if spec == null:
		return 0
	var problems := spec.spawn_problems(origin, direction, speed_multiplier)
	if count < 1 or count > WeaponData.MAX_PELLETS:
		problems.append("pellets/count outside 1–%s" % WeaponData.MAX_PELLETS)
	for field: String in ["spread_degrees", "random_degrees"]:
		var value: float = spread_degrees if field == "spread_degrees" else random_degrees
		if not is_finite(value) or value < 0.0 or value > 360.0:
			problems.append(field + " outside finite 0–360")
	if not problems.is_empty():
		push_error("[WeaponSystem] %s: %s; refusing spread" % [spec.source_context(), problems])
		return 0
	var base := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var total := count # Validated above: at most MAX_PELLETS spawn attempts.
	var spawned := 0
	for i in total:
		var angle := 0.0
		if total > 1:
			angle = lerpf(-spread_degrees * 0.5, spread_degrees * 0.5, float(i) / float(total - 1))
		if random_degrees > 0.0:
			angle += randf_range(-random_degrees, random_degrees)
		if ProjectilePool.spawn(spec, origin, base.rotated(deg_to_rad(angle)), team, speed_multiplier) == null:
			break # A full/unbound pool cannot recover within this synchronous shot.
		spawned += 1
	return spawned
