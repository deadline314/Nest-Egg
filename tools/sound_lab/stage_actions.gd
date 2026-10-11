class_name StageActions
extends RefCounted
## 舞台情境的動作：每個 act_<名稱>(params) 是一個動作，讓遊戲的玩家、敵人、道具做真實的事，聲音由遊戲自己的程式路徑播出。
## 情境資料（data/audio/stage_scenes.json）只寫「動作名稱＋參數」；新增情境不用改程式，新增動作種類只要在這裡加一個 act_ 函式。
## 動作是協程；等待一律用 _wait（受慢動作影響），回傳 false 代表這次執行被新的情境取代了，動作要立刻結束。

const PREFIX := "act_"
## 每個情境結束前多等一下，讓延遲的聲音層與尾音響完（也讓記錄完整）。
const TAIL_TIME := 0.6
## 等連段可以接下一段最多等幾秒的遊戲時間（超過就照按，讓測試看到沒接上）。
const MELEE_CHAIN_TIMEOUT := 1.5
## 連段時限剩不到這麼多秒就不再等節奏，馬上接。
const MELEE_CHAIN_MARGIN := 0.1
## 一段最多按幾次、按下後等幾個物理影格確認有出招。
const MELEE_TAP_TRIES := 3
const MELEE_START_TICKS := 3
## 連射時每隔幾秒重新瞄準一次。
const AIM_REFRESH_TIME := 0.04

var arena: LabArena
## 目前在跑的情境 id（錯誤訊息指出是哪個情境）。
var scene_id := ""
var _token := 0
static var _names: PackedStringArray = PackedStringArray()


func _init(p_arena: LabArena = null) -> void:
	arena = p_arena


## 所有可用的動作名稱（依程式裡的 act_ 函式自動收集）。
static func names() -> PackedStringArray:
	if _names.is_empty():
		for method: Dictionary in StageActions.new().get_script().get_script_method_list():
			var name := str(method["name"])
			if name.begins_with(PREFIX):
				_names.append(name.trim_prefix(PREFIX))
		_names.sort()
	return _names


static func has_action(name: String) -> bool:
	return names().has(name)


## 執行一個動作；動作不存在或參數有問題時記錄具體位置後結束，不崩潰。
func run(action: String, params: Dictionary, p_scene_id := "") -> void:
	_token += 1
	scene_id = p_scene_id
	if not has_action(action):
		_fail("動作「%s」不存在（可用：%s）" % [action, ", ".join(names())])
		return
	await call(PREFIX + action, params)


## 取消目前的動作：放開按住的按鍵，之後醒來的舊動作會發現自己被取代而結束。
func cancel() -> void:
	_token += 1
	if arena != null:
		arena.release_all()


func _wait(seconds: float) -> bool:
	var token := _token
	await arena.wait(seconds)
	return token == _token


## 等到條件成立或超時（秒）；回傳 false 代表被取代。
func _wait_until(condition: Callable, timeout: float) -> bool:
	var token := _token
	var left := timeout
	while left > 0.0 and not condition.call():
		await arena.wait(0.05)
		if token != _token:
			return false
		left -= 0.05
	return token == _token


func _fail(message: String) -> void:
	push_error("[StageActions] 情境「%s」：%s" % [scene_id, message])


func _text(params: Dictionary, key: String, fallback := "") -> String:
	return str(params.get(key, fallback))


# ---------------------------------------------------------------------------
# 武器
# ---------------------------------------------------------------------------

## 玩家用某把武器開火。weapon、shots（預設 3）、target（可選：材質靶的材質，放在前方讓子彈打得到）。
func act_fire(params: Dictionary) -> void:
	var weapon := arena.use_weapon(_text(params, "weapon"))
	if weapon == null:
		_fail("找不到武器「%s」" % _text(params, "weapon"))
		return
	if params.has("target"):
		arena.spawn_target(StringName(_text(params, "target")), 10.0)
	if not await _wait(0.2):
		return
	arena.aim_right()
	if not await _fire_burst(weapon, int(params.get("shots", 3))):
		return
	await _wait(TAIL_TIME)
	arena.release_all()


