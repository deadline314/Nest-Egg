extends RefCounted
## Camera-dependent drawing owners still need updates in a held simulation.
## Never advances simulation time or changes authored quality limits.


static func transform_values(value: Transform2D) -> Array[float]:
	return [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]


static func preserve_physics_bodies(root: Node) -> void:
	# Node.DISABLED normally removes CollisionObject2D from its physics space.
	# Keep body shapes available for real support/contact-shadow queries while
	# their scripts and simulation time remain held. Areas stay disabled so
	# moving the test actor cannot trigger gameplay zones during the fixture.
	for node in root.find_children("*", "PhysicsBody2D", true, false):
		node.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE


static func sync_contact_shadows(root: Node) -> void:
	for shadow in root.find_children("*", "ContactShadow", true, false):
		for ray in shadow._rays:
			ray.force_raycast_update()
		# Its nearest-light cache normally expires in simulation time. A held
		# actor can move without that time elapsing, so request the real update.
		shadow._light_timer = 0.0
		shadow._physics_process(0.0)


static func sync_owners(budget: LightBudget, walls: Array[WallShadows]) -> void:
	if budget != null:
		budget.refresh()
	for wall in walls:
		if not wall.is_enabled() or wall.suspended:
			continue
		# Request the owner's ordinary rescan and silhouette render, now rather
		# than after its time/frame interval (which cannot elapse while held).
		wall._since_scan = WallShadows.RESCAN
		wall._frame = WallShadows.REDRAW_EVERY - 1
		wall._process(0.0)


static func sync(level: Level) -> void:
	var walls: Array[WallShadows] = []
	for node in level.find_children("*", "", true, false):
		if node is WallShadows:
			walls.append(node)
	sync_owners(level._light_budget, walls)
	sync_contact_shadows(level)


static func snapshot(level: Level) -> Dictionary:
	var lights: Array[Dictionary] = []
	for node in level.get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
		if node is PointLight2D:
			lights.append({"instance": node.get_instance_id(), "position": str(node.global_position),
				"path": str(node.get_path()), "budget_visible": node.visible,
				"visible": node.is_visible_in_tree(), "enabled": node.enabled,
				"shadow": node.shadow_enabled, "energy": node.energy})
	var walls: Array[Dictionary] = []
	var valid := true
	var viewport := level.get_viewport()
	var to_screen := viewport.get_final_transform() * viewport.get_canvas_transform()
	var expected := Transform2D(0.0, Vector2.ONE * WallShadows.RESOLUTION, 0.0, Vector2.ZERO) * to_screen
	for node in level.find_children("*", "", true, false):
		if not node is WallShadows:
			continue
		var synchronized: bool = not node.is_enabled() or node.suspended or node._viewport.canvas_transform.is_equal_approx(expected)
		valid = valid and synchronized
		var chosen: Array[int] = []
		for light in node._chosen:
			if is_instance_valid(light): chosen.append(light.get_instance_id())
		walls.append({"enabled": node.is_enabled(), "suspended": node.suspended,
			"active_lights": node.active_lights(), "limit": node._limit,
			"chosen": chosen, "camera_synchronized": synchronized,
			"caster_transform": str(node._viewport.canvas_transform) if node.is_enabled() else "disabled by quality",
			"caster_transform_values": transform_values(node._viewport.canvas_transform) if node.is_enabled() else [],
			"expected_transform": str(expected), "drawn_origin": str(node._drawn_origin),
			"expected_transform_values": transform_values(expected),
			"drawn_scale": str(node._drawn_scale), "flagged_casters": node._flagged.size()})
	var parallax: Array[Dictionary] = []
	for node in level.find_children("*", "Parallax2D", true, false):
		# Camera2D notifies its viewport camera group directly even when the
		# parent is disabled; no internal process or autoscroll is advanced.
		parallax.append({"position": str(node.position), "screen_offset": str(node.screen_offset),
			"scroll_offset": str(node.scroll_offset)})
	var bodies: Array[Dictionary] = []
	for body in level.find_children("*", "PhysicsBody2D", true, false):
		var in_space := PhysicsServer2D.body_get_space(body.get_rid()).is_valid()
		valid = valid and in_space and body.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		bodies.append({"instance": body.get_instance_id(), "path": str(body.get_path()),
			"space_valid": in_space, "disable_mode": body.disable_mode})
	var contacts: Array[Dictionary] = []
	for shadow in level.find_children("*", "ContactShadow", true, false):
		var bounds: Rect2 = shadow.world_rect()
		contacts.append({"instance": shadow.get_instance_id(), "path": str(shadow.get_path()),
			"visible": shadow.is_visible_in_tree(), "cast": shadow.is_cast(), "shift": shadow._shift,
			"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})
	return {"valid": valid, "viewport_final_transform": str(viewport.get_final_transform()),
		"viewport_final_transform_values": transform_values(viewport.get_final_transform()),
		"active_lights": level._light_budget.active_lights,
		"active_shadow_lights": level._light_budget.active_shadow_lights,
		"scene_lights": lights, "wall_shadows": walls, "parallax": parallax,
		"physics_bodies": bodies, "contact_shadows": contacts}
