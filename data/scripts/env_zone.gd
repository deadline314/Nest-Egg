class_name EnvZone
extends Resource
## 環境區段：從 from_tile 欄起（到下一個區段之前）使用哪一組地形材質與建築立面。

@export var from_tile: int = 0
@export var material: TerrainMaterialData
## 室外立面（街邊建築）；空陣列時退回原本的程式繪製。
@export var facades: Array[FacadeData] = []
## 室內牆面貼圖（64×64 可平鋪，4 倍解析度為 256）；空白時沿用預設金屬牆板。
@export_file("*.png") var interior: String = ""
## 室內牆面鏤空（露出夜景）的機率。
@export_range(0.0, 1.0) var hole_chance: float = 0.22
## 備註：這一段是什麼地方（例如「屋頂巷弄」）。
@export var label: String = ""


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if material == null:
		problems.append("區段「%s」沒有指定地形材質" % label)
	else:
		problems.append_array(material.validate())
	for facade in facades:
		if facade == null:
			problems.append("區段「%s」的立面清單有空項目" % label)
		else:
			problems.append_array(facade.validate())
	if not interior.is_empty() and not ResourceLoader.exists(interior):
		problems.append("區段「%s」的室內牆面貼圖不存在：%s" % [label, interior])
	return problems
