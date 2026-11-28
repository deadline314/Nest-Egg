class_name GaitLimits
extends RefCounted
## 走路與跑步姿勢的門檻（NE-480）：擋住「坐在看不見的椅子上往前挪」那種步態——骨盆太低、支撐中段膝蓋彎太深、
## 兩腳幾乎併在一起、上身往後仰。數字依 design/12-cast-redraw/LOCOMOTION_REFERENCE.md 與 skill rig-animation
## （骨盆基準高度：走 0.93 L、跑 0.88 L；走的支撐中段膝蓋約 15–25 度、跑約 40 度；走的步長 0.55–0.85 L）。

## 只管走路（速度不到跑速的六成）：跑步本來就會壓低身體，主角滿速跑的骨盆約 0.68 L 是已經定案的樣子。
## 骨盆平均高度下限（以 L 計）：其他腳踩實地的敵人約 0.80–0.85，「坐在看不見的椅子上」的那幾個都在 0.77 以下。
const MIN_HIP_HEIGHT := 0.78
## 支撐中段膝蓋彎曲上限（度）。
const MAX_STANCE_KNEE := 40.0
## 兩腳前後分開的最大距離的下限（以 L 計）：一步至少要邁開這麼多。
const MIN_FOOT_SPREAD := 0.3
## 上身後仰上限（度）。
const MAX_BACK_LEAN := 8.0


## LocomotionAudit.measure 的結果（走路速度）超過哪些門檻（空的代表通過）。
static func problems(r: Dictionary, skin := "") -> PackedStringArray:
	var found := PackedStringArray()
	if float(r["hip_height_l"]) < MIN_HIP_HEIGHT:
		found.append("pelvis %.2f L < %.2f" % [r["hip_height_l"], MIN_HIP_HEIGHT])
	if float(r["stance_knee"]) > MAX_STANCE_KNEE:
		found.append("mid-stance knee %.0f° > %.0f°" % [r["stance_knee"], MAX_STANCE_KNEE])
	if float(r["foot_spread_l"]) < MIN_FOOT_SPREAD and not SHORT_STEPS.has(skin):
		found.append("feet only %.2f L apart < %.2f" % [r["foot_spread_l"], MIN_FOOT_SPREAD])
	if float(r["back_lean"]) > MAX_BACK_LEAN:
		found.append("leans back %.0f° > %.0f°" % [r["back_lean"], MAX_BACK_LEAN])
	return found


## 走路是角色設定、步子本來就小的角色（原因寫在這裡，不放寬門檻）。
const SHORT_STEPS := {"ah_po": "阿婆是老人家，走路小步是角色設定"}
## 主角凜（NE-481）：她的站姿本來就是定案的持槍半蹲（站著時骨盆約 0.77 L、膝約 49 度），走路的門檻改成「不低於她自己的站姿」：
## 骨盆不比站姿低超過 PROTAGONIST_HIP_SLACK、膝蓋不比站姿多彎超過 PROTAGONIST_KNEE_SLACK；小跑段（PROTAGONIST_JOG）的骨盆另外不得低於滿速跑（0.68 L）。
const PROTAGONIST := "rin"
const PROTAGONIST_RUN := 150.0
const PROTAGONIST_WALK: Array[float] = [40.0, 60.0]
const PROTAGONIST_JOG: Array[float] = [90.0, 105.0, 120.0]
const PROTAGONIST_JOG_MIN_HIP := 0.68
const PROTAGONIST_HIP_SLACK := 0.06
const PROTAGONIST_KNEE_SLACK := 15.0


## 主角走路與小跑的問題清單（空的代表通過）。stance：站著不動時的量測（LocomotionAudit.measure 以極慢速度量到的站姿）。
static func protagonist_problems(stance: Dictionary, walks: Array, jogs: Array) -> PackedStringArray:
	var found := PackedStringArray()
	for r: Dictionary in walks:
		if float(r["hip_height_l"]) < float(stance["hip_height_l"]) - PROTAGONIST_HIP_SLACK:
			found.append("walk at %.0f: pelvis %.2f L, more than %.2f below her stance %.2f" % [r["speed"], r["hip_height_l"], PROTAGONIST_HIP_SLACK, stance["hip_height_l"]])
		if float(r["stance_knee"]) > float(stance["stance_knee"]) + PROTAGONIST_KNEE_SLACK:
			found.append("walk at %.0f: knee %.0f°, more than %.0f° past her stance %.0f°" % [r["speed"], r["stance_knee"], PROTAGONIST_KNEE_SLACK, stance["stance_knee"]])
		if float(r["back_lean"]) > MAX_BACK_LEAN:
			found.append("walk at %.0f: leans back %.0f°" % [r["speed"], r["back_lean"]])
	for r: Dictionary in jogs:
		if float(r["hip_height_l"]) < PROTAGONIST_JOG_MIN_HIP:
			found.append("jog at %.0f: pelvis %.2f L < %.2f (her full run)" % [r["speed"], r["hip_height_l"], PROTAGONIST_JOG_MIN_HIP])
	return found
## 主角與過場、場景人物走路的速度與跑速（RigInput 的預設跑速）。
const ACTOR_WALK := 60.0
const ACTOR_RUN := 150.0


## 外觀 id → [走路速度, 跑速]：敵人用自己資料的 move_speed（跑速 = 2 倍，和 Enemy 驅動骨架的方式一樣），
## 同一個外觀有多種敵人時取最慢的那個；其他角色用 ACTOR_WALK／ACTOR_RUN。
static func walk_speeds() -> Dictionary:
	var speeds := {}
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data == null or data.rig_skin.is_empty() or data.move_speed <= 0.0:
			continue
		if not speeds.has(data.rig_skin) or data.move_speed < float((speeds[data.rig_skin] as Array)[0]):
			speeds[data.rig_skin] = [data.move_speed, maxf(40.0, data.move_speed * 2.0)]
	return speeds


static func pace_for(skin: String, speeds: Dictionary) -> Array:
	return speeds.get(skin, [ACTOR_WALK, ACTOR_RUN])
