class_name MeleeWeaponsSuite
extends EnemySuiteBase
## 近戰武器（NE-117）：武器是資料（.tres 指向 data/melee/<id>.json）；判定只在出招區間、同一目標只算一次、
## 距離與死角、電量消耗與充電、任兩把有取捨、武器欄與背包能顯示、既有槍械不受影響。

const WEAPONS: Array[String] = ["melee_dagger", "melee_blade", "melee_maul", "melee_glaive", "melee_whip"]


func run() -> void:
	_test_data()
	_test_balance()
	_test_loadout()
	await _test_reach_and_dead_zone()
	await _test_single_hit_and_windows()
	await _test_charge()
	await _test_ui()
	await _test_gun_unchanged()
	AimInput.using_gamepad = false


func _weapon(id: String) -> WeaponData:
	return load("res://data/weapons/melee/%s.tres" % id) as WeaponData


func _test_data() -> void:
	for id in WEAPONS:
		var weapon := _weapon(id)
		check(weapon != null and weapon.is_melee() and weapon.is_valid(), "%s is a valid melee weapon" % id)
		if weapon == null:
			continue
		var errors := MeleeData.set_of(weapon).validate()
		check(errors.is_empty(), "%s melee data has no errors: %s" % [id, ", ".join(errors)])
		check(not weapon.description.is_empty() and not weapon.short_name.is_empty(), "%s has a one-line description" % id)
		check(WeaponSounds.name_for(weapon.id, &"empty") != &"", "%s falls back to the default empty-click sound" % id)
		check(WeaponSystem.fire(weapon, Vector2.ZERO, Vector2.RIGHT, Combat.Team.PLAYER) == 0, "%s fires no bullets" % id)
	var bad := WeaponData.new()
	bad.melee_profile = "test_no_such_attack"
	var fallback := MeleeData.set_of(bad).attack("whatever")
	check(float(fallback["windup"]) > 0.0, "a missing profile falls back to safe defaults instead of crashing")


## 速度、威力、距離、衝擊力四軸：任兩把都要各有勝負，沒有哪一把全面勝過其他。
func _test_balance() -> void:
	var stats: Dictionary = {}
	for id in WEAPONS:
		var set := MeleeData.set_of(_weapon(id))
		var first := set.attack(str(set.combo()[0]))
		var impact := 0.0
		for attack_id: Variant in set.combo():
			impact = maxf(impact, float(set.attack(str(attack_id))["impact"]))
		stats[id] = {"speed": -float(first["windup"]), "dps": set.damage_per_second(), "reach": set.max_range(), "impact": impact}
	for a in WEAPONS:
		for b in WEAPONS:
			if a >= b:
				continue
			var a_wins := 0
			var b_wins := 0
			for axis: String in ["speed", "dps", "reach", "impact"]:
				if float(stats[a][axis]) > float(stats[b][axis]):
					a_wins += 1
				elif float(stats[a][axis]) < float(stats[b][axis]):
					b_wins += 1
			check(a_wins > 0 and b_wins > 0, "%s and %s trade off (wins %d vs %d)" % [a, b, a_wins, b_wins])
	check(float(stats["melee_dagger"]["speed"]) > float(stats["melee_blade"]["speed"]), "the dagger starts swinging fastest")
	check(float(stats["melee_whip"]["reach"]) > float(stats["melee_glaive"]["reach"]) and float(stats["melee_glaive"]["reach"]) > float(stats["melee_blade"]["reach"]), "whip reaches farther than the glaive, glaive farther than the blade")
	check(float(stats["melee_maul"]["impact"]) > float(stats["melee_blade"]["impact"]), "the maul hits hardest")
	var stagger := MeleeData.set_of(_weapon("melee_maul")).attack("smash")
	check(int(stagger["stagger"]) >= 3 and float(stagger["impact"]) >= 9.0, "the maul can stagger enemies (impact tier)")


