class_name WeaponUpgradeData
extends Resource
## 武器改裝項目定義。新增一種改裝只需建立 .tres；每把武器每種改裝只能買一次。
## 改裝只改「手感」（彈匣、散佈、換彈），不改傷害與射速，所以成長不會讓戰鬥失去挑戰。

enum Effect {
	## 彈匣容量增加 amount 倍（0.5 = +50%）。
	MAGAZINE,
	## 散佈角度（固定與隨機）減少 amount 倍（0.3 = -30%）。
	SPREAD,
	## 換彈時間減少 amount 倍（0.25 = -25%）。
	RELOAD,
	## 解鎖專屬近戰接續，不被動調整伤害／射速。
	MELEE_TECHNIQUE,
}

@export var id: StringName = &"upgrade"
@export var display_name: String = "改裝"
@export var effect: Effect = Effect.MAGAZINE
@export_range(0.0, 0.9) var amount: float = 0.5
@export var cost: int = 100
## 一句話說明（背包 tooltip）。
@export var description: String = ""
## 排序（小的在前）。
@export var order: int = 0
@export var melee_weapon_id: StringName = &""
## 選購不計入章節最低必要準備，仍列在總價目與選購合計。
@export var optional_purchase: bool = false


## 這項改裝對這把武器有意義嗎（沒有彈匣的武器不能擴彈匣、沒有散佈的不能減散佈）。
func applies_to(weapon: WeaponData) -> bool:
	if weapon == null:
		return false
	match effect:
		Effect.MELEE_TECHNIQUE:
			return weapon.is_melee() and weapon.id == melee_weapon_id and melee_weapon_id != &""
		Effect.MAGAZINE, Effect.RELOAD:
			return weapon.has_magazine()
		Effect.SPREAD:
			return weapon.spread_degrees > 0.0 or weapon.random_spread_degrees > 0.0
	return false


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("改裝缺少 id")
	if cost < 1:
		problems.append("%s 的價格必須至少 1" % id)
	if effect == Effect.MELEE_TECHNIQUE and melee_weapon_id == &"":
		problems.append("%s 缺少近戰適用武器" % id)
	if effect != Effect.MELEE_TECHNIQUE and (amount <= 0.0 or amount > 0.9):
		problems.append("%s 的幅度必須在 0～0.9 之間" % id)
	if description.is_empty():
		problems.append("%s 缺少說明" % id)
	return problems
