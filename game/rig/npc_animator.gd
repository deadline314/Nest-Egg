class_name NpcAnimator
extends HumanoidAnimator
## NPC 動畫器：不戰鬥的人物。待機時雙手自然下垂（不舉槍）、呼吸；可以坐、靠牆、蹲；說話時點頭與手勢，聆聽時微微偏頭，揮手；
## 每個角色可以有專屬的工作循環（攪鍋、敲打、打字…）。全部由資料驅動（art/rigs/npc_animations.json），沒有動畫程式要改。
##
## 沿用 HumanoidAnimator 的骨架計算、彈簧骨（頭髮、衣襬）與套用流程，只換掉「目標角度怎麼算」：
## 角色在走、跑、跳、蹲、格擋、倒下、持武器或瞄準時，仍交給人形動畫器處理（過場裡的演員常常這樣用）。

## 遠側手臂的姿勢角度在這個範圍內算「垂著」（弧度）。
const FAR_ARM_HANGING := 0.4
const DATA_PATH := "res://art/rigs/npc_animations.json"
const FADE_SPEED := 5.0
const GATE_EDGE := 0.25
## 工作循環開始、停止的淡入淡出秒數。
const LOOP_FADE := 0.45
## 姿勢切換沒有寫在 transitions 時的預設秒數。
const DEFAULT_TRANSITION := 0.45
## 姿勢下沉與搆腳下沉交叉時的圓滑寬度（腿長的比例）。
const SAG_BLEND := 0.012
## 骨盆下沉接近上限時的圓滑寬度（像素）。
const SHIFT_CAP_BLEND := 3.0
## 起身時腳收回到身體下方所用的進度（前 55%，比骨盆升起早）。
const FEET_TUCK := 0.55
## 站→坐開頭把腳的 IK 淡入、坐→站做完之後把腳的 IK 淡掉的秒數（快的角色也不少於這個時間，否則換腳的那幾格會跳）。
const HANDOFF_TIME := 0.3
## 沒有資料時的站姿交接（腳在骨盆下、膝微彎）。
## reach 不能接近 1：腿接近打直時兩骨 IK 的膝角對高度是平方根關係，骨盆緩停時膝蓋仍等速伸直再突然停住（跳格）；
## 交接時膝蓋保留一點彎曲，最後的伸直交給 IK→站姿的緩入緩出。
const DEFAULT_HANDOFF := {"x": [0.1, -0.15], "sag": 0.0, "reach": 0.99}

## 資料裡所有工作循環的名稱（驗證 NPC 資料用）。
static func loop_names() -> PackedStringArray:
	var names := PackedStringArray()
	var loops: Variant = RigLibrary.load_json(DATA_PATH).get("loops", {})
	if typeof(loops) == TYPE_DICTIONARY:
		for key: Variant in (loops as Dictionary).keys():
			names.append(str(key))
	return names


static var _reported: Dictionary[String, bool] = {}

var _use_npc := false
## 姿勢資料的 feet（腳踩實地）：目前姿勢的、最後一個有效的（淡出時還要用）、與淡入淡出的權重。
var _feet_last: Dictionary = {}
var _feet_w := 0.0
var _w_talk := 0.0
var _w_listen := 0.0
var _w_wave := 0.0
## 生命感層（NE-206）：飄動、呼吸變化、重心轉移、轉頭、說話的手勢與彈簧餘勢。第一次用到才建立。
var _life: NpcLife
var _breath_phase := 0.0
## 姿勢切換（NE-250）：目前的姿勢、切換的進度與資料、切換起點（上一格混合後的基本姿勢）與目前混合的結果。
var _pose_now := &""
var _pose_before := &""  # 過渡的前半段還顯示這個姿勢的零件
var _parts_pose := &""  # 目前顯示的是哪個姿勢的專屬零件
var _trans_t := -1.0
var _trans_def: Dictionary = {}
var _from_base: Dictionary = {}
var _base_now: Dictionary = {}
var _feet_from: Dictionary = {}
var _feet_to: Dictionary = {}
var _feet_weight := 0.0
## 坐↔站切換中，站姿交接位置的「搆腳下沉」佔多少（0＝純姿勢、1＝完全是交接位置）：讓骨盆高度平順地收斂到交接位置。
var _feet_floor := 0.0
var _posture_u := 1.0
var _feet_floor_def: Dictionary = {}
## 工作循環：目前播放的循環、淡入淡出權重、累計圈數（小數＝圈內進度）與這一圈的長度、幅度倍率（每圈略有不同）。
var _loop_name := &""
var _w_loop := 0.0
var _loop_u := 0.0
var _loop_cycle := -1
var _cycle_period := 1.0
var _cycle_amp := 1.0


