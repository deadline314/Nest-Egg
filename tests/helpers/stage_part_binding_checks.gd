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
