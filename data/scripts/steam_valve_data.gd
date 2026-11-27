class_name SteamValveData
extends Resource
## 蒸汽閥（NE-398）：玩家射中閥門，管口噴出一道蒸汽牆，幾秒內擋住雙方的子彈；角色可以穿過去。
## 散去後冷卻一段時間才能再用。新增一個只需要一份 .tres，再在關卡地圖的 legend 對應一個字元（放在閥門腳底那一格）。

@export var id: StringName = &"steam_valve"
@export var display_name: String = "蒸汽閥"
## 靠近時顯示的一句提示（中文）；其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 閥門外觀（貼圖）與在遊戲裡的大小（世界像素）。
@export_file("*.png") var texture: String = "res://art/environment/scene_props/broadcast_outside/broadcast_outside__cooling_valve.png"
@export var size: Vector2 = Vector2(40, 36)
## 蒸汽牆：離閥門中心多遠（正值＝往右；地圖上可以用 flip 反過來）、寬與高（世界像素）。
@export var screen_offset: float = 30.0
@export_range(8.0, 48.0) var screen_width: float = 22.0
@export_range(32.0, 160.0) var screen_height: float = 72.0
## 蒸汽持續幾秒、散去後幾秒才能再用。
@export_range(1.0, 15.0) var screen_seconds: float = 6.0
@export_range(0.0, 30.0) var cooldown_seconds: float = 8.0


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("蒸汽閥缺少 id")
	if texture.is_empty() or not ResourceLoader.exists(texture):
		problems.append("蒸汽閥 %s 的貼圖不存在：%s" % [id, texture])
	for value: float in [size.x, size.y, screen_offset, screen_width, screen_height, screen_seconds, cooldown_seconds]:
		if not is_finite(value):
			problems.append("蒸汽閥 %s 有不是數字的設定" % id)
			break
	if size.x <= 0.0 or size.y <= 0.0 or screen_width <= 0.0 or screen_height <= 0.0 or screen_seconds <= 0.0:
		problems.append("蒸汽閥 %s 的大小或時間無效" % id)
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("蒸汽閥 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
