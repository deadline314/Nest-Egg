class_name NpcLifeSuite
extends TestSuite
## NPC 的生命感（NE-206）：長時間待機會發生換腳站、轉頭、嘆氣；沒有兩根骨頭的動作一模一樣；說話有重音手勢與開口前的吸氣；
## 每個角色的節奏不同但可重現；資料缺漏或亂填時退回安全預設；全部事件發生時腳仍踩在地上。
## NE-250：手勢有預備、準備、重音、停留、收回，結束時回到原位不跳格；說話不是固定循環；聆聽會點頭、沒事會做角色自己的小動作，
## 手在忙或說話時不做小動作；兩個角色的手勢選擇與節奏不同。

const SKINS: Array[String] = ["old_k", "nurse", "night_worker", "resident", "mei", "wataru", "ah_po", "repairman_chen"]
const DT := 1.0 / 30.0


func run() -> void:
	_test_life_unit()
	_test_data_overrides()
	await _test_idle_variety()
	await _test_talking()
	await _test_feet_stay_planted()
	_test_gesture_phases()
	_test_gesture_bad_data()
	_test_listen_and_fidget()
	_test_personality()
	await _test_talk_is_not_a_loop()


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


func _gestures() -> Dictionary:
	return RigLibrary.load_json(NpcAnimator.DATA_PATH).get("gestures", {})


## 一個手勢：先反向蓄勢、到位、停留、收回到 0 並結束；每格變化的二階差分小（沒有跳格）；有拖曳延遲的骨頭比較晚到；中途收回也不跳。
func _test_gesture_phases() -> void:
	var def := {"pose": {"arm_front_upper": -1.0, "arm_front_lower": -0.5}, "stroke": {"arm_front_upper": -0.2}, "wind": 0.2,
			"drag": {"arm_front_lower": 0.1}, "time": {"wind": 0.1, "prep": 0.3, "stroke": 0.1, "hold": [0.3, 0.3], "retract": 0.4}}
	var rng := RandomNumberGenerator.new()
	var gesture := NpcGesture.new()
	gesture.start(&"test", def, rng, 1.0, 1.0)
	var upper: Array[float] = []
	var lower: Array[float] = []
	var step := 1.0 / 60.0
	while gesture.active() and upper.size() < 600:
		var out := gesture.step(step)
		upper.append(float(out.get(&"arm_front_upper", 0.0)))
		lower.append(float(out.get(&"arm_front_lower", 0.0)))
	check(upper.size() < 600, "a gesture finishes (%d frames)" % upper.size())
	check(upper.max() > 0.05, "it winds up in the opposite direction first (%.3f)" % upper.max())
	check(upper.min() < -1.1, "it reaches the pose plus the stroke accent (%.3f)" % upper.min())
	check(absf(upper[upper.size() - 1]) < 0.02 and absf(lower[lower.size() - 1]) < 0.02, "it ends back at rest without a jump")
	# 1 弧度在 0.3 秒內緩入緩出，最大角加速度約 0.022 弧度／格²；舊的狀態切換約 0.06～0.1
	check(_max_jerk(upper) < 0.035 and _max_jerk(lower) < 0.035, "no frame pops during the gesture (%.4f / %.4f)" % [_max_jerk(upper), _max_jerk(lower)])
	var halfway := int((0.1 + 0.15) * 60.0)
	check(absf(lower[halfway]) / 0.5 < absf(upper[halfway]) / 1.0, "the dragged bone (forearm) arrives later than the upper arm")
	# 準備到一半就收回：從目前位置平順地回去
	var cut := NpcGesture.new()
	cut.start(&"test", def, rng, 1.0, 1.0)
	var values: Array[float] = []
	for i in 300:
		if i == 15:
			cut.release()
		var out := cut.step(step)
		values.append(float(out.get(&"arm_front_upper", 0.0)))
		if not cut.active():
			break
	check(not cut.active(), "a released gesture finishes")
	check(_max_jerk(values) < 0.035, "releasing mid-gesture does not jump (%.4f)" % _max_jerk(values))
	# 資料裡每個手勢都能完整播完並回到原位
	for name: Variant in _gestures().keys():
		var g := NpcGesture.new()
		g.start(StringName(str(name)), _gestures()[name], rng, 1.0, 1.0)
		var last: Dictionary = {}
		var frames_left := 900
		while g.active() and frames_left > 0:
			var out := g.step(step)
			if g.active():
				last = out
			frames_left -= 1
		var residual := 0.0
		for value: Variant in last.values():
			residual = maxf(residual, absf(float(value)))
		check(frames_left > 0 and residual < 0.03, "gesture %s finishes back at rest (last %.3f)" % [name, residual])


func _max_jerk(values: Array[float]) -> float:
	var worst := 0.0
	for i in range(2, values.size()):
		worst = maxf(worst, absf(values[i] - 2.0 * values[i - 1] + values[i - 2]))
	return worst


