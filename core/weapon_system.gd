class_name WeaponSystem
extends RefCounted
## 射擊共用邏輯：玩家、載具、敵人與頭目都透過這裡發射子彈，確保行為一致。


## 依武器資料開火，回傳實際生成的子彈數（子彈池滿載時可能少於預期）。
## extra_random_degrees：額外的隨機散佈（例如連射造成的準星擴散）。
static func fire(weapon: WeaponData, origin: Vector2, direction: Vector2, team: Combat.Team, speed_multiplier := 1.0,
		extra_random_degrees := 0.0) -> int:
	if weapon == null or not weapon.is_valid():
		return 0
	return fire_spread(weapon.projectile, origin, direction, weapon.pellets, weapon.spread_degrees,
			weapon.random_spread_degrees + maxf(0.0, extra_random_degrees), team, speed_multiplier)


## 以扇形發射多顆子彈。count = 1 時即為單發。
static func fire_spread(spec: ProjectileSpec, origin: Vector2, direction: Vector2, count: int,
		spread_degrees: float, random_degrees: float, team: Combat.Team, speed_multiplier := 1.0) -> int:
	if spec == null:
		return 0
	var base := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var total := maxi(1, count)
	var spawned := 0
	for i in total:
		var angle := 0.0
		if total > 1:
			angle = lerpf(-spread_degrees * 0.5, spread_degrees * 0.5, float(i) / float(total - 1))
		if random_degrees > 0.0:
			angle += randf_range(-random_degrees, random_degrees)
		if ProjectilePool.spawn(spec, origin, base.rotated(deg_to_rad(angle)), team, speed_multiplier) != null:
			spawned += 1
	return spawned
