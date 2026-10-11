class_name ProgressionSuite
extends TestSuite
## 成長系統（NE-32）：信用點、武器改裝、背包改裝頁、檢查點還原。

const MAP_PATH := "res://tests/fixtures/credits_map.json"
const RIFLE_PATH := "res://data/weapons/rifle.tres"
const PISTOL_PATH := "res://data/weapons/pistol.tres"
const SPREAD_PATH := "res://data/weapons/spread.tres"
const CANNON_PATH := "res://data/weapons/mech_cannon.tres"
const MAG_ID := &"mag_boost"
const BARREL_ID := &"steady_barrel"
const RELOAD_ID := &"quick_reload"


func run() -> void:
	_test_data()
	_test_melee_catalog_preparation()
	_test_unified_weapon_catalog()
	_test_corrupt_catalog_definitions()
	_test_nested_catalog_resources()
	_test_extreme_numeric_definitions()
	_test_actual_schema_negative_guard()
	_test_bounded_runtime_fire()
	_test_credits()
	_test_upgrades()
	_test_loadout_tuning()
	_test_snapshot()
	await _test_pickups_and_checkpoint()
	await _test_upgrades_page()


func _test_melee_catalog_preparation() -> void:
	var saved := Progression.snapshot()
	Progression.reset_run()
	Progression.add_credits(1000)
	var purchased: Array[WeaponData] = []
	for file in DirAccess.get_files_at("res://data/weapons/melee"):
		if not file.ends_with(".tres"):
			continue
		var weapon := load("res://data/weapons/melee/" + file) as WeaponData
		var upgrade := Progression.find_upgrade(MeleeData.set_of(weapon).extension_upgrade())
		check(Progression.buy_upgrade(weapon, upgrade), "catalog preparation buys real technique: %s" % weapon.id)
		purchased.append(weapon)
	var bought := Progression.snapshot()
	var prepared := Progression.prepare_install(bought)
	check(not prepared.has("error"), "all real melee techniques pass strict preparation: %s" % prepared.get("error", "accepted"))
	check(Progression.snapshot() == bought, "preparation does not mutate live progression")
	if prepared.has("data"):
		Progression.reset_run()
		Progression._install_prepared(prepared.data)
		for weapon in purchased:
			check(Progression.has_upgrade(weapon, MeleeData.set_of(weapon).extension_upgrade()), "prepared install retains purchased technique: %s" % weapon.id)
	var before := Progression.snapshot()
	for corruption in ["unknown_weapon", "wrong_technique", "repeat", "unknown_upgrade"]:
		var bad := bought.duplicate(true)
		match corruption:
			"unknown_weapon": bad.upgrades.test_no_such_weapon = ["technique_dagger"]
			"wrong_technique": bad.upgrades.melee_blade = ["technique_dagger"]
			"repeat": bad.upgrades.melee_dagger = ["technique_dagger", "technique_dagger"]
			"unknown_upgrade": bad.upgrades.melee_dagger = ["test_catalog_unknown_upgrade"]
		var rejected := Progression.prepare_install(bad)
		check(rejected.has("error") and str(rejected.error).begins_with("install/progression/upgrades"), "strict catalog rejects %s with a concrete field" % corruption)
		check(Progression.snapshot() == before, "rejected %s preserves live state" % corruption)
	Progression.restore(saved)


func _test_unified_weapon_catalog() -> void:
	var path := "res://core/weapon_catalog.gd"
	check(ResourceLoader.exists(path), "runtime has one authoritative weapon/profile/upgrade catalog")
	if not ResourceLoader.exists(path):
		return
	var script: Script = load(path)
	var catalog = script.call(&"load_all")
	check(catalog.issues.is_empty(), "real authoritative weapon catalog has no invalid definitions: %s" % catalog.issues)
	check(catalog.default_melee == MeleeData.default_set(), "catalog also includes the actual unarmed/default melee profile")
	var files := _weapon_definition_files("res://data/weapons")
	check(catalog.weapons.size() == files.size(), "catalog covers every actual weapon resource, including nested melee")
	for file in files:
		var weapon := load(file) as WeaponData
		var found = catalog.find_weapon(weapon.id)
		check(found == weapon and found.display_name == weapon.display_name, "catalog keeps actual resource and weapon name: %s" % file)
		if weapon.is_melee():
			var profile = catalog.profiles.get(weapon.id)
			check(profile == MeleeData.set_of(weapon), "catalog references actual runtime melee profile: %s" % weapon.id)
			var json: JSON = load("res://data/melee/%s.json" % weapon.melee_profile)
			for attack_id: String in json.data.attacks:
				var original: Dictionary = json.data.attacks[attack_id]
				var actual: Dictionary = profile.attack(attack_id)
				for key in ["windup", "active", "recovery", "damage", "knockback"]:
					check(actual[key] == original[key], "catalog preserves %s/%s/%s actual definition" % [weapon.id, attack_id, key])
				check(actual.guard_cost == original.get("guard_cost", 0.0), "catalog preserves %s/%s energy cost" % [weapon.id, attack_id])
			var upgrade = catalog.find_upgrade(profile.extension_upgrade())
			check(upgrade == Progression.find_upgrade(profile.extension_upgrade()) and upgrade.applies_to(weapon), "catalog links actual optional upgrade: %s" % weapon.id)