func _test_loadout() -> void:
	var loadout := Loadout.new()
	loadout.reset(load("res://data/weapons/pistol.tres") as WeaponData)
	loadout.equip(_weapon("melee_blade"))
	loadout.equip(_weapon("melee_whip"))
	check(loadout.weapon_in(1).id == &"melee_blade" and loadout.active_weapon().id == &"melee_whip", "melee weapons are picked up and equipped like guns")
	loadout.select(1)
	check(loadout.active_weapon().id == &"melee_blade", "a melee weapon can be switched to")
	var restored := Loadout.new()
	restored.restore(loadout.snapshot(), load("res://data/weapons/pistol.tres") as WeaponData)
	check(restored.find_slot(&"melee_whip") >= 0 and restored.active_weapon().id == &"melee_blade", "the loadout snapshot keeps melee weapons")


## 瞄準方向固定（模擬手把右搖桿），不受測試環境的滑鼠位置影響。
func _aim(player: Player, dir: Vector2) -> void:
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = dir.normalized()
	player.aim_dir = dir.normalized()
	player.facing = 1 if dir.x >= 0.0 else -1


func _arm(weapon_id: String) -> Player:
	var player := level.player
	player.loadout.equip(_weapon(weapon_id))
	_aim(player, Vector2.RIGHT)
	player._melee_cooldown_left = 0.0
	return player


func _dummy(offset_px: float) -> Enemy:
	var enemy := spawn(GRUNT_PATH, 10.0)
	enemy.position = Vector2(level.player.global_position.x + offset_px, FLOOR_Y)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.health.setup(999, 0.0)
	return enemy


## 揮一次並等到收招結束，回傳目標損失的生命。
func _swing_at(weapon_id: String, offset_px: float, aim := Vector2.RIGHT) -> int:
	await open_level(10.0)
	var player := _arm(weapon_id)
	_aim(player, aim)
	var enemy := _dummy(offset_px)
	await physics_frames(3)
	var before := enemy.health.current
	player._try_melee()
	var frames_left := 200
	while player._melee_phase != Player.MeleePhase.NONE and frames_left > 0:
		await physics_frames(1)
		frames_left -= 1
	var lost := before - enemy.health.current
	enemy.queue_free()
	await physics_frames(3)
	await end_level(level)
	return lost


func _test_reach_and_dead_zone() -> void:
	check(await _swing_at("melee_dagger", 80.0) == 0, "the dagger cannot reach 80 px")
	check(await _swing_at("melee_dagger", 14.0) > 0, "the dagger hits at close range")
	check(await _swing_at("melee_glaive", 50.0) > 0, "the glaive hits at 50 px")
	check(await _swing_at("melee_glaive", 14.0) == 0, "the glaive has a dead zone up close")
	check(await _swing_at("melee_whip", 85.0) > 0, "the whip hits at 85 px")
	check(await _swing_at("melee_whip", 18.0) == 0, "the whip cannot hit at point-blank range")
	check(await _swing_at("melee_blade", 85.0) == 0, "the blade cannot reach 85 px")


