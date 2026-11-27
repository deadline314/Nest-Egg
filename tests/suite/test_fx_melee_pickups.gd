class_name FxMeleePickupsSuite
extends EnemySuiteBase
## 特效升級（二）（NE-101）：近戰揮砍的軌跡樣式與每把武器自己的顏色、命中與揮擊特效、終結技；拾取特效與閃光；同屏多個爆炸的效能。

const WEAPONS: Array[String] = ["melee_dagger", "melee_blade", "melee_maul", "melee_glaive", "melee_whip"]
## 同屏爆炸的效能預算：十二個爆炸同時發生時，每影格的處理時間比平時多出來的部分（毫秒）不超過這個上限、節點不暴增。
const EXPLOSION_COUNT := 12
const EXTRA_FRAME_BUDGET_MS := 6.0
const NODE_GROWTH_BUDGET := 40


class ProcessEdge extends Node:
	var observe: Callable

	func _process(_delta: float) -> void:
		observe.call()


## TIME_PROCESS stores an engine peak refreshed once a second. Measure the
## actual scene process callbacks in the current frame instead.
class SceneProcessWindow extends Node:
	var _start := ProcessEdge.new()
	var _end := ProcessEdge.new()
	var _from_usec := 0
	var _elapsed_usec := 0
	var _remaining := 0

	func _ready() -> void:
		_start.process_priority = -100000
		_start.observe = func() -> void: _from_usec = Time.get_ticks_usec()
		_end.process_priority = 100000
		_end.observe = func() -> void: _record.call_deferred()
		add_child(_start)
		add_child(_end)
		_start.set_process(false)
		_end.set_process(false)

	func measure(frames_to_sample: int) -> float:
		_remaining = frames_to_sample
		_elapsed_usec = 0
		_start.set_process(true)
		_end.set_process(true)
		while _remaining > 0:
			await get_tree().process_frame
		_start.set_process(false)
		_end.set_process(false)
		return float(_elapsed_usec) / float(frames_to_sample) / 1000.0

	func _record() -> void:
		if _remaining > 0:
			_elapsed_usec += Time.get_ticks_usec() - _from_usec
			_remaining -= 1


func run() -> void:
	_test_melee_data()
	await _test_melee_fx()
	await _test_trail_styles()
	_test_pickup_kinds()
	_test_pickup_outline()
	await _test_pickup_prompt_lifecycle()
	await _test_pickup_collect()
	await preload("res://tests/helpers/deferred_pickup_checks.gd").run(self)
	await _test_explosion_budget()


func _test_pickup_outline() -> void:
	var sprite := ItemIcons.world("credits_small")
	check(sprite.has("outline"), "world art has a persistent pickup contour")
	if not sprite.has("outline"):
		return
	var outline := sprite["outline"] as Texture2D
	var base := sprite["base"] as Texture2D
	check(outline != null and outline.get_width() > base.get_width(), "contour extends outside the item without clipping")
	check(ItemIcons.world("credits_small")["outline"] == outline, "contour texture is reused instead of allocating per frame")
	var image := outline.get_image()
	var pixels := 0
	var center_pixels := 0
	var scale := ItemIcons.WORLD_OUTLINE_SCALE
	var inner := Vector2i(ItemIcons.WORLD_SIZE) * scale
	var pad := int((image.get_width() - inner.x) / 2)
	var original := base.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.01:
				continue
			pixels += 1
			var source := Vector2i(int(floor(float(x - pad) * original.get_width() / inner.x)), int(floor(float(y - pad) * original.get_height() / inner.y)))
			if x >= pad and y >= pad and source.x < original.get_width() and source.y < original.get_height():
				if original.get_pixel(source.x, source.y).a > 0.1:
					center_pixels += 1
	check(pixels > 0 and center_pixels == 0, "highlight follows only the outside silhouette and preserves item detail")
	check(scale >= 2 and pad == 1, "the contour is a thin line, finer than one world pixel")
	var detailed := ItemIcons.world("ch1_data_disk")
	if detailed.has("outline") and detailed["outline"] != null:
		check((detailed["outline"] as Texture2D).get_size() == outline.get_size(),
				"every pickup gets the same contour width regardless of its art resolution")


func _weapon(id: String) -> WeaponData:
	return load("res://data/weapons/melee/%s.tres" % id) as WeaponData


