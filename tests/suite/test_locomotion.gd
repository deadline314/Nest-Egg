class_name LocomotionSuite
extends TestSuite
## 主角的移動動作量測（NE-208）：以固定速度走、跑，量骨盆上下起伏的幅度、頻率、平滑度與腳滑步，
## 門檻依據 design/12-cast-redraw/LOCOMOTION_REFERENCE.md 第 6 節（長度以站立骨盆高度 L 為單位）。
## 其他角色（敵人）的移動動作尚未調整，不在這個套件的範圍；要看它們的數字用 tools/rig_locomotion_report.tscn。

const SKIN := "rin"
## 主角的滿速。
const RUN_SPEED := 150.0
## 量測的速度：慢走、走、慢跑、衝刺邊緣、滿速。
const SPEEDS: Array[float] = [30.0, 70.0, 105.0, 135.0, 150.0]
## 起伏幅度（峰谷，以 L 計）上限：業界走 0.03–0.06、跑 0.06–0.09（見參考文件第 2 節）。
const MAX_PP_L := 0.09
## 高於 3 倍主頻率的能量比例：越小越平滑。
const MAX_HF := 0.05
## 垂直加速度峰值相對於同幅度純正弦的倍率。
const MAX_ACC_RATIO := 3.5
## 單格骨盆高度的最大變化（以 L 計）。
const MAX_FRAME_STEP_L := 0.02
## 踩地的腳在世界座標的最大滑動（以 L 計）。
const MAX_SLIDE_L := 0.03
## 步頻（每秒幾步）的合理範圍：走 1.4–2.4、跑 2.4–5。
const MIN_STEP_HZ := 1.0
const MAX_STEP_HZ := 4.5


func run() -> void:
	await _test_motion_data()
	await _test_gait_is_smooth()
	await _test_stride_scales_with_speed()


func _make() -> CharacterRig:
	var holder := Node2D.new()
	runner.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(SKIN), "rig builds: %s" % SKIN)
	return rig


func _free(rig: CharacterRig) -> void:
	rig.get_parent().queue_free()


## 主角的資料啟用等高跑法與步長縮放；預設值不啟用，所以其他角色不受影響。
func _test_motion_data() -> void:
	var defaults: Dictionary = HumanoidAnimator.DEFAULT_MOTION["move"]
	check(float(defaults["level"]) == 0.0 and float(defaults["stride_exp"]) == 0.0, "the new gait fields are off by default")
	var motion := HumanoidAnimator._load_motion(SKIN)
	var move: Dictionary = motion["move"]
	check(float(move["level"]) > 0.0 and float(move["stride_exp"]) > 0.0, "%s uses the level gait with speed-scaled strides" % SKIN)
	check(float(move["bounce"]) + float(move["rise"]) <= MAX_PP_L * 27.0, "%s's designed bob stays inside the budget (%.1f px)" % [SKIN, float(move["bounce"]) + float(move["rise"])])
	await frames(1)


## 各速度的量測都在門檻內：幅度小、單一頻率、沒有高頻抖動、腳不滑。
func _test_gait_is_smooth() -> void:
	var rig := _make()
	var leg := absf(rig.rest(&"hip").y)
	for speed in SPEEDS:
		var r := LocomotionAudit.measure(rig, speed, RUN_SPEED)
		var label := "%s at %.0f px/s" % [SKIN, speed]
		check(float(r["pp_l"]) <= MAX_PP_L, "%s: the pelvis moves %.3f L peak to peak (limit %.2f)" % [label, r["pp_l"], MAX_PP_L])
		check(float(r["hf"]) <= MAX_HF, "%s: the pelvis motion has no high-frequency shake (%.3f of the energy)" % [label, r["hf"]])
		check(float(r["acc_ratio"]) <= MAX_ACC_RATIO, "%s: the vertical acceleration is %.1fx a pure sine (limit %.1f)" % [label, r["acc_ratio"], MAX_ACC_RATIO])
		check(float(r["frame_step"]) <= MAX_FRAME_STEP_L * leg, "%s: the pelvis changes %.2f px per frame at most" % [label, r["frame_step"]])
		check(float(r["slide_l"]) <= MAX_SLIDE_L, "%s: a planted foot slides %.3f L (limit %.2f)" % [label, r["slide_l"], MAX_SLIDE_L])
		check(float(r["f_main"]) >= MIN_STEP_HZ and float(r["f_main"]) <= MAX_STEP_HZ, "%s: the bob repeats %.2f times a second (one per step)" % [label, r["f_main"]])
		check(float(r["head_pp"]) <= float(r["pp"]) * 1.5 + 0.2, "%s: the head moves no more than the pelvis (%.2f vs %.2f px)" % [label, r["head_pp"], r["pp"]])
	_free(rig)
	await frames(1)


## 慢走的步頻不比全速跑快；速度夠快（走到跑）之後步頻維持在同一個範圍、不隨速度亂跳。
func _test_stride_scales_with_speed() -> void:
	var rig := _make()
	var rates: Array[float] = []
	for speed in [30.0, 60.0, 90.0, 120.0, 150.0]:
		rates.append(float(LocomotionAudit.measure(rig, speed, RUN_SPEED)["f_main"]))
	check(rates[0] < rates[4], "a slow walk steps slower than a full run (%.2f vs %.2f Hz)" % [rates[0], rates[4]])
	for i in range(2, rates.size()):
		check(absf(rates[i] - rates[i - 1]) <= 0.5, "the step rate stays steady once the stride has grown (%.2f → %.2f Hz)" % [rates[i - 1], rates[i]])
	_free(rig)
	await frames(1)
