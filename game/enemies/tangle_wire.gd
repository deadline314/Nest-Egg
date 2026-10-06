extends ChainEnemy
## 纏絲（第二章升降井、電力室的伏擊者）：從牆上扯斷的導管，開口裡藏著一簇電纜觸手，不會走動。
## 行為：平常縮在洞裡；玩家進入範圍後電纜抖動並冒火花（預兆 0.8 秒），接著朝玩家伸出鞭打，打完縮回、休息一下。
## 應對：看到火花就離開範圍，或趁牠伸出時打斷觸手——每條觸手有自己的生命，只有伸出時打得到；五條全斷牠就報銷。

const LASH_TIME := 0.7
const RETRACT_TIME := 0.5
const SPARK_INTERVAL := 0.12

var _cooldown := 0.0
var _spark_left := 0.0
var _facing_set := false


func _setup_states() -> void:
	fsm.add(&"hidden", _hidden_tick)
	fsm.add(&"warn", _warn_tick, _warn_enter)
	fsm.add(&"lash", _lash_tick, _lash_enter, _lash_exit)
	fsm.add(&"retract", _retract_tick, _retract_enter)
	fsm.start(&"hidden")


func _tentacles_hittable() -> bool:
	return not fsm.is_in(&"hidden")


func _hidden_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown <= 0.0 and _token_free() and _can_see_target(data.detect_range, 90.0):
		if not _facing_set:
			_face_target()  # 洞口朝向第一次發現的玩家，之後固定（導管釘在牆上）
			_facing_set = true
		fsm.transition(&"warn")


func _warn_enter() -> void:
	_start_telegraph(data.telegraph_time)
	_spark_left = 0.0


func _warn_tick(delta: float) -> void:
	_spark_left -= delta
	if _spark_left <= 0.0:
		_spark_left = SPARK_INTERVAL
		Fx.sparks(global_position + Vector2(facing * 13.0, -5.5), Palette.WARNING, 2, 120.0, 0.2, Vector2(facing, -0.3), 1.2)
	if not is_telegraphing():
		fsm.transition(&"lash")


func _lash_enter() -> void:
	var all := PackedInt32Array()
	for i in chain.tentacle_count():
		if chain.is_alive(i):
			all.append(i)
	_strike_begin(all)
	Fx.flash_light(_center(), Palette.WARNING, 50.0, 0.9, 0.15)


func _lash_tick(_delta: float) -> void:
	if fsm.time_in_state >= LASH_TIME:
		fsm.transition(&"retract")


func _lash_exit() -> void:
	_strike_end()


func _retract_enter() -> void:
	_cooldown = _scaled_cooldown(data.attack_cooldown)


func _retract_tick(_delta: float) -> void:
	if fsm.time_in_state >= RETRACT_TIME:
		fsm.transition(&"hidden")


## 觸手全部斷光：導管沒有可以露出的核心，直接報銷（算玩家擊殺）。
func _on_tentacle_lost(_index: int) -> void:
	if chain.alive_tentacles() == 0 and not _dying:
		health.kill(DamageInfo.create(health.current, Combat.Team.PLAYER, &"severed"))


func _on_core_exposed() -> void:
	pass


func _on_stunned() -> void:
	_strike_end()
	if not fsm.is_in(&"hidden"):
		fsm.transition(&"retract")
