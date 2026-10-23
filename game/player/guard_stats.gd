class_name GuardStats
extends RefCounted
## 格擋的有效數值（NE-269）：PlayerTuning 的基礎值加上已裝的臂盾零件。Player 的格擋判定只讀這裡，
## 沒有零件時每個值都等於原本的 PlayerTuning（規則完全不變）。零件只存「加多少、乘多少」，
## 基礎值每次從 tuning 即時讀（調整工具改 tuning 會立刻生效），不配置記憶體。
## 零件資料不合理時記錄錯誤並略過那個零件。

## 基礎時間窗的夾值範圍（沿用原本規則）；零件加長之後的上限另外放寬，但仍有界。
const PARRY_WINDOW_MIN := 0.14
const PARRY_WINDOW_MAX := 0.22
const PARRY_WINDOW_WITH_PARTS_MAX := 0.3
const BLOCK_ARC_MAX := 200.0
const BLOCK_SPEED_MAX := 0.9
const BREAK_STUN_MIN := 0.15
const REGEN_DELAY_MIN := 0.1

var tuning: PlayerTuning
## 一般格擋擋下的子彈也彈回去（偏折塗層）。
var deflect_on_block := false
## 實際套用的零件 id（給呈現層決定畫哪些外觀）。
var parts: Array[StringName] = []
var _parry_bonus := 0.0
var _arc_bonus := 0.0
var _guard_scale := 1.0
var _break_stun_scale := 1.0
var _regen_delay_scale := 1.0
var _regen_rate_scale := 1.0
var _speed_bonus := 0.0


## 依零件算出加成。tuning 為 null 時用 PlayerTuning 的預設值。
static func build(p_tuning: PlayerTuning, installed: Array) -> GuardStats:
	var stats := GuardStats.new()
	stats.tuning = p_tuning if p_tuning != null else PlayerTuning.new()
	for item: Variant in installed:
		var part := item as ArmShieldPartData
		if part == null:
			push_error("[GuardStats] 臂盾零件不是 ArmShieldPartData，已略過：%s" % [item])
			continue
		var problems := part.validate()
		if not problems.is_empty():
			push_error("[GuardStats] 臂盾零件資料不合理，已略過：%s" % "；".join(problems))
			continue
		if stats.parts.has(part.id):
			continue
		stats.parts.append(part.id)
		match part.effect:
			ArmShieldPartData.Effect.PARRY_WINDOW:
				stats._parry_bonus += part.amount
			ArmShieldPartData.Effect.BLOCK_ARC:
				stats._arc_bonus += part.amount
			ArmShieldPartData.Effect.CUSHION:
				stats._guard_scale *= 1.0 + part.amount
				stats._break_stun_scale *= 1.0 - part.amount
			ArmShieldPartData.Effect.HEAT_SINK:
				stats._regen_delay_scale *= 1.0 - part.amount
				stats._regen_rate_scale *= 1.0 + part.amount
			ArmShieldPartData.Effect.LIGHT_FRAME:
				stats._speed_bonus += part.amount
			ArmShieldPartData.Effect.DEFLECT:
				stats.deflect_on_block = true
	return stats


func has_part(id: StringName) -> bool:
	return parts.has(id)


## 完美格擋時間窗（秒，連按縮短之前）。
func parry_window() -> float:
	var base := clampf(tuning.parry_window, PARRY_WINDOW_MIN, PARRY_WINDOW_MAX)
	return minf(PARRY_WINDOW_WITH_PARTS_MAX, base + _parry_bonus) if _parry_bonus > 0.0 else base


## 擋得住的扇形總角度（度）。
func block_arc_degrees() -> float:
	return minf(BLOCK_ARC_MAX, tuning.block_arc_degrees + _arc_bonus) if _arc_bonus > 0.0 else tuning.block_arc_degrees


func guard_max() -> float:
	return tuning.guard_max * _guard_scale


func guard_break_stun() -> float:
	return maxf(BREAK_STUN_MIN, tuning.guard_break_stun * _break_stun_scale) if _break_stun_scale < 1.0 else tuning.guard_break_stun


func guard_regen_delay() -> float:
	return maxf(REGEN_DELAY_MIN, tuning.guard_regen_delay * _regen_delay_scale) if _regen_delay_scale < 1.0 else tuning.guard_regen_delay


func guard_regen_per_second() -> float:
	return tuning.guard_regen_per_second * _regen_rate_scale


## 舉盾時的移動速度倍率。
func block_speed_multiplier() -> float:
	return minf(BLOCK_SPEED_MAX, tuning.block_speed_multiplier + _speed_bonus) if _speed_bonus > 0.0 else tuning.block_speed_multiplier
