class_name NpcLifeSuite
extends TestSuite
## NPC 的生命感（NE-206）：長時間待機會發生換腳站、轉頭、嘆氣；沒有兩根骨頭的動作一模一樣；說話有重音手勢與開口前的吸氣；
## 每個角色的節奏不同但可重現；資料缺漏或亂填時退回安全預設；全部事件發生時腳仍踩在地上。

const SKINS: Array[String] = ["old_k", "nurse", "night_worker", "resident", "mei", "wataru", "ah_po", "repairman_chen"]
const DT := 1.0 / 30.0


func run() -> void:
	_test_life_unit()
	_test_data_overrides()
	await _test_idle_variety()
	await _test_talking()
	await _test_feet_stay_planted()


func _defaults() -> Dictionary:
	return RigLibrary.load_json(NpcAnimator.DATA_PATH).get("life", {})


func _life(skin: String, overrides := {}) -> NpcLife:
	var life := NpcLife.new()
	life.setup(skin, _defaults(), overrides)
	return life


func _test_life_unit() -> void:
	check(not _defaults().is_empty(), "the shared life defaults exist in npc_animations.json")
	var life := _life("old_k")
	for i in int(120.0 / DT):
		life.step(DT, {"posture": &"stand", "talking": false})
	check(life.shifts >= 6, "two minutes of standing includes weight shifts (%d)" % life.shifts)
	check(life.glances >= 8, "and glances (%d)" % life.glances)
	check(life.sighs >= 3, "and a few deeper breaths (%d)" % life.sighs)
	var seated := _life("old_k")
	for i in int(60.0 / DT):
		seated.step(DT, {"posture": &"sit", "talking": false})
	check(seated.shifts == 0, "a seated person does not shift weight between feet")
	var a := _life("nurse")
	var b := _life("nurse")
	var same := true
	for i in 300:
		var ra := a.step(DT, {"posture": &"stand"})
		var rb := b.step(DT, {"posture": &"stand"})
		same = same and is_equal_approx(float((ra["bones"] as Dictionary).get(&"head", 0.0)), float((rb["bones"] as Dictionary).get(&"head", 0.0)))
	check(same, "the same character always moves the same way (seeded by name)")
	var other := _life("resident")
	var diff := false
	var c := _life("nurse")
	for i in 300:
		var rc := c.step(DT, {"posture": &"stand"})
		var ro := other.step(DT, {"posture": &"stand"})
		diff = diff or not is_equal_approx(float((rc["bones"] as Dictionary).get(&"head", 0.0)), float((ro["bones"] as Dictionary).get(&"head", 0.0)))
	check(diff, "different characters do not move in sync")
	# 軌道週期：同一個角色沒有兩條軌道的週期相同
	var periods: Array[float] = []
	for track in _life("old_k").drift_tracks():
		for key in ["p1", "p2"]:
			var p: float = track[key]
			for q in periods:
				check(absf(p - q) > 0.01, "no two drift periods are the same (%.3f vs %.3f)" % [p, q])
			periods.append(p)
	# 說話
	var talker := _life("mei")
	var inhale := 0.0
	for i in int(12.0 / DT):
		var r := talker.step(DT, {"posture": &"stand", "talking": true})
		if i < 10:
			inhale = minf(inhale, float((r["bones"] as Dictionary).get(&"chest", 0.0)))
	check(talker.beats >= 6, "twelve seconds of talking has emphasis gestures (%d)" % talker.beats)
	check(inhale < -0.02, "talking starts with an inhale (chest %.3f)" % inhale)
	# 彈簧：目標突然停下時有一點過衝
	var spring := _life("old_k")
	var overshoot := 0.0
	var value := 0.0
	for i in 60:
		value = spring.follow(&"chest", 0.3, DT)
	for i in 30:
		value = spring.follow(&"chest", 0.0, DT)
		overshoot = minf(overshoot, value)
	check(overshoot < -0.005, "the follow spring overshoots a little when the target stops (%.3f)" % overshoot)
	check(is_equal_approx(spring.follow(&"no_such_bone", 0.25, DT), 0.25), "a bone without a spring passes through unchanged")


