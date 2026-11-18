extends RefCounted
## Replays the two native captures that exposed the near-straight whip recovery.

const PATH := "res://tests/fixtures/soft_whip_native_inputs.json"


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func run(suite: TestSuite) -> void:
	_check_idle(suite)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var valid: bool = (parsed is Dictionary and parsed.get("version") == 1
		and parsed.get("nodes") == SoftWhip.NODES and parsed.get("cases") is Array and parsed.cases.size() == 2)
	suite.check(valid, "native whip fixture retains two sides and the captured node count: " + PATH)
	if not valid:
		return
	for case: Dictionary in parsed.cases:
		_replay(suite, case)


static func _replay(suite: TestSuite, case: Dictionary) -> void:
	var label := "native whip " + str(case.side)
	var state: Dictionary = case.initial
	var complete: bool = (state.pos.size() == SoftWhip.NODES and state.prev.size() == SoftWhip.NODES
		and case.frames.size() == 1474)
	suite.check(complete, label + " has the complete recorded prefix")
	if not complete:
		return
	var whip := SoftWhip.new()
	for i in SoftWhip.NODES:
		whip._pos[i] = _vector(state.pos[i])
		whip._prev[i] = _vector(state.prev[i])
	whip._length = float(state.length)
	whip._laid = bool(state.laid)
	var observed := {}
	for index in case.observed_indices:
		observed[int(index)] = true
	var windup := {}
	for index in case.windup_indices:
		windup[int(index)] = true
	var side := -1.0 if case.side == "left" else 1.0
	var metrics := {}
	for name in case.moves:
		metrics[name] = {"frames": 0, "active": 0, "ratio": 0.0, "bow": INF, "tip_gap": INF, "wave": false}
	var observed_count := 0
	var observed_ratio := 0.0
	var floor_error := 0.0
	var root_error := 0.0
	var segment_ratio := 0.0
	var finite := true
	for index in case.frames.size():
		var row: Dictionary = case.frames[index]
		if bool(row.clear):
			whip.clear()
		whip.floor_y = float(row.floor)
		var root := _vector(row.root)
		var target := _vector(row.tip_target)
		whip.step(float(row.delta), root, _vector(row.handle_dir), float(row.length_target), target, float(row.pull))
		var rest_segment := maxf(0.0001, whip.length() / float(SoftWhip.NODES - 1))
		var arc := 0.0
		for i in SoftWhip.NODES:
			var point := whip.node(i)
			finite = finite and point.is_finite()
			floor_error = maxf(floor_error, point.y - whip.floor_y)
			if i > 0:
				var edge := point.distance_to(whip.node(i - 1))
				arc += edge
				segment_ratio = maxf(segment_ratio, edge / rest_segment)
		finite = finite and is_finite(arc) and arc > 0.0
		root_error = maxf(root_error, whip.node(0).distance_to(root))
		var chord := whip.tip() - whip.node(0)
		var visible_length := maxf(0.001, arc)
		var ratio := chord.length() / visible_length
		if observed.has(index):
			observed_count += 1
			observed_ratio = maxf(observed_ratio, ratio)
		for name in case.moves:
			var bounds: Dictionary = case.moves[name]
			if index < bounds.begin or index > bounds.end:
				continue
			var metric: Dictionary = metrics[name]
			metric.frames += 1
			metric.ratio = maxf(metric.ratio, ratio)
			if windup.has(index) and (whip.node(4).x - root.x) * side > 2.0 and chord.x * side < -2.0:
				metric.wave = true
			if index >= bounds.active_begin and index <= bounds.active_end:
				metric.active += 1
				var bow := 0.0
				var direction := chord.normalized()
				for i in SoftWhip.NODES:
					bow = maxf(bow, absf((whip.node(i) - whip.node(0)).cross(direction)))
				metric.bow = minf(metric.bow, bow / visible_length)
				metric.tip_gap = minf(metric.tip_gap, whip.tip().distance_to(target))
	suite.check(observed_count == 541, label + " covers all observed frames")
	suite.check(observed_ratio < 0.99, label + " observed chord / actual polyline length < .99 (%.9f)" % observed_ratio)
	suite.check(finite, label + " keeps all nodes and lengths finite")
	suite.check(floor_error <= 0.01 and root_error <= 0.01,
		label + " keeps floor contact and root anchor (%.6f / %.6f)" % [floor_error, root_error])
	suite.check(segment_ratio <= 1.001, label + " does not stretch solved segments (%.9f)" % segment_ratio)
	for name in case.moves:
		var bounds: Dictionary = case.moves[name]
		var metric: Dictionary = metrics[name]
		var move_label := label + " " + str(name)
		suite.check(metric.frames == bounds.end - bounds.begin + 1 and metric.active == bounds.active_end - bounds.active_begin + 1,
			move_label + " includes the complete move and recovery")
		suite.check(metric.ratio < 0.99, move_label + " chord / actual polyline length < .99 (%.9f)" % metric.ratio)
		suite.check(metric.bow >= 0.04, move_label + " active bow remains at least 4%% (%.6f)" % metric.bow)
		suite.check(metric.tip_gap <= bounds.range * 0.15, move_label + " reaches its recorded target (%.6f)" % metric.tip_gap)
		suite.check(metric.wave, move_label + " sends the curve forward while its tip still trails")
	print("SOFT_WHIP_NATIVE ", label, " ", JSON.stringify(metrics), " observed_ratio=", observed_ratio)


## 90 physics ticks of natural grip motion while equipping, then 20 more at rest.
static func _check_idle(suite: TestSuite) -> void:
	var path := "res://tests/fixtures/soft_whip_idle_inputs.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var valid: bool = data is Dictionary and data.get("version") == 1 and data.get("grip_frames") is Array and data.grip_frames.size() == 110
	suite.check(valid, "idle whip fixture contains the recorded grip motion: " + path)
	if not valid:
		return
	var whip := SoftWhip.new()
	whip.floor_y = float(data.floor_y)
	var before := Vector2.ZERO
	for i in data.grip_frames.size():
		var frame: Array = data.grip_frames[i]
		var root := Vector2(frame[0], frame[1])
		var handle := Vector2(frame[2], frame[3])
		whip.step(float(data.delta), root, handle, float(data.length), root, 0.0)
		if i == 89:
			before = whip.tip()
	var distance := whip.tip().distance_to(before)
	suite.check(distance < 1.5, "idle-whip recorded tip travel under 1.5 px in 20 ticks (%.5f)" % distance)
