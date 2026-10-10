extends "res://game/enemies/warden_boss.gd"
## Private instrumentation only: call the original Warden FSM tick, then snapshot pool positions synchronously.

var core_fire_probe: Dictionary = {}


func begin_probe_fire() -> void:
	_phase = 2
	fsm.transition(&"core_windup")


func _core_windup_tick(delta: float) -> void:
	if is_telegraphing():
		super._core_windup_tick(delta)
		return
	var local_core := _core_point()
	var expected_world := to_global(local_core)
	var legacy_world := local_core + global_position
	var active_before: Dictionary = {}
	var pool := ProjectilePool.container()
	if pool != null:
		for child in pool.get_children():
			var projectile := child as Projectile
			if projectile != null and projectile.active:
				active_before[projectile.get_instance_id()] = true
	super._core_windup_tick(delta)
	var spawned: Array[Dictionary] = []
	if pool != null:
		for child in pool.get_children():
			var projectile := child as Projectile
			if projectile == null or not projectile.active or active_before.has(projectile.get_instance_id()):
				continue
			if projectile.team != Combat.Team.ENEMY or projectile.spec != data.find_projectile(&"boss_fan"):
				continue
			var actual := projectile.global_position
			spawned.append({
				"global_position": [projectile.global_position.x, projectile.global_position.y],
				"velocity": [projectile.velocity.x, projectile.velocity.y],
				"error_to_expected_core": actual.distance_to(expected_world),
				"error_to_legacy_formula": actual.distance_to(legacy_world),
			})
	core_fire_probe = {
		"local_core": [local_core.x, local_core.y],
		"expected_core_world": [expected_world.x, expected_world.y],
		"legacy_formula_world": [legacy_world.x, legacy_world.y],
		"legacy_to_expected_error": legacy_world.distance_to(expected_world),
		"rig_core_bone_world": [rig.bone(&"core_port").global_position.x, rig.bone(&"core_port").global_position.y],
		"spawned_projectiles": spawned,
		"spawn_count": spawned.size(),
	}
