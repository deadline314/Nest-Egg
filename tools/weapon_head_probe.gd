extends RefCounted
## Same-frame conservative head exposure bound, following the existing BG-49 opaque-head method.
## Raw world W includes the head rectangle's background; opaque head H is a lower area bound.


static func capture(owner: Node, level: Level, output: String, name: String, blank := false, require_muzzle := false) -> Dictionary:
	var muzzle_energy := 0.0
	var waited_frames := 0
	# Keep real firing input active outside this helper; capture the first rendered flash, not a later dark frame.
	for frame in 120:
		await RenderingServer.frame_post_draw
		waited_frames += 1
		muzzle_energy = 0.0
		var weapon := level.player.loadout.active_weapon()
		for light: PointLight2D in Fx._lights:
			if light.enabled and light.global_position.distance_to(level.player.muzzle_position()) <= 16.0 \
					and is_equal_approx(light.texture_scale * LightKit.TEXTURE_SIZE * 0.5, weapon.muzzle_light_radius) \
					and light.color.is_equal_approx(weapon.color):
				muzzle_energy += light.energy
		if not require_muzzle or muzzle_energy > 0.0:
			break
	if require_muzzle and muzzle_energy <= 0.0:
		return {"error": "no rendered muzzle flash within 120 frames of real firing", "waited_render_frames": waited_frames}
	var viewport := owner.get_viewport()
	var main := viewport.get_texture().get_image()
	var raw_physics_frame := Engine.get_physics_frames()
	var mode := level.process_mode
	level.process_mode = Node.PROCESS_MODE_DISABLED
	var head: Node2D
	for part: CanvasItem in level.player._visual.rig._parts:
		if part.name == &"head" and part.is_visible_in_tree():
			if head != null:
				level.process_mode = mode
				return {"error": "ambiguous visible head"}
			head = part as Node2D
	if head == null or not (head is Sprite2D or head is Polygon2D) or (head is Polygon2D and head.get_bone_count() > 0):
		level.process_mode = mode
		return {"error": "missing or unsupported GPU-skinned head"}
	var shader := head.material as ShaderMaterial
	if shader != null and shader.shader != CharacterRig.LIGHT_SHADER:
		level.process_mode = mode
		return {"error": "unsupported head shader"}
	var ancestor: Node = head
	while ancestor is CanvasItem:
		if not is_equal_approx(ancestor.modulate.a, 1.0) or ancestor.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			level.process_mode = mode
			return {"error": "head ancestor alpha/clipping requires a compositing proof"}
		ancestor = ancestor.get_parent()
	var before := head.global_transform
	var transform := viewport.get_final_transform() * viewport.get_canvas_transform()
	var local_bounds: Rect2
	if head is Sprite2D:
		local_bounds = head.get_rect()
	else:
		var vertices: PackedVector2Array = head.polygon
		if vertices.is_empty():
			level.process_mode = mode
			return {"error": "empty head polygon"}
		local_bounds = Rect2(vertices[0], Vector2.ZERO)
		for vertex in vertices:
			local_bounds = local_bounds.expand(vertex)
	for uniform in [&"sway_a_shape", &"sway_b_shape"]:
		var shape: Variant = head.get_instance_shader_parameter(uniform)
		if shape is Vector2 and shape.x > 0:
			var padding: Variant = head.get_instance_shader_parameter(&"sway_padding")
			local_bounds = local_bounds.grow(absf(float(padding)) if padding != null else 24.0)
			break
	var geometry_fits := true
	for corner in [local_bounds.position, Vector2(local_bounds.end.x, local_bounds.position.y), local_bounds.end, Vector2(local_bounds.position.x, local_bounds.end.y)]:
		geometry_fits = geometry_fits and Rect2(Vector2.ZERO, Vector2(main.get_size())).has_point(transform * before * corner)
	var view := SubViewport.new()
	view.size = main.get_size()
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.use_hdr_2d = true
	view.disable_3d = true
	view.canvas_item_default_texture_filter = viewport.canvas_item_default_texture_filter
	view.canvas_item_default_texture_repeat = viewport.canvas_item_default_texture_repeat
	view.msaa_2d = viewport.msaa_2d
	view.snap_2d_transforms_to_pixel = viewport.snap_2d_transforms_to_pixel
	view.snap_2d_vertices_to_pixel = viewport.snap_2d_vertices_to_pixel
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	owner.add_child(view)
	view.canvas_transform = transform
	var copy := head.duplicate(0) as Node2D
	for child in copy.get_children():
		copy.remove_child(child)
		child.free()
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	view.add_child(copy)
	copy.global_transform = before
	var parent := head.get_parent()
	while parent is CanvasItem:
		if copy.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and parent.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			copy.texture_filter = parent.texture_filter
		if copy.texture_repeat == CanvasItem.TEXTURE_REPEAT_PARENT_NODE and parent.texture_repeat != CanvasItem.TEXTURE_REPEAT_PARENT_NODE:
			copy.texture_repeat = parent.texture_repeat
		parent = parent.get_parent()
	for uniform in [&"sway_a", &"sway_a_shape", &"sway_b", &"sway_b_shape", &"sway_padding", &"sway_bounds"]:
		var value: Variant = head.get_instance_shader_parameter(uniform)
		if value != null:
			copy.set_instance_shader_parameter(uniform, value)
	if blank:
		copy.hide()
	await owner.get_tree().process_frame
	await owner.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var mask := view.get_texture().get_image()
	var held := head.global_transform == before and copy.global_transform == before
	var rect := mask.get_used_rect()
	var opaque := 0
	var white := 0
	var white_head := 0
	var peak := 0.0
	if mask.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var alpha := mask.get_pixel(x, y).a
				opaque += int(alpha >= 0.999)
				var pixel := main.get_pixel(x, y)
				var is_white := pixel.r > 0.92 and pixel.g > 0.92 and pixel.b > 0.92
				white += int(is_white)
				white_head += int(is_white and alpha > 0.0)
				peak = maxf(peak, maxf(pixel.r, maxf(pixel.g, pixel.b)))
	var result := {"opaque_head_pixels": opaque, "white_rectangle_pixels": white, "bound_valid": held and opaque > 0 and geometry_fits,
		"white_ratio_upper_bound": float(white) / opaque if opaque > 0 else null, "peak": peak,
		# Nonzero alpha contains the full head silhouette; opaque alpha remains the area lower bound.
		"white_head_pixels_upper_bound": white_head, "white_head_ratio_upper_bound": float(white_head) / opaque if opaque > 0 else null,
		"sample_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "source_held": held,
		"expanded_geometry_fully_in_bounds": geometry_fits,
		"muzzle_energy_at_raw_capture": muzzle_energy, "physics_frame_at_raw_capture": raw_physics_frame,
		"requires_active_muzzle": require_muzzle, "waited_render_frames": waited_frames,
		"gun_light_enabled_at_raw_capture": level.player._weapon_light._light.enabled, "gun_light_lit_at_raw_capture": level.player._weapon_light.is_lit(),
		"head_source": str(head.get_path()), "world_format": main.get_format(), "mask_format": mask.get_format(),
		"width": main.get_width(), "height": main.get_height(), "blank_negative_control": blank,
		"world_to_image": [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y],
		"scope": "arranged unobstructed player head; conservative W/H, not exact per-character white fraction"}
	for pair in [[name, main], [name + "-head-alpha", mask]]:
		var image: Image = pair[1]
		var writer := FileAccess.open(output.path_join(pair[0] + ".bin"), FileAccess.WRITE)
		if writer == null:
			result["bound_valid"] = false
			continue
		writer.store_buffer(image.get_data())
		writer.close()
		if preload("res://tools/viewport_capture.gd").encode(image, true).save_png(output.path_join(pair[0] + ".png")) != OK:
			result["bound_valid"] = false
	result["files"] = {"world_raw": name + ".bin", "world_png": name + ".png", "mask_raw": name + "-head-alpha.bin", "mask_png": name + "-head-alpha.png"}
	view.queue_free()
	level.process_mode = mode
	return result
