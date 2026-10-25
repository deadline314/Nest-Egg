extends RefCounted

static func run(s: TestSuite) -> void:
	const TEX := "res://art/environment/props/trash_can.png"
	var native := RigLibrary.texture_size(TEX)
	var body_def := {"kind": "sprite", "id": "body", "path": TEX, "pos": [120, 180], "source_width": native.x * 2.0, "scale": 0.25,
		"region": [0, 0, native.x, native.y], "pivot": [native.x * 0.5, native.y * 0.8], "states": {"same": {"path": TEX}}}
	var lid_def := {"kind": "sprite", "id": "lid", "path": TEX, "pos": [0, 0], "source_width": native.x * 2.0, "scale": 0.1,
		"region": [0, 0, native.x * 0.5, native.y * 0.5], "pivot": [native.x * 0.25, native.y * 0.4], "parent_prop": "body", "anchor": [native.x * 0.4, native.y * 0.4]}
	s.check(StageLibrary._parent_problems(&"fixture", [body_def, lid_def]).is_empty(), "registered prop hierarchy validates source-space hinge")
	var stage := StageLibrary.Stage.new()
	var body := StageLayers.create(body_def, "parent fixture") as StageLayers._Sprite
	var lid := StageLayers.create(lid_def, "child fixture") as StageLayers._Sprite
	stage.add_layer(body)
	stage.add_layer(lid)
	stage.resolve_prop_parents()  # 正式 build 同樣在加入場景樹之前組裝。
	s.check(lid.get_parent() == body and lid.anchored(), "actual stage assembly attaches the existing child before entering the tree")
	s.runner.add_child(stage)
	stage.position = Vector2(40, 70)
	stage.rotation = 0.15
	stage.scale = Vector2.ONE * 1.2
	var source_anchor := native * 0.4
	var lid_pivot := Vector2(native.x * 0.25, native.y * 0.4)
	for frame in 8:
		body.position += Vector2(3, -1)
		body.rotation = frame * 0.1
		lid.rotation = frame * 0.15
		if frame == 3:
			var image := Image.create(maxi(1, body.texture.get_width() / 2), maxi(1, body.texture.get_height() / 2), false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			body._state_textures["half_fixture"] = ImageTexture.create_from_image(image)
			body._state_glows["half_fixture"] = null
			body.set_prop_state("half_fixture")
		var physical_hinge := body.to_global(body.source_point(source_anchor))
		var child_hinge := lid.to_global(lid.source_point(lid_pivot))
		var local := stage.global_transform.affine_inverse() * lid.global_transform
		s.check(physical_hinge.distance_to(child_hinge) < 0.001, "hinge stays physically joined through parent motion rotation and resolution change at frame %d" % frame)
		s.check(absf(lid.region_rect.size.x * local.x.length() - native.x * 0.05) < 0.01, "child retains its authored stage width despite its parent's import resolution")
		s.check(absf(wrapf(local.x.angle() - body.rotation - lid.rotation, -PI, PI)) < 0.001, "lid rotates around its own hinge while inheriting body rotation")
	s.check(not stage.hold_prop("lid", null, &"front", lid_pivot).is_empty() and lid.get_parent() == body, "holding an anchored part cannot tear it off its parent")
	s.check(not body.anchor_to(lid, Vector2.ZERO).is_empty() and body.get_parent() == stage.back, "runtime rejects cyclic reparenting without altering the body")
	var cycle := body_def.merged({"parent_prop": "lid", "anchor": [0, 0]}, true)
	var issues := StageLibrary._parent_problems(&"fixture", [cycle, lid_def])
	s.check("cyclic" in " ".join(issues), "content checker detects a real two-prop cycle")
	s.check(not StageLibrary._parent_problems(&"fixture", [body_def, lid_def.merged({"parent_prop": "missing"}, true)]).is_empty(), "content checker rejects missing parents")
	s.check(not StageLibrary._parent_problems(&"fixture", [body_def, lid_def.merged({"anchor": [native.x * 3.0, 0]}, true)]).is_empty(), "content checker rejects anchor points outside parent source geometry")
	var many: Array = [body_def]
	for index in 9:
		many.append(lid_def.merged({"id": "part_%d" % index}, true))
	s.check("eight" in " ".join(StageLibrary._parent_problems(&"fixture", many)), "content checker bounds prop hierarchy links")
	lid.free()
	for index in 32:
		var temporary := StageLayers.create(lid_def, "temporary child") as StageLayers._Sprite
		stage.back.add_child(temporary)
		s.check(temporary.anchor_to(body, source_anchor).is_empty() and body._anchored_children.size() == 1, "repeated assembly discards dead weak child links")
		temporary.free()
	body.set_prop_state("same")
	s.check(body._anchored_children.is_empty(), "parent texture-state refresh retains no dead child references")
	stage.free()
