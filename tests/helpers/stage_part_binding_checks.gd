extends RefCounted
## Actor-part contacts use registered visible source art and weak ownership.

static func run(s: TestSuite) -> void:
	var command := {"hand": "front", "space": "part", "target_actor": "rin", "part": "head", "to": [152, 145], "offset": [9, 3], "grip": true}
	s.check(CutsceneReach.problem(command).is_empty(), "named actor-part source contact accepts a finite stage offset")
	for edit: Dictionary in [{"target_actor": "../head"}, {"part": "head/child"}, {"part": 1}, {"offset": [NAN, 0]}, {"offset": [0, INF]}, {"offset": [0, 8193]}, {"offset": ["9", 3]}, {"offset": [1]}, {"space": "stage"}]:
		s.check(not CutsceneReach.problem(command.merged(edit, true)).is_empty(), "actor-part target rejects malformed paths or offset: " + str(edit))
	var skins: Dictionary[String, String] = {"rin": "rin"}
	s.check(CutsceneChecker._check_reach_part("part fixture", skins, command).is_empty(), "content checker resolves registered head source geometry")
	for edit: Dictionary in [{"target_actor": "absent"}, {"part": "absent"}, {"to": [-1, 145]}, {"to": [152, 9999]}]:
		s.check(not CutsceneChecker._check_reach_part("part fixture", skins, command.merged(edit, true)).is_empty(), "content checker rejects unavailable actor/part or off-image source point")
	var stage := Node2D.new()
	s.runner.add_child(stage)
	var actor := CutsceneActor.new()
	stage.add_child(actor)
	actor.setup(&"rin", "rin", "", 1.7, "")
	actor.set_process(false)
	actor.position = Vector2(120, 300)
	actor._process(1.0 / 60.0)
	var head := actor.rig.contact_part(&"head")
	s.check(head != null and actor.rig.contact_part(&"absent") == null, "runtime resolves only registered visible sprite parts")
	var point := CharacterRig.part_source_point(head, Vector2(152, 145))
	var offset := Vector2(9, 3)
	var binding := StagePropBinding.new(head, point, offset)
	for facing: int in [-1, 1]:
		actor.face(facing)
		for frame in 12:
			stage.rotation = .03 * frame
			stage.scale = Vector2(1.1, .95)
			actor._process(1.0 / 30.0)
			var expected := stage.to_local(head.to_global(point)) + offset
			s.check(binding.stage_point(stage).distance_to(expected) < .001, "part binding follows actual head breathing, facing and stage transform")
		s.check(actor.set_hand_target(command, binding), "named part binds without taking weapon ownership")
	var previous := actor._reaches[0].target
	s.check(not actor.set_hand_target(command) and actor._reaches[0].target == previous, "missing runtime binding preserves the prior contact")
	s.check(not CharacterRig.part_source_point(head, Vector2(-1, 0)).is_finite(), "runtime rejects source coordinates outside visible art")
	var invalid := StagePropBinding.new(head, point, Vector2(INF, 0))
	s.check(not invalid.stage_point(stage).is_finite(), "invalid direct binding offset cannot enter animation matrices")
	var duplicate := Sprite2D.new()
	duplicate.name = &"head"
	actor.add_child(duplicate)
	# Godot uniquifies sibling names; a different registered owner may still
	# expose an ambiguous slot and must fail rather than guessing.
	duplicate.name = &"contact_duplicate"
	head.name = &"contact_duplicate"
	actor.rig._parts.append(duplicate)
	s.check(actor.rig.contact_part(&"contact_duplicate") == null, "ambiguous visible part rejects contact")
	actor.rig._parts.erase(duplicate)
	duplicate.free()
	head.queue_free()
	s.check(not binding.stage_point(stage).is_finite(), "queued target is unavailable before deallocation")
	stage.free()
	s.check(not binding.stage_point(null).is_finite(), "weak actor-part target cannot extend its deleted scene lifetime")
	_mesh_contacts(s)


