class_name BreakableData
extends Resource
## 可破壞物件定義（木箱、油桶、玻璃牆…）。新增一種只需建立新的 .tres，再在關卡的 legend 對應一個字元。
## 玩家的子彈、近戰與爆炸都能破壞它；敵人的子彈會被它擋住（所以它也是掩體）。

enum Look {
	## 金屬貨箱。
	CRATE,
	## 油桶：外觀；是否爆炸由 explosion_radius 決定。
	BARREL,
	## 玻璃牆：半透明，擋路但擋不住視線，碎裂時有碎片。
	GLASS,
	## 有裂縫的牆：外觀和地形一樣，只有裂紋與微弱的標示；打破後露出隱藏房間的入口。
	WALL,
}

@export var id: StringName = &"breakable"
@export var display_name: String = "貨箱"
@export var look: Look = Look.CRATE
## 靠近時顯示的一句提示，空白代表不顯示。
@export var hint: String = ""
@export var max_health: int = 3
## 大小（格）。以所在格的底邊中點為腳底。
@export var size_tiles := Vector2i(2, 2)
@export var color: Color = Color(0.45, 0.4, 0.34, 1.0)
@export_group("Explosion")
## > 0 代表被破壞時爆炸，同時傷害敵人與玩家，也會引爆旁邊的油桶。
@export var explosion_radius: float = 0.0
@export var explosion_damage: int = 2
## 玩家被爆炸擊殺時的死因（要有敗北圖鑑卡片）。
@export var explosion_source_id: StringName = &"explosive_barrel"
@export_group("Drops")
## 可能掉出的道具（WeaponData 或 ConsumableData），破壞時依 drop_chance 隨機挑一個。
@export var drops: Array[Resource] = []
@export_range(0.0, 1.0) var drop_chance: float = 0.0
@export_range(0.0, 1.0) var health_drop_chance: float = 0.0


func is_explosive() -> bool:
	return explosion_radius > 0.0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("可破壞物缺少 id")
	if max_health < 1:
		problems.append("%s 的生命值必須至少 1" % id)
	if size_tiles.x < 1 or size_tiles.y < 1:
		problems.append("%s 的大小必須至少 1×1 格" % id)
	if is_explosive() and explosion_damage < 1:
		problems.append("%s 會爆炸但爆炸傷害小於 1" % id)
	for drop in drops:
		if not (drop is WeaponData or drop is ConsumableData):
			problems.append("%s 的掉落物必須是 WeaponData 或 ConsumableData" % id)
	if (drop_chance > 0.0 and drops.is_empty()):
		problems.append("%s 設定了掉落機率但沒有掉落物" % id)
	return problems
