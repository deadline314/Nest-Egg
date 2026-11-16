extends RefCounted
## Known interior rays: shadow visibility, not soft-edge photometry or physics visibility.


static func run(suite: TestSuite) -> void:
	var holder := Node2D.new()
	holder.position = Vector2(10000, -10000)
	suite.runner.get_tree().root.add_child(holder)
	var tree := holder.get_tree()
	var light := LightKit.create_point_light(Color.WHITE, 200.0, 1.0, true, false)
	holder.add_child(light)
	LightKit.mark_aimed(light, 200.0, 90.0)
	var point := holder.global_position + Vector2(100, 0)
	var baseline := LightKit.light_level_at(tree, point)
	suite.check(is_equal_approx(baseline, 0.5), "open gun-light query retains its original distance contribution")
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(40,-20), Vector2(60,-20), Vector2(60,20), Vector2(40,20)])
	var blocker := LightOccluder2D.new()
	blocker.occluder = polygon
	LightKit.mark_shadow_occluder(blocker)
	holder.add_child(blocker)
	suite.check(is_zero_approx(LightKit.light_level_at(tree, point)), "real shadow polygon blocks the interior gun-light query")
	blocker.hide()
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline), "hidden shadow polygon does not block")
	blocker.show()
	blocker.occluder_light_mask = 2
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline), "nonmatching render shadow mask does not block")
	light.shadow_item_cull_mask = 2
	suite.check(is_zero_approx(LightKit.light_level_at(tree, point)), "matching alternate render shadow masks still block")
	light.shadow_item_cull_mask = 1
	blocker.occluder_light_mask = 1
	light.shadow_enabled = false
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline), "shadow-disabled gun light retains its original contribution")
	light.shadow_enabled = true
	blocker.position.y = 100
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline), "moving the actual blocker off the ray restores the light")
	blocker.position = Vector2(50, 0)
	polygon.polygon = PackedVector2Array([Vector2(-10,-20), Vector2(10,-20), Vector2(10,20), Vector2(-10,20)])
	blocker.rotation = PI * 0.25
	blocker.scale = Vector2(1.5, 0.8)
	suite.check(is_zero_approx(LightKit.light_level_at(tree, point)), "transformed actual occluder geometry blocks in its local coordinates")
	blocker.rotation = 0
	blocker.scale = Vector2.ONE
	polygon.cull_mode = OccluderPolygon2D.CULL_CLOCKWISE
	print("EXPECTED_WARNING_BEGIN directional shadow diagnostic")
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline) and blocker.has_meta(&"light_query_cull_warning"), "unsupported directional culling is explicitly diagnosed and retains the prior contribution")
	print("EXPECTED_WARNING_END directional shadow diagnostic")
	polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
	polygon.closed = false
	polygon.polygon = PackedVector2Array([Vector2(0,-20), Vector2(0,20)])
	suite.check(is_zero_approx(LightKit.light_level_at(tree, point)), "open double-sided occluder uses its real segment without an invented closing edge")
	blocker.hide()
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 40)
	shape.shape = rectangle
	body.position = Vector2(50, 0)
	body.add_child(shape)
	holder.add_child(body)
	await tree.physics_frame
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline), "WORLD collision without an actual render occluder does not invent a shadow")
	var canvas := CanvasLayer.new()
	suite.runner.get_tree().root.add_child(canvas)
	var other := LightOccluder2D.new()
	other.position = holder.global_position + Vector2(50,0)
	other.occluder = polygon
	LightKit.mark_shadow_occluder(other)
	canvas.add_child(other)
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), baseline), "an occluder on a different canvas does not block world gun light")
	var scene_light := LightKit.create_point_light(Color.WHITE, 200.0, 0.5, false, true)
	holder.add_child(scene_light)
	light.enabled = false
	var scene_only := LightKit.light_level_at(tree, point)
	suite.check(is_equal_approx(scene_only, 0.25), "existing scene-light contribution remains unchanged")
	light.enabled = true
	blocker.show()
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), scene_only), "wall only filters the aimed contribution and preserves scene light")
	blocker.queue_free()
	await tree.process_frame
	await tree.process_frame
	suite.check(is_equal_approx(LightKit.light_level_at(tree, point), scene_only + baseline), "freed actual occluders leave no stale visibility blocker")
	canvas.queue_free()
	holder.queue_free()
	await tree.process_frame