## 連續開 shots 槍（照武器射速按住射擊）；回傳 false 代表被新的情境取代。
## track 有給時（回傳瞄準的世界座標），射擊期間持續重新瞄準，敵人走動或玩家被擊退都不會打偏。
func _fire_burst(weapon: WeaponData, shots: int, track := Callable()) -> bool:
	if track.is_valid():
		arena.aim_at(track.call())
	if shots <= 1:
		await arena.tap(&"shoot")
		return true
	arena.hold(&"shoot")
	var left := float(shots - 1) * weapon.fire_interval + 0.5 * weapon.fire_interval
	while left > 0.0:
		var step := minf(left, AIM_REFRESH_TIME)
		if not await _wait(step):
			return false
		left -= step
		if track.is_valid():
			arena.aim_at(track.call())
	arena.release(&"shoot")
	return true


## 換彈整段。weapon、left（換彈前彈匣剩幾發，預設 0）。整段由遊戲的換彈聲音時間軸（reload_cues）播出。
func act_reload(params: Dictionary) -> void:
	var weapon := arena.use_weapon(_text(params, "weapon"))
	if weapon == null or not weapon.has_magazine():
		_fail("武器「%s」找不到或沒有彈匣，無法換彈" % _text(params, "weapon"))
		return
	if not await _wait(0.2):
		return
	var loadout := arena.player.loadout
	loadout.set_ammo(loadout.active_slot, int(params.get("left", 0)), weapon.max_reserve)
	if not loadout.start_reload():
		_fail("武器「%s」無法開始換彈（彈匣已滿或沒有備彈）" % weapon.id)
		return
	if not await _wait_until(func() -> bool: return not loadout.is_reloading(), weapon.reload_time * 2.0 + 1.0):
		return
	await _wait(TAIL_TIME)


## 空槍：彈匣與備彈都空了還扣扳機。weapon。
func act_empty(params: Dictionary) -> void:
	var weapon := arena.use_weapon(_text(params, "weapon"))
	if weapon == null:
		_fail("找不到武器「%s」" % _text(params, "weapon"))
		return
	if not await _wait(0.2):
		return
	var loadout := arena.player.loadout
	loadout.set_ammo(loadout.active_slot, 0, 0)
	arena.aim_right()
	for i in 3:
		await arena.tap(&"shoot")
		if not await _wait(0.45):
			return
	await _wait(TAIL_TIME)


## 換槍：先拿 from（預設手槍），再換到 weapon。
func act_equip(params: Dictionary) -> void:
	if arena.use_weapon(_text(params, "from", "pistol")) == null:
		_fail("找不到武器「%s」" % _text(params, "from", "pistol"))
		return
	if not await _wait(0.4):
		return
	if arena.pick_up_weapon(_text(params, "weapon")) == null:
		_fail("找不到武器「%s」" % _text(params, "weapon"))
		return
	await _wait(TAIL_TIME + 0.4)


## 近戰。attacks（連續出幾招，1 輕斬、3 含重斬，預設 1）、target（前方是否放靶，預設 true；false 就是揮空）、
## weapon（預設 pistol＝徒手連段；近戰武器寫 melee/melee_blade 這種路徑）、distance（靶離玩家幾格，預設 1.7；有近身死角的
## 鞭子要放遠）、gap（每一下之間等幾秒，預設 0.34；出招慢的錘要等久一點才接得上下一段）。
func act_melee(params: Dictionary) -> void:
	arena.use_weapon(_text(params, "weapon", "pistol"))
	if bool(params.get("target", true)):
		arena.spawn_target(&"flesh", float(params.get("distance", 1.7)))
	if not await _wait(0.3):
		return
	arena.aim_right()
	var attacks := clampi(int(params.get("attacks", 1)), 1, MeleeData.combo().size())
	var gap := float(params.get("gap", 0.34))
	var token := _token
	for i in attacks:
		for attempt in MELEE_TAP_TRIES:
			if i > 0 and not await _wait_melee_chain(i - 1, gap if attempt == 0 else 0.0):
				return
			await arena.tap(&"melee")
			# 這一下有沒有真的出招：按鍵的緩衝用真實時間算，機器忙到一個物理影格比緩衝還久時這一下會被吃掉，要再按一次。
			for _tick in MELEE_START_TICKS:
				if _melee_reached(i):
					break
				await arena.get_tree().physics_frame
			if token != _token:
				return
			if _melee_reached(i):
				break
	# 最後一段揮完（命中聲響過）才收尾。
	if not await _wait(0.7) or not await _wait_until(func() -> bool: return arena.player == null or arena.player._melee_phase == Player.MeleePhase.NONE, MELEE_CHAIN_TIMEOUT):
		return
	await _wait(TAIL_TIME)


