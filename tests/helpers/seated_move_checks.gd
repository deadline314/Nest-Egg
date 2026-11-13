extends RefCounted
## Exercises the actual actor/animator and move dispatcher, including interruption.
class ClockActor extends CutsceneActor:
	func _process(_delta: float) -> void:
		super._process(1.0 / 60.0)

static func _fixture(s: TestSuite, script: Script, seated: bool, animator_script: Script = null) -> Dictionary:
	var p := script.new() as CutscenePlayer
	s.runner.add_child(p)
	p._root = Control.new()
	p.add_child(p._root)
	p._running = true
	var a := ClockActor.new()
	p.add_child(a)
	s.check(a.setup(&"visitor", "old_k", "", 1.0, ""), "move fixture builds a real NPC")
	if animator_script != null:
		a.rig.animator = animator_script.new(a.rig)
	a.ground_y = 100.0
	a.position = Vector2(30, 100)
	a.set_pose(&"sit" if seated else &"idle")
	for i in 180:
		a._process(1.0 / 60.0)
	p._actors[&"visitor"] = a
	return {"player":p, "actor":a}

static func _step(s: TestSuite, p) -> void:
	await s.frames(1)
	if is_instance_valid(p):
		for tween: Tween in p._tweens:
			if tween.is_valid():
				tween.custom_step(.05)

static func _start(p: CutscenePlayer, done: Array[bool], wait := true) -> void:
	await p._do_move({"id":"visitor", "to":[90,100], "time":.5, "pose":"walk", "then":"idle", "wait":wait})
	done[0] = true

static func readiness(s: TestSuite, animator_script: Script = null) -> void:
	var f := _fixture(s, preload("res://game/cutscene/cutscene_player.gd"), true, animator_script)
	var p: CutscenePlayer = f.player
	var a: CutsceneActor = f.actor
	var animation: NpcAnimator = a.rig.animator
	s.check(animation.has_method("posture_active") and animation.has_method("posture_ready"), "NPC exposes consumed-posture readiness")
	if not animation.has_method("posture_ready"):
		p.free()
		return
	s.check(animation.call("posture_active") and animation.call("posture_ready", &"sit"), "settled sit is actually ready")
	a.set_pose(&"idle")
	s.check(not animation.call("posture_ready", &"stand"), "desired stand cannot reuse completed sit progress")
	var before := [animation._pose_now, animation._trans_t, animation._posture_u, animation._use_npc]
	for i in 12:
		animation.call("posture_ready", &"stand")
		animation.call("posture_active")
	s.check(before == [animation._pose_now, animation._trans_t, animation._posture_u, animation._use_npc], "readiness getters do not animate or mutate")
	a._process(1.0 / 60.0)
	s.check(not animation.call("posture_ready", &"stand"), "consumed stand transition is not prematurely ready")
	var handoff_seen := false
	for i in 180:
		a._process(1.0 / 60.0)
		if animation.posture_progress() == 1.0 and animation._trans_t >= 0.0:
			handoff_seen = true
			s.check(not animation.call("posture_ready", &"stand"), "completed main rise still waits for actual foot-IK handoff")
	s.check(handoff_seen, "real rise exercises post-progress foot-IK handoff")
	s.check(animation.call("posture_ready", &"stand"), "actual completed stand becomes ready")
	a._input.two_handed = true
	a._process(1.0 / 60.0)
	s.check(not animation.call("posture_active") and not animation.call("posture_ready", &"stand"), "armed mode does not pretend to use NPC posture")
	p.free()