static func _mesh_contacts(s: TestSuite) -> void:
	var stage := Node2D.new()
	s.runner.add_child(stage)
	var rig := CharacterRig.new()
	stage.add_child(rig)
	var mesh := RigPartMesh.new()
	mesh.name = &"contact_body"
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.gradient = Gradient.new()
	mesh.texture = texture
	mesh.uv = PackedVector2Array([Vector2.ZERO, Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)])
	mesh.polygons = [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3])]
	mesh._deformed = mesh.uv.duplicate()
	mesh.polygon = mesh._deformed
	rig.add_child(mesh)
	rig._parts.append(mesh)
	s.check(rig.contact_part(&"contact_body") == null and rig.contact_surface(&"contact_body") == mesh, "mesh contact extends the surface interface without changing the original Sprite return type")
	var binding := StagePropBinding.mesh_part(mesh, Vector2(16, 32), Vector2(3, 4))
	for frame in 20:
		var bend := float(frame) * .5
		mesh._deformed = PackedVector2Array([Vector2.ZERO, Vector2(64, 0), Vector2(64 + bend, 64 + bend * 2), Vector2(-bend, 64)])
		stage.rotation = frame * .01
		stage.scale = Vector2(1.1, .9)
		rig.scale.x = -1.3 if frame % 2 else 1.3
		mesh.position = Vector2(12, -25)
		var expected := stage.to_local(mesh.to_global(mesh._deformed[0] * .5 + mesh._deformed[2] * .25 + mesh._deformed[3] * .25)) + Vector2(3, 4)
		s.check(binding.stage_point(stage).distance_to(expected) < .0001, "cached source triangle follows genuine deformation and mirrored stage transforms: %d" % frame)
	s.check(binding._mesh_triangle == 1 and binding._mesh_indices == PackedInt32Array([0, 2, 3]), "binding resolves the containing source triangle once")
	# 已知仿射F(u,v)=(2u+.25v,.5u+1.5v)，UV-x切線解析值為(2,.5)。
	mesh._deformed=PackedVector2Array([Vector2.ZERO,Vector2(128,32),Vector2(144,128),Vector2(16,96)])
	mesh.rotation=.27
	for mirror in [-1.0,1.0]:
		stage.rotation=.41
		stage.scale=Vector2(1.3,.8)
		rig.scale=Vector2(mirror*1.2,.9)
		var exact:=stage.global_transform.affine_inverse().basis_xform(mesh.global_transform.basis_xform(Vector2(2,.5)))
		s.check(absf(angle_difference(binding.stage_angle(stage),exact.angle()))<.00001,"網格UV-x切線符合仿射/鏡像/旋轉舞台解析方向")
	var old_texture:=mesh.texture
	mesh.texture=GradientTexture2D.new()
	s.check(is_nan(binding.stage_angle(stage)),"替換來源貼圖時方向綁定拒收")
	mesh.texture=old_texture
	mesh._deformed=PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2(16,96),Vector2(16,96)])
	s.check(is_nan(binding.stage_angle(stage)),"退化至零UV-x切線時回傳NaN而非任意方向")
	mesh._deformed=PackedVector2Array([Vector2.ZERO,Vector2(64,0),Vector2(64,64),Vector2(0,64)])
	for source: Vector2 in [Vector2(-1, 2), Vector2(65, 2), Vector2(2, 65), Vector2(NAN, 2), Vector2(2, INF)]:
		s.check(not StagePropBinding.mesh_part(mesh, source).stage_point(stage).is_finite(), "mesh source rejects nonfinite and off-canvas coordinates")
	mesh.visible = false
	s.check(rig.contact_surface(&"contact_body") == null and not binding.stage_point(stage).is_finite(), "hidden mesh cannot remain an active contact")
	mesh.visible = true
	var original_uv := mesh.uv
	mesh.uv = PackedVector2Array([Vector2.ZERO, Vector2(64, 0), Vector2(63, 64), Vector2(0, 64)])
	s.check(not binding.stage_point(stage).is_finite(), "changed cached triangle UV cannot silently reuse stale barycentric weights")
	mesh.uv = original_uv
	var original_polygons := mesh.polygons
	mesh.polygons = []
	s.check(not binding.stage_point(stage).is_finite() and not StagePropBinding.mesh_part(mesh, Vector2(16, 32)).stage_point(stage).is_finite(), "missing mesh triangles reject existing and new bindings")
	mesh.polygons = original_polygons
	var original_vertices := mesh._deformed
	mesh._deformed = PackedVector2Array([Vector2.ZERO, Vector2(64, 0), Vector2(INF, 64), Vector2(0, 64)])
	s.check(not binding.stage_point(stage).is_finite(), "nonfinite deformed vertices never reach actor matrices")
	mesh._deformed = original_vertices
	var duplicate_owner := Node2D.new()
	rig.add_child(duplicate_owner)
	var duplicate := Sprite2D.new()
	duplicate.name = &"contact_body"
	duplicate_owner.add_child(duplicate)
	rig._parts.append(duplicate)
	s.check(rig.contact_surface(&"contact_body") == null, "mixed Sprite and mesh duplicate names reject contact instead of guessing")
	rig._parts.erase(duplicate)
	duplicate_owner.free()
	mesh.queue_free()
	s.check(not binding.stage_point(stage).is_finite(), "queued mesh releases its weak contact before deallocation")
	stage.free()
	s.check(not binding.stage_point(null).is_finite(), "deleted mesh binding cannot prolong scene ownership")