func _body_pose(delta: float, input: RigInput, v: Vector2, aim_angle: float) -> Dictionary:
	_use_npc = _is_npc_state(input)
	if not _use_npc:
		_show_pose_parts(&"")
		return super._body_pose(delta, input, v, aim_angle)
	var data := RigLibrary.load_json(DATA_PATH)
	var pose: Dictionary = {}
	for bone_name in _rig.bone_order():
		pose[bone_name] = 0.0
	# 手的貼圖朝 +X 畫：先轉到順著前臂，姿勢與循環的手部角度再疊上去。
	for hand_bone: StringName in [&"hand_front", &"hand_back"]:
		if pose.has(hand_bone):
			pose[hand_bone] = HAND_FOLLOWS_FOREARM
	var mine: Dictionary = _motion["npc"]  # 這個角色自己的站姿微調與說話的速度、幅度
	if _life == null:
		_life = NpcLife.new()
		var life_defaults: Variant = data.get("life", {})
		var gestures: Variant = data.get("gestures", {})
		_life.setup(_rig.skin_id, life_defaults if typeof(life_defaults) == TYPE_DICTIONARY else {}, mine.get("life", {}),
				gestures if typeof(gestures) == TYPE_DICTIONARY else {})
	# 基本姿勢：切換時有預備動作（例如起身前上身先前傾）與緩入緩出，不是瞬間換或等速滑過去。
	_step_posture(data, mine, input.npc_pose, delta)
	_show_pose_parts(_pose_now if posture_progress() >= 0.5 else _pose_before)
	for key: StringName in _base_now.keys():
		pose[key] = float(pose.get(key, 0.0)) + float(_base_now[key])
	# 這個姿勢的遠側手臂只是垂著（上臂、前臂都接近垂直）：改用這副骨架量出來的藏手角度，手才不會從髖前緣探出來（NE-222）。
	if _far_arm_tuck.is_finite() and absf(float(pose.get(&"arm_back_upper", 1.0))) < FAR_ARM_HANGING and absf(float(pose.get(&"arm_back_lower", 1.0))) < FAR_ARM_HANGING:
		pose[&"arm_back_upper"] = _far_arm_tuck.x
		pose[&"arm_back_lower"] = _far_arm_tuck.y
	# 生命感：緩慢飄動、重心轉移、轉頭看一下、呼吸速率變化與嘆氣、說話前吸氣與重音手勢、聆聽點頭、小動作。
	var busy := input.waving or _loop_name != &"" or input.npc_loop != &""
	var life := _life.step(delta, {"posture": input.npc_pose, "talking": input.talking, "listening": input.listening, "busy": busy,
			"thigh": _rig.rest(&"leg_front_lower").length()})
	_add_bones(pose, life["bones"], 1.0)
	pose[&"_hip_x"] = float(pose[&"_hip_x"]) + float(life["hip_x"])
	pose[&"_hip_y"] = float(pose[&"_hip_y"]) + float(life["hip_y"])
	# 呼吸：吸氣短、呼氣長（約 4：6），胸口與骨盆微微起伏（速率會緩慢變化，偶爾較深）。
	var idle: Dictionary = _motion["idle"]
	_breath_phase += delta * float(idle["breath_speed"]) * float(life["breath_rate"])
	var breath := breath_curve(fmod(_breath_phase / TAU, 1.0))
	pose[&"chest"] = float(pose.get(&"chest", 0.0)) + breath * (1.0 + float(life["breath_extra"])) * float(idle["breath_amp"])  # 嘆氣只讓胸口起伏更深，骨盆不跟著動（腳才不會被帶著上下）
	pose[&"_hip_y"] = float(pose[&"_hip_y"]) + breath * float(idle["hip_bob"])
	# 專屬工作循環：開始與停止淡入淡出；換循環時先淡出舊的再淡入新的。
	_step_loop(data, input, pose, delta)
	# 說話、聆聽、揮手：緩入緩出地疊上去。
	var step := FADE_SPEED * delta
	_w_talk = move_toward(_w_talk, 1.0 if input.talking else 0.0, step)
	_w_listen = move_toward(_w_listen, 1.0 if input.listening and not input.talking else 0.0, step)
	_w_wave = move_toward(_w_wave, 1.0 if input.waving else 0.0, step * 0.7)
	for entry: Array in [["talk", _w_talk], ["listen", _w_listen], ["wave", _w_wave]]:
		var weight: float = NpcGesture._smooth(entry[1])
		if weight <= 0.0:
			continue
		var overlay := _entry(data, "overlays", entry[0], "")
		var talking: bool = entry[0] == "talk"
		_add_bones(pose, overlay.get("bones", {}), weight)
		_add_tracks(pose, overlay.get("tracks", []), weight * (float(mine["talk_amp"]) if talking else 1.0), 1.0, float(mine["talk_speed"]) if talking else 1.0)
	# 餘勢與過衝：頭、軀幹、前臂追目標角度時帶一點彈性。
	for bone_name: StringName in pose.keys():
		if not String(bone_name).begins_with("_"):
			pose[bone_name] = _life.follow(bone_name, float(pose[bone_name]), delta)
	return pose


