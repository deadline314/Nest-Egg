class_name DecoyRadioData
extends Resource
## 誘餌收音機（NE-404）：射中就大聲播放幾秒，範圍內還沒發現玩家的敵人會走過去盯著它看，背後的人看不到。
## 用一次就壞。新增一台只需要一份 .tres，再在關卡地圖的 legend 對應一個字元（放在地面那一格）。

@export var id: StringName = &"decoy_radio"
@export var display_name: String = "收音機"
## 靠近時顯示的一句提示（中文）；其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 吸引範圍（像素，水平距離）與上下多遠內的敵人會聽到。
@export_range(48.0, 600.0) var lure_radius: float = 220.0
@export_range(16.0, 200.0) var lure_height: float = 64.0
## 播放幾秒；停了之後敵人還會多盯 linger_seconds 秒才回去巡邏。
@export_range(1.0, 20.0) var play_seconds: float = 6.0
@export_range(0.0, 10.0) var linger_seconds: float = 2.5


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("收音機缺少 id")
	for field: String in ["lure_radius", "lure_height", "play_seconds", "linger_seconds"]:
		var value: float = get(field)
		if not is_finite(value) or value < 0.0:
			problems.append("收音機 %s 的 %s 無效" % [id, field])
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("收音機 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
