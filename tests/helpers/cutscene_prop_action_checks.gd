extends RefCounted

static func run(s: TestSuite) -> void:
	var move := {"do": "prop_move", "id": "lid", "angle": 1.2, "time": .25}
	var hold := {"do": "prop_hold", "id": "body", "actor": "k", "hand": "front", "point": [12, 15]}
	for step: Dictionary in [move, hold, {"do": "prop_release", "id": "body"}, {"do": "prop_visible", "id": "water", "visible": true}]:
		s.check(CutscenePropAction.problem(step).is_empty(), "finite named prop command validates: " + step["do"])
	for edit: Dictionary in [{"id": "../body"}, {"angle": INF}, {"time": -1}, {"time": 6}, {"wait": 1}, {"to": [0, NAN]}, {"to": [8193, 0]}, {"method": "free"}]:
		s.check(not CutscenePropAction.problem(move.merged(edit, true)).is_empty(), "reject malformed prop move without arbitrary node access: " + str(edit))
	for edit: Dictionary in [{"actor": ""}, {"hand": "rear"}, {"point": [-1, 0]}, {"point": [0]}, {"point": [0, "2"]}]:
		s.check(not CutscenePropAction.problem(hold.merged(edit, true)).is_empty(), "reject malformed prop pickup: " + str(edit))
	s.check(not CutscenePropAction.problem({"do": "prop_move", "id": "body"}).is_empty(), "move must change a bounded position or angle")
	s.check(not CutscenePropAction.problem({"do": "prop_visible", "id": "body", "visible": 1}).is_empty(), "visibility is strictly boolean")
	var initial := {"body": {"pos": [10, 20], "angle": .2, "visible": true}}
	s.check(CutscenePropAction.initial_problem(initial).is_empty(), "initial scene props accept a finite transform and visibility")
	for invalid: Variant in [null, [], {"body": {}}, {"body": {"position": [0, 0]}}, {"body": {"pos": [NAN, 0]}}, {"body": {"state": "../bad"}}]:
		s.check(not CutscenePropAction.initial_problem(invalid).is_empty(), "invalid initial props are rejected: " + str(invalid))
	var stage := StageLibrary.Stage.new()
	var dial := StageLayers.create({"kind": "dial", "id": "body", "pos": [30, 40], "radius": 5, "color": "#222222", "pointer": "#dddddd"}, "prop fixture")
	var flow_def := {"kind": "rain", "id": "water", "area": [10, 20, .6, 5], "speed": [24, 36], "length": [2, 3], "count": 8, "wind": 0, "visible": false}
	var flow := StageLayers.create(flow_def, "flow fixture") as StageLayers._Rain
	stage.add_layer(dial)
	stage.add_layer(flow)
	s.runner.add_child(stage)
	s.check(flow.process_mode == Node.PROCESS_MODE_DISABLED and not flow.visible, "hidden flow consumes no update work")
	s.check(not stage.initial_props({"body": {"pos": [99, 99]}, "missing": {"visible": true}}).is_empty() and dial.position == Vector2(30, 40), "missing last prop cannot partially apply initial scene state")
	s.check(not stage.initial_props({"body": {"pos": [99, 99]}, "water": {"state": "filled"}}).is_empty() and dial.position == Vector2(30, 40), "unavailable last material state cannot partially apply initial scene state")
	s.check(stage.initial_props(initial).is_empty() and dial.position == Vector2(10, 20) and is_equal_approx(dial.rotation, .2), "initial state applies coherently before a scene is shown")
	s.check(stage.set_prop_visible("water", true) and flow.visible and flow.process_mode != Node.PROCESS_MODE_DISABLED, "showing local flow restores its original processing policy")
	var before := flow._drops.duplicate()
	flow._process(.8)
	var varied := false
	for index in flow._drops.size():
		var expected := fposmod(before[index].y + flow._speeds[index] * .8 - 20, 5) + 20
		s.check(absf(flow._drops[index].y - expected) < .0001 and flow._drops[index].x >= 10 and flow._drops[index].x <= 10.6, "local flow preserves overshoot and stays within its authored outlet at low frame rates")
		varied = varied or absf(flow._drops[index].y - flow._drops[0].y) > .01
	s.check(varied and flow._drops.size() == 8, "low-rate flow retains distinct phases and a fixed allocation")
	s.check(stage.set_prop_visible("water", false) and flow.process_mode == Node.PROCESS_MODE_DISABLED, "ending fill disables its updates again")
	var rain := StageLayers.create({"kind": "rain"}, "legacy rain") as StageLayers._Rain
	s.check(rain._drops.size() == 140 and rain._area == Rect2(-80, -40, 800, 440) and not rain._local_flow, "existing outdoor rain keeps its original defaults and wrap policy")
	rain.free()
	stage.free()
	for edit: Dictionary in [{"area": [0, 0, 0, 5]}, {"area": [0, 0, INF, 5]}, {"speed": [36, 24]}, {"length": [-1, 2]}, {"wind": NAN}]:
		s.check(not StageLayers.prop_state_problem(flow_def.merged(edit, true)).is_empty(), "reject malformed local water effect: " + str(edit))
	var id := &"test_prop_action_contract"
	StageLibrary._cache[id] = {"layers": [{"kind": "sprite", "id": "lid", "parent_prop": "body"}, {"kind": "dial", "id": "dial"}]}
	s.check(not CutsceneChecker._check_initial_props("fixture", id, {"lid": {"pos": [0, 0]}}).is_empty(), "content checker rejects a child hinge translation before playback")
	s.check(CutsceneChecker._check_initial_props("fixture", id, {"lid": {"angle": .4}}).is_empty(), "content checker permits the intended independent lid rotation")
	StageLibrary._cache.erase(id)
