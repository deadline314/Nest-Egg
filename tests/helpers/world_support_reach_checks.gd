extends RefCounted
## ST-21 扶守門人坐下：用真的凜骨架與真的守門人（場景人物同一個演員類別），從站著到坐上凳子的整段，
## 確認資料寫的站位讓凜的前手一路扶得到他的肩膀（握點誤差在容許值內）；也驗 support 的資料檢查與階段。
## 不跑劇情；地圖上的實際演出由第三章流程探針驗。

const SCENE := "ch3_t_c12_aftercare"
const ID := "janus_sit_support"


static func run(suite: TestSuite) -> void:
	_test_data(suite)
	_test_reach(suite)


static func _test_data(suite: TestSuite) -> void:
	suite.check(WorldPropAction.problem(ID, SCENE, true).is_empty(), "the gatekeeper support is valid data: " + WorldPropAction.problem(ID, SCENE, true))
	suite.check(not WorldPropAction.problem(ID, "ch3_t_c12_revisit", true).is_empty(), "the support cannot be borrowed by the revisit line")
	var spec := WorldPropAction.definition(ID)
	var original := spec.duplicate(true)
	for key_value: Array in [["bone", "../chest"], ["bone", ""], ["pose", "fly"], ["contact", [INF, 0]], ["contact", null], ["station", [0, 300]], ["person_facing", 0], ["person_facing", "1"]]:
		spec[key_value[0]] = key_value[1]
		suite.check(not WorldPropAction.problem(ID, SCENE, true).is_empty(), "bad support %s is rejected: %s" % [key_value[0], key_value[1]])
		spec.assign(original)
	var data := load("res://data/npcs/ch3_gatekeeper.tres") as NpcData
	var never := func(_flag: StringName) -> bool: return false
	var always := func(_flag: StringName) -> bool: return true
	suite.check(data.current_pose(never) == &"idle" and data.current_pose(always) == &"sit", "the gatekeeper stands until the aftercare flag is saved, then sits")


## 守門人面向凜站著（呼吸、張望）一段時間，再換成坐姿坐下；每一格都把凜的前手放到他肩上量誤差。
static func _test_reach(suite: TestSuite) -> void:
	var spec := WorldPropAction.definition(ID)
	var holder := Node2D.new()
	suite.runner.add_child(holder)
	var actor := CutsceneActor.new()
	holder.add_child(actor)
	suite.check(actor.setup(&"ch3_gatekeeper", "janus", "", 1.0, ""), "support reach check uses the actual gatekeeper rig")
	actor.position = Vector2(520, 320)
	actor.ground_y = 320.0
	actor.set_loop(&"glance", 1.0)
	actor.set_pose(&"idle")
	var rig := CharacterRig.new()
	holder.add_child(rig)
	suite.check(rig.setup("rin"), "support reach check uses the actual Rin rig")
	rig.global_position = actor.position + Vector2(spec["station"][0], spec["station"][1])
	actor.face(int(spec["person_facing"]))
	var input := RigInput.new()
	input.facing = int(spec["facing"])
	input.aim_dir = Vector2(input.facing, 0)
	input.on_floor = true
	input.hand_grip_front = true
	var angle := 0.0 if input.facing > 0 else PI
	var failures := 0
	var worst := 0.0
	var frames := 0
	for frame in 240 + 90:
		if frame == 240:
			actor.set_pose(StringName(spec["pose"]))
		actor._process(1.0 / 60.0)
		rig.animate(1.0 / 60.0, input)
		var target := actor.rig.bone(StringName(spec["bone"])).global_position + Vector2(float(spec["contact"][0]) * actor.facing, float(spec["contact"][1]))
		rig.animate(0.0, input)
		if not rig.place_hand(&"front", target, angle):
			failures += 1
		worst = maxf(worst, rig.hand_contact_global(&"front").distance_to(target))
		frames += 1
	print("SUPPORT_REACH %s" % JSON.stringify({"frames": frames, "unreachable": failures, "worst_palm_error": worst, "station": spec["station"], "contact": spec["contact"]}))
	suite.check(failures == 0 and worst <= WorldPropAction.CONTACT_TOLERANCE,
			"Rin's hand stays on the gatekeeper's shoulder from standing to seated (worst %.3f, %d unreachable of %d)" % [worst, failures, frames])
	holder.queue_free()
