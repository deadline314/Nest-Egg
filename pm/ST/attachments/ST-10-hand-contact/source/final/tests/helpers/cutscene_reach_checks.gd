extends RefCounted

static func run(s: TestSuite) -> void:
	var good := {"do": "reach", "id": "rin", "hand": "front", "to": [100, 120], "time": 0.35}
	s.check(CutsceneReach.problem(good).is_empty(), "reach accepts a finite stage point")
	for edit: Dictionary in [{"hand": "third"}, {"hand": 1}, {"space": "screen"}, {"space": []}, {"to": null}, {"to": [1]}, {"to": [NAN, 2]}, {"to": [1, INF]}, {"to": [9000, 0]}, {"to": ["1", 2]}, {"time": "fast"}, {"time": NAN}, {"time": -1}, {"time": 6}, {"angle": INF}, {"angle": []}, {"wait": "yes"}, {"release": 1}]:
		var invalid := good.merged(edit, true)
		s.check(not CutsceneReach.problem(invalid).is_empty(), "reach rejects damaged field %s" % str(edit))
	var scene := {"mode": "animated", "steps": [{"do": "scene", "id": "test_room"}, good]}
	s.check(not CutsceneChecker.validate("test_bad_cutscene_reach_missing_actor", scene, {}).is_empty(), "reach requires a previously defined actor")
	s.check(CutsceneReach.problem({"hand": "back", "release": true}).is_empty(), "release needs no unused target")
	s.check(is_equal_approx(CutsceneChecker.estimate_seconds({"steps": [good]}), 0.35), "blocking reach contributes its actual default-wait duration to the story budget")

	var stage := Node2D.new()
	stage.position = Vector2(170, 95)
	stage.rotation = 0.17
	s.runner.add_child(stage)
	for kind: String in ["rin", "old_k"]:
		for facing: int in [-1, 1]:
			for pose: StringName in [&"idle", &"sit"]:
				var actor := CutsceneActor.new()
				stage.add_child(actor)
				actor.setup(&"contact_test", kind, "", 3.9 if kind == "rin" else 4.0, "")
				actor.position = Vector2(230, 304)
				actor.face(facing)
				actor.set_pose(pose)
				actor.set_process(false)
				for frame in 120:
					actor._process(1.0 / 60.0)
				var rig := actor.rig
				for hand: StringName in [&"front", &"back"]:
					var chain: Array = HumanoidAnimator.ARM_CHAINS[0 if hand == &"front" else 1]
					var shoulder := rig.bone(chain[0])
					var elbow := rig.bone(chain[1])
					var wrist := rig.bone(chain[2])
					var upper_length := shoulder.global_position.distance_to(elbow.global_position)
					var lower_length := elbow.global_position.distance_to(wrist.global_position)
					var skeleton := shoulder.get_parent()
					while not skeleton is Skeleton2D:
						skeleton = skeleton.get_parent()
					var local_shoulder := (skeleton as Node2D).to_local(shoulder.global_position)
					var local_target := local_shoulder + Vector2(0.65, 0.35) * (rig.rest(chain[1]).length() + rig.rest(chain[2]).length())
					var target := (skeleton as Node2D).to_global(local_target)
					var label := "%s facing %d %s %s" % [kind, facing, pose, hand]
					s.check(rig.place_hand(hand, target, 0.6), label + " reachable hand is accepted")
					s.check(wrist.global_position.distance_to(target) < 0.01, label + " actual rendered wrist reaches the world target after actor scale mirror and stage rotation")
					s.check(absf(wrapf(wrist.global_transform.x.angle() - 0.6, -PI, PI)) < 0.001, label + " hand direction is a world angle even when the actor is mirrored")
					s.check(absf(shoulder.global_position.distance_to(elbow.global_position) - upper_length) < 0.01 and absf(elbow.global_position.distance_to(wrist.global_position) - lower_length) < 0.01, label + " keeps both bone lengths")
					var before := Vector3(shoulder.rotation, elbow.rotation, wrist.rotation)
					s.check(not rig.place_hand(hand, target + Vector2(5000, 0), 0.0) and before == Vector3(shoulder.rotation, elbow.rotation, wrist.rotation), label + " unreachable target preserves the whole original chain")
					s.check(not rig.place_hand(hand, Vector2(INF, 0), 0.0), label + " rejects nonfinite input before touching transforms")
					var stage_target := stage.to_local(target)
					var command := {"hand": String(hand), "to": [stage_target.x, stage_target.y], "time": 0.35}
					s.check(actor.set_hand_target(command), label + " configures persistent stage contact")
					actor._process(0.175)
					var slot: CutsceneReach = actor._reaches[0 if hand == &"front" else 1]
					s.check(is_equal_approx(slot.weight, 0.5), label + " approach blends halfway rather than snapping")
					actor._process(0.175)
					s.check(wrist.global_position.distance_to(target) < 0.01, label + " actor applies contact after its normal breathing and posture animation")
					var moved_target := stage_target + Vector2(2, -2)
					actor.set_hand_target({"hand": String(hand), "to": [moved_target.x, moved_target.y], "time": 0.35})
					s.check(slot.target.distance_to(stage_target) < 0.01, label + " replacing a held target starts from its current point")
					actor._process(0.175)
					s.check(wrist.global_position.distance_to(stage.to_global(stage_target.lerp(moved_target, 0.5))) < 0.01, label + " retargeting follows an eased path without releasing the hand")
					actor._process(0.175)
					var relative := moved_target - actor.position
					actor.set_hand_target({"hand": String(hand), "space": "actor", "to": [relative.x, relative.y], "time": 0.35})
					actor._process(0.35)
					actor.position += Vector2(20, 0)
					actor._process(1.0 / 60.0)
					s.check(wrist.global_position.distance_to(stage.to_global(moved_target + Vector2(20, 0))) < 0.01, label + " actor-space contact follows translation using stage units")
					var previous_target := slot.target
					s.check(not actor.set_hand_target({"hand": String(hand), "to": [NAN, 0]}) and slot.target == previous_target and slot.weight == 1.0, label + " damaged replacement preserves the current contact")
					actor.set_hand_target({"hand": String(hand), "space": "actor", "to": [relative.x + 4, relative.y - 4], "time": 0.35})
					actor._process(0.175)
					var release_point := slot.target
					actor.set_hand_target({"hand": String(hand), "release": true, "time": 0.35})
					actor._process(0.175)
					s.check(slot.target == release_point, label + " releasing halfway through a retarget freezes that current point while the arm returns")
					s.check(is_equal_approx(slot.weight, 0.5), label + " releasing preserves its previous coordinate space while fading out")
					actor._process(0.175)
					s.check(slot.weight == 0.0 and wrist.global_position.distance_to(stage.to_global(moved_target + Vector2(20, 0))) > 1.0, label + " release returns control to the original animation")
				var saved_scale := rig.scale
				rig.scale = Vector2.ZERO
				s.check(not rig.place_hand(&"front", Vector2.ZERO, 0.0), "%s rejects a singular world transform before affine inversion" % kind)
				rig.scale = saved_scale
				s.check(not rig.place_hand(&"third", Vector2.ZERO, 0.0) and not rig.place_hand(&"front", Vector2.ZERO, 0.0, NAN), "%s rejects an unknown chain and a nonfinite blend weight" % kind)
				actor.free()
	stage.free()
