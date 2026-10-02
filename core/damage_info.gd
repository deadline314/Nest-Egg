class_name DamageInfo
extends RefCounted
## 一次傷害的完整描述。source_id 會被敗北圖鑑用來判斷死因。

var amount: int = 1
var team: Combat.Team = Combat.Team.ENEMY
var source_id: StringName = &""
var knockback: Vector2 = Vector2.ZERO
var origin: Vector2 = Vector2.ZERO
## 破防值（目前保留給未來的破防量表系統）。
var stagger: int = 1
var is_finisher: bool = false
## 掉落深淵等強制傷害會無視無敵時間。
var ignore_invulnerability: bool = false
## 爆炸與終結技可無視盾牌格擋（讓「換武器／換打法」成為有效應對）。
var bypass_guard: bool = false
## 攻擊是否來自子彈（只有子彈能被反彈；接觸攻擊被完美格擋時改為讓攻擊者暈眩）。
var is_projectile: bool = false
## 發動攻擊的節點（弱參照，可能已被移除）。
var attacker: WeakRef = null


func get_attacker() -> Node:
	return attacker.get_ref() as Node if attacker != null else null


static func create(p_amount: int, p_team: Combat.Team, p_source: StringName, p_knockback := Vector2.ZERO) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.team = p_team
	info.source_id = p_source
	info.knockback = p_knockback
	return info