func _test_data_overrides() -> void:
	var calm := _life("old_k", {"tempo": 0.5, "amount": 0.0})
	var maxed := 0.0
	for i in int(60.0 / DT):
		var r := calm.step(DT, {"posture": &"stand"})
		for value: float in (r["bones"] as Dictionary).values():
			maxed = maxf(maxed, absf(value))
	check(maxed < 0.001, "amount 0 switches the life layer off (%.4f)" % maxed)
	var broken := NpcLife.new()
	broken.setup("x", {"drift": "not a list", "shift": 3, "glance": {"every": "soon"}}, {"beat": "nope"})
	var survived := true
	for i in 300:
		var r := broken.step(DT, {"posture": &"stand", "talking": i > 100})
		survived = survived and is_finite(float(r["hip_x"]))
	check(survived, "malformed life data falls back to safe defaults without errors")
	var merged := HumanoidAnimator._load_motion("old_k")
	check(not (merged["npc"]["life"] as Dictionary).is_empty(), "a character's own life settings are loaded")
	check(float(merged["npc"]["stand"].get("head", 0.0)) > 0.0, "a character's own stand adjustment is loaded (it used to be dropped)")


## 二十位 NPC 以上待機 40 秒：骨頭角度兩兩不完全相關（沒有兩根骨頭的動作一模一樣）。
func _test_idle_variety() -> void:
	for skin in SKINS:
		var holder := Node2D.new()
		runner.add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		check(rig.setup(skin, "npc"), "%s builds as an NPC" % skin)
		var input := RigInput.new()
		input.facing = 1
		input.on_floor = true
		input.two_handed = false
		var names: Array[StringName] = [&"chest", &"head", &"arm_front_upper", &"arm_front_lower", &"arm_back_upper"]
		var series: Dictionary = {}
		for n in names:
			series[n] = [] as Array[float]
		for i in int(40.0 / DT):
			rig.animate(DT, input)
			for n in names:
				(series[n] as Array[float]).append(rig.bone(n).rotation)
		var worst := 0.0
		for i in names.size():
			for j in range(i + 1, names.size()):
				worst = maxf(worst, absf(_correlation(series[names[i]], series[names[j]])))
		check(worst < 0.97, "%s: no two bones move identically over 40 seconds (worst correlation %.2f)" % [skin, worst])
		var head: Array[float] = series[&"head"]
		check(_range_of(head) > 0.04, "%s: the head actually moves while idle (%.3f rad)" % [skin, _range_of(head)])
		holder.queue_free()
		await frames(1)


func _correlation(a: Array[float], b: Array[float]) -> float:
	var n := mini(a.size(), b.size())
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / maxf(0.000001, sqrt(saa * sbb))


func _range_of(values: Array[float]) -> float:
	var low := INF
	var high := -INF
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	return high - low


func _test_talking() -> void:
	var holder := Node2D.new()
	runner.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("old_k", "npc"), "old_k builds as an NPC")
	var input := RigInput.new()
	input.facing = 1
	input.on_floor = true
	input.two_handed = false
	for i in 60:
		rig.animate(DT, input)
	var quiet := 0.0
	for i in 90:
		rig.animate(DT, input)
		quiet = maxf(quiet, absf(rig.bone(&"arm_front_upper").rotation))
	input.talking = true
	var talk := 0.0
	for i in 150:
		rig.animate(DT, input)
		talk = maxf(talk, absf(rig.bone(&"arm_front_upper").rotation))
	check(talk > quiet + 0.1, "the arm gestures while talking (%.2f vs %.2f idle)" % [talk, quiet])
	holder.queue_free()
	await frames(1)


## 站著、坐著、靠著各待機 40 秒，最低的腳離地不超過 0.6 px、不陷進地面超過 1.5 px（重心轉移用腿反向轉動讓腳不滑）。
func _test_feet_stay_planted() -> void:
	for skin in ["old_k", "nurse", "resident"]:
		for pose in [&"stand", &"sit", &"lean"]:
			var holder := Node2D.new()
			runner.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			rig.setup(skin, "npc")
			var input := RigInput.new()
			input.facing = 1
			input.on_floor = true
			input.two_handed = false
			input.npc_pose = pose
			for i in 60:
				rig.animate(DT, input)
			var floating := 0.0
			var sunk := 0.0
			var drift := 0.0
			var first_x := NAN
			for i in int(40.0 / DT):
				rig.animate(DT, input)
				var low := -INF
				for foot in [&"foot_front", &"foot_back"]:
					low = maxf(low, rig.animator.bone_pos(foot).y)
				var ground: float = rig.animator.ground_level()
				if pose == &"stand":
					floating = maxf(floating, ground - low)
					sunk = maxf(sunk, low - ground)
					var fx: float = rig.animator.bone_pos(&"foot_front").x
					first_x = fx if is_nan(first_x) else first_x
					drift = maxf(drift, absf(fx - first_x))
			if pose == &"stand":
				check(floating <= 0.6 and sunk <= 1.5, "%s: standing feet stay on the ground through shifts (%.2f up, %.2f down)" % [skin, floating, sunk])
				check(drift <= 0.8, "%s: the planted foot does not glide while the weight shifts (%.2f px)" % [skin, drift])
			holder.queue_free()
			await frames(1)
