extends RefCounted
## Independent coordinate axes, real alpha holes, fast sweep, window clipping and exact hurtbox geometry.
const Sweep = preload("res://core/melee_contact_sweep.gd")

static func run(suite: TestSuite) -> void:
	var tree := suite.runner.get_tree()
	await _check_nonfinite_contact(suite, tree)
	var box := Hurtbox.new()
	box.setup(Combat.Team.ENEMY, null, Vector2(2, 2))
	tree.root.add_child(box)
	for xf: Transform2D in [Transform2D.IDENTITY, Transform2D(0.7, Vector2(4, 7)), Transform2D(Vector2(-2, 0), Vector2(0, 0.5), Vector2(12, -9))]:
		box.transform = xf
		suite.check(box.triangle_contact(xf * Vector2(-3, 0), xf * Vector2(3, 0), xf * Vector2(3, 0.1)).is_finite(), "a thin triangle crossing real hurtbox edges is detected under rotation, reflection and scale")
		suite.check(box.triangle_contact(xf * Vector2(-9, -9), xf * Vector2(9, -9), xf * Vector2(0, 9)).is_finite(), "a triangle containing the hurtbox is detected without any triangle vertex inside")
		suite.check(not box.triangle_contact(xf * Vector2(2, 2), xf * Vector2(3, 2), xf * Vector2(3, 3)).is_finite(), "separate triangles remain rejected under transformed hurtboxes")
	var definition := RigLibrary.load_json("res://data/melee/hydraulic_maul.json").duplicate(true)
	for invalid: Variant in [null, {}, [0], [0, 1, 2], [1, 1], [2, 1], [-513, 1], [0, INF], [false, 1], ["0", 1]]:
		definition["contact_span"] = invalid
		var problems := MeleeSet.definition_problems(definition, "test_contact")
		var located := false
		for problem in problems:
			located = located or problem.contains("test_contact/contact_span")
		suite.check(located, "invalid damaging spans fail closed with the exact profile/field location: " + str(invalid))
	var held := MeleeHeld.new()
	tree.root.add_child(held)
	var weapon := load("res://data/weapons/melee/melee_maul.tres") as WeaponData
	held._weapon = weapon
	held._tip = 28.0
	for canvas: Transform2D in [Transform2D.IDENTITY, Transform2D(Vector2(1.2, 0.2), Vector2(-0.1, 0.8), Vector2(23, 31)), Transform2D(Vector2(-1.15, 0), Vector2(0, 1.15), Vector2(23, 31))]:
		held.transform = canvas
		for side in [-1, 1]:
			for angle: float in [0.0, 0.7, -1.2]:
				held._origin = Vector2(111, 222)
				held._direction = Vector2(cos(angle) * side, sin(angle))
				var inverse := canvas.affine_inverse()
				var along := inverse.basis_xform(held._direction).normalized()
				var down := Vector2(-along.y, along.x) * (-1.0 if along.x < 0.0 else 1.0)
				var expected := Transform2D(along, down, inverse * held._origin)
				var shared := MeleeArt.draw_transform(inverse * held._origin, along)
				suite.check(shared == expected and held.draw_transform() == canvas * shared, "renderer and collision use identical axes, origin and canvas matrix in both directions")
				var expected_tip := (canvas * shared) * Vector2(held._tip, 0)
				suite.check(held.tip_point().is_equal_approx(expected_tip), "reported rigid tip matches the renderer's true world point including rig scale")
				if canvas != Transform2D.IDENTITY:
					suite.check(not (held._origin + held._direction * held._tip).is_equal_approx(expected_tip), "the old unscaled tip proxy is rejected under real canvas scale/reflection")
				var wrong := Transform2D(along, -down, inverse * held._origin)
				suite.check(wrong != shared, "the old inverted transverse-axis mutation is rejected")
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for y in range(1, 3):
		for x in range(1, 3):
			image.set_pixel(x, y, Color.TRANSPARENT)
	var synthetic := weapon.duplicate() as WeaponData
	synthetic.id = &"test_no_such_weapon_alpha_geometry"
	MeleeArt._art[synthetic.id] = {"texture": ImageTexture.create_from_image(image), "size": Vector2(4, 4), "grip": Vector2.ZERO}
	var sweep := Sweep.new()
	sweep.capture(synthetic, Transform2D.IDENTITY, 1, null, Transform2D.IDENTITY)
	box.transform = Transform2D(0, Vector2(2, 2))
	box.resize(Vector2(0.25, 0.25), Vector2.ZERO)
	suite.check(not sweep.contact(box).is_finite(), "actual alpha holes remain non-damaging rather than filling an outer contour")
	box.position = Vector2(0.5, 0.5)
	suite.check(sweep.contact(box).is_finite(), "actual opaque source pixels contact the hurtbox")
	sweep.capture(synthetic, Transform2D(0, Vector2(10, 0)), 1, null, Transform2D.IDENTITY)
	box.position = Vector2(6, 0.5)
	suite.check(not sweep.contact(box, 0, 0).is_finite() and not sweep.contact(box, 1, 1).is_finite(), "fast-sweep control has neither endpoint overlapping the target")
	suite.check(sweep.contact(box, 0, 1).is_finite(), "the actual previous-to-current weapon surface catches a thin target between endpoints")
	suite.check(not sweep.contact(box, 0.9, 1).is_finite(), "contact outside the authored window fraction is rejected")
	# Clear alpha history when the facing changes, rather than sweeping through the actor on a flip.
	sweep.capture(synthetic, Transform2D(0, Vector2(20, 0)), -1, null, Transform2D.IDENTITY)
	box.position = Vector2(16, 0.5)
	suite.check(not sweep.contact(box).is_finite(), "a facing change invalidates the old surface instead of creating a phantom cross-body hit")
	var head := Sweep.new()
	head.capture(weapon, Transform2D.IDENTITY, 1, null, Transform2D.IDENTITY, Vector2(20.5, 28))
	box.position = Vector2(5, 0)
	suite.check(not head.contact(box).is_finite(), "a hammer's non-damaging shaft cannot substitute for head contact")
	box.position = Vector2(24, 0)
	suite.check(head.contact(box).is_finite(), "the declared hammer head still has its actual opaque contact surface")
	MeleeArt._art.erase(synthetic.id)
	held.queue_free()
	box.queue_free()
	await tree.process_frame


