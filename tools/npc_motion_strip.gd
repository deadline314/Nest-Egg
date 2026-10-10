extends Node2D
## 開發工具：NPC／過場演員的「連續畫面」與動作量測（NE-250）。
## 每格都是同一個角色從 0 秒模擬到該時間點（同一角色的亂數種子固定，所以每格是同一段表演的不同瞬間）。
## 用法：godot --path . res://tools/npc_motion_strip.tscn -- --out=/絕對路徑.png --chars=old_k,mei --script=converse
##   --script=名稱：SCRIPTS 裡的表演腳本（converse 待機→說話→聆聽、sit_cycle 站→坐→站、lean_cycle、wave、idle、
##            cower 聽到槍響縮一下→蹲下抱頭→站起來、greet 工作中抬頭招呼），
##            或 loop:循環名稱[@stand|sit|lean|squat]（工作循環），或 gallery:手勢1,手勢2…（每格一個手勢，停在重音後 0.25 秒，檢查舉手時的接縫）。
##   --frames=格數（預設 10）、--from=第一格的秒數、--step=每格間隔秒數（預設依腳本）、--zoom=放大（預設 2.2＝遊戲；3.4＝過場）、
##   --facing=-1 看左面向、--bright 亮背景。
##   --trace=骨頭@開始秒數（搭配 --metrics）：另外印出該骨頭從開始秒數起 0.4 秒的逐格角度，找跳格的原因。
##   --metrics：不截圖，模擬整段腳本印出量測（跳格、循環重複度、兩人同步度、起身預備），給修前修後比較。

const SCRIPTS := {
	# [開始秒數, 狀態]：狀態是 idle／talk／listen／wave／sit／sit_talk／lean／lean_listen／squat／loop:名稱[@姿勢]
	"converse": {"length": 12.0, "step": 0.4, "from": 0.8, "segments": [[0.0, "idle"], [1.0, "talk"], [6.0, "listen"], [10.0, "idle"]]},
	"talk": {"length": 20.0, "step": 0.2, "from": 2.0, "segments": [[0.0, "idle"], [1.0, "talk"]]},
	"sit_cycle": {"length": 7.0, "step": 0.15, "from": 0.85, "segments": [[0.0, "idle"], [1.0, "sit"], [4.0, "idle"]]},
	"crouch_cycle": {"length": 7.0, "step": 0.15, "from": 0.85, "segments": [[0.0, "idle"], [1.0, "squat"], [4.0, "idle"]]},
	"stand_up": {"length": 5.0, "step": 0.1, "from": 2.9, "segments": [[0.0, "sit"], [3.0, "idle"]]},
	"lean_cycle": {"length": 7.0, "step": 0.2, "from": 0.8, "segments": [[0.0, "idle"], [1.0, "lean"], [4.0, "lean_listen"], [5.5, "idle"]]},
	"wave": {"length": 5.0, "step": 0.15, "from": 0.4, "segments": [[0.0, "idle"], [0.5, "wave"], [3.0, "idle"]]},
	"idle": {"length": 40.0, "step": 3.0, "from": 1.0, "segments": [[0.0, "idle"]]},
	"listen": {"length": 20.0, "step": 1.0, "from": 1.0, "segments": [[0.0, "listen"]]},
	# NE-240：聽到槍響縮一下、再兩聲蹲下抱頭、安靜後站起來回去工作（cue:手勢＝在那個時間點做指定手勢）
	"cower": {"length": 9.0, "step": 0.5, "from": 0.6, "segments": [[0.0, "loop:wipe_hands"], [1.0, "cue:flinch"], [2.4, "squat"], [2.4, "cue:cover_head"], [6.0, "cue:release"], [6.0, "loop:wipe_hands"]]},
	"greet": {"length": 4.0, "step": 0.15, "from": 0.9, "segments": [[0.0, "loop:wipe_hands"], [1.0, "cue:greet"]]},
}
const METRIC_BONES: Array[StringName] = [&"head", &"neck", &"chest", &"arm_front_upper", &"arm_front_lower", &"hand_front", &"arm_back_upper", &"arm_back_lower", &"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"]
const DT := 1.0 / 60.0