func _weapon_definition_files(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			result.append(dir.path_join(file))
	for child in DirAccess.get_directories_at(dir):
		result.append_array(_weapon_definition_files(dir.path_join(child)))
	return result


func _test_corrupt_catalog_definitions() -> void:
	var script: Script = load("res://core/weapon_catalog.gd")
	var good := load(RIFLE_PATH) as WeaponData
	var upgrades: Array[Resource] = []
	for upgrade in Progression.upgrade_catalog():
		upgrades.append(upgrade)
	for kind in ["duplicate", "wrong_type", "nonfinite_fire", "negative_ammo", "missing_projectile", "nonfinite_projectile", "unknown_shape", "missing_profile"]:
		var bad := good.duplicate() as WeaponData
		bad.id = &"test_catalog_bad_weapon"
		var resources: Array[Resource] = [good]
		match kind:
			"duplicate": bad.id = good.id
			"wrong_type": resources.append(Resource.new())
			"nonfinite_fire": bad.fire_interval = NAN
			"negative_ammo": bad.magazine_size = -1
			"missing_projectile": bad.projectile = null
			"nonfinite_projectile":
				bad.projectile = bad.projectile.duplicate()
				bad.projectile.knockback = INF
			"unknown_shape":
				bad.melee_profile = "mono_dagger"
				bad.melee_shape = "test_catalog_unknown_shape"
			"missing_profile": bad.melee_profile = "test_no_such_attack_catalog"
		if kind != "wrong_type":
			resources.append(bad)
		var catalog = script.call(&"from_resources", resources, upgrades)
		check(not catalog.issues.is_empty(), "catalog diagnoses %s instead of accepting a bad resource" % kind)
		check(catalog.weapons.size() == 1 and catalog.find_weapon(good.id) == good, "catalog excludes %s and retains the actual valid resource" % kind)
		check(catalog.find_weapon(&"test_no_such_weapon") == null, "unknown weapon has no fabricated definition")
	for kind in ["nan_amount", "unknown_effect", "wrong_weapon", "missing_tail_upgrade", "duplicate_upgrade"]:
		var bad := Progression.find_upgrade(&"technique_dagger").duplicate() as WeaponUpgradeData
		var resources: Array[Resource] = [load("res://data/weapons/melee/melee_dagger.tres")]
		var candidates: Array[Resource] = [bad]
		match kind:
			"nan_amount": bad.amount = NAN
			"unknown_effect": bad.effect = 99
			"wrong_weapon": bad.melee_weapon_id = &"test_no_such_weapon"
			"missing_tail_upgrade": bad.id = &"test_catalog_wrong_upgrade"
			"duplicate_upgrade": candidates.append(bad.duplicate())
		var catalog = script.call(&"from_resources", resources, candidates)
		check(not catalog.issues.is_empty(), "catalog diagnoses %s upgrade reference" % kind)
		if kind != "duplicate_upgrade":
			check(catalog.weapons.is_empty() and catalog.upgrades.is_empty(), "invalid %s cannot authorize a tail purchase or install" % kind)
	var original: JSON = load("res://data/melee/mono_dagger.json")
	for field in ["windup", "damage", "guard_cost", "knockback", "shape", "sweep", "trail", "sounds", "test_catalog_unknown_field"]:
		var set := MeleeSet.new("res://test_no_such_attack_catalog_corrupt")
		set._loaded = true
		set._data = original.data.duplicate(true)
		var attack: Dictionary = set._data.attacks.stab_1
		match field:
			"windup": attack.windup = NAN
			"damage": attack.damage = 1.0e30
			"guard_cost": attack.guard_cost = -30.0
			"knockback": attack.knockback = ["bad", INF]
			"shape": attack.shape = ["wrong type"]
			"sweep": attack.sweep = "not boolean"
			"trail": attack.trail = {"life": "bad"}
			"sounds": attack.sounds = {"hit": ["not sound"]}
			_: attack[field] = 1
		var issues := set.validate()
		check(not issues.is_empty() and str(issues).contains(field), "corrupt attack reports exact %s field" % field)
		var fallback := set.attack("stab_1")
		check(fallback == MeleeSet.DEFAULT_ATTACK, "corrupt %s returns the entire safe attack, never partially invalid values" % field)
	var invalid := MeleeSet.new("res://tests/fixtures/test_no_such_attack_catalog_corrupt.json")
	check(not invalid.validate().is_empty(), "loaded corrupt JSON retains its diagnostics after fallback")
	check(invalid.combo() == ["light"] and invalid.combo(true) == ["light"] and invalid.attack("light") == MeleeSet.DEFAULT_ATTACK, "loaded corrupt JSON cannot expose its broken combo or optional free tail")


func _test_nested_catalog_resources() -> void:
	var script: Script = load("res://core/weapon_catalog.gd")
	var weapon_dir := "user://test_catalog_nested/weapons"
	var upgrade_dir := "user://test_catalog_nested/upgrades"
	DirAccess.make_dir_recursive_absolute(weapon_dir.path_join("extra/deeper"))
	DirAccess.make_dir_recursive_absolute(upgrade_dir)
	var weapon := (load(RIFLE_PATH) as WeaponData).duplicate() as WeaponData
	weapon.id = &"test_catalog_future_weapon"
	weapon.display_name = "測試型錄步槍"
	var weapon_path := weapon_dir.path_join("extra/deeper/future.tres")
	check(ResourceSaver.save(weapon, weapon_path) == OK, "nested catalog fixture saves a real WeaponData resource")
	check(ResourceSaver.save(Progression.find_upgrade(MAG_ID).duplicate(), upgrade_dir.path_join("mag.tres")) == OK, "nested catalog fixture saves the actual upgrade definition")
	var catalog = script.call(&"load_all", weapon_dir, upgrade_dir)
	var loaded = catalog.find_weapon(weapon.id)
	check(catalog.issues.is_empty() and catalog.weapons.size() == 1 and loaded != null, "new deeply nested weapon is discovered without changing an ID whitelist")
	if loaded != null:
		check(loaded.resource_path == weapon_path and loaded.display_name == weapon.display_name and loaded.projectile.damage == weapon.projectile.damage, "nested weapon retains its actual name, source and projectile definition")
	var missing = script.call(&"load_all", "user://test_catalog_missing_directory", upgrade_dir)
	check(not missing.issues.is_empty() and str(missing.issues).contains("test_catalog_missing_directory"), "missing catalog directory is reported, not silently accepted")
	check(missing.weapons.is_empty(), "missing directory exposes no weapon definitions")


func _test_extreme_numeric_definitions() -> void:
	var weapon := (load(RIFLE_PATH) as WeaponData).duplicate() as WeaponData
	weapon.id = &"test_catalog_extreme_weapon"
	weapon.pellets = 2147483647
	check(str(weapon.validate()).contains("pellets"), "extreme pellet count is rejected by its exact field")
	check(not weapon.is_valid(), "legacy runtime fire guard also rejects an extreme pellet count")
	for property: Dictionary in weapon.projectile.get_property_list():
		if property.type != TYPE_FLOAT or (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var field := String(property.name)
		var spec := (load(RIFLE_PATH) as WeaponData).projectile.duplicate() as ProjectileSpec
		spec.set(field, 1.0e308)
		check(str(spec.validate()).contains(field), "finite double overflow is rejected before Vector2 conversion: %s" % field)
	for property: Dictionary in weapon.get_property_list():
		if property.type != TYPE_FLOAT or (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var field := String(property.name)
		var bad := weapon.duplicate() as WeaponData
		bad.pellets = 1
		bad.set(field, 1.0e308)
		check(str(bad.validate()).contains(field), "weapon finite extreme reports its exact %s field" % field)
	for resource: Resource in [weapon, weapon.projectile]:
		for property: Dictionary in resource.get_property_list():
			if property.type != TYPE_INT or (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var field := String(property.name)
			var bad := resource.duplicate()
			bad.set(field, 2147483647)
			check(str(bad.call(&"validate")).contains(field), "integer work/cost limit rejects extreme %s/%s" % [resource.get_class(), field])
	for resource: Resource in [weapon, weapon.projectile]:
		var bad := resource.duplicate()
		bad.set("color", Color(1.0e20, 0.0, 0.0, 1.0))
		check(str(bad.call(&"validate")).contains("color/r"), "finite HDR extreme is rejected before visual arithmetic")
	var upgrade := Progression.find_upgrade(&"technique_dagger").duplicate() as WeaponUpgradeData
	upgrade.amount = 1.0e308
	check(not upgrade.validate().is_empty(), "technique amount also rejects a finite-double extreme")
	upgrade.amount = 0.5
	upgrade.cost = 2147483647
	check(str(upgrade.validate()).contains("cost"), "upgrade price cannot overflow bounded economy data")
	var original: JSON = load("res://data/melee/mono_dagger.json")
	for field in ["advance", "range", "height", "windup", "active", "recovery", "cancel_after", "move_scale", "damage", "stagger", "arc_degrees", "min_range", "guard_cost", "hitstop", "impact", "knockback", "trail"]:
		var set := MeleeSet.new("res://test_no_such_attack_extreme_numeric")
		set._loaded = true
		set._data = original.data.duplicate(true)
		var attack: Dictionary = set._data.attacks.stab_1
		if field == "knockback":
			attack[String("knockback")] = [1.0e308, -1.0e308]
		elif field == "trail":
			var trail: Dictionary = attack[String("trail")]
			trail[String("radius")] = 1.0e308
		else:
			attack[String(field)] = 1.0e308
		check(str(set.validate()).contains(field), "melee finite extreme reports its exact %s field" % field)
		check(set.attack("stab_1") == MeleeSet.DEFAULT_ATTACK, "extreme %s uses the entire safe attack" % field)
	var window_set := MeleeSet.new("res://test_no_such_attack_extreme_window")
	window_set._loaded = true
	window_set._data = original.data.duplicate(true)
	window_set._data[String("combo_window")] = 1.0e308
	check(str(window_set.validate()).contains("combo_window"), "extreme combo window has an exact root-field diagnostic")
	check(window_set.combo_window() == 0.5, "live extreme combo window returns the existing safe half-second window")
	var tail_set := MeleeSet.new("res://test_no_such_attack_extreme_tail")
	tail_set._loaded = true
	tail_set._data = original.data.duplicate(true)
	var tail: Dictionary = tail_set._data["attacks"][tail_set._data["extension"]["attack"]]
	tail[String("advance")] = 1.0e308
	check(tail_set.combo(true) == tail_set.combo(), "live unsafe tail is not appended as a free fallback finish")
	var spec := (load(RIFLE_PATH) as WeaponData).projectile.duplicate() as ProjectileSpec
	spec.source_id = &"test_catalog_runtime"
	spec.speed = 10000.0
	check(spec.validate().is_empty(), "documented upper speed boundary remains a valid definition")
	spec.speed = 10000.01
	check(str(spec.validate()).contains("speed"), "first value above speed boundary is rejected")
	weapon.pellets = 64
	check(weapon.validate().is_empty(), "documented 64 pellet boundary is valid")
	weapon.pellets = 65
	check(str(weapon.validate()).contains("pellets"), "first value above pellet boundary is rejected")


func _test_actual_schema_negative_guard() -> void:
	var original: JSON = load("res://data/melee/mono_dagger.json")
	var set := MeleeSet.new("res://test_no_such_attack_negative_guard_range")
	set._loaded = true
	set._data = original.data.duplicate(true)
	var attack: Dictionary = set._data["attacks"]["stab_1"]
	attack[String("guard_cost")] = -30.0
	for key: Variant in attack:
		check(typeof(key) == TYPE_STRING, "negative guard regression uses actual JSON String keys")
	var issues := set.validate()
	check(str(issues).contains("/guard_cost cannot be negative"), "actual-schema negative guard enters the numeric range rejection")
	check(not str(issues).contains("unknown field"), "negative guard is not mistaken for an unknown key type")
	check(set.attack("stab_1") == MeleeSet.DEFAULT_ATTACK, "negative actual-schema guard never creates a free or energy-granting move")


func _test_bounded_runtime_fire() -> void:
	var container := Node2D.new()
	runner.add_child(container)
	ProjectilePool.bind_container(container)
	var weapon := (load(RIFLE_PATH) as WeaponData).duplicate() as WeaponData
	weapon.id = &"test_catalog_runtime"
	var spec := weapon.projectile.duplicate() as ProjectileSpec
	spec.source_id = &"test_catalog_runtime"
	weapon.projectile = spec
	for count in [0, -1, 65]:
		check(WeaponSystem.fire_spread(spec, Vector2.ZERO, Vector2.RIGHT, count, 0.0, 0.0, Combat.Team.PLAYER) == 0, "direct spread rejects out-of-budget count %s without entering an unbounded loop" % count)
	check(ProjectilePool.active_count() == 0, "rejected counts do not consume any pooled projectile")
	weapon.pellets = 2147483647
	# Do not hang an unfixed baseline: validate the boundary first, then assert it.
	if not weapon.is_valid():
		check(WeaponSystem.fire(weapon, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER) == 0, "extreme weapon fire safely returns zero")
	else:
		check(false, "extreme weapon requires runtime rejection before firing")
	for field in ["speed", "knockback"]:
		var bad := spec.duplicate() as ProjectileSpec
		bad.set(field, 1.0e308)
		check(ProjectilePool.spawn(bad, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER) == null, "direct pool rejects finite-double extreme %s before activation" % field)
		check(WeaponSystem.fire_spread(bad, Vector2.ZERO, Vector2.RIGHT, 1, 0.0, 0.0, Combat.Team.PLAYER) == 0, "direct spread rejects finite-double extreme %s" % field)
	for multiplier in [NAN, INF, 1.0e308, -1.0]:
		check(ProjectilePool.spawn(spec, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER, multiplier) == null, "direct pool rejects unsafe speed multiplier %s" % multiplier)
		check(WeaponSystem.fire_spread(spec, Vector2.ZERO, Vector2.RIGHT, 1, 0.0, 0.0, Combat.Team.PLAYER, multiplier) == 0, "direct spread rejects unsafe speed multiplier %s" % multiplier)
	for vector in [Vector2(INF, 0.0), Vector2(NAN, 0.0), Vector2(1.0e20, 0.0)]:
		check(ProjectilePool.spawn(spec, vector, Vector2.RIGHT, Combat.Team.PLAYER) == null, "pool rejects unsafe origin before activating physics")
		check(ProjectilePool.spawn(spec, Vector2.ZERO, vector, Combat.Team.PLAYER) == null, "pool rejects unsafe direction before normalizing a float32 vector")
	var previous_fx := WeaponSystem._last_muzzle_fx.duplicate()
	var invalid_feedback := weapon.duplicate() as WeaponData
	invalid_feedback.pellets = 1
	invalid_feedback.camera_kick = 1.0e308
	check(not WeaponSystem.muzzle_feedback(invalid_feedback, Vector2.ZERO, Vector2.RIGHT), "unsafe feedback refuses its finite-double extreme before Fx")
	check(WeaponSystem._last_muzzle_fx == previous_fx, "unsafe feedback does not update its throttle state")
	for angle in [NAN, INF, 1.0e308, -1.0]:
		check(WeaponSystem.fire_spread(spec, Vector2.ZERO, Vector2.RIGHT, 1, angle, 0.0, Combat.Team.PLAYER) == 0, "spread rejects unsafe angle %s before trigonometry" % angle)
	check(ProjectilePool.active_count() == 0, "all numeric rejections leave pool state untouched")
	check(WeaponSystem.fire_spread(spec, Vector2.ZERO, Vector2.RIGHT, 64, 0.0, 0.0, Combat.Team.PLAYER) == 64, "runtime permits the bounded 64 projectile boundary")
	for i in ProjectilePool.MAX_SIZE - 65:
		ProjectilePool.spawn(spec, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER)
	check(ProjectilePool.active_count() == ProjectilePool.MAX_SIZE - 1, "real pool has exactly one remaining slot")
	check(WeaponSystem.fire_spread(spec, Vector2.ZERO, Vector2.RIGHT, 6, 20.0, 0.0, Combat.Team.PLAYER) == 1, "partial capacity returns one real projectile and stops at the first refusal")
	check(WeaponSystem.fire_spread(spec, Vector2.ZERO, Vector2.RIGHT, 64, 0.0, 0.0, Combat.Team.PLAYER) == 0, "full pool rejects a bounded shot without growing")
	check(ProjectilePool.active_count() == ProjectilePool.MAX_SIZE, "full pool remains bounded")
	for child in container.get_children():
		var projectile := child as Projectile
		if projectile != null and projectile.active:
			check(is_finite(projectile.velocity.x) and is_finite(projectile.velocity.y), "every accepted pooled velocity is finite")
	container.free()


func _upgrade(id: StringName) -> WeaponUpgradeData:
	return Progression.find_upgrade(id)


func _fresh() -> void:
	Progression.reset_run()


func _test_data() -> void:
	var catalog := Progression.upgrade_catalog()
	check(catalog.size() >= 3, "upgrade catalog loads (%d)" % catalog.size())
	var last_order := -INF
	for upgrade in catalog:
		check(upgrade.validate().is_empty(), "upgrade valid: %s %s" % [upgrade.id, upgrade.validate()])
		check(upgrade.order >= last_order, "upgrades sorted: %s" % upgrade.id)
		last_order = upgrade.order
		# 平衡：改裝只改手感，幅度有上限，價格不是零頭。
		check(upgrade.amount <= 0.6 and upgrade.cost >= 50, "upgrade stays modest: %s" % upgrade.id)
	for path in ["res://data/props/credits_small.tres", "res://data/props/credits_large.tres"]:
		var pile := load(path) as CreditPileData
		check(pile != null and pile.validate().is_empty(), "credit pile valid: %s" % path)
	var bad := WeaponUpgradeData.new()
	bad.cost = 0
	bad.amount = 0.0
	check(bad.validate().size() >= 3, "invalid upgrade data is reported")
	for file in DirAccess.get_files_at("res://data/enemies"):
		var enemy := load("res://data/enemies/%s" % file) as EnemyData
		check(enemy != null and enemy.credit_value > 0, "enemy drops credits: %s" % file)


func _test_credits() -> void:
	_fresh()
	var changes: Array[int] = []
	var on_change := func(_credits: int, delta: int) -> void: changes.append(delta)
	Progression.credits_changed.connect(on_change)
	check(Progression.credits == 0, "run starts with no credits")
	check(Progression.add_credits(50) == 50 and Progression.credits == 50, "credits are added")
	check(Progression.add_credits(0) == 0 and Progression.add_credits(-5) == 0 and Progression.credits == 50, "zero and negative gains are ignored")
	check(not Progression.spend(80) and Progression.credits == 50, "cannot overspend")
	check(Progression.spend(20) and Progression.credits == 30, "spending deducts")
	check(not Progression.spend(-5), "negative cost is refused")
	check(Progression.can_afford(30) and not Progression.can_afford(31), "can_afford matches the balance")
	Progression.add_credits(Progression.MAX_CREDITS * 2)
	check(Progression.credits == Progression.MAX_CREDITS, "credits are capped")
	check(changes == [50, -20, Progression.MAX_CREDITS - 30], "credits_changed reports each real change %s" % [changes])
	Progression.credits_changed.disconnect(on_change)
	_fresh()


func _test_upgrades() -> void:
	_fresh()
	var rifle := load(RIFLE_PATH) as WeaponData
	var cannon := load(CANNON_PATH) as WeaponData
	var mag := _upgrade(MAG_ID)
	check(Progression.upgrade_block_reason(rifle, mag).contains("不足"), "cannot buy without credits")
	check(not Progression.buy_upgrade(rifle, mag) and Progression.credits == 0, "failed purchase does not charge")
	check(Progression.upgrade_block_reason(cannon, mag).contains("用不到"), "mag upgrade does not apply to magazine-less weapons")
	Progression.add_credits(1000)
	check(Progression.upgrade_block_reason(rifle, mag).is_empty(), "purchase allowed with enough credits")
	var before := Progression.credits
	check(Progression.buy_upgrade(rifle, mag) and Progression.credits == before - mag.cost, "purchase deducts the price")
	check(Progression.has_upgrade(rifle, MAG_ID) and Progression.upgrade_block_reason(rifle, mag).contains("已經"), "an upgrade can only be bought once")
	check(not Progression.buy_upgrade(rifle, mag) and Progression.credits == before - mag.cost, "second purchase is refused without charge")
	var tuned := Progression.tuned(rifle)
	check(tuned != rifle and tuned.magazine_size > rifle.magazine_size, "tuned rifle has a bigger magazine (%d)" % tuned.magazine_size)
	check(WeaponTuning.base_of(tuned) == rifle and WeaponTuning.base_of(rifle) == rifle, "base_of finds the original data")
	# 其他武器不受影響；改裝不改傷害與射速。
	var pistol := load(PISTOL_PATH) as WeaponData
	check(Progression.tuned(pistol) == pistol, "untouched weapons are returned as-is")
	check(tuned.fire_interval == rifle.fire_interval and tuned.projectile == rifle.projectile and tuned.pellets == rifle.pellets, "upgrades never change damage or fire rate")
	Progression.buy_upgrade(rifle, _upgrade(RELOAD_ID))
	Progression.buy_upgrade(rifle, _upgrade(BARREL_ID))
	tuned = Progression.tuned(rifle)
	check(tuned.reload_time < rifle.reload_time and tuned.reload_time >= rifle.reload_time * 0.4, "reload is faster but bounded")
	check(tuned.random_spread_degrees < rifle.random_spread_degrees, "spread is reduced")
	check(rifle.magazine_size == 30, "original weapon data is never modified")
	# 散霧槍的固定散佈角也會減少。
	var spread := load(SPREAD_PATH) as WeaponData
	Progression.add_credits(1000)
	Progression.buy_upgrade(spread, _upgrade(BARREL_ID))
	check(Progression.tuned(spread).spread_degrees < spread.spread_degrees, "pellet spread is reduced")
	check(Progression.upgrades_for(cannon).is_empty() or not Progression.upgrades_for(cannon).any(func(u: WeaponUpgradeData) -> bool: return u.effect == WeaponUpgradeData.Effect.MAGAZINE), "magazine-less weapons are not offered a magazine upgrade")
	_fresh()


func _test_loadout_tuning() -> void:
	_fresh()
	var rifle := load(RIFLE_PATH) as WeaponData
	var loadout := Loadout.new()
	loadout.reset(load(PISTOL_PATH) as WeaponData)
	loadout.equip(rifle)
	var slot := loadout.find_slot(rifle.id)
	check(loadout.mag_in(slot) == 30 and loadout.weapon_in(slot) == rifle, "unmodified weapon behaves exactly as before")
	Progression.add_credits(500)
	var changed := [0]
	loadout.changed.connect(func() -> void: changed[0] += 1)
	Progression.upgrades_changed.connect(loadout.retune)
	Progression.buy_upgrade(rifle, _upgrade(MAG_ID))
	var tuned_size := loadout.weapon_in(slot).magazine_size
	check(tuned_size > 30 and loadout.mag_in(slot) == tuned_size, "a bigger magazine is filled immediately (%d/%d)" % [loadout.mag_in(slot), tuned_size])
	check(changed[0] >= 1, "loadout announces the retune")
	# 快照只存原始資料路徑；還原後重新套用改裝。
	var snapshot := loadout.snapshot()
	check((snapshot["weapons"] as Array).has(RIFLE_PATH), "snapshot stores the base weapon path")
	var restored := Loadout.new()
	restored.restore(snapshot, load(PISTOL_PATH) as WeaponData)
	check(restored.weapon_in(restored.find_slot(rifle.id)).magazine_size == tuned_size, "restored loadout re-applies upgrades")
	check(WeaponTuning.base_of(restored.weapon_in(restored.find_slot(rifle.id))) == rifle, "restored loadout still knows the base weapon")
	# 撿到同款武器（補彈）不會丟掉改裝。
	loadout.equip(rifle)
	check(loadout.weapon_in(loadout.find_slot(rifle.id)).magazine_size == tuned_size, "picking up the same weapon keeps the upgrade")
	Progression.upgrades_changed.disconnect(loadout.retune)
	_fresh()


func _test_snapshot() -> void:
	_fresh()
	var rifle := load(RIFLE_PATH) as WeaponData
	Progression.add_credits(400)
	Progression.buy_upgrade(rifle, _upgrade(MAG_ID))
	var snapshot := Progression.snapshot()
	Progression.reset_run()
	check(Progression.credits == 0 and not Progression.has_upgrade(rifle, MAG_ID), "reset_run clears credits and upgrades")
	Progression.restore(snapshot)
	check(Progression.credits == snapshot["credits"] and Progression.has_upgrade(rifle, MAG_ID), "snapshot restores credits and upgrades")
	# 損毀的快照不會崩潰，無效部分退回預設。
	Progression.restore({"credits": "lots", "upgrades": {"rifle": ["no_such_upgrade", MAG_ID, MAG_ID], "x": 5}})
	check(Progression.credits == 0, "garbage credits fall back to zero")
	check(Progression.has_upgrade(rifle, MAG_ID) and Progression.owned_upgrades(rifle).size() == 1, "unknown and duplicate upgrades are dropped")
	Progression.restore({"credits": -50})
	check(Progression.credits == 0, "negative credits are clamped")
	Progression.restore({})
	check(Progression.credits == 0 and Progression.owned_upgrades(rifle).is_empty(), "empty snapshot restores a clean state")
	_fresh()


func _level_data() -> LevelData:
	var data := LevelData.new()
	data.id = &"credits_test"
	data.layout_path = MAP_PATH
	data.legend = {
		"c": load("res://data/props/credits_small.tres"),
		"a": load("res://data/props/crate.tres"),
	}
	return data


func _pile_at(level: Level, column: int) -> CreditPickup:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CreditPickup and (node as CreditPickup).cell.x == column and (node as CreditPickup).visible:
			return node
		stack.append_array(node.get_children())
	return null


func _touch(level: Level, pickup: Pickup) -> void:
	level.player.global_position = pickup.global_position
	level.player.velocity = Vector2.ZERO
	await frames(8)


func _test_pickups_and_checkpoint() -> void:
	var data := _level_data()
	var level := await start_level(data)
	var first := _pile_at(level, 12)
	check(first != null and first.value == 10, "credit pile spawned from the legend")
	check(level.hud.credits_tag.value() == 0, "HUD shows the credits")
	await _touch(level, first)
	check(Progression.credits == 10, "touching a pile adds its value (%d)" % Progression.credits)
	check(level.hud.credits_tag.value() == 10, "HUD follows the credits")
	check(_pile_at(level, 12) == null, "a collected pile disappears")
	# 到檢查點存檔。
	var checkpoint: Checkpoint = null
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Checkpoint:
			checkpoint = node
		stack.append_array(node.get_children())
	level.player.global_position = checkpoint.global_position
	await frames(6)
	check(not GameState.has_checkpoint, "just walking past the phone booth does not record")
	check(checkpoint.start_call(level.player), "dialing at the booth starts the call")
	await frames(90)  # 撥號要一秒多
	check(GameState.has_checkpoint and GameState.checkpoint_progress.get("credits") == 10, "checkpoint stores the credits")
	# 檢查點之後再賺一些：重生後還原成檢查點當下，而且不能重新撿檢查點前的錢。
	await _touch(level, _pile_at(level, 18))
	check(Progression.credits == 20, "second pile collected after the checkpoint")
	await end_level(level)
	level = await spawn_level(data)
	check(Progression.credits == 10, "respawning restores the checkpoint credits (%d)" % Progression.credits)
	check(_pile_at(level, 12) == null, "a pile collected before the checkpoint stays collected")
	check(_pile_at(level, 18) != null, "a pile collected after the checkpoint comes back")
	# 沒有檢查點（殘機用盡）時還原成進入關卡時。
	await end_level(level)
	GameState.clear_checkpoint()
	level = await spawn_level(data)
	check(Progression.credits == 0, "no checkpoint restores the level-start credits")
	check(_pile_at(level, 12) != null, "all piles are back without a checkpoint")
	# 敵人與箱子掉信用點。
	var crate := _crate(level)
	var info := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	crate.hit_by_projectile(info)
	await frames(6)
	var dropped: CreditPickup = null
	for node in level._entities.get_children():
		if node is CreditPickup and (node as CreditPickup).cell == Vector2i(-1, -1):
			dropped = node
	check(dropped != null and dropped.value == crate.data.credit_drop, "a broken crate drops credits")
	if dropped != null:
		await _touch(level, dropped)
		check(Progression.credits == crate.data.credit_drop, "drops add credits")
	var grunt := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	grunt.position = Vector2(30 * 16.0, 20 * 16.0)
	level._entities.add_child(grunt)
	await frames(3)
	var lethal := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	lethal.bypass_guard = true
	grunt.hurtbox.receive(lethal)
	await frames(6)
	var enemy_drop := 0
	for node in level._entities.get_children():
		if node is CreditPickup and (node as CreditPickup).cell == Vector2i(-1, -1) and (node as CreditPickup).value == 8:
			enemy_drop += 1
	check(enemy_drop == 1, "a defeated enemy drops credits")
	await frames(60)
	await end_level(level)
	GameState.clear_checkpoint()


func _crate(level: Level) -> Breakable:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Breakable:
			return node
		stack.append_array(node.get_children())
	return null


func _test_upgrades_page() -> void:
	var level := await start_level(_level_data())
	var player := level.player
	var rifle := load(RIFLE_PATH) as WeaponData
	player.loadout.equip(rifle)
	var context := InventoryContext.new(player)
	var messages: Array[String] = []
	var warnings := [0]
	context.message.connect(func(text: String, is_warning: bool) -> void:
		messages.append(text)
		if is_warning:
			warnings[0] += 1)
	var page := UpgradesPage.new()
	page.bind(context)
	var entries := page._build_entries()
	check(entries.size() >= 3, "upgrades page lists the rifle's upgrades (%d)" % entries.size())
	var mag_index := -1
	for i in page._targets.size():
		if page._targets[i]["upgrade"].id == MAG_ID and WeaponTuning.base_of(page._targets[i]["weapon"]) == rifle:
			mag_index = i
	check(mag_index >= 0, "rifle magazine upgrade is listed")
	var entry := entries[mag_index]
	check(entry.subtitle.begins_with("¥") and not entry.action_enabled, "unaffordable upgrade shows its price and a disabled action")
	check(entry.detail_stats.size() >= 2 and entry.detail_stats[1].contains("→"), "upgrade preview shows before and after: %s" % [entry.detail_stats])
	check(not entry.action_hint.is_empty() and not entry.hint.is_empty(), "upgrade has hints")
	# 錢不夠：被拒絕並提示。
	check(not page._activate_entry(mag_index) and warnings[0] == 1 and Progression.credits == 0, "insufficient funds are refused with a warning")
	Progression.add_credits(500)
	entries = page._build_entries()
	check(entries[mag_index].action_enabled, "upgrade becomes available with credits")
	check(page._activate_entry(mag_index), "buying from the page succeeds")
	check(Progression.has_upgrade(rifle, MAG_ID) and Progression.credits == 500 - _upgrade(MAG_ID).cost, "the page charged the price")
	check(player.loadout.weapon_in(player.loadout.find_slot(rifle.id)).magazine_size > 30, "the player's weapon is upgraded immediately")
	entries = page._build_entries()
	check(entries[mag_index].subtitle == "已改裝" and not entries[mag_index].action_enabled and entries[mag_index].badge == "已改裝", "an owned upgrade is marked and locked")
	check(page.tab_tooltip().contains("¥"), "tab tooltip shows the credits")
	page.free()
	await end_level(level)