func _test_single_hit_and_windows() -> void:
	await open_level(10.0)
	var player := _arm("melee_blade")
	var enemy := _dummy(24.0)
	await physics_frames(3)
	var before := enemy.health.current
	player._try_melee()
	check(enemy.health.current == before, "the wind-up deals no damage")
	var attack: Dictionary = player._melee_attack
	var guard := 0
	while player._melee_phase != Player.MeleePhase.NONE and guard < 120:
		await physics_frames(1)
		guard += 1
	check(before - enemy.health.current == int(attack["damage"]), "a sweeping swing hits the same target only once (%d damage)" % (before - enemy.health.current))
	# 出招區間內才走進範圍的目標也算（持續判定），但出招結束後走進來的不算。
	enemy.queue_free()  # 命中會讓玩家頓幀；第二次揮擊只留下要測的目標
	await physics_frames(2)
	var late := _dummy(120.0)
	await physics_frames(3)
	player._melee_cooldown_left = 0.0
	player._melee_combo_left = 0.0
	player._try_melee()
	while player._melee_phase == Player.MeleePhase.WINDUP:
		await physics_frames(1)
	late.global_position.x = player.global_position.x + 24.0
	await physics_frames(2)
	check(late.health.current < 999 or player._melee_phase != Player.MeleePhase.ACTIVE, "a target stepping in during the active window can be hit")
	while player._melee_phase != Player.MeleePhase.NONE:
		await physics_frames(1)
	var hp_after := late.health.current
	late.global_position.x = player.global_position.x + 20.0
	await physics_frames(6)
	check(late.health.current == hp_after, "nothing is hit after the active window ends")
	late.queue_free()
	await physics_frames(3)
	await end_level(level)


func _test_charge() -> void:
	await open_level(10.0)
	var player := _arm("melee_maul")
	var weapon := player.loadout.active_weapon()
	var swings := 0
	for i in weapon.magazine_size + 2:
		player._melee_cooldown_left = 0.0
		player._melee_combo_left = 0.0
		player._try_melee()
		if player._melee_phase != Player.MeleePhase.NONE:
			swings += 1
		player._end_melee()
		await physics_frames(2)
	check(swings == weapon.magazine_size, "the maul swings %d times then needs charging (swung %d)" % [weapon.magazine_size, swings])
	check(player.loadout.is_reloading(), "an empty charge starts recharging")
	await physics_frames(int(weapon.reload_time * 60.0) + 20)
	check(player.loadout.mag_in(player.loadout.active_slot) == weapon.magazine_size, "the charge is full again after recharging")
	var free := _arm("melee_blade")
	check(not free.loadout.active_weapon().has_magazine(), "a charge-free blade never runs out")
	await physics_frames(3)
	await end_level(level)


func _test_ui() -> void:
	await open_level(10.0)
	var player := _arm("melee_blade")
	player.loadout.equip(_weapon("melee_maul"))
	var bar := WeaponBar.new()
	level.add_child(bar)
	bar.update_from(player.loadout)
	check(bar.row_count() == Loadout.MAX_SLOTS and bar.row_state(1) == AmmoIcons.State.FULL, "the weapon bar shows melee weapons")
	for id in WEAPONS:
		var weapon := _weapon(id)
		check(MeleeArt.item_icon(weapon).get_size() == Vector2(MeleeArt.ITEM_SIZE), "%s has a card icon" % id)
		check(AmmoIcons.for_weapon(weapon).get_size() == Vector2(MeleeArt.AMMO_SIZE), "%s has a weapon-bar icon" % id)
	var page := WeaponsPage.new()
	check(page._kind_text(_weapon("melee_blade")) == "近戰", "inventory cards label melee weapons")
	bar.queue_free()
	await physics_frames(3)
	await end_level(level)


func _test_gun_unchanged() -> void:
	await open_level(10.0)
	var player := level.player
	_aim(player, Vector2.RIGHT)
	check(not player.holds_melee_weapon(), "the starting pistol is not a melee weapon")
	var enemy := _dummy(24.0)
	await physics_frames(3)
	var before := enemy.health.current
	player._try_melee()
	var guard := 0
	while player._melee_phase != Player.MeleePhase.NONE and guard < 120:
		await physics_frames(1)
		guard += 1
	check(before - enemy.health.current == int(MeleeData.attack(str(MeleeData.combo()[0]))["damage"]), "the melee key with a gun still uses the default light slash")
	var mag := player.loadout.mag_in(player.loadout.active_slot)
	player._fire_cooldown_left = 0.0
	player._try_fire()
	check(player.loadout.mag_in(player.loadout.active_slot) == mag - 1, "the pistol still fires")
	enemy.queue_free()
	await physics_frames(3)
	await end_level(level)