var _out := ""
var _chars: PackedStringArray = ["old_k"]
var _script_name := "converse"
var _frames := 10
var _from := -1.0
var _step := -1.0
var _zoom := 2.2
var _facing := 1
var _bright := false
var _metrics := false
var _trace := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--chars="):
			_chars = arg.trim_prefix("--chars=").split(",", false)
		elif arg.begins_with("--script="):
			_script_name = arg.trim_prefix("--script=")
		elif arg.begins_with("--frames="):
			_frames = clampi(int(arg.trim_prefix("--frames=")), 1, 16)
		elif arg.begins_with("--from="):
			_from = float(arg.trim_prefix("--from="))
		elif arg.begins_with("--step="):
			_step = float(arg.trim_prefix("--step="))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--facing="):
			_facing = -1 if int(arg.trim_prefix("--facing=")) < 0 else 1
		elif arg == "--bright":
			_bright = true
		elif arg.begins_with("--trace="):
			_trace = arg.trim_prefix("--trace=")
		elif arg == "--metrics":
			_metrics = true
	var script := _script_def()
	if script.is_empty():
		push_error("[npc_motion_strip] --script=%s 不存在，可用：%s 或 loop:名稱[@姿勢]" % [_script_name, ", ".join(SCRIPTS.keys())])
		get_tree().quit(1)
		return
	if _metrics:
		_print_metrics(script)
		get_tree().quit()
		return
	_build_strip(script)


## 腳本定義；loop:名稱[@姿勢] 產生一段 12 秒的工作循環；gallery:… 是待機 1.5 秒（各格另外指定手勢）。
func _script_def() -> Dictionary:
	if _script_name.begins_with("gallery:"):
		return {"length": 3.0, "step": 0.0, "from": 0.0, "segments": [[0.0, "idle"]]}
	if _script_name.begins_with("loop:"):
		return {"length": 12.0, "step": 0.2, "from": 2.0, "segments": [[0.0, _script_name]]}
	return SCRIPTS.get(_script_name, {})


## 時間 t 的狀態寫進 input。
static func apply_state(input: RigInput, script: Dictionary, t: float, facing: int) -> void:
	var state := "idle"
	for segment: Array in script["segments"]:
		if t >= float(segment[0]) and not str(segment[1]).begins_with("cue:"):
			state = str(segment[1])
	input.facing = facing
	input.aim_dir = Vector2(float(facing), 0.0)
	input.on_floor = true
	input.velocity = Vector2.ZERO
	input.two_handed = false
	input.npc_pose = &"stand"
	input.npc_loop = &""
	input.talking = false
	input.listening = false
	input.waving = false
	match state:
		"talk":
			input.talking = true
		"listen":
			input.listening = true
		"wave":
			input.waving = true
		"sit":
			input.npc_pose = &"sit"
		"sit_talk":
			input.npc_pose = &"sit"
			input.talking = true
		"lean":
			input.npc_pose = &"lean"
		"lean_listen":
			input.npc_pose = &"lean"
			input.listening = true
		"squat":
			input.npc_pose = &"crouch"
	if state.begins_with("loop:"):
		var spec := state.trim_prefix("loop:").split("@")
		input.npc_loop = StringName(spec[0])
		if spec.size() > 1:
			input.npc_pose = &"crouch" if spec[1] == "squat" else StringName(spec[1])


func _new_rig(parent: Node, skin: String) -> CharacterRig:
	var rig := CharacterRig.new()
	parent.add_child(rig)
	if not rig.setup(skin, "npc"):
		push_error("[npc_motion_strip] 角色不存在：%s" % skin)
		return null
	rig.set_weapon("")
	return rig


func _simulate(rig: CharacterRig, input: RigInput, script: Dictionary, until: float) -> void:
	var t := 0.0
	while t < until - 0.0001:
		apply_state(input, script, t, _facing)
		_cue(rig, script, t)
		rig.animate(DT, input)
		t += DT


## 腳本裡 cue:手勢 的時間點到了就讓角色做那個手勢。
static func _cue(rig: CharacterRig, script: Dictionary, t: float) -> void:
	for segment: Array in script["segments"]:
		var state := str(segment[1])
		if state.begins_with("cue:") and t >= float(segment[0]) and t - DT < float(segment[0]) and rig.animator is NpcAnimator:
			if state == "cue:release":
				(rig.animator as NpcAnimator).release_gesture()
			else:
				(rig.animator as NpcAnimator).play_gesture(StringName(state.trim_prefix("cue:")))