func _melee_reached(step: int) -> bool:
	return arena.player == null or arena.player._melee_index >= step


## 等到可以接連段的下一段：第 step 段已經出招，而且現在按近戰會接上（命中後可取消，或剛收完、連段時限還沒過）。
## 照 gap 秒的節奏按，但不拖到連段時限快過（揮空時時限只有一半）。全程用物理影格計時：機器忙的時候
## 計時器跑得比遊戲時間快，照秒數按會按太早或太晚，連段就斷了（NE-261）。回傳 false 代表被取代。
func _wait_melee_chain(step: int, gap: float) -> bool:
	var token := _token
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var waited := 0.0
	while waited < MELEE_CHAIN_TIMEOUT:
		var player := arena.player
		if player == null:
			break
		if player._melee_index == step and player.is_melee_cancellable():
			var closing := player._melee_phase == Player.MeleePhase.NONE and player._melee_combo_left <= MELEE_CHAIN_MARGIN
			if waited >= gap or closing:
				break
		await arena.get_tree().physics_frame
		if token != _token:
			return false
		waited += tick
	return token == _token


## 終結技：把敵人打到可終結的血量（會暈眩），玩家在身邊按近戰。enemy（預設 grunt）。
func act_finisher(params: Dictionary) -> void:
	var enemy := arena.spawn_enemy(_text(params, "enemy", "grunt"), 1.8)
	if enemy == null:
		_fail("找不到敵人「%s」" % _text(params, "enemy", "grunt"))
		return
	if not await _wait(0.4):
		return
	arena.damage_enemy_to_finishable(enemy)
	if not await _wait(0.3):
		return
	arena.aim_right()
	await arena.tap(&"melee")
	await _wait(TAIL_TIME + 0.6)


# ---------------------------------------------------------------------------
# 命中與材質
# ---------------------------------------------------------------------------

## 玩家對敵人開槍。enemy（預設 grunt）、weapon（預設 rifle）、shots（預設 4）、distance（離玩家幾格，預設 7）、
## height（瞄準敵人腳下往上幾像素，預設 24 打身體；打頭部弱點用 49）、tough（預設 false：true 就給敵人很多血，打不死才能一直看命中回饋）、
## shield（給敵人幾層護盾，子彈會被擋下彈開）。敵人照常行動（暈住的敵人會蹲低，頭打不到）。
func act_shoot_enemy(params: Dictionary) -> void:
	var weapon := arena.use_weapon(_text(params, "weapon", "rifle"))
	var enemy := arena.spawn_enemy(_text(params, "enemy", "grunt"), float(params.get("distance", 7.0)))
	if weapon == null or enemy == null:
		_fail("找不到武器「%s」或敵人「%s」" % [_text(params, "weapon", "rifle"), _text(params, "enemy", "grunt")])
		return
	if bool(params.get("tough", false)):
		enemy.health.setup(9999, 0.0)
	if int(params.get("shield", 0)) > 0:
		enemy.add_shield(int(params["shield"]))
	if not await _wait(0.3):
		return
	var height := float(params.get("height", 24.0))
	if not await _fire_burst(weapon, int(params.get("shots", 4)), func() -> Vector2: return enemy.global_position + Vector2(0.0, -height)):
		return
	await _wait(TAIL_TIME + 0.4)
	arena.release_all()


