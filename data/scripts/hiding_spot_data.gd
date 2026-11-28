class_name HidingSpotData
extends Resource
## 可躲藏的位置：掛著塑膠條門簾的凹室或門洞。玩家蹲在簾子後面時，還沒發現玩家的敵人看不到他（走過去也一樣），
## 已經在戰鬥或被警報引來的敵人照常看得到。新增一處只需要一份 .tres，再在關卡地圖的 legend 對應一個字元：
## 字元放在凹室最左那一格的地面上，往右延伸 width_tiles 格。

@export var id: StringName = &"hiding_spot"
@export var display_name: String = "門簾凹室"
## 玩家靠近時的一句提示（中文）；空白代表不顯示。其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 寬度與簾子的高度（格）：要比蹲下的主角寬、比站著的主角高，簾子才蓋得住人。
@export_range(2, 6) var width_tiles: int = 3
@export_range(3, 6) var height_tiles: int = 3


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("可躲藏的位置缺少 id")
	if width_tiles < 2 or width_tiles > 6:
		problems.append("可躲藏的位置 %s 的寬度無效（%d 格，要 2～6）" % [id, width_tiles])
	if height_tiles < 3 or height_tiles > 6:
		problems.append("可躲藏的位置 %s 的高度無效（%d 格，要 3～6）" % [id, height_tiles])
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("可躲藏的位置 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
