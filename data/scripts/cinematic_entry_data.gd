class_name CinematicEntryData
extends Resource
## 明確、可退回的電影入口；不取代既有 & 強制事件。位置是角色腳底所在格。

@export var id: StringName = &"cinematic_entry"
@export var scene: StringName = &""
@export var cell := Vector2i.ZERO
@export var once := true
@export var prompt := "{interact} 觀看這段演出。"


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"" or scene == &"":
		problems.append("電影入口必須指定 id 與場景。")
	if prompt.is_empty() or not prompt.contains("{interact}"):
		problems.append("電影入口 %s 必須說明互動按鍵。" % id)
	return problems
