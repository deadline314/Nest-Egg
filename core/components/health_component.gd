class_name HealthComponent
extends Node
## 生命值元件：受傷、治療、無敵時間與死亡判定。
## 與外觀、操控完全解耦，玩家／敵人／載具共用。

signal health_changed(current: int, maximum: int)
signal damaged(info: DamageInfo)
signal healed(amount: int)
signal died(info: DamageInfo)

var max_health: int = 3
## 每次受傷後自動給予的無敵秒數。
var invulnerability_time: float = 0.0
var current: int = 0
var is_dead: bool = false

var _invulnerable_left: float = 0.0


func setup(p_max_health: int, p_invulnerability_time: float) -> void:
	max_health = maxi(1, p_max_health)
	invulnerability_time = maxf(0.0, p_invulnerability_time)
	current = max_health
	is_dead = false


func _ready() -> void:
	if current <= 0 and not is_dead:
		current = max_health


func _physics_process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(0.0, _invulnerable_left - delta)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func grant_invulnerability(seconds: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left, seconds)


func can_take_damage(info: DamageInfo = null) -> bool:
	if is_dead:
		return false
	if info != null and info.ignore_invulnerability:
		return true
	return not is_invulnerable()


## 成功造成傷害時回傳 true。
func take_damage(info: DamageInfo) -> bool:
	if info == null or info.amount <= 0 or not can_take_damage(info):
		return false
	current = maxi(0, current - info.amount)
	if invulnerability_time > 0.0:
		grant_invulnerability(invulnerability_time)
	damaged.emit(info)
	health_changed.emit(current, max_health)
	if current == 0:
		is_dead = true
		died.emit(info)
	return true


## 直接擊殺（例如載具掉落深淵）。
func kill(info: DamageInfo) -> void:
	if is_dead:
		return
	current = 0
	is_dead = true
	health_changed.emit(current, max_health)
	died.emit(info)


## 回傳實際回復量。
func heal(amount: int) -> int:
	if is_dead or amount <= 0:
		return 0
	var before := current
	current = mini(max_health, current + amount)
	var gained := current - before
	if gained > 0:
		healed.emit(gained)
		health_changed.emit(current, max_health)
	return gained


func is_full() -> bool:
	return current >= max_health


func ratio() -> float:
	return float(current) / float(max_health)
