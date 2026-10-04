class_name StageActions
extends RefCounted
## 舞台情境的動作：每個 act_<名稱>(params) 是一個動作，讓遊戲的玩家、敵人、道具做真實的事，聲音由遊戲自己的程式路徑播出。
## 情境資料（data/audio/stage_scenes.json）只寫「動作名稱＋參數」；新增情境不用改程式，新增動作種類只要在這裡加一個 act_ 函式。
## 動作是協程；等待一律用 _wait（受慢動作影響），回傳 false 代表這次執行被新的情境取代了，動作要立刻結束。

const PREFIX := "act_"
## 每個情境結束前多等一下，讓延遲的聲音層與尾音響完（也讓記錄完整）。
const TAIL_TIME := 0.6

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
	var shots := int(params.get("shots", 3))
	if shots <= 1:
		await arena.tap(&"shoot")
	else:
		arena.hold(&"shoot")
		if not await _wait(float(shots - 1) * weapon.fire_interval + 0.5 * weapon.fire_interval):
			return
		arena.release(&"shoot")
	await _wait(TAIL_TIME)
	arena.release_all()


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


## 近戰。attacks（連續出幾招，1 輕斬、3 含重斬，預設 1）、target（前方是否放靶，預設 true；false 就是揮空）。
func act_melee(params: Dictionary) -> void:
	arena.use_weapon(_text(params, "weapon", "pistol"))
	if bool(params.get("target", true)):
		arena.spawn_target(&"flesh", 1.7)
	if not await _wait(0.3):
		return
	arena.aim_right()
	var attacks := clampi(int(params.get("attacks", 1)), 1, MeleeData.combo().size())
	for i in attacks:
		await arena.tap(&"melee")
		if not await _wait(0.34 if i < attacks - 1 else 0.7):
			return
	await _wait(TAIL_TIME)


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
