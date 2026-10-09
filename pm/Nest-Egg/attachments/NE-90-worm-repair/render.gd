extends Node2D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("RENDER ", Engine.get_version_info(), " / ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_current_rendering_driver_name(), " / ", RenderingServer.get_video_adapter_name())
	var bg := ColorRect.new()
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(4000, 4000)
	bg.color = Color(0.38, 0.38, 0.38)
	add_child(bg)
	var camera := Camera2D.new()
	camera.zoom = Vector2(3.4, 3.4)
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.position = Vector2(12, 12)
	canvas.add_child(label)
	var states: Array = RigLibrary.load_json(WormCreature.PATH % "cloud_serpent")["states"].keys()
	for face in [-1, 1]:
		for state: String in states:
			var worm := WormCreature.new()
			add_child(worm)
			if not worm.setup("cloud_serpent"):
				get_tree().quit(1)
				return
			worm.position = Vector2(320, 210)
			worm.reset_trail(Vector2(face, 0))
			for frame in 120:
				worm.animate(1.0 / 60.0, StringName(state))
			camera.position = Vector2(320 - face * 25, 210)
			await _save(worm, label, "%s-face%d-frame119" % [state, face])
			worm.free()
	var turning := WormCreature.new()
	add_child(turning)
	turning.setup("cloud_serpent")
	turning.position = Vector2(320, 210)
	turning.reset_trail(Vector2.RIGHT)
	var previous_head_mirrored := false
	for frame in 480:
		# Two full turns: exercise heading wrap without shortening or reinitializing the trail.
		var angle := float(frame) * TAU / 240.0
		turning.position += Vector2.from_angle(angle) * 1.2
		turning.animate(1.0 / 60.0, &"erupt")
		var current_head := turning.get_node("Head") as Sprite2D
		var head_mirrored := current_head.scale.y < 0.0
		if head_mirrored != previous_head_mirrored:
			print("HEAD_BOUNDARY frame=", frame, " mirrored=", head_mirrored, " roll=", turning.get("_belly_roll"))
		previous_head_mirrored = head_mirrored
		var boundary := absf(current_head.global_transform.x.normalized().x) < 0.3
		if frame in [119, 239, 359, 479] or boundary:
			var body := turning.get_node("Body") as Polygon2D
			var bounds := Rect2(body.polygon[0], Vector2.ZERO)
			for point: Vector2 in body.polygon:
				bounds = bounds.expand(point)
			var head := turning.get_node("Head") as Sprite2D
			for corner: Vector2 in [Vector2.ZERO, Vector2(head.texture.get_width(), 0), head.texture.get_size(), Vector2(0, head.texture.get_height())]:
				bounds = bounds.expand(head.to_global(corner + head.offset))
			camera.position = bounds.get_center()
			await _save(turning, label, ("boundary-frame%d" if boundary else "turn-frame%d") % frame)
	turning.free()
	get_tree().quit()

func _save(worm: WormCreature, label: Label, name_tag: String) -> void:
	label.visible = not name_tag.begins_with("boundary")
	label.text = "cloud_serpent / %s / complete 20 joints / Forward+ zoom3.4" % name_tag
	for frame in 4:
		await get_tree().process_frame
	var viewport_transform := get_viewport().get_canvas_transform()
	var body := worm.get_node("Body") as Polygon2D
	var inside := true
	for point: Vector2 in body.polygon:
		inside = inside and get_viewport_rect().has_point(viewport_transform * point)
	var head := worm.get_node("Head") as Sprite2D
	for corner: Vector2 in [Vector2.ZERO, Vector2(head.texture.get_width(), 0), head.texture.get_size(), Vector2(0, head.texture.get_height())]:
		inside = inside and get_viewport_rect().has_point(viewport_transform * head.to_global(corner + head.offset))
	var path := "res://pm/Nest-Egg/images/NE-90-worm-repair/%s.png" % name_tag
	var error := preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(path)
	print("PNG ", path, " error=", error, " joints=", worm.joint_count(), " body_inside=", inside)
	if error != OK or not inside:
		push_error("incomplete native worm evidence " + name_tag)
		get_tree().quit(1)
