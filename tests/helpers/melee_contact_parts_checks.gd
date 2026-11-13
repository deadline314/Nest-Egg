extends RefCounted
## Natural armed attacks: broadphase traps never grant weak damage or suppress a real body hit.
static func run(suite: Variant) -> void:
	for configuration in ["body", "phantom_weak", "later_real_weak", "closed_guard", "shield_before_weak", "disabled_weak"]:
		await suite.open_level(10)
		var player: Player = suite.level.player
		player.loadout.reset(load("res://data/weapons/melee/melee_blade.tres") as WeaponData)
		player.facing = 1
		player.aim_dir = Vector2.RIGHT
		AimInput.using_gamepad = true
		AimInput._last_stick_dir = Vector2.RIGHT
		var enemy: Enemy = await suite._target_at(22)
		enemy.hurtbox.parts_take_melee = true
		for original in enemy.hurtbox.parts:
			original.enabled = false
		var remote := enemy.hurtbox.add_part(&"remote", Vector2(2, 2), Vector2(0, -4), 3)
		remote.guard = Callable()
		var real := enemy.hurtbox.add_part(&"real", Vector2(6, 6), Vector2(-2, -40), 3)
		real.guard = Callable()
		remote.enabled = configuration in ["phantom_weak", "later_real_weak"]
		real.enabled = configuration in ["later_real_weak", "closed_guard", "shield_before_weak"]
		if configuration in ["closed_guard", "shield_before_weak"]:
			real.guard = func(_info: DamageInfo) -> Hurtbox.Guard: return Hurtbox.Guard.BLOCK
		if configuration == "shield_before_weak":
			var exposed := enemy.hurtbox.add_part(&"behind_shield", Vector2(2, 3), Vector2(-2, -40), 4)
			exposed.guard = Callable()
			# A high-priority exposed point must not bypass a really touched protective part.
			enemy.hurtbox.parts.erase(exposed)
			enemy.hurtbox.parts.push_front(exposed)
		await suite.physics_frames(3)
		var part_facts: Array = []
		for part in enemy.hurtbox.parts:
			part_facts.append({"id":str(part.part_id),"center":str(part.center()),"enabled":part.enabled,"guard":part.guard.is_valid(),"space":PhysicsServer2D.area_get_space(part.get_rid()).is_valid(),"in_bounds":player.melee._contact_in_bounds(part,MeleeData.set_of(player.loadout.active_weapon()).attack("cut_1"))})
		var candidates: Array = []
		for candidate in player.melee.targets(MeleeData.set_of(player.loadout.active_weapon()).attack("cut_1")):
			candidates.append(str(candidate.part_id))
		print("NE277_PART_SETUP ",JSON.stringify({"configuration":configuration,"player":str(player.global_position),"facing":player.facing,"enemy":str(enemy.global_position),"parts":part_facts,"candidates":candidates}))
		var hits: Array = []
		var blocks: Array = []
		enemy.health.damaged.connect(func(info: DamageInfo) -> void: hits.append([info.part, info.weak_hit, info.amount]))
		for box in enemy.hurtbox.parts:
			box.hit_blocked.connect(func(info: DamageInfo) -> void: blocks.append([info.part, info.weak_hit, info.amount]))
		if remote.enabled:
			suite.check(player.melee.targets(MeleeData.set_of(player.loadout.active_weapon()).attack("cut_1")).has(remote), configuration + " genuinely nominates a remote high-priority broadphase part")
		suite.check(player._try_melee(), configuration + " starts a formal armed attack")
		for frame in 90:
			await suite.physics_frames(1)
			if player.melee.phase == MeleeModule.Phase.NONE:
				break
		print("NE277_PART_RESULT ",JSON.stringify({"configuration":configuration,"hits":hits,"blocked":blocks,"hp":enemy.health.current}))
		var expected := 6 if configuration == "later_real_weak" else 2
		if configuration in ["closed_guard", "shield_before_weak"]:
			suite.check(hits.is_empty() and enemy.health.current == 999 and blocks.size() == 1, configuration + " actual shield/closed-part contact blocks once without damage behind it")
			suite.check(blocks.size() == 1 and blocks[0] == [&"", false, 2], configuration + " preserves original blocked DamageInfo part/weak/amount semantics")
		else:
			suite.check(hits.size() == 1 and 999 - enemy.health.current == expected, configuration + " keeps exactly one correct damage amount")
			suite.check(hits.size() == 1 and hits[0][0] == (&"real" if expected == 6 else &"") and hits[0][1] == (expected == 6), configuration + " selects the actually touched weak part or the ordinary body")
		Input.action_release(&"aim_right")
		await suite.end_level(suite.level)
