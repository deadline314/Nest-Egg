extends RefCounted

static func run(s: TestSuite) -> void:
	var command := {"do": "reach", "id": "rin", "hand": "front", "to": [120, 180], "grip": true}
	s.check(CutsceneReach.problem(command).is_empty(), "explicit prop grip is accepted without weapon state")
	for edit: Dictionary in [{"grip": 1}, {"grip": "yes"}, {"contact": [30, 20]}, {"release": true}]:
		s.check(not CutsceneReach.problem(command.merged(edit, true)).is_empty(), "closed grip rejects malformed or conflicting source points: " + str(edit))
	var hold := {"do": "prop_hold", "id": "tool", "actor": "rin", "hand": "front", "point": [10, 10], "follow_rotation": true}
	s.check(CutscenePropAction.problem(hold).is_empty(), "held tool may explicitly follow actual hand rotation")
	for invalid: Variant in [1, "yes", [], null]:
		s.check(not CutscenePropAction.problem(hold.merged({"follow_rotation": invalid}, true)).is_empty(), "hold rotation flag is strictly boolean")
	const TEX := "res://art/environment/props/trash_can.png"
	var native := RigLibrary.texture_size(TEX)
	var source_grip := native * .5
	var source_tip := source_grip + Vector2(minf(10, native.x * .25), 0)
	for facing in [-1, 1]:
		for hand: StringName in [&"front", &"back"]:
			var stage := StageLibrary.Stage.new()
			s.runner.add_child(stage)
			var actor := CutsceneActor.new()
			stage.actors.add_child(actor)
			actor.setup(&"rin", "rin", "", 1.7, "")
			actor.position = Vector2(120, 300)
			actor.face(facing)
			actor.set_process(false)
			actor._process(1.0 / 60.0)
			var wrist := actor.rig.bone(&"hand_front" if hand == &"front" else &"hand_back")
			var shoulder := actor.rig.bone(&"arm_front_upper" if hand == &"front" else &"arm_back_upper")
			var goal := stage.actors.to_local(shoulder.global_position) + Vector2(facing * 15, 10)
			var step := {"hand": String(hand), "to": [goal.x, goal.y], "time": 0.0, "grip": true}
			s.check(actor.set_hand_target(step), "registered closed hand configures in both directions: %s/%d" % [hand, facing])
			actor._process(1.0 / 60.0)
			s.check(actor.rig.hand_grip_offset(wrist.name).length() > .1 and actor.rig.weapon_def().is_empty() and not actor._input.melee_grip, "generic grip uses the calibrated closed texture without weapon or melee state")
			s.check(stage.actors.to_local(actor.hand_contact_global(hand)).distance_to(goal) < .01, "closed palm reaches the actual configured point")
			var prop := StageLayers.create({"kind": "sprite", "id": "tool", "path": TEX, "pos": [0, 0], "scale": .1, "source_width": native.x}, "rotation fixture") as StageLayers._Sprite
			stage.add_layer(prop)
			prop.global_position = actor.hand_contact_global(hand) - prop.global_transform.basis_xform(prop.source_point(source_grip))
			var original := stage.global_transform.affine_inverse() * prop.global_transform
			var start_angle := stage.global_transform.affine_inverse().basis_xform(wrist.global_transform.x).angle()
			s.check(stage.hold_prop("tool", actor, hand, source_grip, true).is_empty(), "rotating hold requires and accepts an actual settled closed palm")
			var local_delta := prop.source_point(source_tip) - prop.source_point(source_grip)
			for angle: float in [-.3, -1.0, -2.8, 2.8, 3.1, -3.1, 0.0]:
				actor.set_hand_target({"hand": String(hand), "to": [goal.x, goal.y], "angle": angle, "time": 0.0})
				actor._process(1.0 / 60.0)
				stage._process(1.0 / 60.0)
				var actual_angle := stage.global_transform.affine_inverse().basis_xform(wrist.global_transform.x).angle()
				var delta := wrapf(actual_angle - start_angle, -PI, PI)
				var palm := stage.to_local(actor.hand_contact_global(hand))
				var tip := stage.to_local(prop.to_global(prop.source_point(source_tip)))
				var expected := palm + original.basis_xform(local_delta).rotated(delta)
				s.check(stage.to_local(prop.to_global(prop.source_point(source_grip))).distance_to(palm) < .001, "rotating actual tool cannot detach its grip")
				s.check(tip.distance_to(expected) < .001, "actual source tip follows the hand basis across angle wrapping")
				s.check(absf(prop.transform.determinant() - original.determinant()) < .00001, "rotation preserves prop size and winding")
			s.check(stage.release_prop("tool"), "rotating tool releases the same held node")
			actor.set_hand_target({"hand": String(hand), "release": true, "time": 0.0})
			actor._process(1.0 / 60.0)
			s.check(actor.rig.hand_grip_offset(wrist.name) == Vector2.ZERO, "finished release restores the resting hand")
			actor.set_hand_target({"hand": String(hand), "to": [goal.x, goal.y], "time": 0.0})
			actor._process(1.0 / 60.0)
			var index := 0 if hand == &"front" else 1
			var before := actor._reaches[index].target
			actor.rig._hand_grips.clear()  # Isolated missing-attachment fault, never shared character data.
			s.check(not actor.set_hand_target(step) and actor._reaches[index].target == before, "missing grip attachment rejects the new request and preserves contact")
			stage.free()