# ---------------------------------------------------------------------------
# 連續畫面

func _build_strip(script: Dictionary) -> void:
	var start := _from if _from >= 0.0 else float(script["from"])
	var step := _step if _step > 0.0 else float(script["step"])
	var rows := mini(_chars.size(), 3)
	var cell := 640.0 / float(_frames)
	var row_h := 360.0 / float(rows)
	RenderingServer.set_default_clear_color(Color("c9ccd2") if _bright else Color("10141c"))
	for row in rows:
		var floor_y := row_h * (row + 1) - 14.0
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(0, floor_y), Vector2(640, floor_y)])
		line.width = 1.0
		line.default_color = Color("2a3446")
		add_child(line)
		for i in _frames:
			var t := start + step * i
			var gallery := _script_name.trim_prefix("gallery:").split(",", false) if _script_name.begins_with("gallery:") else PackedStringArray()
			var holder := Node2D.new()
			holder.position = Vector2(cell * (i + 0.5), floor_y)
			holder.scale = Vector2.ONE * _zoom
			add_child(holder)
			var rig := _new_rig(holder, _chars[row])
			if rig == null:
				continue
			var input := RigInput.new()
			if i < gallery.size():
				_simulate(rig, input, script, 1.5)
				if not (rig.animator as NpcAnimator).play_gesture(StringName(gallery[i])):
					push_error("[npc_motion_strip] 手勢不存在或這個姿勢不能用：%s" % gallery[i])
				_simulate(rig, input, script, _gesture_peak(gallery[i]))
			elif not gallery.is_empty():
				holder.queue_free()
				continue
			else:
				_simulate(rig, input, script, t)
			var label := Label.new()
			label.text = gallery[i] if i < gallery.size() else "%.2fs" % t
			label.position = Vector2(cell * i + 2, floor_y + 1)
			label.add_theme_font_size_override("font_size", 8)
			add_child(label)
	for spot: Vector2 in [Vector2(160, 40), Vector2(480, 40), Vector2(320, 200)]:
		var light := LightKit.create_point_light(Color("f0f4ff"), 900.0, 0.75 if _bright else 0.6)
		light.position = spot
		add_child(light)
	if not _out.is_empty():
		_capture.call_deferred()


## 手勢準備＋重音之後 0.25 秒（停留中）的秒數。
func _gesture_peak(gesture_name: String) -> float:
	var def: Variant = (RigLibrary.load_json(NpcAnimator.DATA_PATH).get("gestures", {}) as Dictionary).get(gesture_name, {})
	var times: Dictionary = (def as Dictionary).get("time", {}) if typeof(def) == TYPE_DICTIONARY else {}
	return float(times.get("wind", 0.08)) + float(times.get("prep", 0.24)) + float(times.get("stroke", 0.14)) + 0.25


func _capture() -> void:
	for i in 3:
		await get_tree().process_frame
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	image.save_png(_out)
	print("saved ", _out)
	get_tree().quit()


# ---------------------------------------------------------------------------
# 量測

func _print_metrics(script: Dictionary) -> void:
	var traces: Array[Dictionary] = []
	for skin in _chars:
		var rig := _new_rig(self, skin)
		if rig == null:
			continue
		traces.append(record(rig, script, _facing))
		rig.queue_free()
	if not _trace.is_empty() and not traces.is_empty():
		var spec := _trace.split("@")
		var values: Array[float] = traces[0].get(StringName(spec[0]), [] as Array[float])
		var from := int(float(spec[1]) / DT) if spec.size() > 1 else 0
		print("NPC_TRACE ", _chars[0], " ", spec[0], " ", values.slice(from, from + int(0.4 / DT)).map(func(v: float) -> float: return snappedf(v, 0.001)))
	var report := {}
	for i in traces.size():
		report[_chars[i]] = summarize(traces[i], script)
	if traces.size() >= 2:
		report["sync_arm"] = correlation(_talk_slice(traces[0]["arm_front_upper"], script), _talk_slice(traces[1]["arm_front_upper"], script))
	print("NPC_METRICS ", JSON.stringify(report))