func _test_pickup_prompt_lifecycle() -> void:
	await open_level(10.0)
	var player := level.player
	player.set_physics_process(false)
	var health := HealthPickup.new()
	health.position = player.position + Vector2(30, 0)
	level._entities.add_child(health)
	var prompt := health.get_child(1) as WorldPrompt
	health._on_body_entered(player)
	await frames(30)
	check(is_instance_valid(health) and prompt.is_showing(), "a full-health pickup remains and shows its nearby hint")
	# 輪廓微光（NE-391）：靠近才變亮並脈動，離開回到低調；「減少閃光」時不脈動。
	var previous_flashes := Settings.get_reduce_flashes()
	Settings.set_reduce_flashes(false)
	check(Pickup.OUTLINE_NEAR * (1.0 - Pickup.OUTLINE_PULSE) > Pickup.OUTLINE_REST
			and health.outline_strength() > Pickup.OUTLINE_REST and health.outline_strength() <= Pickup.OUTLINE_NEAR,
			"the contour brightens once the player is close enough to notice the pickup")
	Settings.set_reduce_flashes(true)
	check(is_equal_approx(health.outline_strength(), Pickup.OUTLINE_NEAR), "reduce flashes keeps the near contour steady")
	Settings.set_reduce_flashes(previous_flashes)
	player.position.x -= 180.0
	await frames(30)
	check(not prompt.is_showing() and is_zero_approx(prompt._alpha), "leaving the pickup hides its hint")
	check(is_equal_approx(health.outline_strength(), Pickup.OUTLINE_REST), "the contour returns to its quiet level when the player leaves")
	player.position.x += 180.0
	await frames(30)
	check(prompt.is_showing(), "returning to the retained pickup restores its hint")
	player.health.current -= 1
	health._on_body_entered(player)
	await frames(2)
	check(not is_instance_valid(health) and not is_instance_valid(prompt), "collecting health removes both the pickup and its hint")
	var med := ConsumableBag.find(&"med_injector")
	for i in med.max_carry:
		player.consumables.add(med)
	var supply := ConsumablePickup.new()
	supply.configure(med)
	supply.position = player.position + Vector2(30, 0)
	level._entities.add_child(supply)
	var supply_prompt := supply.get_child(1) as WorldPrompt
	supply._on_body_entered(player)
	await frames(30)
	check(is_instance_valid(supply) and supply_prompt.is_showing(), "a full bag retains the item and its nearby hint")
	player.consumables.restore({str(med.id): med.max_carry - 1})
	supply._on_body_entered(player)
	await frames(2)
	check(not is_instance_valid(supply) and not is_instance_valid(supply_prompt), "collecting after freeing bag space leaves no stale hint")
	await end_level(level)


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
	var health := HealthPickup.new()
	var credits := CreditPickup.new()
	var collectible := CollectiblePickup.new()
	var consumable := ConsumablePickup.new()
	check(health._fx_kind() == &"heal" and health._fx_color() == Palette.NEON_GREEN, "health pickups play the heal effect in green")
	check(credits._fx_kind() == &"credit", "credit pickups play the credit effect")
	var weapon_pickup := WeaponPickup.new()
	weapon_pickup.configure(_weapon("melee_whip"))
	check(weapon_pickup._fx_kind() == &"weapon" and weapon_pickup._fx_color() == _weapon("melee_whip").color, "weapon pickups play the weapon effect in the weapon's color")
	check(collectible._fx_kind() == &"story", "story items play the story effect")
	check(consumable._fx_kind() == &"item", "consumables play the item effect")
	for fixture: Pickup in [health, credits, weapon_pickup, collectible, consumable]: fixture.free()


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


## 三次各觸發十二個原生爆炸。用前後閒置樣本抵消主機負載變化，
## 取三次差值的中位數，保留原本的 6 ms、粒子和節點上限。
func _test_explosion_budget() -> void:
	await open_level(10.0)
	var previous_fps := Engine.max_fps
	Engine.max_fps = 60
	var window := SceneProcessWindow.new()
	level.add_child(window)
	await physics_frames(60)
	var deltas: Array[float] = []
	var max_nodes := 0
	var max_particles := 0
	var max_leftovers := 0
	for trial in 3:
		var idle_before := await window.measure(40)
		var idle_nodes := level.get_tree().get_node_count()
		for i in EXPLOSION_COUNT:
			Fx.explosion(level.player.global_position + Vector2(-120 + i * 24, -40 - (i % 3) * 16),
				40.0, 0, Combat.Team.ENEMY, &"test_no_such_source")
		var peak_particles := Fx.particle_count()
		var peak_nodes := level.get_tree().get_node_count()
		var active := await window.measure(40)
		peak_nodes = maxi(peak_nodes, level.get_tree().get_node_count())
		max_nodes = maxi(max_nodes, peak_nodes - idle_nodes)
		max_particles = maxi(max_particles, peak_particles)
		await physics_frames(120)
		var idle_after := await window.measure(40)
		max_leftovers = maxi(max_leftovers, level.get_tree().get_node_count() - idle_nodes)
		var added := active - (idle_before + idle_after) * 0.5
		deltas.append(added)
		print("FX_PERF sample %d: idle %.2f / %.2f ms, %d explosions %.2f ms, delta %+.2f ms, particles %d, nodes +%d"
			% [trial + 1, idle_before, idle_after, EXPLOSION_COUNT, active, added, peak_particles, peak_nodes - idle_nodes])
	deltas.sort()
	var added := deltas[1]
	check(added <= EXTRA_FRAME_BUDGET_MS, "%d simultaneous explosions add little to a frame (+%.2f ms, budget %.0f ms)"
		% [EXPLOSION_COUNT, added, EXTRA_FRAME_BUDGET_MS])
	check(max_nodes <= NODE_GROWTH_BUDGET, "explosions do not create a pile of nodes (+%d)" % max_nodes)
	check(max_particles > 0 and max_particles <= ParticleField.CAPACITY * 2,
		"particles stay within the fixed capacity (%d)" % max_particles)
	check(max_leftovers <= 8, "the nodes created by the explosions are gone afterwards")
	Engine.max_fps = previous_fps
	await end_level(level)
