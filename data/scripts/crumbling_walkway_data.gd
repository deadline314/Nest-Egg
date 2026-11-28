class_name CrumblingWalkwayData
extends Resource
## 會塌的走道：架在落差上的一段舊鐵走道，分成幾片；有人（玩家或敵人）站上某一片，那一片先抖、過一下就掉下去，
## 空出來一陣子之後再補回來。站著不動就會跟著掉下去，所以要一路走過去。
## 新增一段只需要一份 .tres，再在關卡地圖的 legend 對應一個字元：字元放在走道最左那一格（走道面就是那一格的上緣），往右延伸 length_tiles 格。

@export var id: StringName = &"crumbling_walkway"
@export var display_name: String = "會塌的走道"
## 玩家靠近時的一句提示（中文）；空白代表不顯示。其他語言寫在 localized_hints（"ja"、"en"）。
@export var hint: String = ""
@export var localized_hints: Dictionary[String, String] = {}
## 整段長度與每一片的長度（格）；最後一片可以比較短。
@export_range(2, 48) var length_tiles: int = 12
@export_range(1, 6) var segment_tiles: int = 2
## 有人站上去之後多久掉下去（秒）：太短來不及反應，太長就不用趕。
@export_range(0.15, 3.0) var warn_seconds: float = 0.5
## 掉下去之後多久補回來（秒）。
@export_range(0.5, 30.0) var respawn_seconds: float = 3.0


func hint_for(language: String) -> String:
	return StoryLocale.optional_text(localized_hints, language, hint)


## 分成幾片（最後一片可以比較短）。
func segment_count() -> int:
	return ceili(float(maxi(length_tiles, 1)) / float(maxi(segment_tiles, 1)))


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("會塌的走道缺少 id")
	if length_tiles < 2 or segment_tiles < 1 or segment_tiles > length_tiles:
		problems.append("會塌的走道 %s 的長度無效：全長 %d 格、每片 %d 格" % [id, length_tiles, segment_tiles])
	if not is_finite(warn_seconds) or warn_seconds < 0.15:
		problems.append("會塌的走道 %s 的預警時間無效（%s 秒，至少 0.15）" % [id, warn_seconds])
	if not is_finite(respawn_seconds) or respawn_seconds < 0.5:
		problems.append("會塌的走道 %s 的補回時間無效（%s 秒，至少 0.5）" % [id, respawn_seconds])
	if not hint.is_empty():
		for language in ["ja", "en"]:
			if str(localized_hints.get(language, "")).strip_edges().is_empty():
				problems.append("會塌的走道 %s 的提示缺少 %s 譯文" % [id, language])
	return problems