## 整段腳本每格的骨頭角度與骨盆位置。
static func record(rig: CharacterRig, script: Dictionary, facing := 1) -> Dictionary:
	var input := RigInput.new()
	var trace: Dictionary = {"hip_y": [] as Array[float]}
	for bone_name in METRIC_BONES:
		trace[bone_name] = [] as Array[float]
	var t := 0.0
	while t < float(script["length"]):
		apply_state(input, script, t, facing)
		_cue(rig, script, t)
		rig.animate(DT, input)
		for bone_name in METRIC_BONES:
			var bone := rig.bone(bone_name)
			(trace[bone_name] as Array[float]).append(bone.rotation if bone != null else 0.0)
		var hip := rig.bone(&"hip")
		(trace["hip_y"] as Array[float]).append(hip.position.y if hip != null else 0.0)
		t += DT
	return trace


## 量測摘要：pop＝骨頭角度的最大二階差分（rad／格²，越大越像跳格；略過開頭 0.5 秒）、repeat＝說話時前臂上段 0.5～4 秒延遲的最大自相關（越接近 1 越像固定循環）、
## arm_range＝說話時前臂上段的擺動範圍（rad）、same_pair／same_corr＝動作最像的兩根骨頭與相關係數。
static func summarize(trace: Dictionary, script: Dictionary) -> Dictionary:
	var pop := 0.0
	var pop_at := ""
	for bone_name in METRIC_BONES:
		var values: Array[float] = trace[bone_name]
		for i in range(int(0.5 / DT), values.size()):  # 前 0.5 秒是從零開始的初始化，不算
			var acc := absf(values[i] - 2.0 * values[i - 1] + values[i - 2])
			if acc > pop:
				pop = acc
				pop_at = "%s@%.2fs" % [bone_name, i * DT]
	# 兩根骨頭的動作最像的一對（絕對相關係數；接近 1＝兩根骨頭一起動，像機器）
	var pair := ""
	var worst := 0.0
	var names: Array[StringName] = [&"chest", &"head", &"arm_front_upper", &"arm_front_lower", &"arm_back_upper"]
	for i in names.size():
		for j in range(i + 1, names.size()):
			var c := absf(correlation(trace[names[i]], trace[names[j]]))
			if c > worst:
				worst = c
				pair = "%s~%s" % [names[i], names[j]]
	var arm := _talk_slice(trace["arm_front_upper"], script)
	return {"pop": snappedf(pop, 0.0001), "pop_at": pop_at, "repeat": snappedf(autocorr_peak(arm, 0.5, 4.0), 0.001),
			"arm_range": snappedf(_range(arm), 0.001), "same_pair": pair, "same_corr": snappedf(worst, 0.001)}


## 腳本裡第一段說話的資料（沒有說話就回傳空陣列）。
static func _talk_slice(values: Array[float], script: Dictionary) -> Array[float]:
	var segments: Array = script["segments"]
	for i in segments.size():
		if str(segments[i][1]) in ["talk", "sit_talk"]:
			var a := int((float(segments[i][0]) + 1.0) / DT)
			var b := int(float(segments[i + 1][0]) / DT) if i + 1 < segments.size() else values.size()
			return values.slice(clampi(a, 0, values.size()), clampi(b, 0, values.size()))
	return [] as Array[float]


## 自相關在延遲 lo～hi 秒之間的最大值（去平均、正規化）。固定週期的正弦會接近 1。
static func autocorr_peak(values: Array[float], lo: float, hi: float) -> float:
	var n := values.size()
	if n < 10:
		return 0.0
	var mean := 0.0
	for v in values:
		mean += v
	mean /= n
	var energy := 0.0
	for v in values:
		energy += (v - mean) * (v - mean)
	if energy <= 0.000001:
		return 0.0
	var best := -1.0
	for lag in range(int(lo / DT), mini(int(hi / DT), n / 2)):
		var s := 0.0
		for i in n - lag:
			s += (values[i] - mean) * (values[i + lag] - mean)
		best = maxf(best, s / energy * float(n) / float(n - lag))
	return best


static func correlation(a: Array[float], b: Array[float]) -> float:
	var n := mini(a.size(), b.size())
	if n < 10:
		return 0.0
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
	return snappedf(sab / sqrt(maxf(saa * sbb, 0.0000001)), 0.001)


static func _range(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	return values.max() - values.min()
