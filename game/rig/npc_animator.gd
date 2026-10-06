class_name NpcAnimator
extends HumanoidAnimator
## NPC 動畫器：不戰鬥的人物。待機時雙手自然下垂（不舉槍）、呼吸；可以坐、靠牆、蹲；說話時點頭與手勢，聆聽時微微偏頭，揮手；
## 每個角色可以有專屬的工作循環（攪鍋、敲打、打字…）。全部由資料驅動（art/rigs/npc_animations.json），沒有動畫程式要改。
##
## 沿用 HumanoidAnimator 的骨架計算、彈簧骨（頭髮、衣襬）與套用流程，只換掉「目標角度怎麼算」：
## 角色在走、跑、跳、蹲、格擋、倒下、持武器或瞄準時，仍交給人形動畫器處理（過場裡的演員常常這樣用）。

const DATA_PATH := "res://art/rigs/npc_animations.json"
const FADE_SPEED := 5.0
const GATE_EDGE := 0.25

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
var _feet_def: Dictionary = {}
var _feet_last: Dictionary = {}
var _feet_w := 0.0
var _w_talk := 0.0
var _w_listen := 0.0
var _w_wave := 0.0


func _body_pose(delta: float, input: RigInput, v: Vector2, aim_angle: float) -> Dictionary:
	_use_npc = _is_npc_state(input)
	if not _use_npc:
		return super._body_pose(delta, input, v, aim_angle)
	var data := RigLibrary.load_json(DATA_PATH)
	var pose: Dictionary = {}
	for bone_name in _rig.bone_order():
		pose[bone_name] = 0.0
	# 手的貼圖朝 +X 畫：先轉到順著前臂，姿勢與循環的手部角度再疊上去。
	for hand_bone: StringName in [&"hand_front", &"hand_back"]:
		if pose.has(hand_bone):
			pose[hand_bone] = HAND_FOLLOWS_FOREARM
	var base := _entry(data, "poses", str(input.npc_pose), "stand")
	var feet: Variant = base.get("feet", {})
	_feet_def = feet if typeof(feet) == TYPE_DICTIONARY else {}
	if not _feet_def.is_empty():
		_feet_last = _feet_def
	_add_bones(pose, base.get("bones", {}), 1.0)
	var mine: Dictionary = _motion["npc"]  # 這個角色自己的站姿微調與說話的速度、幅度
	_add_bones(pose, mine["stand"], 1.0)
	pose[&"_hip_x"] = float(base.get("hip_x", 0.0))
	pose[&"_hip_y"] = float(base.get("hip_y", 0.0))
	# 呼吸：胸口與骨盆微微起伏。
	var idle: Dictionary = _motion["idle"]
	var breath := sin(_time * float(idle["breath_speed"]))
	pose[&"chest"] = float(pose.get(&"chest", 0.0)) + breath * float(idle["breath_amp"])
	pose[&"_hip_y"] = float(pose[&"_hip_y"]) + breath * float(idle["hip_bob"])
	# 專屬工作循環。
	if input.npc_loop != &"":
		var loop := _entry(data, "loops", str(input.npc_loop), "")
		if not loop.is_empty():
			_add_bones(pose, loop.get("bones", {}), 1.0)
			_add_tracks(pose, loop.get("tracks", []), input.npc_loop_scale, _gate(loop.get("gate", {})))
	# 說話、聆聽、揮手：淡入淡出地疊上去。
	var step := FADE_SPEED * delta
	_w_talk = move_toward(_w_talk, 1.0 if input.talking else 0.0, step)
	_w_listen = move_toward(_w_listen, 1.0 if input.listening and not input.talking else 0.0, step)
	_w_wave = move_toward(_w_wave, 1.0 if input.waving else 0.0, step)
	for entry: Array in [["talk", _w_talk], ["listen", _w_listen], ["wave", _w_wave]]:
		var weight: float = entry[1]
		if weight <= 0.0:
			continue
		var overlay := _entry(data, "overlays", entry[0], "")
		var talking: bool = entry[0] == "talk"
		_add_bones(pose, overlay.get("bones", {}), weight)
		_add_tracks(pose, overlay.get("tracks", []), weight * (float(mine["talk_amp"]) if talking else 1.0), 1.0, float(mine["talk_speed"]) if talking else 1.0)
	return pose


## 腳踩實地：姿勢資料有 feet 時，兩隻腳用 IK 平放在地面上（腳掌放平），骨盆下沉讓腿彎起來（不靠手調骨盆高度），
## 坐、蹲才不會懸空或陷進地面。所有數字都是比例，不同身高、腿長的骨架共用同一份資料：
## feet：{"x": [前腳, 後腳]（相對骨盆的前後位置，單位＝大腿長）, "sag": 骨盆下沉（單位＝髖到踝的腿長）, "reach": 腿伸展上限比例（預設 0.98）}。
## 姿勢切換時用權重淡入淡出。
func _post_pose(delta: float, _input: RigInput) -> void:
	var want := 1.0 if _use_npc and not _feet_def.is_empty() else 0.0
	_feet_w = move_toward(_feet_w, want, FADE_SPEED * delta)
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
	var sag := float(_feet_last.get("sag", 0.0)) * _leg_length
	_place_feet(offsets, angles, _feet_w, sag, float(_feet_last.get("reach", 0.98)), true)


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


func _add_tracks(pose: Dictionary, tracks: Variant, scale: float, gate: float, speed := 1.0) -> void:
	if typeof(tracks) != TYPE_ARRAY:
		return
	for track: Variant in tracks:
		if typeof(track) != TYPE_DICTIONARY:
			continue
		var t := track as Dictionary
		var factor := 1.0
		if bool(t.get("gated", false)):
			factor *= gate
		if bool(t.get("inv", false)):
			factor *= 1.0 - gate
		var period := maxf(0.01, float(t.get("period", 1.0)))
		var value := float(t.get("mean", 0.0)) * factor \
				+ float(t.get("amp", 0.0)) * scale * factor * sin(TAU * _time * speed / period + float(t.get("phase", 0.0)))
		var bone_name := StringName(str(t.get("bone", "")))
		if pose.has(bone_name):
			pose[bone_name] = float(pose[bone_name]) + value
		elif not _warned("track:" + str(bone_name)):
			push_error("[NpcAnimator] %s：動畫資料裡的骨頭不存在：%s" % [DATA_PATH, bone_name])


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
