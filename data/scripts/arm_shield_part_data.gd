class_name ArmShieldPartData
extends Resource
## 臂盾零件（NE-269）：凜機械左臂的折疊臂盾可以裝的改裝零件。每個零件只改格擋的一項數值或規則，
## 新增零件只需建立 .tres（data/arm_shield/）；要新的效果種類才在 GuardStats 加一個分支。
## 零件全部可選購（不是推進章節的必要準備），買了立刻生效並跟著檢查點保存。

enum Effect {
	## 完美格擋的時間窗加長 amount 秒。
	PARRY_WINDOW,
	## 擋得住的扇形總角度加大 amount 度（畫面上的盾面一起變寬）。
	BLOCK_ARC,
	## 防禦量上限乘上 (1 + amount)，被打穿後的硬直乘上 (1 - amount)。
	CUSHION,
	## 防禦量開始回復前的等待乘上 (1 - amount)，回復速度乘上 (1 + amount)。
	HEAT_SINK,
	## 舉盾時的移動速度倍率加上 amount。
	LIGHT_FRAME,
	## 一般格擋擋下的子彈也彈回去（原本只有完美格擋會反彈）；amount 不使用。
	DEFLECT,
}

## 每種效果的 amount 合理範圍（含端點）；超出時記錄錯誤並不套用這個零件。
const AMOUNT_RANGE := {
	Effect.PARRY_WINDOW: Vector2(0.01, 0.1),
	Effect.BLOCK_ARC: Vector2(5.0, 60.0),
	Effect.CUSHION: Vector2(0.05, 0.6),
	Effect.HEAT_SINK: Vector2(0.05, 0.8),
	Effect.LIGHT_FRAME: Vector2(0.05, 0.5),
	Effect.DEFLECT: Vector2(0.0, 1.0),
}

@export var id: StringName = &"arm_shield_part"
@export var display_name: String = "臂盾零件"
@export var effect: Effect = Effect.PARRY_WINDOW
@export var amount: float = 0.0
@export var cost: int = 100
## 一句話說明這個零件做什麼（改裝頁的說明與提示）。
@export var description: String = ""
## 排序（小的在前）。
@export var order: int = 0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var where := resource_path if not resource_path.is_empty() else String(id)
	if id == &"":
		problems.append("%s：臂盾零件缺少 id" % where)
	if display_name.strip_edges().is_empty():
		problems.append("%s：臂盾零件缺少名稱" % where)
	if not AMOUNT_RANGE.has(effect):
		problems.append("%s：未知的效果 %d" % [where, effect])
	else:
		var range: Vector2 = AMOUNT_RANGE[effect]
		if not is_finite(amount) or amount < range.x or amount > range.y:
			problems.append("%s：amount %.3f 超出 %s 的合理範圍 %.2f～%.2f" % [where, amount, Effect.keys()[effect], range.x, range.y])
	if cost < 1 or cost > 100000:
		problems.append("%s：cost 必須在 1～100000" % where)
	if description.strip_edges().is_empty():
		problems.append("%s：缺少一句話說明" % where)
	return problems
