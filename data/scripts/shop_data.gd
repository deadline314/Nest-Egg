class_name ShopData
extends Resource
## 補給點的貨架：賣哪些消耗品。價格取自 ConsumableData.price（單一來源），受攜帶上限限制。
## 在關卡 legend 把字元對應到它，就會在地圖上放一個補給點。

@export var id: StringName = &"supply"
@export var display_name: String = "補給點"
@export var stock: Array[ConsumableData] = []


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("補給點缺少 id")
	if stock.is_empty():
		problems.append("%s 沒有任何商品" % id)
	for item in stock:
		if item == null:
			problems.append("%s 的商品清單有空項目" % id)
		elif item.price < 1:
			problems.append("%s 的商品「%s」沒有設定價格（ConsumableData.price）" % [id, item.id])
	return problems
