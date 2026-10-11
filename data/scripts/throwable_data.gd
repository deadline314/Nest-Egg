class_name ThrowableData
extends Resource
## 可撿起來丟的場景物件（NE-254）：木箱、鐵管、水泥塊、油桶…新增一種只要建立新的 .tres，再在關卡的 legend 對應一個字元。
## 重量決定丟出的速度、弧線與拿著時的移動速度；油桶類（explosion_radius > 0）丟中、落地或被子彈打中都會爆炸。
## 設計見 design/15-combat-feel/THROWABLES.md。

enum Look {
	## 小木箱：撞到就碎。
	CRATE,
	## 油桶：紅色桶身、黃色易燃標誌、頂端警示燈。
	BARREL,
	## 鐵管：細長、重、會彈。
	PIPE,
	## 水泥塊：小、重、不會碎。
	CHUNK,
}

@export var id: StringName = &"throwable"
@export var display_name: String = "木箱"
@export var look: Look = Look.CRATE
## 靠近時的一句提示，{interact} 會換成實際按鍵；空白代表不顯示。
@export var hint: String = "{interact} 撿起"
## 大小（像素），原點在底邊中點。
@export var size: Vector2 = Vector2(12, 12)
@export var color: Color = Color(0.55, 0.42, 0.28, 1.0)
@export_group("Throw")
## 丟出的初速（像素／秒）；越重越慢。
@export_range(120.0, 700.0) var throw_speed: float = 420.0
## 飛行時的重力（像素／秒²）；越重弧線越彎。
@export_range(200.0, 2000.0) var gravity: float = 700.0
## 撿起與丟出的動作時間（秒）；越重越久。
@export_range(0.05, 0.8) var lift_time: float = 0.2
## 拿著時的移動速度倍率。
@export_range(0.3, 1.0) var carry_speed_scale: float = 0.85
## 撞到牆或地面時保留的速度比例（0＝停住）。
@export_range(0.0, 0.8) var bounce: float = 0.25
@export_group("Hit")
@export var damage: int = 2
## 打中敵人的擊退（像素／秒）與衝擊力（受擊分層：大於敵人韌性就硬直）。
@export var knockback: float = 200.0
@export var impact: float = 4.0
## 打中東西（敵人或落地時速度夠快）就碎掉。
@export var breaks_on_impact: bool = false
## 被打中（子彈、近戰、爆炸）幾下會碎或爆；0＝打不壞。
@export var max_health: int = 0
## 玩家被它（爆炸或撞擊）擊殺時的死因（要有敗北圖鑑卡片）。
@export var source_id: StringName = &"thrown_object"
@export_group("Explosion")
## > 0 代表會爆炸：丟出後撞到東西立刻爆；放在地上被打壞時先燒 fuse 秒再爆（有預兆，連鎖會一個接一個）。
@export var explosion_radius: float = 0.0
@export var explosion_damage: int = 3
@export_range(0.0, 2.0) var fuse: float = 0.6


func is_explosive() -> bool:
	return explosion_radius > 0.0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("可投擲物缺少 id")
	if size.x < 4.0 or size.y < 4.0:
		problems.append("%s 的大小必須至少 4×4 像素" % id)
	if damage < 0:
		problems.append("%s 的傷害不能是負數" % id)
	if is_explosive() and explosion_damage < 1:
		problems.append("%s 會爆炸但爆炸傷害小於 1" % id)
	if is_explosive() and max_health < 1:
		problems.append("%s 會爆炸，但打不壞就不能用子彈引爆（max_health 至少 1）" % id)
	if source_id == &"":
		problems.append("%s 缺少死因 source_id" % id)
	return problems
