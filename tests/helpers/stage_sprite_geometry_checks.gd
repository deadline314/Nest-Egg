extends RefCounted

static func run(s: TestSuite) -> void:
	const TEX := "res://art/environment/scene_props/pawnshop_kitchen/pawnshop_kitchen__kettle_stove.png"
	var native := RigLibrary.texture_size(TEX)
	var def := {"kind": "sprite", "path": TEX, "pos": [130, 170], "source_width": native.x * 2.0, "scale": 0.25,
		"region": [native.x * 0.25, native.y * 0.25, native.x, native.y], "pivot": [native.x * 0.5, native.y * 0.5],
		"id": "geometry_fixture", "states": {"same": {"path": TEX}}}
	s.check(StageSpriteGeometry.problem(def).is_empty(), "atlas accepts source-pixel region and a pivot within that region")
	for edit: Dictionary in [
		{"region": null}, {"region": [0, 0, 1]}, {"region": [0, 0, -1, 5]}, {"region": [-1, 0, 5, 5]},
		{"region": [0, 0, INF, 5]}, {"region": [0, 0, "5", 5]}, {"region": [0, 0, native.x * 3, 5]},
		{"pivot": [NAN, 0]}, {"pivot": [0]}, {"pivot": [-1, 0]}, {"pivot": [native.x + 1, 0]},
		{"source_width": "wide"}, {"source_width": 0}, {"source_width": INF}, {"centered": true}, {"kind": "poly"}
	]:
		s.check(not StageSpriteGeometry.problem(def.merged(edit, true)).is_empty(), "atlas rejects malformed geometry %s" % str(edit))
	var sprite := StageLayers.create(def, "geometry fixture") as StageLayers._Sprite
	if sprite == null:
		s.check(false, "valid atlas creates an actual stage sprite")
		return
	s.check(sprite.region_enabled and sprite.region_filter_clip_enabled, "stage sprite clips atlas filtering to the selected part")
	var size := sprite.region_rect.size * sprite.scale
	s.check(size.distance_to(native * 0.25) < 0.01, "selected part keeps its authored stage size after import resolution compensation")
	var pivot := native * 0.75
	s.check(sprite.source_point(pivot).length() < 0.001, "source pivot maps exactly to the sprite's rotation origin")
	var glow := sprite._glow_sprite
	s.check(glow != null and (glow.region_rect.size * glow.scale).distance_to(sprite.region_rect.size) < 0.01 and (glow.offset * glow.scale).distance_to(sprite.offset) < 0.01, "emissive overlay keeps the same physical atlas region and pivot")
	var original_texture := sprite.texture
	s.check(sprite.set_prop_state("same") and sprite.texture == original_texture and sprite.source_point(pivot).length() < 0.001, "texture-state selection preserves atlas geometry and reuses the cached texture")
	s.check(not sprite.source_point(Vector2(-1, 0)).is_finite(), "source contact point outside the selected part is rejected")
	sprite.free()

	# Independent 2:1 import-resolution pair: equal physical geometry, source point and rotated pivot.
	var world_points: Array[Vector2] = []
	for resolution: Vector2i in [Vector2i(32, 24), Vector2i(16, 12)]:
		var image := Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var part := Sprite2D.new()
		part.texture = ImageTexture.create_from_image(image)
		part.centered = false
		part.region_enabled = true
		part.position = Vector2(30, 80)
		part.rotation = 0.3
		part.scale = Vector2.ONE * (0.5 * 64.0 / resolution.x)
		var frame := Rect2(8, 8, 32, 24)
		var contact := Vector2(24, 18)
		StageSpriteGeometry.apply(part, 64.0, frame, Vector2(8, 20))
		var local := StageSpriteGeometry.source_point(part, contact, 64.0, frame)
		var actual := part.transform * local
		var expected := Transform2D(0.3, Vector2(30, 80)) * ((contact - frame.position - Vector2(8, 20)) * 0.5)
		s.check(actual.distance_to(expected) < 0.001, "actual imported resolution %s keeps the independently calculated rotated source contact" % resolution)
		world_points.append(actual)
		part.free()
	s.check(world_points[0].distance_to(world_points[1]) < 0.001, "halving the texture cannot move a prop's physical grip point")
