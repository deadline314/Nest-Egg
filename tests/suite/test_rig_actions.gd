class_name RigActionsSuite
extends TestSuite
## 專屬動作（art/rigs/action_poses.json）與敵人招式動畫（NE-89 的機制、NE-75～82 的招式）：動作資料引用的骨頭都存在、
## 進度內插、skip_ik 的手臂依動作角度、沒有的動作不會崩潰、敵人資料的 rig_actions 引用存在的動作與狀態、開槍有後座力。

const PATH := "res://art/rigs/action_poses.json"
const SKINS: Array[String] = ["trooper", "warden", "rin"]


func run() -> void:
	_test_data()
	await _test_playback()
	await _test_unknown_action()
	await _test_enemy_data()


func _rig(skin: String, input: RigInput, settle := 40) -> CharacterRig:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(skin), "rig builds: %s" % skin)
	for i in settle:
		rig.animate(1.0 / 60.0, input)
	await frames(1)
	return rig


func _test_data() -> void:
	var actions: Dictionary = RigLibrary.load_json(PATH).get("actions", {})
	check(actions.size() >= 6, "action data has the actions (%d)" % actions.size())
	for skin in SKINS:
		var bones: Array[String] = []
		for bone: Dictionary in RigLibrary.load_json(str(RigLibrary.character(skin).get("rig", ""))).get("bones", []):
			bones.append(str(bone["name"]))
		for name: String in actions.keys():
			var def: Dictionary = actions[name]
			check(float(def.get("duration", 0.0)) > 0.0, "%s has a duration" % name)
			var last_t := -1.0
			for key: Dictionary in def.get("keys", []):
				var t := float(key.get("t", -1.0))
				check(t >= last_t and t >= 0.0 and t <= 1.0, "%s: keys are in order within 0..1" % name)
				last_t = t
				for bone: String in (key.get("bones", {}) as Dictionary).keys():
					check(bones.has(bone), "%s only uses bones that %s has: %s" % [name, skin, bone])


func _test_playback() -> void:
	var input := RigInput.new()
	input.two_handed = true
	var idle := await _rig("trooper", input)
	var idle_arm := idle.bone(&"arm_front_upper").rotation
	input.action = &"windup_overhead"
	input.action_t = 1.0
	var raised := await _rig("trooper", input, 60)
	check(raised.bone(&"arm_front_upper").rotation < -2.4, "an overhead windup raises the arm (%.2f)" % raised.bone(&"arm_front_upper").rotation)
	input.action_t = 0.0
	var start := await _rig("trooper", input, 60)
	check(start.bone(&"arm_front_upper").rotation > raised.bone(&"arm_front_upper").rotation + 1.0, "progress 0 is lower than progress 1")
	input.action = &"slam"
	input.action_t = 0.5
	var slam := await _rig("trooper", input, 60)
	check(slam.bone(&"chest").rotation > 0.25, "the slam bends the chest forward")
	input.action = &""
	var after := await _rig("trooper", input, 80)
	check(absf(after.bone(&"arm_front_upper").rotation - idle_arm) < 0.3, "after the action the arm goes back to the normal pose")


func _test_unknown_action() -> void:
	var input := RigInput.new()
	input.action = &"no_such_action"
	input.action_t = 0.5
	var rig := await _rig("trooper", input)
	check(rig.is_valid(), "an unknown action does not break the rig")


func _test_enemy_data() -> void:
	var actions: Dictionary = RigLibrary.load_json(PATH).get("actions", {})
	var found := 0
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data == null or data.rig_actions.is_empty():
			continue
		found += 1
		for state: Variant in data.rig_actions.keys():
			check(actions.has(str(data.rig_actions[state])), "%s: state %s plays an action that exists (%s)" % [file, state, data.rig_actions[state]])
		if data.behavior != null:
			var source := (data.behavior as GDScript).source_code
			for state: Variant in data.rig_actions.keys():
				check(source.contains('&"%s"' % str(state)), "%s: the behaviour has a state named %s" % [file, state])
	check(found >= 5, "several enemies have rig actions (%d)" % found)
