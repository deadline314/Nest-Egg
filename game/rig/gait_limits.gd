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
## 主角的走路另外由主角的動作測試管（LocomotionSuite 的主角項目、ProtagonistMotionSuite）。
const PROTAGONIST := "rin"
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