## 玩家對場景道具開槍（木箱、油桶、玻璃牆…）。prop（data/props 的檔名，預設 crate）、weapon、shots（一輪幾發）、distance；
## 道具有血量的話最多補打三輪，直到它被打破或打光為止（打破的聲音一定要看得到）。
func act_shoot_prop(params: Dictionary) -> void:
	var weapon := arena.use_weapon(_text(params, "weapon", "pistol"))
	var prop := arena.spawn_prop("res://data/props/%s.tres" % _text(params, "prop", "crate"), float(params.get("distance", 6.0)))
	if weapon == null or prop == null:
		_fail("找不到武器「%s」或道具「%s」" % [_text(params, "weapon", "pistol"), _text(params, "prop", "crate")])
		return
	if not await _wait(0.3):
		return
	var track := func() -> Vector2: return prop.global_position + Vector2(0.0, -12.0)
	for round in 3:
		if not await _fire_burst(weapon, int(params.get("shots", 1)), track):
			return
		if not await _wait(0.2):
			return
		if bool(params.get("single", false)) or not (prop is Breakable) or (prop as Breakable).is_broken:
			break
	await _wait(TAIL_TIME + 0.6)
	arena.release_all()


## 玩家對材質靶開槍。material（flesh／armor／metal／concrete／glass／wood／energy／generic）、weapon、shots、distance（預設 5 格；步槍的子彈飛不到太遠）。
func act_shoot_target(params: Dictionary) -> void:
	var weapon := arena.use_weapon(_text(params, "weapon", "rifle"))
	if weapon == null:
		_fail("找不到武器「%s」" % _text(params, "weapon", "rifle"))
		return
	var target := arena.spawn_target(StringName(_text(params, "material", "generic")), float(params.get("distance", 5.0)))
	if not await _wait(0.3):
		return
	if not await _fire_burst(weapon, int(params.get("shots", 3)), func() -> Vector2: return target.global_position + Vector2(0.0, -20.0)):
		return
	await _wait(TAIL_TIME)
	arena.release_all()


## 玩家打到敵人的弱點（頭部等傷害倍率大於 1 的部位）。enemy、hits（預設 2）。
func act_hit_weak(params: Dictionary) -> void:
	var enemy := arena.spawn_enemy(_text(params, "enemy", "grunt"), 4.0)
	if enemy == null:
		_fail("找不到敵人「%s」" % _text(params, "enemy", "grunt"))
		return
	enemy.stun(30.0)
	if not await _wait(0.3):
		return
	for i in int(params.get("hits", 2)):
		arena.damage_enemy(enemy, 1, true)
		if not await _wait(0.5):
			return
	await _wait(TAIL_TIME)


## 爆炸。radius（像素；小於 SMALL_EXPLOSION_RADIUS 是小爆炸）。在玩家前方不遠處，用遊戲自己的爆炸函式。
func act_explosion(params: Dictionary) -> void:
	var at := arena.player.global_position + Vector2(float(params.get("distance", 5.0)) * LabArena.TILE, -12.0)
	Fx.explosion(at, float(params.get("radius", 40.0)), 0, Combat.Team.PLAYER, &"", Palette.WARNING)
	await _wait(TAIL_TIME + 0.8)


# ---------------------------------------------------------------------------
# 玩家格擋
# ---------------------------------------------------------------------------

