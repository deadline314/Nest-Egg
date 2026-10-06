class_name LocomotionAudit
extends RefCounted
## 移動動作稽核（開發與測試用）：讓骨架角色以固定速度走／跑一段時間，量出「身體上下抖不抖」的數字。
## 指標與門檻依據 design/12-cast-redraw/LOCOMOTION_REFERENCE.md 第 6 節（業界生物力學數字與我們的建議值）；
## 長度單位 L = 站立時骨盆離地的高度（和那份資料的「腿長」同義），所以不同身高的角色用同一組門檻。
##
## 用法：LocomotionAudit.measure(rig, speed, run_speed) -> Dictionary（見 measure 的說明）。
## 取樣：先跑 WARMUP 秒讓步態穩定，再取 SECONDS 秒，每影格記錄骨盆高度、頭高度與兩隻腳的世界位置。

const DT := 1.0 / 60.0
const WARMUP := 1.5
const SECONDS := 6.0
## 腳底離地不到這麼多像素就算踩地（骨架空間）。
const CONTACT_TOLERANCE := 0.2
## 速度的低通：連續幾格取平均（過濾像素級的雜訊，只看看得見的上下反轉）。
const SMOOTH_FRAMES := 5


## 回傳（Dictionary）：
##   leg        L：站立時骨盆離地高度（像素）
##   pp         骨盆高度的峰谷幅度（像素）　pp_l  同上以 L 為單位
##   f_main     骨盆高度的主頻率（Hz；走路與跑步每步一個週期，所以等於每秒幾步）
##   hf         高於 3 倍主頻率的能量佔總能量的比例（越小越平滑）
##   peak_vel   垂直速度峰值（像素／秒）　peak_acc  垂直加速度峰值（像素／秒²）
##   theory_acc 同幅度同頻率的純正弦加速度峰值　acc_ratio  peak_acc / theory_acc（1＝純正弦）
##   frame_step 單格骨盆高度的最大變化（像素）
##   reversals_per_second  低通後骨盆垂直速度每秒反轉幾次（理想是主頻率的 2 倍：一峰一谷）
##   slide      踩地期間支撐腳在世界座標的最大位移（像素）　slide_l  以 L 為單位
##   head_pp    頭高度的峰谷幅度（像素）
##   samples    取樣格數
static func measure(rig: CharacterRig, speed: float, run_speed: float) -> Dictionary:
	var input := RigInput.new()
	input.facing = 1
	input.on_floor = true
	input.aim_dir = Vector2.RIGHT
	input.two_handed = false
	input.run_speed = run_speed
	for i in int(0.6 / DT):
		rig.animate(DT, input)  # 先站穩
	input.velocity = Vector2(speed, 0.0)
	for i in int(WARMUP / DT):
		rig.animate(DT, input)
	var animator := rig.animator
	var ground := animator.ground_level()
	var body_x := 0.0
	var hips := PackedFloat32Array()
	var heads := PackedFloat32Array()
	var contacts: Array[Dictionary] = [{"on": false, "min": 0.0, "max": 0.0}, {"on": false, "min": 0.0, "max": 0.0}]
	var slide := 0.0
	var count := int(SECONDS / DT)
	for i in count:
		rig.animate(DT, input)
		body_x += speed * DT
		hips.append(animator.bone_pos(&"hip").y)
		if rig.has_bone(&"head"):
			heads.append(animator.bone_pos(&"head").y)
		var feet: Array[StringName] = [&"foot_front", &"foot_back"]
		for f in feet.size():
			var foot := animator.bone_pos(feet[f])
			var world_x := body_x + foot.x
			var on_ground := absf(foot.y - ground) <= CONTACT_TOLERANCE
			var state: Dictionary = contacts[f]
			if on_ground and not state["on"]:
				state["min"] = world_x
				state["max"] = world_x
			elif on_ground:
				state["min"] = minf(state["min"], world_x)
				state["max"] = maxf(state["max"], world_x)
			if on_ground:
				slide = maxf(slide, float(state["max"]) - float(state["min"]))
			state["on"] = on_ground
	var leg := absf(rig.rest(&"hip").y)
	var result := _analyse(hips, speed)
	result["leg"] = leg
	result["pp_l"] = float(result["pp"]) / maxf(0.001, leg)
	result["slide"] = slide
	result["slide_l"] = slide / maxf(0.001, leg)
	result["samples"] = hips.size()
	result["head_pp"] = _peak_to_peak(heads)
	return result


static func _peak_to_peak(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var low := values[0]
	var high := values[0]
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	return high - low


static func _analyse(hips: PackedFloat32Array, speed: float) -> Dictionary:
	var n := hips.size()
	var mean := 0.0
	for v in hips:
		mean += v
	mean /= maxf(1.0, float(n))
	var centred := PackedFloat32Array()
	for v in hips:
		centred.append(v - mean)
	var pp := _peak_to_peak(hips)
	# 離散傅立葉：只算 0.3~12 Hz（每 0.05 Hz 一格），夠找出主頻率與高頻能量。
	var best_f := 0.0
	var best_energy := 0.0
	var total := 0.0
	var spectrum: Array[Vector2] = []
	var f := 0.3
	while f <= 12.0:
		var re := 0.0
		var im := 0.0
		for i in n:
			var a := TAU * f * float(i) * DT
			re += centred[i] * cos(a)
			im += centred[i] * sin(a)
		var energy := re * re + im * im
		spectrum.append(Vector2(f, energy))
		total += energy
		if energy > best_energy:
			best_energy = energy
			best_f = f
		f += 0.05
	var high_energy := 0.0
	for entry in spectrum:
		if entry.x > best_f * 3.0:
			high_energy += entry.y
	# 垂直速度與加速度（有限差分）。
	var peak_vel := 0.0
	var peak_acc := 0.0
	var frame_step := 0.0
	var velocity := PackedFloat32Array()
	for i in range(1, n):
		var step := hips[i] - hips[i - 1]
		frame_step = maxf(frame_step, absf(step))
		velocity.append(step / DT)
		peak_vel = maxf(peak_vel, absf(step / DT))
	for i in range(1, velocity.size()):
		peak_acc = maxf(peak_acc, absf((velocity[i] - velocity[i - 1]) / DT))
	# 低通後的速度反轉次數。
	var reversals := 0
	var last_sign := 0
	for i in range(SMOOTH_FRAMES, velocity.size()):
		var avg := 0.0
		for k in SMOOTH_FRAMES:
			avg += velocity[i - k]
		var s := 1 if avg > 0.0 else -1
		if last_sign != 0 and s != last_sign:
			reversals += 1
		last_sign = s
	var seconds := float(n) * DT
	var theory_acc := 0.5 * pp * pow(TAU * best_f, 2.0)
	return {
		"pp": pp, "f_main": best_f, "hf": high_energy / maxf(0.000001, total),
		"peak_vel": peak_vel, "peak_acc": peak_acc, "theory_acc": theory_acc,
		"acc_ratio": peak_acc / maxf(0.001, theory_acc), "frame_step": frame_step,
		"reversals_per_second": float(reversals) / maxf(0.001, seconds), "speed": speed,
	}
