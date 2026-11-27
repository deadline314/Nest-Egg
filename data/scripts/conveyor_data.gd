class_name ConveyorData
extends Resource
## 輸送帶（NE-401）：工廠地板上的一段輸送帶，站在上面的人（玩家與敵人都一樣）會被往同一個方向帶走。
## 一端有馬達，玩家射中馬達就讓輸送帶反轉。新增一條只需要一份 .tres，再在關卡地圖的 legend 對應一個字元
## （放在輸送帶起點那一格的地面上；輸送帶往右延伸 length_tiles 格，馬達在右端）。

@export var id: StringName = &"conveyor"
@export var display_name: String = "輸送帶"
## 靠近馬達時顯示的一句提示（中文）；其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 長度（格）與速度（像素／秒；正值往右、負值往左）。
@export_range(3, 60) var length_tiles: int = 16
@export_range(-160.0, 160.0) var speed: float = -55.0
## 反轉後多久才能再反轉（秒），避免一陣連射讓它來回抖。
@export_range(0.2, 5.0) var reverse_cooldown: float = 1.0


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("輸送帶缺少 id")
	if length_tiles < 3:
		problems.append("輸送帶 %s 太短（%d 格）" % [id, length_tiles])
	if not is_finite(speed) or is_zero_approx(speed) or not is_finite(reverse_cooldown):
		problems.append("輸送帶 %s 的速度或冷卻無效" % id)
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("輸送帶 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