## Geometry-only zero-transform controls avoid CollisionObject2D's separate setter diagnostics.
static func _check_nonfinite_contact(suite: TestSuite, tree: SceneTree) -> void:
	var box := Hurtbox.new()
	box.setup(Combat.Team.ENEMY, null, Vector2(2, 2))
	tree.root.add_child(box)
	var holder := Node2D.new()
	tree.root.add_child(holder)
	box._shape_node.reparent(holder, false)
	for bad: Vector2 in [Vector2(INF, 0), Vector2(-INF, 0), Vector2(NAN, 0), Vector2(0, NAN)]:
		for vertex in 3:
			var points := [Vector2.ZERO, Vector2(3, 0), Vector2(3, 0.1)]
			points[vertex] = bad
			suite.check(not box.triangle_contact(points[0], points[1], points[2]).is_finite(), "non-finite world triangle vertex %d %s cannot nominate a finite contact" % [vertex, bad])
	for xf: Transform2D in [Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2(7, 9)), Transform2D(Vector2(1, 2), Vector2(2, 4), Vector2(7, 9))]:
		box._shape_node.transform = xf
		suite.check(not box.triangle_contact(Vector2(7, 9), Vector2(10, 9), Vector2(10, 9.1)).is_finite(), "an exactly singular hurtbox transform fails closed before affine inversion")
	for xf: Transform2D in [Transform2D(Vector2(-2, 0), Vector2(0, 0.5), Vector2(12, -9)), Transform2D(Vector2(0.00001, 0), Vector2(0, 0.00001), Vector2.ZERO)]:
		box._shape_node.transform = xf
		suite.check(box.triangle_contact(xf * Vector2(-3, 0), xf * Vector2(3, 0), xf * Vector2(3, 0.1)).is_finite(), "finite reflection and small nonzero determinants remain valid without an arbitrary epsilon cutoff")
	box._shape_node.transform = Transform2D(Vector2(0.00000000000000000001, 0), Vector2(0, 100000000000000000000.0), Vector2.ZERO)
	suite.check(not box.triangle_contact(Vector2(100000000000000000000.0, 0), Vector2.ZERO, Vector2(1, 1)).is_finite(), "finite inputs that overflow after box-local conversion cannot nominate a finite contact")
	box._shape_node.transform = Transform2D.IDENTITY
	for invalid_size: Vector2 in [Vector2(INF, INF), Vector2(NAN, NAN)]:
		box.resize(invalid_size, Vector2.ZERO)
		suite.check(not box.triangle_contact(Vector2(100, 100), Vector2(101, 100), Vector2(100, 101)).is_finite(), "a non-finite rectangle size cannot turn a distant normal triangle into a contact")
	box.resize(Vector2.ZERO, Vector2.ZERO)
	suite.check(box.triangle_contact(Vector2(-3, 0), Vector2(3, 0), Vector2(3, 0.1)).is_finite(), "a finite zero-size rectangle retains its existing point-contact semantics")
	box.queue_free()
	holder.queue_free()
	await tree.process_frame
