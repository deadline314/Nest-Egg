class_name CreditPileData
extends Resource
## 信用點堆（地圖上撿的貨幣）。在關卡 legend 把字元對應到它。撿過的不會再出現（存進檢查點）。

@export var id: StringName = &"credits_small"
@export var value: int = 10
@export var color: Color = Color(1.0, 0.82, 0.25, 1.0)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("信用點堆缺少 id")
	if value < 1:
		problems.append("%s 的金額必須至少 1" % id)
	return problems