## 提早結束指定的手勢（例如蹲下抱頭之後站起來）：從目前位置平順收回。
func release_gesture() -> void:
	if _life != null:
		_life.release_cue()


## 姿勢切換的進度（0~1，主要動作的緩動後進度；沒有在切換時是 1）。過場演員從座位起身時，用它讓身體落回地面與起身同步。
func posture_progress() -> float:
	return _posture_u if _trans_t >= 0.0 else 1.0


## 讓這個 NPC 做一個指定的手勢或小動作（art/rigs/npc_animations.json 的 gestures）；還沒開始動畫、手勢不存在或姿勢不允許時回傳 false。
func play_gesture(gesture_name: StringName) -> bool:
	if _life == null:
		return false
	return _life.play_gesture(gesture_name, _pose_now if _pose_now != &"" else &"stand")


## 腳踩實地：姿勢資料有 feet 時，兩隻腳用 IK 平放在地面上（腳掌放平），骨盆下沉讓腿彎起來（不靠手調骨盆高度），
## 坐、蹲才不會懸空或陷進地面。所有數字都是比例，不同身高、腿長的骨架共用同一份資料：
## feet：{"x": [前腳, 後腳]（相對骨盆的前後位置，單位＝大腿長）, "sag": 骨盆下沉（單位＝髖到踝的腿長）, "reach": 腿伸展上限比例（預設 0.98）}。
## 姿勢切換時用權重淡入淡出。
func _post_pose(delta: float, _input: RigInput) -> void:
	# NPC 姿勢中直接用切換算好的權重（已是平順曲線）；離開 NPC 狀態（開始走、拿武器）時才用固定速度淡出。
	_feet_w = _feet_weight if _use_npc else move_toward(_feet_w, 0.0, FADE_SPEED * delta)
	if _use_npc and not _feet_to.is_empty():
		_feet_last = _feet_to
	if _feet_w <= 0.001 or _feet_last.is_empty():
		return
	_feet_placed = true
	var thigh := _rig.rest(&"leg_front_lower").length()
	var xs: Variant = _feet_last.get("x", [0.0, 0.0])
	var offsets: Array[Vector2] = []
	var angles: Array[float] = []
	for i in LEG_CHAINS.size():
		var ratio := float((xs as Array)[i]) if typeof(xs) == TYPE_ARRAY and (xs as Array).size() > i else 0.0
		offsets.append(Vector2(ratio * thigh, 0.0))
		angles.append(0.0)
	var reach_ratio := float(_feet_last.get("reach", 0.98))
	var sag := float(_feet_last.get("sag", 0.0)) * _leg_length
	# _place_feet 取「姿勢下沉」與「腳搆得到目標所需的下沉」較大的一個；起身時兩者交叉會讓骨盆突然停住（折角）。
	# 這裡先用平滑的最大值，交叉處圓滑過渡（_place_feet 是主角也用的共用流程，不改它）。
	var reach := _leg_length * reach_ratio
	# 坐↔站：骨盆高度往交接位置自己的「搆腳下沉」收斂（兩條曲線在速度為零處相會，不會在交會點急停）
	if _feet_floor > 0.0:
		var floor_reach := _leg_length * _num(_feet_floor_def, "reach", 0.99)
		var floor_x: Variant = _feet_floor_def.get("x", [0.0, 0.0])
		var floor_need := 0.0
		for i in 2:
			var ratio := float((floor_x as Array)[i]) if typeof(floor_x) == TYPE_ARRAY and (floor_x as Array).size() > i else 0.0
			floor_need = maxf(floor_need, _leg_length - sqrt(maxf(0.0, floor_reach * floor_reach - pow(ratio * thigh, 2.0))))
		sag += floor_need * _feet_floor
	for offset in offsets:
		var need := _leg_length - sqrt(maxf(0.0, reach * reach - offset.x * offset.x))
		sag = _smooth_max(sag, need, SAG_BLEND * _leg_length)
	# 深蹲會碰到共用的下沉上限 GROUND_MAX_SHIFT：硬夾的話起身時骨盆要等下沉低於上限才突然開始動，這裡先平滑地靠近上限
	sag = _soft_cap(sag, GROUND_MAX_SHIFT - 0.25, SHIFT_CAP_BLEND)
	if _feet_w >= 1.0 or not _use_npc:
		_place_feet(offsets, angles, _feet_w, sag, reach_ratio, true)
		return
	# IK 只佔一部分（坐、蹲的開頭淡入，或起身最後交還給站姿）：骨盆高度在「站姿自己貼地的高度」與「IK 的下沉」之間按權重內插，
	# 而不是把下沉乘上權重——那會讓骨盆升高、IK 腿被拉直到奇異點而跳格。站姿貼地高度在 IK 之前用原本的腿算（不會互相影響）。
	var planted := clampf(_ground_y - _lowest_foot_y(), -GROUND_MAX_SHIFT, GROUND_MAX_SHIFT)
	_place_feet(offsets, angles, _feet_w, sag, reach_ratio, false)
	var shift := lerpf(planted, _ground_shift, _feet_w)
	var hip := _rig.bone(&"hip")
	if hip != null:
		hip.position.y += shift - _ground_shift  # 只移骨盆（_apply_body 會把 IK 解好的腿蓋回原本角度）
	_ground_shift = shift
	_forward_kinematics()


