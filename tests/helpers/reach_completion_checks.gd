extends RefCounted
## The real actor publishes its hand pose on a different clock from the caller.

class SlowActor extends CutsceneActor:
	func _process(_delta: float) -> void:
		super._process(1.0 / 240.0)


static func _fixture(s: TestSuite) -> Dictionary:
	var player := CutscenePlayer.new()
	s.runner.add_child(player)
	player._root = Control.new()
	player.add_child(player._root)
	player._running = true
	player.scene_id = &"test_ne287_contact"
	player._stage = StageLibrary.Stage.new()
	player.add_child(player._stage)
	var actor := SlowActor.new()
	s.check(actor.setup(&"visitor", "old_k", "", 1.0, ""), "contact completion fixture builds a real unarmed actor")
	player._stage.actors.add_child(actor)
	actor.position = Vector2(100, 180)
	actor.ground_y = 180
	for frame in 180:
		actor._process(1.0 / 240.0)
	player._actors[&"visitor"] = actor
	var point := player._stage.actors.to_local(actor.hand_contact_global(&"front"))
	return {"player": player, "actor": actor, "point": point + Vector2(2, -2)}


static func _step(point: Vector2, duration := 0.04, wait := true) -> Dictionary:
	return {"do": "reach", "id": "visitor", "hand": "front", "space": "stage",
		"to": [point.x, point.y], "time": duration, "wait": wait}


static func _start(player: CutscenePlayer, step: Dictionary, done: Array[bool]) -> void:
	await player._do_reach(step)
	done[0] = true


static func _wait(s: TestSuite, done: Array[bool], frames := 90) -> void:
	for frame in frames:
		if done[0]:
			return
		await s.runner.get_tree().process_frame


static func run(s: TestSuite) -> void:
	for duration: float in [0.0, 0.04]:
		var fixture := _fixture(s)
		var player: CutscenePlayer = fixture.player
		var actor: CutsceneActor = fixture.actor
		var done: Array[bool] = [false]
		_start(player, _step(fixture.point, duration), done)
		s.check(not done[0] and not actor.hand_target_complete(&"front"), "waiting reach cannot complete before its pose is consumed: %s" % duration)
		var reach: CutsceneReach = actor._reaches[0]
		var before := [reach._elapsed, reach.weight, reach.target, reach._published]
		for query in 12:
			actor.hand_target_complete(&"front")
		s.check(before == [reach._elapsed, reach.weight, reach.target, reach._published], "contact completion reads do not advance animation")
		await _wait(s, done)
		var palm := player._stage.actors.to_local(actor.hand_contact_global(&"front"))
		s.check(done[0] and actor.hand_target_complete(&"front") and palm.distance_to(fixture.point) < .08, "waiting reach returns only after actual IK reaches its endpoint: %s" % duration)
		done[0] = false
		_start(player, {"do": "reach", "id": "visitor", "hand": "front", "release": true, "time": 0.04}, done)
		s.check(not done[0], "release waits for the original animation to reclaim the hand")
		await _wait(s, done)
		s.check(done[0] and actor.hand_target_complete(&"front") and not actor.hand_targets_active(), "completed release leaves no active hand target")
		player.free()
		await s.frames(1)
	var fixture := _fixture(s)
	var player: CutscenePlayer = fixture.player
	var actor: CutsceneActor = fixture.actor
	var done: Array[bool] = [false]
	_start(player, _step(fixture.point, 0.04, false), done)
	s.check(done[0] and not actor.hand_target_complete(&"front"), "wait=false remains asynchronous while the real pose is still pending")
	player.free()
	await s.frames(1)
	# Exercise the real dispatcher result tail, not only a detached coroutine.
	for interruption: String in ["none", "skip", "cancel", "dead", "free", "replace", "exit", "disable", "rig_removed", "player_free"]:
		fixture = _fixture(s)
		player = fixture.player
		actor = fixture.actor
		var tail: Array[bool] = [false]
		var completed: Array[bool] = [false]
		player._steps = [_step(fixture.point), {"do": "test_ne287_tail"}]
		player._handlers["test_ne287_tail"] = func(_data: Dictionary) -> void: tail[0] = true
		player.finished.connect(func(_id: StringName) -> void: completed[0] = true)
		player._run()
		match interruption:
			"skip": player.skip()
			"cancel": player.cancel()
			"dead": actor.set_pose(&"dead")
			"free": actor.queue_free()
			"replace": player._actors.erase(&"visitor")
			"exit": s.runner.remove_child(player)
			"disable": actor.set_process(false)
			"rig_removed":
				actor.rig.free()
				actor.rig = null
			"player_free": player.queue_free()
		for frame in 90:
			if not is_instance_valid(player) or not player._running:
				break
			await s.runner.get_tree().process_frame
		s.check(tail[0] == (interruption == "none"), "%s cannot execute an interrupted contact's result tail" % interruption)
		s.check(completed[0] == (interruption in ["none", "skip"]), "%s contact preserves complete/skip/cancel semantics" % interruption)
		if is_instance_valid(player):
			player.free()
		await s.frames(1)