## 玩家舉盾被敵人子彈打中。mode：block（一般格擋）、parry（舉盾瞬間的完美格擋）、break（連續被打到破防）。
func act_guard(params: Dictionary) -> void:
	var mode := _text(params, "mode", "block")
	arena.aim_right()
	# 先確定上一個情境的舉盾已經放掉，這次才是「剛舉盾」。
	arena.release(&"block")
	var settle_token := _token
	var settle_left := 90
	while arena.player.is_blocking and settle_left > 0:
		await arena.get_tree().physics_frame
		settle_left -= 1
	if settle_token != _token:
		return
	arena.player._since_block_release = 10.0
	arena.hold(&"block")
	# 一個物理影格一個物理影格等舉盾成功：完美格擋要在剛舉盾的窗口內被打中。
	var token := _token
	var frames_left := 90
	while not arena.player.is_blocking and frames_left > 0:
		await arena.get_tree().physics_frame
		frames_left -= 1
	if token != _token:
		return
	# 一般格擋等窗口過了再被打。
	if mode != "parry" and not await _wait(arena.player.parry_window_length() + 0.15):
		return
	var hits := 8 if mode == "break" else 1
	for i in hits:
		arena.enemy_bullet_hits_player(60 if mode == "break" else 1)
		if not await _wait(0.2):
			return
	await _wait(TAIL_TIME)
	arena.release_all()


# ---------------------------------------------------------------------------
# 角色
# ---------------------------------------------------------------------------

## 敵人受傷。enemy（預設 grunt）、hits（預設 3，每次間隔超過受擊叫聲冷卻）。
func act_enemy_hurt(params: Dictionary) -> void:
	var enemy := arena.spawn_enemy(_text(params, "enemy", "grunt"), 5.0)
	if enemy == null:
		_fail("找不到敵人「%s」" % _text(params, "enemy", "grunt"))
		return
	enemy.stun(30.0)
	if not await _wait(0.3):
		return
	for i in int(params.get("hits", 3)):
		arena.damage_enemy(enemy, 1)
		if not await _wait(0.6):
			return
	await _wait(TAIL_TIME)


## 敵人死亡。enemy（預設 grunt）。
func act_enemy_die(params: Dictionary) -> void:
	var enemy := arena.spawn_enemy(_text(params, "enemy", "grunt"), 5.0)
	if enemy == null:
		_fail("找不到敵人「%s」" % _text(params, "enemy", "grunt"))
		return
	enemy.stun(30.0)
	if not await _wait(0.3):
		return
	arena.damage_enemy(enemy, enemy.health.current)
	await _wait(TAIL_TIME + 1.0)


## 讓敵人自己行動一段時間：預兆、攻擊、警戒、開火都由它的 AI 做。enemy、seconds（預設 6）、distance（預設 6）、
## lift（離地高度，飛行的探照無人機要懸在玩家上方才照得到）。
func act_enemy_behave(params: Dictionary) -> void:
	arena.use_weapon("pistol")
	var enemy := arena.spawn_enemy(_text(params, "enemy", "grunt"), float(params.get("distance", 6.0)), float(params.get("lift", 0.0)))
	if enemy == null:
		_fail("找不到敵人「%s」" % _text(params, "enemy", "grunt"))
		return
	await _wait(float(params.get("seconds", 6.0)))


## 玩家受傷。hits（預設 2）。
func act_player_hurt(params: Dictionary) -> void:
	for i in int(params.get("hits", 2)):
		arena.enemy_bullet_hits_player(1)
		if not await _wait(0.6):
			return
	await _wait(TAIL_TIME)


## 玩家死亡（場地之後會自動重建）。
func act_player_die(_params: Dictionary) -> void:
	arena.player.health.setup(3, 0.0)
	arena.enemy_bullet_hits_player(99)
	await _wait(TAIL_TIME + 1.0)


# ---------------------------------------------------------------------------
# 移動
# ---------------------------------------------------------------------------

## 走路。surface（腳下的地面種類）、seconds（預設 2）。
func act_walk(params: Dictionary) -> void:
	arena.player.surface_override = StringName(_text(params, "surface"))
	arena.hold(&"move_right")
	if not await _wait(float(params.get("seconds", 2.0))):
		return
	arena.release(&"move_right")
	await _wait(0.4)
	arena.player.surface_override = &""