static func _smoother(u: float) -> float:
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


## 軟上限：低於 cap − width 時原樣不變，之上以指數平順地靠近 cap（一階連續，永遠不超過 cap）。
static func _soft_cap(x: float, cap: float, width: float) -> float:
	var knee := cap - width
	return x if x <= knee else cap - width * exp(-(x - knee) / width)


## 平滑的最大值：a、b 差距遠大於 width 時就是 max，接近時圓滑過渡。
static func _smooth_max(a: float, b: float, width: float) -> float:
	return (a + b + sqrt((a - b) * (a - b) + width * width)) * 0.5


## 推進姿勢切換一格，結果放在 _base_now（骨頭角度與 _hip_x／_hip_y）、_feet_to／_feet_weight（腳踩實地的參數與權重）。
## 切換資料（npc_animations.json 的 transitions，鍵是「舊>新」，找不到用 default）：time 秒數、delay 主要動作延後開始的比例
## （先做預備再動）、peak 預備動作最大的時間點（0~1）、lead 預備動作的骨頭增量（例如起身前上身前傾）。
## 角色自己的 npc.life.posture：speed（>1 換得快）、lead（預備動作的幅度倍率）。中途再換姿勢時從目前混合的樣子接著換，不跳格。
## 有專屬零件的姿勢（坐下時的臀與大腿是另外畫的一塊）在過渡過半時換上；這個外觀沒有那一組就用平常的零件。
func _show_pose_parts(posture: StringName) -> void:
	if posture == _parts_pose:
		return
	_parts_pose = posture
	_rig.set_pose_parts(posture if _rig.has_pose_parts(posture) else &"")