static func run(s: TestSuite, script: Script = preload("res://game/cutscene/cutscene_player.gd"), animator_script: Script = null) -> void:
	var f := _fixture(s, script, true, animator_script)
	var p: CutscenePlayer = f.player
	var a: CutsceneActor = f.actor
	var done: Array[bool] = [false]
	_start(p, done)
	s.check(a.pose == &"idle" and p._tweens.is_empty(), "seated move first requests stand without translating")
	var premature := false
	for i in 200:
		if done[0]: break
		if is_instance_valid(p) and not p._tweens.is_empty() and a.rig.animator._pose_now != &"stand":
			premature = true
		if a.rig.animator._use_npc and a.rig.animator._pose_now != &"stand":
			s.check(is_equal_approx(a.position.x, 30.0), "rising actor stays at its original stage position")
		await _step(s, p)
	s.check(done[0] and not premature and is_equal_approx(a.position.x, 90.0), "move completes only after consumed stand posture")
	for i in 8: a._process(1.0 / 60.0)
	s.check(a.pose == &"idle" and a.rig.animator._pose_now == &"stand" and a.rig.animator.posture_progress() == 1.0, "arrival does not resume an unfinished sit-to-stand")
	p.free()
	# Standing and non-posture actors retain the zero-await fast path.
	for mode: String in ["standing", "armed", "portrait"]:
		f = _fixture(s, script, false, animator_script)
		p = f.player
		a = f.actor
		if mode == "armed":
			a._input.two_handed = true
			a._process(1.0 / 60.0)
		elif mode == "portrait":
			a.rig.free()
			a.rig = null
		done = [false]
		_start(p, done)
		s.check(a.pose == &"walk" and p._tweens.size() == 1, "%s move starts synchronously" % mode)
		p.free()
		await s.frames(1)
	f = _fixture(s, script, true, animator_script)
	p = f.player
	done = [false]
	_start(p, done, false)
	s.check(done[0], "wait=false returns while standing preparation remains asynchronous")
	p.free()
	await s.frames(1)
	# The same lifecycle failures are exercised both before and after movement.
	for phase: String in ["rise", "move"]:
		for interruption: String in ["skip", "cancel", "dead", "free", "replace", "exit", "mode"]:
			f = _fixture(s, script, phase == "rise", animator_script)
			p = f.player
			a = f.actor
			done = [false]
			var completed: Array[bool] = [false]
			p.finished.connect(func(_id: StringName) -> void: completed[0] = true)
			_start(p, done)
			match interruption:
				"skip": p.skip()
				"cancel": p.cancel()
				"dead": a.set_pose(&"dead")
				"free": a.queue_free()
				"replace": p._actors.erase(&"visitor")
				"exit": s.runner.remove_child(p)
				"mode":
					a._input.two_handed = true
					a._process(1.0 / 60.0)
			for i in 30: await _step(s, p)
			s.check(done[0] or not is_instance_valid(p) or not p._running, "%s/%s stops or cancels safely" % [phase, interruption])
			s.check(not completed[0], "%s/%s cannot fabricate Story completion" % [phase, interruption])
			if is_instance_valid(a) and interruption == "dead":
				s.check(a.pose == &"dead", "%s dead actor cannot receive arrival idle callback" % phase)
			if is_instance_valid(p): p.free()
			await s.frames(1)

static func dispatch(s: TestSuite, script: Script = preload("res://game/cutscene/cutscene_player.gd")) -> void:
	for phase: String in ["rise", "move"]:
		for interruption: String in ["none", "skip", "cancel", "dead", "free", "replace", "exit"]:
			var f := _fixture(s, script, phase == "rise")
			var p: CutscenePlayer = f.player
			var a: CutsceneActor = f.actor
			var tail: Array[bool] = [false]
			var completed: Array[bool] = [false]
			p._steps = [{"do":"move", "id":"visitor", "to":[90,100], "time":.5}, {"do":"test_tail"}]
			p._handlers["test_tail"] = func(_step: Dictionary) -> void: tail[0] = true
			p.finished.connect(func(_id: StringName) -> void: completed[0] = true)
			p._run()
			match interruption:
				"skip": p.skip()
				"cancel": p.cancel()
				"dead": a.set_pose(&"dead")
				"free": a.queue_free()
				"replace": p._actors.erase(&"visitor")
				"exit": s.runner.remove_child(p)
			for i in 220:
				if not is_instance_valid(p) or not p._running: break
				await _step(s, p)
			s.check(tail[0] == (interruption == "none"), "%s/%s dispatcher cannot execute a cancelled move's result tail" % [phase, interruption])
			s.check(completed[0] == (interruption in ["none", "skip"]), "%s/%s preserves existing complete-versus-skip-versus-cancel semantics" % [phase, interruption])
			if is_instance_valid(p): p.free()
			await s.frames(1)
