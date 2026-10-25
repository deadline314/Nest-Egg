extends RefCounted

static func run(s: TestSuite) -> void:
	const TEX := "res://art/environment/props/trash_can.png"
	var native := RigLibrary.texture_size(TEX)
	RigLibrary.optional_texture(TEX)  # 快取預熱；不把首次載入當作持物洩漏。
	var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for kind: String in ["rin", "old_k"]:
		for facing: int in [-1, 1]:
			for hand: StringName in [&"front", &"back"]:
				var stage := StageLibrary.Stage.new()
				s.runner.add_child(stage)
				stage.position = Vector2(40, 70)
				stage.rotation = 0.11
				stage.scale = Vector2.ONE * 1.3
				var def := {"kind": "sprite", "id": "held_fixture", "path": TEX, "pos": [0, 0], "source_width": native.x, "scale": 0.2}
				var sprite := StageLayers.create(def, "hold fixture") as StageLayers._Sprite
				stage.add_layer(sprite)
				sprite.rotation = 0.12
				var actor := CutsceneActor.new()
				stage.actors.add_child(actor)
				actor.setup(&"hold_test", kind, "", 3.9 if kind == "rin" else 4.0, "")
				actor.position = Vector2(160, 304)
				actor.layer_slot = 1
				actor.z_index = WorldLayers.stage_actor_z(1)
				actor.face(facing)
				actor.set_process(false)
				for frame in 120:
					actor._process(1.0 / 60.0)
				var source := native * Vector2(0.5, 0.2)
				sprite.position = Vector2(160, 154) - sprite.transform.basis_xform(sprite.source_point(source))
				var raw_contact := Vector2(64, 39) if kind == "old_k" else (Vector2(73, 40) if hand == &"front" else Vector2(92, 38))
				var command := {"hand": String(hand), "space": "prop", "prop": "held_fixture", "to": [source.x, source.y], "contact": [raw_contact.x, raw_contact.y], "angle": PI * 0.5, "time": 0.1}
				var binding := StagePropBinding.new(sprite, source)
				var label := "%s/%d/%s" % [kind, facing, hand]
				s.check(actor.set_hand_target(command, binding), label + " starts calibrated prop contact")
				actor._process(0.1)
				var contact_position := sprite.position
				sprite.position += Vector2(8, 0)
				s.check(not stage.hold_prop("held_fixture", actor, hand, source).is_empty() and sprite.position == contact_position + Vector2(8, 0), label + " distant prop cannot teleport into the hand")
				sprite.position = contact_position
				var instance := sprite.get_instance_id()
				var parent := sprite.get_parent()
				var original_z := sprite.z_index
				var original_relative := sprite.z_as_relative
				var original_width := sprite.texture.get_width() * (stage.global_transform.affine_inverse() * sprite.global_transform).x.length()
				s.check(stage.hold_prop("held_fixture", actor, hand, source).is_empty(), label + " actual touching prop can be held")
				s.check(stage.prop_held("held_fixture") and sprite.get_instance_id() == instance and sprite.get_parent() == parent, label + " holds the identical stage node without reparenting or cloning")
				s.check(not stage.hold_prop("held_fixture", actor, hand, source).is_empty(), label + " rejects duplicate ownership of one prop")
				for frame in 8:
					actor.position.x = 160.0 + frame * 8.0
					actor.face(facing if frame % 2 == 0 else -facing)
					stage.position += Vector2(2, -1)
					stage.rotation += 0.03
					stage.scale = Vector2.ONE * (1.3 + frame * 0.02)
					if frame == 3:
						var image := Image.create(maxi(1, sprite.texture.get_width() / 2), maxi(1, sprite.texture.get_height() / 2), false, Image.FORMAT_RGBA8)
						image.fill(Color.WHITE)
						sprite.texture = ImageTexture.create_from_image(image)
					actor._process(1.0 / 60.0)
					stage._process(1.0 / 60.0)
					var palm := actor.hand_contact_global(hand)
					var physical_prop := sprite.to_global(sprite.source_point(source))
					var transform := stage.global_transform.affine_inverse() * sprite.global_transform
					s.check(palm.distance_to(physical_prop) < 0.02, label + " physical grip follows translation turn and camera at frame %d" % frame)
					s.check(transform.determinant() > 0.0 and absf(wrapf(transform.x.angle() - 0.12, -PI, PI)) < 0.001, label + " actor mirror cannot invert or turn the held prop")
					s.check(absf(sprite.texture.get_width() * transform.x.length() - original_width) < 0.01, label + " texture resolution change preserves authored prop width")
				s.check(stage.release_prop("held_fixture") and not stage.prop_held("held_fixture") and not stage.is_processing(), label + " release removes the binding and disables idle hold work")
				s.check(sprite.z_index == original_z and sprite.z_as_relative == original_relative, label + " release restores its original layer rules")
				var released_position := sprite.position
				actor.position.x += 30
				actor._process(1.0 / 60.0)
				stage._process(1.0 / 60.0)
				s.check(sprite.position.distance_to(released_position) < 0.01, label + " released object stays on stage when actor walks away")
				actor.set_hand_target(command, StagePropBinding.new(sprite, source))
				actor._process(0.1)
				s.check(stage.hold_prop("held_fixture", actor, hand, source).is_empty(), label + " same object can be picked up again after a real new contact")
				actor.free()
				stage._process(1.0 / 60.0)
				s.check(not stage.prop_held("held_fixture") and not stage.is_processing() and sprite.z_as_relative == original_relative, label + " disappearing actor safely releases weak hold ownership")
				stage.free()
	s.check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == initial_nodes, "repeated hold move mirror resize release and owner destruction retain no scene nodes")