## 從高處落地。surface、height（像素，預設 150）。
func act_land(params: Dictionary) -> void:
	arena.player.surface_override = StringName(_text(params, "surface"))
	arena.player.global_position.y -= float(params.get("height", 150.0))
	arena.player.velocity = Vector2.ZERO
	if not await _wait_until(func() -> bool: return arena.player.is_on_floor(), 3.0):
		return
	await _wait(TAIL_TIME)
	arena.player.surface_override = &""


## 跳躍（落地一併發聲）。surface（可選）。
func act_jump(params: Dictionary) -> void:
	if params.has("surface"):
		arena.player.surface_override = StringName(_text(params, "surface"))
	await arena.tap(&"jump")
	if not await _wait(1.2):
		return
	arena.player.surface_override = &""


## 衝刺：邊走邊按衝刺。
func act_dash(_params: Dictionary) -> void:
	arena.hold(&"move_right")
	if not await _wait(0.3):
		return
	await arena.tap(&"dash")
	if not await _wait(0.8):
		return
	arena.release(&"move_right")
	await _wait(TAIL_TIME)


# ---------------------------------------------------------------------------
# 機關與場景互動
# ---------------------------------------------------------------------------

## 玩家撥開關，同頻道的閘門打開再放下。switch、gate（data/props 的檔名，預設 switch_a、gate_a）。
func act_mechanism(params: Dictionary) -> void:
	var gate := arena.spawn_prop("res://data/props/%s.tres" % _text(params, "gate", "gate_a"), 4.0)
	var switch := arena.spawn_prop("res://data/props/%s.tres" % _text(params, "switch", "switch_a"), 0.0)
	if gate == null or switch == null:
		_fail("找不到開關或閘門")
		return
	if not await _wait(0.6):
		return
	for i in 2:
		await arena.tap(&"interact")
		if not await _wait(1.6):
			return
	await _wait(TAIL_TIME)


## 玩家撥電力開關：斷電（區域熄燈）再復電。
func act_power(_params: Dictionary) -> void:
	var switch := arena.spawn_prop("res://data/props/power_switch.tres", 0.0)
	if switch == null:
		_fail("找不到電力開關")
		return
	if not await _wait(0.6):
		return
	for i in 2:
		await arena.tap(&"interact")
		if not await _wait(1.8):
			return
	await _wait(TAIL_TIME)


## 義體能力。ability（data/abilities 的檔名：emp_pulse、overclock）；ready 為 true 時只看「能力就緒」（電量剛好補滿的提示音）。
func act_cyber(params: Dictionary) -> void:
	var path := "res://data/abilities/%s.tres" % _text(params, "ability", "emp_pulse")
	var ability := load(path) as CyberAbilityData if ResourceLoader.exists(path) else null
	if ability == null:
		_fail("找不到義體能力：%s" % path)
		return
	var cyber := arena.player.cyber
	cyber.debug_set_ability(ability)
	if bool(params.get("ready", false)):
		cyber.charge = ability.charge_cost - 1.0
		if not await _wait_until(func() -> bool: return cyber.is_ready(), 3.0):
			return
		await _wait(TAIL_TIME)
		return
	arena.spawn_enemy("grunt", 3.0)
	arena.spawn_enemy("drone", 5.0, 40.0)
	cyber.charge = ability.charge_cost + 10.0
	if not await _wait(0.4):
		return
	cyber.try_activate()
	await _wait(TAIL_TIME + 1.2)


## 撿道具：走過去撿。kind 目前只有 health（回復裝甲，撿之前先讓玩家少一點血）。
func act_pickup(_params: Dictionary) -> void:
	arena.enemy_bullet_hits_player(1)
	var pickup := HealthPickup.new()
	pickup.position = Vector2(arena.player.global_position.x + 3.0 * LabArena.TILE, LabArena.FLOOR_Y)
	arena.level._entities.add_child(pickup)
	arena.adopt(pickup)
	if not await _wait(0.3):
		return
	arena.hold(&"move_right")
	if not await _wait(1.6):
		return
	arena.release(&"move_right")
	await _wait(TAIL_TIME)


