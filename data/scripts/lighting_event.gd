class_name LightingEvent
extends Resource
## 關卡中的光影事件：玩家進入某一段（例如停電的走廊）時暫時覆蓋光影，離開後淡回。

@export var id: StringName = &"event"
## 事件範圍（地圖的欄，含起點、不含終點）。
@export var start_tile: int = 0
@export var end_tile: int = 0
@export var profile: LightingProfile
@export var fade_in: float = 1.0
@export var fade_out: float = 1.5


func contains_tile(tile: float) -> bool:
	return tile >= float(start_tile) and tile < float(end_tile)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("光影事件缺少 id")
	if profile == null:
		problems.append("光影事件「%s」沒有指定光影設定" % id)
	if end_tile <= start_tile:
		problems.append("光影事件「%s」的終點必須大於起點" % id)
	return problems
