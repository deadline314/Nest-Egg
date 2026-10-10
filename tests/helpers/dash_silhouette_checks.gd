class_name DashSilhouetteChecks
extends RefCounted
## Hooked by the existing FxUpgradesSuite; no smoke registry/filter changes.
## Runtime regressions proposed for root to execute. CPU parsing is not a pass.

static func run(suite: EnemySuiteBase) -> void:
	var old_quality := Settings.get_light_quality()
	var old_reduced := Settings.get_reduce_flashes()
	var old_motion := Settings.get_reduce_ui_motion()
	var old_particles := Settings.get_feel_scale("particles")
	var old_trails := Settings.get_dash_silhouettes()
	Settings.set_dash_silhouettes(true)
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Settings.set_reduce_flashes(false)
	Settings.set_feel_scale("particles", 1.0)
	await suite.open_level(10.0)
	var player := suite.level.player
	var visual: PlayerVisual = player._visual
	# Stop automatic updates only for this isolated geometry test. Existing suite
	# already drives a real _try_dash and validates real timer-based fade-out.
	player.set_physics_process(false)
	visual.set_physics_process(false)
	visual.set_process(false)
	var pool := visual._ghost_pool
	suite.check(is_instance_valid(pool) and pool.slots.size() == DashSilhouettePool.CAPACITY, "dash pool creates exactly eight reusable slots")
	if not is_instance_valid(pool):
		await suite.end_level(suite.level)
		_restore_settings(old_quality, old_reduced, old_motion, old_particles, old_trails)
		return
	pool.clear()
	var input := RigInput.new()
	input.velocity = Vector2(300, 0)
	input.dashing = true
	visual.rig.animate(1.0 / 60.0, input)
	suite.check(pool.capture(visual), "formal Rin captures the currently animated dash pose")
	var first := pool.slots[0]
	var expected_parts := 0
	for part: CanvasItem in visual.rig._parts:
		if not part.is_visible_in_tree():
			continue
		expected_parts += 1
		var command := _find(first, part.get_instance_id())
		suite.check(command != null, "actual visible Rin part is present: %s" % part.name)
		if command == null:
			continue
		if part is RigPartMesh:
			suite.check(command.points == (part as RigPartMesh).deformed_vertices(), "captured mesh is current deformation: %s" % part.name)
		elif part is Sprite2D:
			suite.check(command.texture == (part as Sprite2D).texture and command.points[0] == (part as Sprite2D).get_rect().position,
				"sprite keeps its cached current eye/grip/coat texture and pivot: %s" % part.name)
	suite.check(expected_parts > 10, "actual player test contains full body, coat, hair, hands and feet")
	var mesh: RigPartMesh = visual.rig.limb_meshes()[0] if not visual.rig.limb_meshes().is_empty() else null
	suite.check(mesh != null, "actual Rin has a deformable limb to test immutable snapshots")
	if mesh != null:
		var saved := _find(first, mesh.get_instance_id())
		if saved != null:
			var points := saved.points.duplicate()
			var transform := saved.transform
			var texture := saved.texture
			player.position.x += 40.0
			input.crouching = true
			input.dashing = false
			for i in 24:
				visual.rig.animate(1.0 / 60.0, input)
			suite.check(saved.points == points and saved.transform == transform and saved.texture == texture, "old snapshot remains at captured world pose after live movement/deformation")
			suite.check(pool.capture(visual), "new crouch snapshot captures actual changed pose")
			var changed := _find(pool.slots[1], mesh.get_instance_id())
			suite.check(changed != null and (changed.points != points or changed.transform != transform), "second snapshot follows new geometry instead of rest pose")
	var weapon: Sprite2D = visual.rig._weapon_sprite
	if weapon != null and weapon.is_visible_in_tree() and weapon.texture != null:
		pool.clear()
		visual.rig.facing = 1.0
		suite.check(pool.capture(visual), "right-facing held weapon capture succeeds")
		var right := _find(pool.slots[0], weapon.get_instance_id())
		var right_xf := right.transform if right != null else Transform2D.IDENTITY
		visual.rig.facing = -1.0
		suite.check(pool.capture(visual), "left-facing held weapon capture succeeds")
		var left := _find(pool.slots[1], weapon.get_instance_id())
		suite.check(right != null and left != null and right_xf.determinant() * left.transform.determinant() < 0.0,
			"actual gun and rig facing reflect exactly once")
	else:
		suite.check(false, "actual initial player weapon must be visible for gun silhouette coverage")
	# Hidden armor / explicit alpha use actual presentation state, not rest ledger.
	var part := visual.rig._parts[0]
	var prior_visible := part.visible
	var prior_alpha := part.self_modulate.a
	pool.clear()
	part.visible = false
	suite.check(pool.capture(visual) and _find(pool.slots[0], part.get_instance_id()) == null, "hidden actual body part is absent rather than restoring armor")
	part.visible = prior_visible
	part.self_modulate.a = 0.25
	pool.clear()
	suite.check(pool.capture(visual), "part with actual alpha still captures")
	var faded := _find(pool.slots[0], part.get_instance_id())
	suite.check(faded != null and is_equal_approx(faded.colors[0].a, 0.25 * visual.modulate.a), "snapshot freezes actual part self alpha and body modulation once")
	part.self_modulate.a = prior_alpha
	# self_modulate belongs only to Visual's own drawing; its child Rig remains
	# visible. Ancestor modulate, in contrast, must still apply to those children.
	var prior_visual_self := visual.self_modulate.a
	var prior_visual_modulate := visual.modulate.a
	visual.self_modulate.a = 0.0
	visual.modulate.a = 0.6
	pool.clear()
	suite.check(pool.capture(visual), "transparent Visual own drawing does not omit its visible Rig children")
	var visible_child := _find(pool.slots[0], part.get_instance_id())
	suite.check(visible_child != null and is_equal_approx(visible_child.colors[0].a, prior_alpha * 0.6),
		"visible body ignores ancestor self alpha and retains ancestor modulation")
	visual.modulate.a = 0.0
	pool.clear()
	suite.check(not pool.capture(visual) and pool.active_count() == 0, "zero inherited Visual modulation omits an invisible body and gun")
	visual.self_modulate.a = prior_visual_self
	visual.modulate.a = prior_visual_modulate
	_test_trail_toggle(suite, pool, visual)
	_test_visibility_lifecycle(suite, pool, visual)
	_test_native_adapter(suite, pool)
	# These are real registered melee resources and the same Loadout equip path.
	# Their visible presentation is still procedural; the snapshot must not omit it.
	var original_loadout := player.loadout.snapshot()
	for file in ["melee_blade", "melee_maul", "melee_glaive", "melee_whip"]:
		var melee := load("res://data/weapons/melee/%s.tres" % file) as WeaponData
		suite.check(melee != null, "registered actual melee resource exists: " + file)
		if melee == null:
			continue
		player.loadout.equip(melee)
		for facing in [-1.0, 1.0]:
			player.facing = facing
			visual.rig.facing = facing
			pool.clear()
			suite.check(pool.capture(visual), "actual held melee silhouette captures: %s / %s" % [file, facing])
			var line_count := 0
			for i in pool.slots[0].used:
				var command := pool.slots[0].commands[i]
				if command.line_width > 0.0:
					line_count += 1
			suite.check(line_count == MeleeArt.segments(player.loadout.active_weapon()).size(), "all actual melee body segments survive without inventing a replacement")
	player.loadout.restore(original_loadout, player.tuning.default_weapon)
	# Unknown visible topology rejects the entire new sample. It must not leave a
	# partial torso, return a rest pose, or allocate another character to recover.
	var unknown := Node2D.new()
	visual.rig.add_child(unknown)
	visual.rig._parts.append(unknown)
	pool.clear()
	suite.check(not pool.capture(visual) and pool.active_count() == 0 and not pool.failure_reason.is_empty(), "unknown visible part fails safely with no partial ghost")
	visual.rig._parts.erase(unknown)
	unknown.free()
	var slot_ids: Array[int] = []
	var command_ids: Array[int] = []
	for slot in pool.slots:
		slot_ids.append(slot.get_instance_id())
		command_ids.append(slot.commands[0].get_instance_id())
	for i in 32:
		suite.check(pool.capture(visual), "ring capture succeeds at reuse %d" % i)
	suite.check(pool.active_count() <= DashSilhouettePool.CAPACITY, "repeated capture never grows the node pool")
	for i in pool.slots.size():
		suite.check(pool.slots[i].get_instance_id() == slot_ids[i] and pool.slots[i].commands[0].get_instance_id() == command_ids[i], "slot and command object identity is reused")
	pool.tick(DashSilhouettePool.LIFETIME + 0.01)
	suite.check(pool.active_count() == 0, "explicit elapsed lifetime clears the pool")
	for slot in pool.slots:
		suite.check(slot.used == 0 and slot.commands[0].texture == null, "expired slot releases old texture references")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	suite.check(DashSilhouettePool.slot_budget() == 2 and DashSilhouettePool.sample_interval() >= 0.09, "low quality reduces sampling without a different silhouette model")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Settings.set_reduce_flashes(true)
	suite.check(DashSilhouettePool.slot_budget() == 2 and DashSilhouettePool.opacity() < 0.24, "reduced flash lowers silhouette opacity and concurrent samples")
	Settings.set_reduce_ui_motion(true)
	suite.check(DashSilhouettePool.slot_budget() == 2, "UI-motion preference retains its UI-only semantics")
	Settings.set_feel_scale("particles", 0.0)
	pool.tick(0.0)
	suite.check(not pool.capture(visual) and pool.active_count() == 0, "zero particle feedback stops silhouettes and clears leases")
	Settings.set_feel_scale("particles", 1.0)
	Settings.set_reduce_flashes(false)
	_test_lethal_clear(suite, pool, visual)
	_restore_settings(old_quality, old_reduced, old_motion, old_particles, old_trails)
	suite.check(Settings.get_dash_silhouettes() == old_trails, "dash helper restores the exact original trail preference")
	var pool_ref: WeakRef = weakref(pool)
	await suite.end_level(suite.level)
	await suite.frames(2)
	suite.check(pool_ref.get_ref() == null, "actual Level teardown releases the sibling silhouette pool")

