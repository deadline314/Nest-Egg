class_name SuspendedLoadData
extends Resource
## 吊掛貨物（NE-397）：用鏈條吊在半空的貨箱。玩家打到它，鏈條鬆開，貨箱砸到正下方的敵人，落地後留在原地當掩體。
## 新增一種只需要一份 .tres，再在關卡地圖的 legend 對應一個字元；字元放在貨箱落地的那一格。

@export var id: StringName = &"suspended_load"
@export var display_name: String = "吊掛貨箱"
## 靠近時顯示的一句提示（中文）；空白代表不顯示。其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 貨箱的大小（格）。
@export var size_tiles := Vector2i(2, 2)
## 吊著時貨箱底部離地幾格：要高過角色的頭，玩家與敵人才能從底下走過。
@export_range(3, 12) var hang_tiles: int = 4
## 砸中敵人的傷害與範圍（像素，從落地點算起的半徑）。只傷害敵人，不傷害玩家。
@export_range(1, 20) var drop_damage: int = 4
@export_range(8.0, 64.0) var drop_radius: float = 22.0
## 打幾下會鬆開。
@export_range(1, 6) var release_health: int = 1


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("吊掛貨物缺少 id")
	if size_tiles.x < 1 or size_tiles.y < 1:
		problems.append("吊掛貨物 %s 的大小無效：%s" % [id, size_tiles])
	if hang_tiles < 3:
		problems.append("吊掛貨物 %s 吊得太低（%d 格），角色會撞到" % [id, hang_tiles])
	if drop_damage < 1 or not is_finite(drop_radius) or drop_radius <= 0.0:
		problems.append("吊掛貨物 %s 的傷害或範圍無效" % id)
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("吊掛貨物 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