## 電話亭。mode：call（整段撥號備份：拿起話筒、三聲撥號音、話筒裡的錄音、掛上）、rebirth（死後從這個亭子醒來的來電鈴聲）。
func act_phone(params: Dictionary) -> void:
	var booth := _place_booth()
	if not await _wait(0.4):
		return
	if not booth.start_call(arena.player):
		_fail("玩家無法開始撥號")
		return
	if not await _wait_until(func() -> bool: return not booth.is_calling(), 6.0):
		return
	await _wait(0.6)
	if _text(params, "mode", "call") == "rebirth":
		booth.queue_free()
		await arena.get_tree().process_frame
		_place_booth()
		if not await _wait(2.4):
			return
	await _wait(TAIL_TIME)


func _place_booth() -> Checkpoint:
	var booth := Checkpoint.new()
	booth.position = Vector2(arena.player.global_position.x + 1.4 * LabArena.TILE, LabArena.FLOOR_Y)
	arena.level._entities.add_child(booth)
	arena.adopt(booth)
	return booth


## 雨夜閃電與雷聲：過場動畫的閃電效果（疊在舞台畫面上）。
func act_lightning(_params: Dictionary) -> void:
	var cutscene := CutscenePlayer.new()
	arena.add_child(cutscene)
	cutscene.play(&"lab_lightning", {"overlay": true, "steps": [{"do": "fx", "kind": "lightning", "time": 0.6}, {"do": "wait", "time": 1.4}, {"do": "end"}]})
	var token := _token
	await cutscene.finished
	cutscene.queue_free()
	UiKit.set_cursor_visible(true)
	if token != _token:
		return
	await _wait(TAIL_TIME)


# ---------------------------------------------------------------------------
# 介面
# ---------------------------------------------------------------------------

## 暫停選單：開啟、游標移動、按下按鈕、關閉。
func act_menu(_params: Dictionary) -> void:
	var menu: PauseMenu = arena.level._pause_menu
	menu.open()
	if not await _wait(0.8):
		menu.close()
		return
	var buttons: Array[Button] = []
	for child in menu._menu_panel.body.get_children():
		if child is Button:
			buttons.append(child)
	for i in mini(3, buttons.size()):
		buttons[i].grab_focus()
		if not await _wait(0.5):
			menu.close()
			return
	buttons[0].grab_focus()
	buttons[0].pressed.emit()
	await _wait(TAIL_TIME)
	if menu._root.visible:
		menu.close()
	UiKit.set_cursor_visible(true)


## 整個畫面：主選單或結算畫面（各自的曲子一起響起）。screen：menu、victory。
func act_screen(params: Dictionary) -> void:
	arena.audio_on = true
	var screen: Control = MainMenu.new() if _text(params, "screen", "menu") == "menu" else VictoryScreen.new()
	arena.add_child(screen)
	await _wait(float(params.get("seconds", 5.0)))
	screen.queue_free()
	UiKit.set_cursor_visible(true)


# ---------------------------------------------------------------------------
# 環境音與背景音樂
# ---------------------------------------------------------------------------

## 在某個光影區段的場地裡待一段時間，環境音與背景音樂像進遊戲一樣自己響。
## zone（光影設定 id）、seconds（預設 6）、state：calm（平靜）、combat（附近有警戒的敵人）、boss（頭目戰開始）、
## safe（站在電話亭旁）、death（玩家倒下的短曲）。
func act_zone(params: Dictionary) -> void:
	await arena.build(StringName(_text(params, "zone", "neutral")), true)
	if not await _wait(1.0):
		return
	match _text(params, "state", "calm"):
		"combat":
			for i in 3:
				arena.spawn_enemy("grunt", 5.0 + float(i) * 1.5)
		"boss":
			EventBus.boss_started.emit("實驗室頭目", 100)
		"safe":
			_place_booth()
		"death":
			arena.player.health.setup(3, 0.0)
			arena.enemy_bullet_hits_player(99)
	await _wait(float(params.get("seconds", 6.0)))
