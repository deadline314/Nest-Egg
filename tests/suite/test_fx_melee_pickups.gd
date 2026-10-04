class_name FxMeleePickupsSuite
extends EnemySuiteBase
## 特效升級（二）（NE-101）：近戰揮砍的軌跡樣式與每把武器自己的顏色、命中與揮擊特效、終結技；拾取特效與閃光；同屏多個爆炸的效能。

const WEAPONS: Array[String] = ["melee_dagger", "melee_blade", "melee_maul", "melee_glaive", "melee_whip"]
## 同屏爆炸的效能預算：十二個爆炸同時發生時，每影格的處理時間比平時多出來的部分（毫秒）不超過這個上限、節點不暴增。
const EXPLOSION_COUNT := 12
const EXTRA_FRAME_BUDGET_MS := 6.0
const NODE_GROWTH_BUDGET := 40


func run() -> void:
	_test_melee_data()
	await _test_melee_fx()
	await _test_trail_styles()
	_test_pickup_kinds()
	await _test_pickup_collect()
	await _test_explosion_budget()


func _weapon(id: String) -> WeaponData:
	return load("res://data/weapons/melee/%s.tres" % id) as WeaponData


func _test_melee_data() -> void:
	var colors: Dictionary = {}
	for id in WEAPONS:
		var set := MeleeData.set_of(_weapon(id))
		check(set.validate().is_empty(), "%s trail styles, colors and impact fx are valid" % id)
		for attack_id: Variant in set.combo():
			var trail: Dictionary = set.attack(str(attack_id))["trail"]
			colors[str(trail.get("color", ""))] = id
	check(colors.size() >= WEAPONS.size() - 1, "weapons have their own trail colors (%d distinct)" % colors.size())
	check(MeleeData.set_of(_weapon("melee_whip")).attack("lash")["trail"]["style"] == "lash" and MeleeData.set_of(_weapon("melee_glaive")).attack("thrust")["trail"]["style"] == "thrust", "whip lashes and glaive thrusts have their own trail style")
	check(MeleeData.set_of(_weapon("melee_maul")).attack("smash")["impact_fx"] == "crush", "the maul hits with a crushing impact")
	var bad := MeleeSet.new("res://data/melee/test_no_such_attack.json")
	check(bad.attack("x")["impact_fx"] == "slash", "a missing attack falls back to the slash impact")


func _particles(callable: Callable) -> int:
	await physics_frames(50)  # 讓上一個配方的粒子散掉
	var before := Fx.particle_count()
	callable.call()
	return Fx.particle_count() - before


func _test_melee_fx() -> void:
	await open_level(10.0)
	var at := level.player.global_position + Vector2(30, -24)
	for kind in MeleeFx.KINDS:
		var added := await _particles(func() -> void: MeleeFx.hit(at, Vector2.RIGHT, Palette.CYAN, StringName(kind), true))
		check(added >= 3 and added <= 40, "%s impact emits a bounded number of particles (%d)" % [kind, added])
	var crack := await _particles(func() -> void: MeleeFx.swing(at, level.player.global_position, Vector2.RIGHT, 100.0, Palette.MAGENTA, &"slash", true))
	check(crack >= 1, "a whip lash cracks at its tip (%d)" % crack)
	var slam := await _particles(func() -> void: MeleeFx.swing(at, level.player.global_position, Vector2.RIGHT, 40.0, Palette.WARNING, &"crush", false))
	check(slam >= 1, "a heavy swing kicks up dust (%d)" % slam)
	var finish := await _particles(func() -> void: MeleeFx.finisher(at, Palette.CYAN))
	check(finish >= 4 and finish <= 40, "the finisher adds a bounded burst (%d)" % finish)
	# 實際揮擊：鞭子甩出去（沒有目標）也會有爆響。
	var player := level.player
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.loadout.equip(_weapon("melee_whip"))
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	await physics_frames(50)
	var before := Fx.particle_count()
	var peak := before
	player._try_melee()
	var guard := 0
	while player._melee_phase != Player.MeleePhase.NONE and guard < 120:
		await physics_frames(1)
		peak = maxi(peak, Fx.particle_count())
		guard += 1
	check(peak > before, "swinging the whip plays its crack even without a target (%d -> %d)" % [before, peak])
	AimInput.using_gamepad = false
	await physics_frames(3)
	await end_level(level)