func _step_posture(data: Dictionary, mine: Dictionary, posture: StringName, delta: float) -> void:
	var target_def := _entry(data, "poses", str(posture), "stand")
	var target := _base_of(target_def, mine, posture)
	var target_feet := _feet_of(target_def)
	if _pose_now == &"":
		_pose_now = posture
		_base_now = target
		_feet_to = target_feet
		_feet_weight = 0.0 if target_feet.is_empty() else 1.0
		return
	if posture != _pose_now:
		_trans_def = _transition_of(data, _pose_now, posture)
		_from_base = _base_now.duplicate()
		_feet_from = _feet_to if _feet_weight > 0.0 else {}
		_pose_before = _pose_now
		_pose_now = posture
		_trans_t = 0.0
	if _trans_t < 0.0:
		_feet_floor = 0.0
		_base_now = target
		_feet_to = target_feet
		_feet_weight = 0.0 if target_feet.is_empty() else 1.0
		return
	var tune := _life.section("posture")
	var speed := clampf(_num(tune, "speed", 1.0), 0.3, 3.0)
	var duration := maxf(0.1, _num(_trans_def, "time", DEFAULT_TRANSITION)) / speed
	_trans_t += delta
	var raw := clampf(_trans_t / duration, 0.0, 1.0)
	var delay := clampf(_num(_trans_def, "delay", 0.0), 0.0, 0.8)
	# smootherstep：起止的加速度也是 0（C2），收尾更柔和；骨盆接近站直時 IK 膝角對高度很敏感，需要這種收尾
	var u := _smoother(clampf((raw - delay) / (1.0 - delay), 0.0, 1.0))
	_posture_u = u
	var peak := clampf(_num(_trans_def, "peak", 0.4), 0.05, 0.95)
	var lead_w := NpcGesture._smooth(raw / peak) if raw < peak else 1.0 - NpcGesture._smooth((raw - peak) / (1.0 - peak))
	lead_w *= clampf(_num(tune, "lead", 1.0), 0.0, 2.0)
	var blended: Dictionary = {}
	for key: Variant in _from_base.keys():
		blended[key] = float(_from_base[key]) * (1.0 - u)
	for key: Variant in target.keys():
		blended[key] = float(blended.get(key, 0.0)) + float(target[key]) * u
	var lead: Variant = _trans_def.get("lead", {})
	if typeof(lead) == TYPE_DICTIONARY:
		for key: Variant in (lead as Dictionary).keys():
			var bone_name := StringName(str(key))
			if (blended.has(bone_name) or _rig.bone(bone_name) != null) and typeof(lead[key]) in [TYPE_INT, TYPE_FLOAT]:
				blended[bone_name] = float(blended.get(bone_name, 0.0)) + float(lead[key]) * lead_w
	_base_now = blended
	# 腳踩實地：兩個姿勢都有就內插參數。只有一邊有時（坐↔站）不能只淡化 IK 權重——骨盆升高時腳搆不到目標，
	# 膝蓋會沿著 acos 的奇異點突然打直（跳格）。改成把腳的目標平順地移到「站姿交接」位置（腳在骨盆下、膝微彎，與站姿一致），
	# 兩邊一致之後才用 HANDOFF_TIME 秒把 IK 關掉。
	var handoff := _feet_handoff(data)
	_feet_floor = 0.0
	_feet_floor_def = handoff
	if not _feet_from.is_empty() and not target_feet.is_empty():
		_feet_to = _lerp_feet(_feet_from, target_feet, u)
		_feet_weight = 1.0
	elif not target_feet.is_empty():
		_feet_to = _lerp_feet(handoff, target_feet, u)
		_feet_weight = NpcGesture._smooth(clampf(_trans_t / minf(HANDOFF_TIME, duration * 0.5), 0.0, 1.0))
		_feet_floor = 1.0 - u
	elif not _feet_from.is_empty():
		# 起身：主要動作做完（腿已是站姿）之後，再用 HANDOFF_TIME 秒把 IK 淡掉，此時 IK 與站姿幾乎一樣，不會跳
		# 先把腳收回到身體下方（前半段），骨盆再升起：腳的目標才不會超出腿長
		_feet_to = _lerp_feet(_feet_from, handoff, u, NpcGesture._smooth(clampf(raw / FEET_TUCK, 0.0, 1.0)))
		_feet_weight = 1.0 - NpcGesture._smooth(clampf((_trans_t - duration) / HANDOFF_TIME, 0.0, 1.0))
		_feet_floor = u
	else:
		_feet_to = {}
		_feet_weight = 0.0
	if raw >= 1.0 and (_feet_from.is_empty() or not target_feet.is_empty() or _trans_t >= duration + HANDOFF_TIME):
		_trans_t = -1.0