## 亂填的手勢資料不會中斷，照樣播完。
func _test_gesture_bad_data() -> void:
	var gesture := NpcGesture.new()
	gesture.start(&"broken", {"pose": "x", "stroke": [1], "time": 5, "drag": {"a": "slow"}, "wiggle": [3, {"bone": 1}], "wind": "big"},
			RandomNumberGenerator.new(), 1.0, 1.0)
	var frames_left := 600
	while gesture.active() and frames_left > 0:
		gesture.step(1.0 / 60.0)
		frames_left -= 1
	check(frames_left > 0, "a gesture with broken data still finishes")
	var life := NpcLife.new()
	life.setup("x", _defaults(), {"beat": {"vocab": {"no_such_gesture": 1, "beat": "many"}}, "fidget": {"vocab": "none"}}, {"nod": "bad"})
	for i in int(20.0 / DT):
		life.step(DT, {"posture": &"stand", "talking": i < 300})
	check(life.beats >= 3, "unknown gestures fall back to the built-in beat (%d)" % life.beats)
	check(not life.play_gesture(&"no_such_gesture"), "playing an unknown gesture is refused")


## 聆聽時會點頭附和；站著沒事會做小動作；手在忙（工作循環）或說話時不做小動作；坐著只做允許坐姿的小動作。
func _test_listen_and_fidget() -> void:
	var listener := NpcLife.new()
	listener.setup("nurse", _defaults(), _motion_life("nurse"), _gestures())
	for i in int(20.0 / DT):
		listener.step(DT, {"posture": &"stand", "listening": true})
	check(listener.nods >= 4, "a listener nods along (%d nods in 20 s)" % listener.nods)
	for skin in SKINS:
		var idle := NpcLife.new()
		idle.setup(skin, _defaults(), _motion_life(skin), _gestures())
		for i in int(60.0 / DT):
			idle.step(DT, {"posture": &"stand"})
		check(idle.fidgets >= 2, "%s does small idle actions of their own (%d in 60 s)" % [skin, idle.fidgets])
		var busy := NpcLife.new()
		busy.setup(skin, _defaults(), _motion_life(skin), _gestures())
		for i in int(60.0 / DT):
			busy.step(DT, {"posture": &"stand", "busy": true})
		check(busy.fidgets == 0, "%s does not fidget while the hands are busy" % skin)
		var talker := NpcLife.new()
		talker.setup(skin, _defaults(), _motion_life(skin), _gestures())
		for i in int(30.0 / DT):
			talker.step(DT, {"posture": &"stand", "talking": true})
		check(talker.fidgets == 0 and talker.beats >= 8, "%s gestures instead of fidgeting while talking (%d beats)" % [skin, talker.beats])


## 個性：同樣說 30 秒話，每個角色挑的手勢組合與次數不同。
func _test_personality() -> void:
	var seen: Dictionary = {}
	var counts: Dictionary = {}
	for skin in SKINS:
		var life := NpcLife.new()
		life.setup(skin, _defaults(), _motion_life(skin), _gestures())
		var names: Dictionary = {}
		for i in int(30.0 / DT):
			life.step(DT, {"posture": &"stand", "talking": true})
			names[life.current_gesture()] = true
		names.erase(&"")
		var key := ",".join(PackedStringArray(names.keys().map(func(n: StringName) -> String: return String(n)).duplicate()))
		seen[key] = int(seen.get(key, 0)) + 1
		counts[life.beats] = true
		check(names.size() >= 3, "%s uses several different gestures (%s)" % [skin, key])
	check(seen.size() >= SKINS.size() - 2, "characters choose different sets of gestures (%d sets for %d characters)" % [seen.size(), SKINS.size()])
	check(counts.size() >= 4, "and talk with different gesture rates (%d different counts)" % counts.size())


func _motion_life(skin: String) -> Dictionary:
	var motion := RigLibrary.load_json("res://art/motion/%s.json" % skin)
	var npc: Variant = motion.get("npc", {})
	var life: Variant = (npc as Dictionary).get("life", {}) if typeof(npc) == TYPE_DICTIONARY else {}
	return life if typeof(life) == TYPE_DICTIONARY else {}


## 說話不是固定循環：每個角色說 20 秒話，前臂上段的動作在 0.5～4 秒的延遲沒有高度自相關（舊的正弦循環約 0.96）。
func _test_talk_is_not_a_loop() -> void:
	for skin in SKINS + ["rin"] as Array[String]:
		var holder := Node2D.new()
		runner.add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		check(rig.setup(skin, "npc"), "%s builds as an NPC" % skin)
		var input := RigInput.new()
		input.facing = 1
		input.on_floor = true
		input.two_handed = false
		input.talking = true
		var arm: Array[float] = []
		for i in int(22.0 / DT):
			rig.animate(DT, input)
			if i * DT >= 2.0:
				arm.append(rig.bone(&"arm_front_upper").rotation)
		var peak := _autocorr_peak(arm, int(0.5 / DT), int(4.0 / DT))
		check(peak < 0.75, "%s: talking is not a fixed loop (autocorrelation %.2f)" % [skin, peak])
		holder.queue_free()
		await frames(1)


func _autocorr_peak(values: Array[float], lo: int, hi: int) -> float:
	var n := values.size()
	var mean := 0.0
	for v in values:
		mean += v
	mean /= maxf(1.0, n)
	var energy := 0.0
	for v in values:
		energy += (v - mean) * (v - mean)
	if energy <= 0.000001:
		return 0.0
	var best := -1.0
	for lag in range(lo, mini(hi, n / 2)):
		var sum := 0.0
		for i in n - lag:
			sum += (values[i] - mean) * (values[i + lag] - mean)
		best = maxf(best, sum / energy * float(n) / float(n - lag))
	return best
