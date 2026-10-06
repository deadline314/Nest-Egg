class_name PortalData
extends Resource
## 出入口：把一個區域（關卡）連到另一個區域。在關卡 legend 把字元對應到它，就會在地圖上放一扇門。
## 只放資料就能新增連接：目標區域與目標出入口用路徑和 id 指定，不需要改程式。
## 沒有目標區域的出入口是「鎖死的門」（擺設）：互動只會顯示 locked_text。

enum Mode {
	## 走近按互動鍵才進入（室內的門、梯子）。
	INTERACT,
	## 走進去就切換（地圖邊緣的出口）。
	WALK,
}

## 在同一個區域內唯一；其他區域用 target_portal 指向它。
@export var id: StringName = &""
## 目標區域的 LevelData（.tres 路徑）；空白＝鎖死的門。
@export_file("*.tres") var target_level: String = ""
## 目標區域裡的出入口 id；玩家會出現在那個出入口。空白時出現在目標區域的起點 P。
@export var target_portal: StringName = &""
@export var mode: Mode = Mode.INTERACT
## 互動提示（可用 {interact} 佔位符）；空白時用預設。一句話講重點，例如「{interact} 回家」。
@export var prompt: String = ""
## 需要的旗標（GameState.set_flag）；空白＝一直可以通行。
@export var requires_flag: StringName = &""
## 鎖住（缺旗標或沒有目標）時顯示的提示。
@export var locked_text: String = "這扇門打不開。"
## 外觀：門的寬高（像素）與發光顏色的種類（door：暖色門框；ladder：梯子；road：街口，沒有門框；hidden：什麼都不畫，互動範圍落在擺設本身的門上，例如屋頂的樓梯間）。
@export var width: int = 24
@export var height: int = 44
@export_enum("door", "ladder", "road", "hidden") var style: String = "door"


func is_locked_door() -> bool:
	return target_level.is_empty()


func default_prompt() -> String:
	return prompt if not prompt.is_empty() else "{interact} 進入"


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("出入口缺少 id")
	if target_level.is_empty():
		if locked_text.is_empty():
			problems.append("出入口 %s 沒有目標區域，也沒有鎖住的提示文字" % id)
	elif not ResourceLoader.exists(target_level):
		problems.append("出入口 %s 的目標區域不存在：%s" % [id, target_level])
	if width < 8 or height < 8:
		problems.append("出入口 %s 的尺寸太小（%dx%d）" % [id, width, height])
	return problems
