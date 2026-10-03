class_name ConsumableData
extends Resource
## 消耗品定義（醫療針、護盾電池…）。新增消耗品只需在 data/consumables/ 建立新的 .tres。

@export var id: StringName = &"item"
@export var display_name: String = "道具"
## 一句話說明效果（拾取提示、背包說明）。
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE
## 背包與 HUD 的排列順序（小的在前）。
@export var order: int = 0
## 攜帶上限。
@export var max_carry: int = 3
## 補給點的售價（信用點）；0 代表不販售。
@export var price: int = 0
@export_group("Effect")
## 回復的生命格數。
@export var heal_amount: int = 0
## 護盾立即充滿並解除破防。
@export var restores_guard: bool = false
## 是否為快速使用鍵（{use_item}）使用的道具。
@export var quick_use: bool = false
@export_group("Art")
## 背包像素圖示的檔名（art/items/icons/<icon>.png）。
@export var icon: String = ""


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("消耗品缺少 id")
	if max_carry <= 0:
		problems.append("%s 的攜帶上限必須大於 0" % id)
	if heal_amount <= 0 and not restores_guard:
		problems.append("%s 沒有任何效果" % id)
	return problems
