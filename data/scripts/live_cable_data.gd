class_name LiveCableData
extends Resource
## 斷電纜（NE-400）：天花板垂下一條冒火花的電纜，下面是一灘積水。玩家射斷電纜，電纜掉進水裡，
## 短暫預警後整灘水通電幾秒：站在水裡的人（敵人與玩家都一樣）會觸電，跳起來就不會。用過一次就不會再通電。
## 新增一個只需要一份 .tres，再在關卡地圖的 legend 對應一個字元（放在積水中央、腳底那一格）。

@export var id: StringName = &"live_cable"
@export var display_name: String = "斷電纜"
## 靠近時顯示的一句提示（中文）；其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 積水的寬度（世界像素，以字元那一格的中心為準左右各一半）。
@export_range(32.0, 320.0) var water_width: float = 144.0
## 電纜落水後的預警秒數、通電秒數，以及每一下觸電的傷害（同一個人受擊後有原本的無敵時間，不會每格都扣）。
@export_range(0.1, 2.0) var warning_seconds: float = 0.45
@export_range(0.5, 10.0) var live_seconds: float = 3.0
@export_range(1, 6) var damage: int = 2
## 觸電的死因（要有敗北圖鑑卡片）。
@export var source_id: StringName = &"live_cable"


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("斷電纜缺少 id")
	for value: float in [water_width, warning_seconds, live_seconds]:
		if not is_finite(value) or value <= 0.0:
			problems.append("斷電纜 %s 的寬度或時間無效" % id)
			break
	if damage < 1 or source_id == &"":
		problems.append("斷電纜 %s 的傷害或死因無效" % id)
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("斷電纜 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
