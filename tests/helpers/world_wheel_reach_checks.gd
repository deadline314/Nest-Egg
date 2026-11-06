extends RefCounted
## ST-21 排水輪：用真的凜骨架與真的排水輪擺設，在 360 種待機姿勢下確認資料寫的站位能讓前手沿輪緣推完整段，
## 握點誤差在 WorldPropAction 的容許值以內；也驗 turn 的資料檢查與階段順序。不跑劇情，不代替地圖上的實際演出。

const PROP := "res://data/environment/scene_props/sluice_hall/sluice_hall__drain_wheel.tres"


static func run(suite: TestSuite) -> void:
	_test_data(suite)
	for id: String in ["pump_wheel_drain", "pump_wheel_jam"]:
		_test_reach(suite, id)


static func _test_data(suite: TestSuite) -> void:
	suite.check(WorldPropAction.problem("pump_wheel_drain", "ch3_t_c02_drained", true).is_empty(), "the drain-wheel turn is valid data: " + WorldPropAction.problem("pump_wheel_drain", "ch3_t_c02_drained", true))
	suite.check(WorldPropAction.problem("pump_wheel_jam", "ch3_t_c02_wheel_wrong", true).is_empty(), "the jammed-wheel turn is valid data: " + WorldPropAction.problem("pump_wheel_jam", "ch3_t_c02_wheel_wrong", true))
	suite.check(not WorldPropAction.problem("pump_wheel_drain", "ch3_t_c02_wheel_wrong", true).is_empty(), "the drain turn cannot be borrowed by the wrong-way scene")
	var spec := WorldPropAction.definition("pump_wheel_drain")
	var original := spec.duplicate(true)
	for key_value: Array in [["strokes", 0], ["strokes", 4], ["strokes", 1.5], ["stall", 0.0], ["stall", 1.2], ["stall", NAN],
			["radius", [0.5, 0.2]], ["radius", [4, 6]], ["sweep", [90, 85]], ["sweep", [0, 270]], ["hub", [INF, 0]]]:
		spec[key_value[0]] = key_value[1]
		suite.check(not WorldPropAction.problem("pump_wheel_drain", "ch3_t_c02_drained", true).is_empty(), "bad turn %s is rejected: %s" % [key_value[0], key_value[1]])
		spec.assign(original)
	var full := WorldPropAction.turn_sequence(2, 1.0).map(func(step: Dictionary) -> String: return step["id"])
	suite.check(full == ["approach", "reach", "turn", "regrip", "turn", "release"], "a full turn reaches, pushes, regrips and lets go: %s" % [full])
	var stalled := WorldPropAction.turn_sequence(1, 0.4).map(func(step: Dictionary) -> String: return step["id"])
	suite.check(stalled == ["approach", "reach", "turn", "recoil", "release"], "a jammed wheel stops partway and springs back: %s" % [stalled])


static func _test_reach(suite: TestSuite, id: String) -> void:
	var spec := WorldPropAction.definition(id)
	var data := load(PROP) as PropData
	var prop := PropNode.new()
	prop.setup(data, Vector2(475, 166))
	suite.runner.add_child(prop)
	var rig := CharacterRig.new()
	suite.runner.add_child(rig)
	suite.check(rig.setup("rin"), "wheel reach check uses the actual Rin rig")
	rig.global_position = prop.to_global(Vector2(spec["station"][0], spec["station"][1]))
	var action := WorldPropAction.new()
	action._spec = spec
	action._prop = weakref(prop)
	var input := RigInput.new()
	input.facing = int(spec["facing"])
	input.aim_dir = Vector2(input.facing, 0)
	input.on_floor = true
	input.hand_grip_front = true
	var samples := 9
	var failures := 0
	var worst := 0.0
	var angle := 0.0 if input.facing > 0 else PI
	for frame in 360:
		rig.animate(1.0 / 60.0, input)
		for i in samples:
			var target := action.rim_global(action._turn_angle(float(i) / (samples - 1)))
			rig.animate(0.0, input)
			if not rig.place_hand(&"front", target, angle):
				failures += 1
			worst = maxf(worst, rig.hand_contact_global(&"front").distance_to(target))
	var floor_y := prop.global_position.y + data.size.y
	print("WHEEL_REACH %s" % JSON.stringify({"id": id, "poses": 360, "samples": samples, "unreachable": failures, "worst_palm_error": worst,
		"station": spec["station"], "hub_above_floor": floor_y - prop.to_global(Vector2(spec["hub"][0], spec["hub"][1])).y}))
	suite.check(failures == 0 and worst <= WorldPropAction.CONTACT_TOLERANCE,
			"%s: the front hand reaches every rim point from the authored station in all idle poses (worst %.3f, %d unreachable)" % [id, worst, failures])
	rig.queue_free()
	prop.queue_free()