## Actual Health -> Player -> Level signal boundary, with process disabled by a
## genuine presentation lock. No _update_ghosts/clear call repairs the assertion.
## The fixture Level is not a native first-clinic/fee/retry walkthrough.
static func _test_lethal_clear(suite: EnemySuiteBase, pool: DashSilhouettePool, visual: PlayerVisual) -> void:
	var player: Player = visual.player
	player._try_dash(1.0)
	visual._physics_process(1.0 / 60.0)
	visual._update_ghosts(1.0 / 60.0)
	suite.check(player.state == Player.State.DASH and pool.active_count() > 0 and _texture_leases(pool) > 0,
		"lethal boundary starts with real Player dash and source texture leases")
	if player.state != Player.State.DASH or pool.active_count() == 0:
		return
	var observed: Array[bool] = []
	var death_observer: Callable = func(_cause: StringName) -> void:
		observed.append(player.is_dead() and visual._ghost_timer == 0.0 and _samples_empty(pool))
	EventBus.player_died.connect(death_observer)
	var token := GameplayLock.acquire(visual)
	suite.check(token != 0 and suite.runner.get_tree().paused and not visual.can_process(),
		"real modal lock prevents a Visual process frame before lethal health callback")
	var frame_before := Engine.get_process_frames()
	var damage := DamageInfo.create(player.health.current, Combat.Team.ENEMY, &"ne247_lethal_boundary_test")
	damage.ignore_invulnerability = true
	suite.check(player.health.take_damage(damage), "real Health takes lethal damage while visual cannot process")
	EventBus.player_died.disconnect(death_observer)
	suite.check(Engine.get_process_frames() == frame_before and player.health.is_dead and player.is_dead() and suite.level.died,
		"actual Health Player Level death chain completes synchronously without a visual frame")
	suite.check(observed.size() == 1 and observed[0], "real outward death observer already sees retired silhouettes and texture leases")
	suite.check(pool.active_count() == 0 and _texture_leases(pool) == 0 and visual._ghost_timer == 0.0,
		"lethal hit retires every ghost before modal processing can resume")
	for slot in pool.slots:
		suite.check(slot.used == 0 and not slot.visible, "every slot is empty and hidden at the actual health death boundary")
	GameplayLock.release(token)