func _test_trail_styles() -> void:
	await open_level(10.0)
	var visual: PlayerVisual = level.player._visual
	for id in WEAPONS:
		var set := MeleeData.set_of(_weapon(id))
		for attack_id: Variant in set.combo():
			var trail: Dictionary = set.attack(str(attack_id))["trail"]
			visual.notify_melee_swing(trail, 1)
			await frames(3)
	check(visual._trails.size() <= MeleeData.MAX_TRAILS, "trail styles are drawn within the trail cap (%d)" % visual._trails.size())
	var brightest := 0.0
	for id in WEAPONS:
		var set := MeleeData.set_of(_weapon(id))
		for attack_id: Variant in set.combo():
			brightest = maxf(brightest, float(set.attack(str(attack_id))["trail"]["brightness"]))
	check(brightest <= MeleeData.TRAIL_BRIGHTNESS_MAX, "no weapon trail is over-bright (%.1f)" % brightest)
	await physics_frames(3)
	await end_level(level)


func _test_pickup_kinds() -> void:
	check(HealthPickup.new()._fx_kind() == &"heal" and HealthPickup.new()._fx_color() == Palette.NEON_GREEN, "health pickups play the heal effect in green")
	check(CreditPickup.new()._fx_kind() == &"credit", "credit pickups play the credit effect")
	var weapon_pickup := WeaponPickup.new()
	weapon_pickup.configure(_weapon("melee_whip"))
	check(weapon_pickup._fx_kind() == &"weapon" and weapon_pickup._fx_color() == _weapon("melee_whip").color, "weapon pickups play the weapon effect in the weapon's color")
	check(CollectiblePickup.new()._fx_kind() == &"story", "story items play the story effect")
	check(ConsumablePickup.new()._fx_kind() == &"item", "consumables play the item effect")


func _test_pickup_collect() -> void:
	await open_level(10.0)
	for kind in PickupFx.KINDS:
		var added := await _particles(func() -> void: PickupFx.collect(level.player.global_position + Vector2(0, -20), Palette.CYAN, StringName(kind)))
		check(added >= 1 and added <= 30, "%s pickup effect emits a bounded number of particles (%d)" % [kind, added])
	# 實際撿取：撿信用點，特效與加錢一起發生。
	var player := level.player
	var pickup := CreditPickup.new()
	pickup.position = player.global_position + Vector2(300, 0)  # 離開玩家，等一下手動觸發（貼著會自己被撿走）
	level._entities.add_child(pickup)
	await physics_frames(50)
	var before := Fx.particle_count()
	pickup._on_body_entered(player)
	check(Fx.particle_count() > before, "collecting a pickup plays its effect")
	# 閃光：週期內一小段時間會畫（不出錯）。
	var glint := CreditPickup.new()
	glint.position = player.global_position + Vector2(400, 0)
	level._entities.add_child(glint)
	glint._glint_offset = 0.0
	await frames(6)
	check(glint.is_inside_tree(), "the glint draws without errors")
	await physics_frames(3)
	await end_level(level)


## 十二個爆炸同時發生：粒子是固定容量、不新增節點（爆炸本體與光源池除外），每影格處理時間在預算內；數字印在 log 裡。
func _test_explosion_budget() -> void:
	await open_level(10.0)
	await physics_frames(60)
	var idle := await _mean_frame_ms(40)
	var nodes_before := level.get_tree().get_node_count()
	for i in EXPLOSION_COUNT:
		Fx.explosion(level.player.global_position + Vector2(-120 + i * 24, -40 - (i % 3) * 16), 40.0, 0, Combat.Team.ENEMY, &"test_no_such_source")
	var peak_particles := Fx.particle_count()
	var burst := await _mean_frame_ms(40)
	var nodes_peak := level.get_tree().get_node_count()
	print("FX_PERF idle=%.2f ms, %d explosions=%.2f ms per frame, particles=%d, nodes +%d" % [idle, EXPLOSION_COUNT, burst, peak_particles, nodes_peak - nodes_before])
	check(burst - idle <= EXTRA_FRAME_BUDGET_MS, "%d simultaneous explosions add little to a frame (+%.2f ms, budget %.0f ms)" % [EXPLOSION_COUNT, burst - idle, EXTRA_FRAME_BUDGET_MS])
	check(nodes_peak - nodes_before <= NODE_GROWTH_BUDGET, "explosions do not create a pile of nodes (+%d)" % (nodes_peak - nodes_before))
	check(peak_particles > 0 and peak_particles <= ParticleField.CAPACITY * 2, "particles stay within the fixed capacity (%d)" % peak_particles)
	await physics_frames(120)
	check(level.get_tree().get_node_count() - nodes_before <= 8, "the nodes created by the explosions are gone afterwards")
	await end_level(level)


func _mean_frame_ms(count: int) -> float:
	var total := 0.0
	for i in count:
		await frames(1)
		total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return total / float(count)
