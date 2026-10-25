extends RefCounted

static func run(s: TestSuite) -> void:
	var stage := Node2D.new()
	stage.position = Vector2(60, 35)
	stage.rotation = 0.17
	s.runner.add_child(stage)
	for kind: String in ["rin", "old_k"]:
		for facing: int in [-1, 1]:
			for hand: StringName in [&"front", &"back"]:
				var actor := CutsceneActor.new()
				stage.add_child(actor)
				actor.setup(&"binding_test", kind, "", 3.9 if kind == "rin" else 4.0, "")
				actor.position = Vector2(160, 304)
				actor.face(facing)
				actor.set_process(false)
				for frame in 120:
					actor._process(1.0 / 60.0)
				var rig := actor.rig
				var chain: Array = HumanoidAnimator.ARM_CHAINS[0 if hand == &"front" else 1]
				var shoulder := rig.bone(chain[0])
				var elbow := rig.bone(chain[1])
				var wrist := rig.bone(chain[2])
				var lengths := Vector2(shoulder.global_position.distance_to(elbow.global_position), elbow.global_position.distance_to(wrist.global_position))
				var skeleton := rig.get_node("Skeleton") as Node2D
				var shoulder_local := skeleton.to_local(shoulder.global_position)
				var reach := rig.rest(chain[1]).length() + rig.rest(chain[2]).length()
				var target := stage.to_local(skeleton.to_global(shoulder_local + Vector2(0.5, 0.4) * reach))
				var prop := Node2D.new()
				stage.add_child(prop)
				var prop_point := Vector2(4, 0)
				prop.position = target - prop_point
				var origin := prop.position
				var binding := StagePropBinding.new(prop, prop_point)
				var raw_contact := Vector2(64, 39) if kind == "old_k" else (Vector2(73, 40) if hand == &"front" else Vector2(92, 38))
				var contact := rig.hand_source_point(hand, raw_contact)
				var label := "%s/%d/%s" % [kind, facing, hand]
				s.check(contact.is_finite(), label + " palm source pixel belongs to a unique visible hand")
				if not contact.is_finite():
					prop.free()
					actor.free()
					continue
				var command := {"hand": String(hand), "space": "prop", "prop": "fixture", "to": [4, 0], "contact": [raw_contact.x, raw_contact.y], "angle": 0.2, "follow_rotation": true, "time": 0.1}
				s.check(actor.set_hand_target(command, binding), label + " accepts a live named-prop binding and calibrated palm source")
				actor._process(0.1)
				for frame in 9:
					prop.rotation = float(frame) / 8.0 * PI * 0.5
					prop.position = origin + Vector2(sin(frame * 0.4) * 3.0, cos(frame * 0.4) * 2.0)
					actor._process(1.0 / 60.0)
					var physical_palm := wrist.to_global(contact)
					var physical_prop := prop.to_global(prop_point)
					s.check(physical_palm.distance_to(physical_prop) < 0.02, label + " actual palm follows rotating prop arc at frame %d" % frame)
					var desired := stage.global_transform.basis_xform(Vector2.from_angle(prop.rotation + 0.2)).normalized()
					s.check(wrist.global_transform.x.normalized().dot(desired) > 0.999, label + " hand direction follows prop rotation")
					s.check(absf(shoulder.global_position.distance_to(elbow.global_position) - lengths.x) < 0.01 and absf(elbow.global_position.distance_to(wrist.global_position) - lengths.y) < 0.01, label + " prop contact keeps both physical bone lengths")
				var slot := actor._reaches[0 if hand == &"front" else 1]
				var held_target := slot.target
				s.check(not actor.set_hand_target(command.merged({"contact": [8000, 8000]}, true), binding) and slot.target == held_target, label + " out-of-hand source point preserves current contact")
				s.check(not rig.place_hand(hand, wrist.global_position, 0.0, 1.0, Vector2.INF), label + " rejects nonfinite explicit contact offset")
				prop.free()
				actor._process(0.05)
				s.check(slot._binding == null and slot._wanted == 0.0 and slot.weight < 1.0, label + " removed prop clears weak binding and starts a safe return")
				for frame in 10:
					actor._process(0.05)
				s.check(slot.weight == 0.0, label + " removed prop cannot leave the arm permanently constrained")
				actor.free()
	stage.free()

	var command := {"do": "reach", "id": "rin", "hand": "front", "space": "prop", "prop": "noodle_table", "to": [50, 50]}
	var scene := {"mode": "animated", "steps": [{"do": "scene", "id": "ch1_dawn_noodle_stall"}, {"do": "actor", "id": "rin", "kind": "rin", "pos": [300, 300]}, command]}
	s.check(CutsceneChecker.validate("test_reach_prop", scene, {}).is_empty(), "checker accepts a registered prop source point")
	scene["steps"][2] = command.merged({"prop": "missing"}, true)
	s.check(not CutsceneChecker.validate("test_bad_cutscene_reach_prop", scene, {}).is_empty(), "checker rejects a prop missing from the current stage")
	scene["steps"][2] = command.merged({"to": [8000, 1]}, true)
	s.check(not CutsceneChecker.validate("test_bad_cutscene_reach_prop", scene, {}).is_empty(), "checker rejects a source point outside a sprite's source canvas")
