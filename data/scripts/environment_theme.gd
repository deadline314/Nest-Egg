class_name EnvironmentTheme
extends Resource
## 關卡的環境主題：依欄位範圍切成區段，每段指定地形材質與建築立面。
## 關卡沒有指定主題時，沿用原本的單一金屬面板與程式繪製立面。

@export var zones: Array[EnvZone] = []
## 道具資料夾（地圖 JSON 的 props 以 id 在這裡找）。
@export_dir var prop_dir: String = "res://data/environment/props"
## 背景視差層（由遠到近）。空陣列時沿用程式繪製的天際線。
@export var backdrop: Array[BackdropLayer] = []


## 指定欄所在的區段（from_tile 最大且 <= tile 者）。沒有區段時回傳 null。
func zone_at(tile: int) -> EnvZone:
	var result: EnvZone = null
	for zone in zones:
		if zone != null and zone.from_tile <= tile and (result == null or zone.from_tile >= result.from_tile):
			result = zone
	return result


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if zones.is_empty():
		problems.append("環境主題沒有任何區段")
	for layer in backdrop:
		if layer == null:
			problems.append("環境主題的背景層清單有空項目")
		else:
			problems.append_array(layer.validate())
	var last := -1
	for zone in zones:
		if zone == null:
			problems.append("環境主題的區段清單有空項目")
			continue
		problems.append_array(zone.validate())
		if zone.from_tile < last:
			problems.append("環境區段沒有依起點由小到大排列（%d）" % zone.from_tile)
		last = maxi(last, zone.from_tile)
	return problems