## 姿勢資料的骨頭角度加上 _hip_x／_hip_y；站姿再加上這個角色自己的站姿微調。
func _base_of(def: Dictionary, mine: Dictionary, posture: StringName) -> Dictionary:
	var base: Dictionary = {&"_hip_x": _num(def, "hip_x", 0.0), &"_hip_y": _num(def, "hip_y", 0.0)}
	for source: Variant in [def.get("bones", {}), mine.get("stand", {}) if posture == &"stand" else {}]:
		if typeof(source) != TYPE_DICTIONARY:
			continue
		for key: Variant in (source as Dictionary).keys():
			var bone_name := StringName(str(key))
			if _rig.bone(bone_name) == null:
				if not _warned("bone:" + str(key)):
					push_error("[NpcAnimator] %s：動畫資料裡的骨頭不存在：%s" % [DATA_PATH, key])
				continue
			base[bone_name] = float(base.get(bone_name, 0.0)) + _num(source, key, 0.0)
	return base


## 站姿交接的腳參數：poses.stand.feet_handoff（與 feet 同格式），沒有或格式錯誤時用 DEFAULT_HANDOFF。
func _feet_handoff(data: Dictionary) -> Dictionary:
	var stand: Variant = (data.get("poses", {}) as Dictionary).get("stand", {}) if typeof(data.get("poses", {})) == TYPE_DICTIONARY else {}
	var handoff: Variant = (stand as Dictionary).get("feet_handoff", {}) if typeof(stand) == TYPE_DICTIONARY else {}
	return handoff if typeof(handoff) == TYPE_DICTIONARY and not (handoff as Dictionary).is_empty() else DEFAULT_HANDOFF


func _feet_of(def: Dictionary) -> Dictionary:
	var feet: Variant = def.get("feet", {})
	return feet if typeof(feet) == TYPE_DICTIONARY else {}


## 兩組腳參數內插；u_x ≥ 0 時腳的前後位置用自己的進度（起身時腳先收回）。
func _lerp_feet(a: Dictionary, b: Dictionary, u: float, u_x := -1.0) -> Dictionary:
	var ux := u if u_x < 0.0 else u_x
	var xa: Variant = a.get("x", [0.0, 0.0])
	var xb: Variant = b.get("x", [0.0, 0.0])
	var xs: Array = []
	for i in 2:
		var va := float((xa as Array)[i]) if typeof(xa) == TYPE_ARRAY and (xa as Array).size() > i else 0.0
		var vb := float((xb as Array)[i]) if typeof(xb) == TYPE_ARRAY and (xb as Array).size() > i else 0.0
		xs.append(lerpf(va, vb, ux))
	return {"x": xs, "sag": lerpf(_num(a, "sag", 0.0), _num(b, "sag", 0.0), u), "reach": lerpf(_num(a, "reach", 0.98), _num(b, "reach", 0.98), u)}


func _transition_of(data: Dictionary, from: StringName, to: StringName) -> Dictionary:
	var group: Variant = data.get("transitions", {})
	if typeof(group) != TYPE_DICTIONARY:
		return {}
	for key: String in ["%s>%s" % [from, to], "default"]:
		if (group as Dictionary).has(key) and typeof((group as Dictionary)[key]) == TYPE_DICTIONARY:
			return (group as Dictionary)[key]
	return {}


## 工作循環：開始、停止各用 LOOP_FADE 秒緩入緩出；換成另一個循環時先把舊的淡出。
## 循環資料可以有 period（一圈秒數）與 vary（每圈長度與幅度的隨機變化比例，例如 0.12＝±12%），給 keys 軌道用：
## 同一個動作每一圈都略有不同，不像機器重複。
func _step_loop(data: Dictionary, input: RigInput, pose: Dictionary, delta: float) -> void:
	if input.npc_loop != _loop_name and _w_loop <= 0.0:
		_loop_name = input.npc_loop
		_loop_u = 0.0
		_loop_cycle = -1
	# 指定的手勢（招呼、縮一下）做的時候工作先停一下，做完再接回去
	var want := 1.0 if input.npc_loop == _loop_name and _loop_name != &"" and not (_life != null and _life.cue_active()) else 0.0
	_w_loop = move_toward(_w_loop, want, delta / LOOP_FADE)
	if _loop_name == &"":
		return
	var loop := _entry(data, "loops", str(_loop_name), "")
	if loop.is_empty():
		return
	var period := maxf(0.1, _num(loop, "period", 1.0))
	var vary := clampf(_num(loop, "vary", 0.0), 0.0, 0.4)
	if _loop_cycle < 0 or int(_loop_u) != _loop_cycle:
		_loop_cycle = int(_loop_u)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:%s:%d" % [_rig.skin_id, _loop_name, _loop_cycle])
		_cycle_period = 1.0 + rng.randf_range(-vary, vary)
		_cycle_amp = 1.0 + rng.randf_range(-vary, vary)
	_loop_u += delta / (period * _cycle_period)
	var weight := NpcGesture._smooth(_w_loop)
	if weight <= 0.0:
		if want <= 0.0:
			_loop_name = &"" if input.npc_loop == &"" else _loop_name
		return
	_add_bones(pose, loop.get("bones", {}), weight)
	_add_tracks(pose, loop.get("tracks", []), input.npc_loop_scale * _cycle_amp, _gate(loop.get("gate", {})), 1.0, weight, fmod(_loop_u, 1.0))


