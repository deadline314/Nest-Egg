extends RefCounted
## ST-19 阿梨家洗碗：用真的凜骨架與真的洗碗池擺設，在 360 種待機姿勢下確認資料寫的站位讓前手搆得到水槽裡的拿碗點、
## 沖洗的小圈與碗架上的放碗點（握點誤差在容許值內）；也驗 place 的資料檢查與階段。地圖上的實際演出由第二章流程探針驗。

const PROP := "res://data/environment/scene_props/ali_kitchen/ali_kitchen__sink_drying_rack.tres"
const ACTIONS := {"ali_bowl_rack": "ch2_t_s07_soup", "ali_bowl_wet_end": "ch2_t_s07_wash_wrong"}


static func run(suite: TestSuite) -> void:
	for id: String in ACTIONS:
		suite.check(WorldPropAction.problem(id, ACTIONS[id], true).is_empty(), "%s is valid data: %s" % [id, WorldPropAction.problem(id, ACTIONS[id], true)])
	suite.check(not WorldPropAction.problem("ali_bowl_rack", "ch2_t_s07_wash_wrong", true).is_empty(), "the dry-rack placement cannot be borrowed by the wrong-rack scene")
	var spec := WorldPropAction.definition("ali_bowl_rack")
	var original := spec.duplicate(true)
	for key_value: Array in [["texture", "res://data/levels/ch2_ali_home.tres"], ["texture", "res://art/items/world/missing.png"], ["width", 0.5], ["width", 20],
			["scrub_loops", 4], ["scrub_loops", 1.5], ["pick", [INF, 0]], ["drop", null], ["scrub", [1]]]:
		spec[key_value[0]] = key_value[1]
		suite.check(not WorldPropAction.problem("ali_bowl_rack", "ch2_t_s07_soup", true).is_empty(), "bad place %s is rejected: %s" % [key_value[0], key_value[1]])
		spec.assign(original)
	var ids := WorldPropAction.place_sequence(2).map(func(step: Dictionary) -> String: return step["id"])
	suite.check(ids == ["approach", "pick", "lift", "scrub", "place", "release"], "washing picks up, rinses, places and lets go: %s" % [ids])
	for id: String in ACTIONS:
		_test_reach(suite, id)


static func _test_reach(suite: TestSuite, id: String) -> void:
	var spec := WorldPropAction.definition(id)
	var data := load(PROP) as PropData
	var prop := PropNode.new()
	prop.setup(data, Vector2(192, 279.5))
	suite.runner.add_child(prop)
	var rig := CharacterRig.new()
	suite.runner.add_child(rig)
	suite.check(rig.setup("rin"), "place reach check uses the actual Rin rig")
	rig.global_position = prop.to_global(Vector2(spec["station"][0], spec["station"][1]))
	var action := WorldPropAction.new()
	action._spec = spec
	action._prop = weakref(prop)
	var input := RigInput.new()
	input.facing = int(spec["facing"])
	input.aim_dir = Vector2(input.facing, 0)
	input.on_floor = true
	input.hand_grip_front = true
	var targets: Array[Vector2] = [action._prop_point("pick"), action._prop_point("drop")]
	for i in 8:
		targets.append(action._prop_point("pick") + action._scrub_offset(i / 8.0))
	var failures := 0
	var worst := 0.0
	var angle := action.hand_angle()
	for frame in 360:
		rig.animate(1.0 / 60.0, input)
		for target in targets:
			rig.animate(0.0, input)
			if not rig.place_hand(&"front", target, angle):
				failures += 1
			worst = maxf(worst, rig.hand_contact_global(&"front").distance_to(target))
	print("PLACE_REACH %s" % JSON.stringify({"id": id, "poses": 360, "targets": targets.size(), "unreachable": failures, "worst_palm_error": worst, "station": spec["station"]}))
	suite.check(failures == 0 and worst <= WorldPropAction.CONTACT_TOLERANCE,
			"%s: the front hand reaches the sink, the rinse loop and the rack from the authored station (worst %.3f, %d unreachable)" % [id, worst, failures])
	rig.queue_free()
	prop.queue_free()
