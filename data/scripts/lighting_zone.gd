class_name LightingZone
extends Resource
## 關卡中的一個光影區段：從某一欄開始套用哪份光影設定，以及和前一段之間的過渡有多寬。
## 區段必須依 start_tile 由小到大排列（第一段通常從 0 開始）。

## 區段起點（地圖的欄）。
@export var start_tile: int = 0
## 和前一個區段之間的過渡寬度（欄）。以起點為中心前後各一半；0 代表立刻切換。
@export var blend_tiles: int = 12
@export var profile: LightingProfile


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if profile == null:
		problems.append("光影區段（起點 %d）沒有指定光影設定" % start_tile)
	else:
		problems.append_array(profile.validate())
	if start_tile < 0:
		problems.append("光影區段的起點不能是負的（%d）" % start_tile)
	if blend_tiles < 0:
		problems.append("光影區段（起點 %d）的過渡寬度不能是負的" % start_tile)
	return problems
