class_name ShopData
extends Resource
## 補給點的貨架：賣哪些消耗品。價格取自 ConsumableData.price（單一來源），受攜帶上限限制。
## 在關卡 legend 把字元對應到它，就會在地圖上放一個補給點。

@export var id: StringName = &"supply"
@export var display_name: String = "補給點"
@export var stock: Array[ConsumableData] = []
## 收購與贖回（老 K 的當舖）：加一個「典當」分頁，把身上的補給換錢，之後可以加利息贖回。
@export var pawn := false
## 工作檯：加一個「改裝」分頁，花錢改裝攜帶中的武器。
@export var workbench := false
## 外觀：cabinet（補給櫃）或 counter（只有發光標記，用在場景裡已經有櫃台或工作檯擺設的地方）。
@export var style: StringName = &"cabinet"
## 靠近時的一句提示（可用 {interact}）；空白時依功能自動產生。
@export var prompt: String = ""


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("補給點缺少 id")
	if stock.is_empty() and not pawn and not workbench:
		problems.append("%s 沒有任何商品，也不收購、不改裝" % id)
	for item in stock:
		if item == null:
			problems.append("%s 的商品清單有空項目" % id)
		elif item.price < 1:
			problems.append("%s 的商品「%s」沒有設定價格（ConsumableData.price）" % [id, item.id])
	return problems


## 靠近時顯示的提示：資料有寫就用，沒有就依功能組一句重點。
func prompt_text() -> String:
	if not prompt.is_empty():
		return prompt
	var parts := PackedStringArray()
	if not stock.is_empty():
		parts.append("買補給")
	if pawn:
		parts.append("典當")
	if workbench:
		parts.append("改裝武器")
	return "{interact} %s：%s" % [display_name, "、".join(parts)]