static func _texture_leases(pool: DashSilhouettePool) -> int:
	var count := 0
	for slot in pool.slots:
		for command in slot.commands:
			count += int(command.texture != null)
	return count


static func _samples_empty(pool: DashSilhouettePool) -> bool:
	if pool.active_count() != 0 or _texture_leases(pool) != 0:
		return false
	for slot in pool.slots:
		if slot.used != 0 or slot.visible:
			return false
	return true


static func _test_trail_toggle(suite: EnemySuiteBase, pool: DashSilhouettePool, visual: PlayerVisual) -> void:
	pool.clear()
	suite.check(pool.capture(visual) and pool.active_count() > 0, "trail toggle begins with real captured geometry")
	var identity := pool.get_instance_id()
	var slots_before: Array[int] = []
	for slot in pool.slots:
		slots_before.append(slot.get_instance_id())
	# No tick/process call between the setting and lease inspection.
	Settings.set_dash_silhouettes(false)
	suite.check(DashSilhouettePool.slot_budget() == 0 and pool.active_count() == 0, "trail off immediately clears active samples without a gameplay frame")
	var leases := 0
	var commands := 0
	for slot in pool.slots:
		commands += slot.used
		for command in slot.commands:
			leases += int(command.texture != null)
	suite.check(commands == 0 and leases == 0 and not pool.capture(visual), "trail off immediately releases every texture lease and refuses new samples")
	Settings.set_dash_silhouettes(true)
	suite.check(pool.capture(visual) and pool.get_instance_id() == identity, "trail on resumes capture through the same pool")
	for i in pool.slots.size():
		suite.check(pool.slots[i].get_instance_id() == slots_before[i], "trail preference reuses each fixed slot")
	pool.clear()