## 呼吸曲線（-1~1）：前 40% 吸氣、後 60% 呼氣，各自緩入緩出；phase 是 0~1 的週期進度。
static func breath_curve(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	if p < 0.4:
		return -cos(PI * p / 0.4)
	return cos(PI * (p - 0.4) / 0.6)


## 手臂由姿勢直接決定（NPC 不握武器），只有人形動畫器處理的狀態才用 IK。
func _solve_arms(input: RigInput, aim_angle: float) -> void:
	if _use_npc:
		_rig.weapon_root().visible = false
		return
	super._solve_arms(input, aim_angle)


## 是否由 NPC 動畫處理：沒在走動、沒蹲下（人形的蹲）、沒格擋、沒倒下、沒受傷、沒握武器、沒往上下瞄準。
func _is_npc_state(input: RigInput) -> bool:
	return input.velocity.length() < 1.0 and input.on_floor and not input.crouching and not input.blocking and not input.dead \
			and not input.staggered and not input.two_handed and absf(input.aim_dir.y) < 0.05


## 把骨頭角度乘上權重後加到姿勢上；資料裡有不存在的骨頭時記錄一次錯誤。
func _add_bones(pose: Dictionary, bones: Variant, weight: float) -> void:
	if typeof(bones) != TYPE_DICTIONARY:
		return
	for key: Variant in (bones as Dictionary).keys():
		var bone_name := StringName(str(key))
		if pose.has(bone_name):
			pose[bone_name] = float(pose[bone_name]) + float((bones as Dictionary)[key]) * weight
		elif not _warned("bone:" + str(key)):
			push_error("[NpcAnimator] %s：動畫資料裡的骨頭不存在：%s" % [DATA_PATH, key])


## 疊上一組軌道：一般軌道是一條正弦（mean 平均、amp 幅度、period 週期、phase 相位）；有 keys 的軌道是關鍵影格
## [[進度 0~1, 角度, 緩動]…]（緩動：io 緩入緩出（預設）、in 慢起快停（揮下）、out 快起慢停（彈開）、lin 等速），
## 可以做出「慢慢舉起、快速敲下、停一下」這種不對稱的節奏。keys 軌道在工作循環裡跟著整圈的進度 cycle_u，否則用自己的 period；
## offset 把這條軌道的進度往後挪（前臂、手比上臂晚一點＝重疊動作）。正弦軌道可加 env（整圈進度的關鍵影格包絡）。
## scale 只放大縮小擺動（不含 mean），weight 是整體權重（淡入淡出）。
func _add_tracks(pose: Dictionary, tracks: Variant, scale: float, gate: float, speed := 1.0, weight := 1.0, cycle_u := -1.0) -> void:
	if typeof(tracks) != TYPE_ARRAY:
		return
	for track: Variant in tracks:
		if typeof(track) != TYPE_DICTIONARY:
			continue
		var t := track as Dictionary
		var factor := weight
		if bool(t.get("gated", false)):
			factor *= gate
		if bool(t.get("inv", false)):
			factor *= 1.0 - gate
		var period := maxf(0.01, _num(t, "period", 1.0))
		var swing := 0.0
		if typeof(t.get("keys")) == TYPE_ARRAY:
			var u: float = cycle_u if cycle_u >= 0.0 and not t.has("period") else fposmod(_time * speed / period + _num(t, "phase", 0.0) / TAU, 1.0)
			swing = keyed(t["keys"], fposmod(u + _num(t, "offset", 0.0), 1.0))
		else:
			swing = _num(t, "amp", 0.0) * sin(TAU * _time * speed / period + _num(t, "phase", 0.0))
			# env：用整圈進度的關鍵影格當包絡，只在這一圈的某段時間搓動（例如擦手的那幾秒）
			if typeof(t.get("env")) == TYPE_ARRAY:
				swing *= keyed(t["env"], cycle_u if cycle_u >= 0.0 else 0.0)
		var value := _num(t, "mean", 0.0) * factor + swing * scale * factor
		var bone_name := StringName(str(t.get("bone", "")))
		if pose.has(bone_name):
			pose[bone_name] = float(pose[bone_name]) + value
		elif not _warned("track:" + str(bone_name)):
			push_error("[NpcAnimator] %s：動畫資料裡的骨頭不存在：%s" % [DATA_PATH, bone_name])


## 關鍵影格在進度 u（0~1）的值。keys 依進度排序；u 在第一個之前或最後一個之後時，從最後一個繞回第一個（循環接得上）。
## 格式錯誤的關鍵影格略過；沒有任何有效關鍵影格時回傳 0。
static func keyed(keys: Array, u: float) -> float:
	var points: Array[Vector3] = []  # x 進度、y 值、z 緩動代碼
	for key: Variant in keys:
		if typeof(key) != TYPE_ARRAY or (key as Array).size() < 2 or typeof(key[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(key[1]) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var ease_code := 0.0
		if (key as Array).size() > 2:
			ease_code = {"in": 1.0, "out": 2.0, "lin": 3.0}.get(str(key[2]), 0.0)
		points.append(Vector3(clampf(float(key[0]), 0.0, 1.0), float(key[1]), ease_code))
	if points.is_empty():
		return 0.0
	points.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.x < q.x)
	var first := points[0]
	var last := points[points.size() - 1]
	var a := last
	var b := first
	var local := u - last.x if u >= last.x else u + 1.0 - last.x
	var span := first.x + 1.0 - last.x
	if u >= first.x and u < last.x:
		for i in points.size() - 1:
			if u < points[i + 1].x:
				a = points[i]
				b = points[i + 1]
				local = u - a.x
				span = b.x - a.x
				break
	var k := clampf(local / span, 0.0, 1.0) if span > 0.0 else 1.0
	match int(b.z):
		1:
			k = k * k
		2:
			k = 1.0 - (1.0 - k) * (1.0 - k)
		3:
			pass
		_:
			k = NpcGesture._smooth(k)
	return lerpf(a.y, b.y, k)


static func _num(source: Variant, key: Variant, fallback: float) -> float:
	return NpcGesture._num(source, key, fallback)


## 循環的「發生」時段（例如每 8 秒咳 1.6 秒）：0~1，邊緣有淡入淡出。沒有設定 gate 時恆為 1。
func _gate(config: Variant) -> float:
	if typeof(config) != TYPE_DICTIONARY or (config as Dictionary).is_empty():
		return 1.0
	var period := maxf(0.1, float((config as Dictionary).get("period", 8.0)))
	var on := float((config as Dictionary).get("on", 1.0))
	var phase := fmod(_time, period)
	if phase >= on:
		return 0.0
	return clampf(minf(phase / GATE_EDGE, (on - phase) / GATE_EDGE), 0.0, 1.0)


## 取資料裡的一項；找不到時記錄一次錯誤並退回 fallback（空字串＝沒有）。
func _entry(data: Dictionary, section: String, key: String, fallback: String) -> Dictionary:
	var group: Variant = data.get(section, {})
	var items: Dictionary = group if typeof(group) == TYPE_DICTIONARY else {}
	if items.has(key) and typeof(items[key]) == TYPE_DICTIONARY:
		return items[key]
	if key != "" and not _warned("%s:%s" % [section, key]):
		push_error("[NpcAnimator] %s 沒有 %s「%s」，改用%s。" % [DATA_PATH, section, key, ("「" + fallback + "」") if fallback != "" else "無"])
	if fallback != "" and items.has(fallback) and typeof(items[fallback]) == TYPE_DICTIONARY:
		return items[fallback]
	return {}


static func _warned(key: String) -> bool:
	if _reported.has(key):
		return true
	_reported[key] = true
	return false
