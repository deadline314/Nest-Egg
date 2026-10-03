class_name CyberAbilityData
extends Resource
## 義體能力定義。新增一種能力：建立 .tres，若需要新的效果種類再在 CyberSystem 加一個分支。
## 使用條件：義體電量 >= charge_cost 且不在冷卻中；電量隨時間回復，擊敗敵人額外回復。

enum Kind {
	## 超頻：持續 duration 秒，射速、換彈與移動速度提高（倍率見 magnitude）。
	OVERCLOCK,
	## 電磁脈衝：瞬間讓 radius 內的敵人暈眩 duration 秒並消除範圍內的敵方子彈（頭目只會被消除彈幕）。
	EMP,
}

@export var id: StringName = &"ability"
@export var display_name: String = "義體能力"
@export var kind: Kind = Kind.OVERCLOCK
## 一句話說明（背包 tooltip 與詳情）。
@export var description: String = ""
@export var color: Color = Color(0.35, 0.88, 1.0, 1.0)
## 解鎖價格（信用點）。
@export var unlock_cost: int = 250
## 每次使用消耗的義體電量（滿 100）。
@export_range(1.0, 100.0) var charge_cost: float = 50.0
## 使用後的冷卻秒數。
@export var cooldown: float = 6.0
## 效果持續（超頻）或暈眩（脈衝）的秒數。
@export var duration: float = 4.0
## 效果範圍（脈衝的半徑，像素）。
@export var radius: float = 0.0
## 效果強度：超頻的加速倍率增量（0.4 = 射速與換彈快 40%、移動快 15%）。
@export_range(0.0, 1.0) var magnitude: float = 0.4
@export var order: int = 0
## 背包像素圖示（art/items/icons/<icon>.png）。
@export var icon: String = ""
@export var sound: StringName = &"emp"


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("義體能力缺少 id")
	if display_name.is_empty() or description.is_empty():
		problems.append("%s 缺少名稱或說明" % id)
	if unlock_cost < 1:
		problems.append("%s 的解鎖價格必須至少 1" % id)
	if cooldown < 0.0 or duration <= 0.0:
		problems.append("%s 的冷卻與持續時間不合理" % id)
	if kind == Kind.EMP and radius <= 0.0:
		problems.append("%s 是電磁脈衝，必須有範圍 radius" % id)
	if kind == Kind.OVERCLOCK and magnitude <= 0.0:
		problems.append("%s 是超頻，必須有強度 magnitude" % id)
	return problems