static func _test_visibility_lifecycle(suite: EnemySuiteBase, pool: DashSilhouettePool, visual: PlayerVisual) -> void:
	# Presentation boundary coverage only. This does not stand in for a genuine
	# lethal-hit/death/retry gameplay regression or native visual acceptance.
	var prior_state := visual.player.state
	var prior_visible := visual.visible
	for state in [Player.State.DEAD, Player.State.MOUNTED]:
		pool.clear()
		suite.check(pool.capture(visual) and pool.active_count() > 0, "state-boundary test begins with a live silhouette")
		visual.player.state = state
		visual._update_ghosts(0.0)
		suite.check(pool.active_count() == 0, "dead or mounted presentation immediately clears silhouette leases")
		for slot in pool.slots:
			suite.check(slot.used == 0 and slot.commands[0].texture == null, "state-boundary clear releases source texture references")
		visual.player.state = prior_state
	pool.clear()
	suite.check(pool.capture(visual), "visibility-boundary test begins with a live silhouette")
	visual.hide()
	visual._update_ghosts(0.0)
	suite.check(pool.active_count() == 0 and not pool.capture(visual), "hidden actual Visual clears and cannot create silhouettes")
	visual.visible = prior_visible

static func _test_native_adapter(suite: EnemySuiteBase, pool: DashSilhouettePool) -> void:
	# Reuse the established validated native mesh fixture; label it synthetic.
	# This CPU/runtime adapter test is not evidence of native GPU pixel alignment.
	# _fixture/_new_rig require the same environment as PoseMeshSuite.run.
	var old_lit := LitTextures.is_enabled()
	var old_rigid := CharacterRig.force_rigid_limbs
	LitTextures.set_enabled(true)
	CharacterRig.force_rigid_limbs = true
	var fixtures := PoseMeshSuite.new(suite.runner)
	var rig := fixtures._new_rig(fixtures._fixture())
	suite.check(rig.set_pose_parts(&"mesh_a"), "synthetic native pose fixture selects its real Polygon2D path")
	rig.facing = -1.0
	rig.bone(&"hip").rotation += 0.3
	rig.bone(&"chest").rotation -= 0.2
	var geometry := rig.active_pose_mesh_geometries()
	suite.check(not geometry.is_empty(), "native fixture has actual weighted current geometry")
	if not geometry.is_empty():
		var mesh: Polygon2D = geometry[0]["mesh"]
		var vertices: PackedVector2Array = geometry[0]["vertices"]
		var slot := pool.slots[0]
		slot.clear()
		var xf := pool.global_transform.affine_inverse() * rig._skeleton.global_transform
		suite.check(pool._polygon(slot, mesh, vertices, xf), "native pose snapshot adapter accepts validated current skin")
		var command := _find(slot, mesh.get_instance_id())
		suite.check(command != null and command.points == vertices and command.texture == mesh.texture and command.transform == xf,
			"native snapshot retains current weighted vertices, shared texture and one root reflection")
		if command != null:
			suite.check(command.uv[0].is_equal_approx(mesh.uv[0] / mesh.texture.get_size()), "native pixel UVs convert once to normalized texture coordinates")
		slot.clear()
	rig.free()
	CharacterRig.force_rigid_limbs = old_rigid
	LitTextures.set_enabled(old_lit)
	suite.check(CharacterRig.force_rigid_limbs == old_rigid and LitTextures.is_enabled() == old_lit, "native fixture restores prior global rendering controls")

static func _find(slot: DashSilhouettePool.Snapshot, source_id: int) -> DashSilhouettePool.Command:
	for i in slot.used:
		if slot.commands[i].source_id == source_id:
			return slot.commands[i]
	return null

static func _restore_settings(quality: int, reduced: bool, motion: bool, particles: float, trails: bool) -> void:
	Settings.set_light_quality(quality)
	Settings.set_reduce_flashes(reduced)
	Settings.set_reduce_ui_motion(motion)
	Settings.set_feel_scale("particles", particles)
	Settings.set_dash_silhouettes(trails)
