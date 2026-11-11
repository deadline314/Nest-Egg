extends RefCounted
## Formal Fx ownership: pausing scripts must not retire body/area collision RIDs.
static func run(suite: TestSuite) -> void:
	var tree := suite.runner.get_tree()
	var actor := CharacterBody2D.new()
	actor.position = Vector2(11234, 12345)
	actor.collision_layer = Layers.ENEMY_HURTBOX
	actor.collision_mask = 0
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_MAKE_STATIC
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 20)
	shape.shape = rectangle
	actor.add_child(shape)
	var box := Hurtbox.new()
	actor.add_child(box)
	box.setup(Combat.Team.ENEMY, null, Vector2(12, 20))
	var disabled := Area2D.new()
	disabled.process_mode = Node.PROCESS_MODE_DISABLED
	actor.add_child(disabled)
	tree.root.add_child(actor)
	await tree.physics_frame
	await tree.physics_frame
	var expected := actor.get_world_2d().space
	suite.check(PhysicsServer2D.body_get_space(actor.get_rid()) == expected and PhysicsServer2D.area_get_space(box.get_rid()) == expected, "freeze setup has a real body and inherited hurtbox in physics")
	suite.check(not PhysicsServer2D.area_get_space(disabled.get_rid()).is_valid(), "freeze setup includes an independently disabled area")
	Feel.freeze([actor], 1.0)
	suite.check(not actor.can_process() and not box.can_process(), "a local pause still stops actor and inherited hurtbox processing")
	suite.check(PhysicsServer2D.body_get_space(actor.get_rid()) == expected and PhysicsServer2D.area_get_space(box.get_rid()) == expected, "body and inherited hurtbox stay in their real space immediately after freeze")
	await tree.physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.position = actor.global_position
	query.collision_mask = Layers.ENEMY_HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits := actor.get_world_2d().direct_space_state.intersect_point(query)
	var body_seen := false
	var box_seen := false
	for hit in hits:
		body_seen = body_seen or hit["collider"] == actor
		box_seen = box_seen or hit["collider"] == box
	suite.check(body_seen and box_seen, "the paused actor and hurtbox remain discoverable by an actual physics query")
	suite.check(not PhysicsServer2D.area_get_space(disabled.get_rid()).is_valid() and disabled.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE, "freezing an ancestor never activates an independently disabled area")
	var original_lease_count := int((Fx._collision_space_holds.get(box.get_instance_id(), [null, 0, 0]) as Array)[2])
	Feel.freeze([actor], 2.0)
	suite.check(original_lease_count > 0 and int((Fx._collision_space_holds.get(box.get_instance_id(), [null, 0, 0]) as Array)[2]) == original_lease_count and actor.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE, "extending one owner does not add leases or overwrite its original disable mode")
	# An inherited area may also own a longer pause. Parent thaw must not remove its RID.
	Feel.freeze([box], 1.0)
	Fx._frozen[actor][0] = 0
	Fx._release_frozen(Time.get_ticks_msec())
	suite.check(actor.can_process() and not box.can_process() and box.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE, "an overlapping child pause keeps its collision ownership after the parent thaws")
	suite.check(actor.disable_mode == CollisionObject2D.DISABLE_MODE_MAKE_STATIC and PhysicsServer2D.area_get_space(box.get_rid()) == expected, "parent thaw restores its exact old mode without retiring the still-paused child")
	Fx.thaw_all()
	suite.check(box.can_process() and box.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE and actor.disable_mode == CollisionObject2D.DISABLE_MODE_MAKE_STATIC, "final thaw restores every original collision disable mode")
	suite.check(Fx._collision_space_holds.is_empty() and Fx._freeze_collision_owners.is_empty(), "collision pause ownership is fully released")
	# Reverse both acquisition and restoration order: child first, then parent, then child thaw.
	Feel.freeze([box], 1.0)
	Feel.freeze([actor], 1.0)
	Fx._frozen[box][0] = 0
	Fx._release_frozen(Time.get_ticks_msec())
	suite.check(not actor.can_process() and not box.can_process() and box.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE, "thawing the child first preserves its still-paused ancestor's collision lease")
	suite.check(PhysicsServer2D.area_get_space(box.get_rid()) == expected, "reverse freeze and thaw order retains the same actual area space")
	Fx.thaw_all()
	suite.check(actor.can_process() and box.can_process() and box.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE, "reverse ownership order restores normal inherited processing and original mode")
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	Feel.freeze([actor], 1.0)
	Fx.thaw_all()
	suite.check(actor.process_mode == Node.PROCESS_MODE_DISABLED and box.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE and not PhysicsServer2D.area_get_space(box.get_rid()).is_valid(), "a previously disabled actor and its removed hurtbox are never revived")
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	tree.paused = true
	Feel.freeze([actor], 1.0)
	tree.paused = false
	suite.check(not Fx._frozen.has(actor) and actor.process_mode == Node.PROCESS_MODE_INHERIT, "an existing scene pause does not acquire local freeze or collision ownership")
	Feel.freeze([actor], 1.0)
	tree.root.remove_child(actor)
	Fx.thaw_all()
	suite.check(actor.process_mode == Node.PROCESS_MODE_INHERIT and actor.disable_mode == CollisionObject2D.DISABLE_MODE_MAKE_STATIC and box.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE, "leaving the tree while paused still restores all original modes")
	tree.root.add_child(actor)
	await tree.physics_frame
	# Freed paused owners must not leak ownership or try to touch stale CollisionObject2Ds.
	Feel.freeze([actor], 1.0)
	actor.queue_free()
	await tree.process_frame
	Fx.thaw_all()
	suite.check(Fx._collision_space_holds.is_empty() and Fx._freeze_collision_owners.is_empty(), "freeing a paused owner releases its collision bookkeeping safely")

	# Real death behavior disables collision layers and hurtboxes while the pause is owned.
	var level := await suite.start_level(EnemySuiteBase.map_data())
	var enemy := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	enemy.position = Vector2(200, EnemySuiteBase.FLOOR_Y)
	level._entities.add_child(enemy)
	await suite.physics_frames(2)
	Feel.freeze([enemy], 1.0)
	var damage := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
	damage.ignore_invulnerability = true
	damage.bypass_guard = true
	enemy.hurtbox.receive(damage)
	await tree.process_frame
	await tree.process_frame
	suite.check(enemy.health.is_dead and not enemy.hurtbox.enabled and not enemy.contact.active and enemy.collision_layer == 0, "a real frozen grunt's lethal hit still disables its body layer, hurtbox and contact damage")
	Fx.thaw_all()
	await suite.physics_frames(2)
	suite.check(enemy.health.is_dead and not enemy.hurtbox.can_receive() and not enemy.hurtbox.monitorable and enemy.collision_layer == 0 and not enemy.contact.active, "thaw never restores dead enemy layers, hurtbox eligibility or contact damage")
	suite.check(enemy.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE and enemy.hurtbox.disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE, "a dead actor's temporary disable modes are restored without reviving collision eligibility")
	await suite.end_level(level)
