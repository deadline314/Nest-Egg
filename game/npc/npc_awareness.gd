class_name NpcAwareness
extends RefCounted
## 場景人物對周圍的短反應（NE-240），不開口、不鎖操作、不改對話流程：
##  - 走近：玩家進入注意範圍時，依 NpcData.reactions 做一個手勢（初見、回訪、凜死過之後、劇情前後不同）；有冷卻，once 的只做一次並存檔；
##  - 聲響：附近開槍、爆炸、東西碎掉（EventBus.world_noise）時縮一下並轉頭看聲音來源；短時間內連續幾聲就蹲下抱頭，安靜一陣子再站起來。
## 演出交給 CutsceneActor（姿勢切換與手勢都是 NE-250 的資料），這裡只決定「什麼時候做什麼」。人物說話中不反應。

## 玩家走到多近會注意到（像素，比互動範圍大，玩家還沒停下來就看得到反應）。
const NOTICE_RANGE := 110.0
## 同一個人兩次走近反應之間至少隔幾秒（來回走動時不會一直重複）。
const REACTION_COOLDOWN := 12.0
## loudness 1（一聲槍響）聽得到的距離（像素）；爆炸 loudness 最高 3。
const NOISE_RADIUS := 150.0
## 兩次「縮一下」之間至少隔幾秒。
const STARTLE_COOLDOWN := 1.2
## 幾秒內聽到幾聲就蹲下抱頭。
const COWER_COUNT := 3
const COWER_WINDOW := 6.0
## 蹲下之後安靜多久才站起來。
const COWER_QUIET := 3.0
## 轉頭看聲音來源維持幾秒。
const LOOK_HOLD := 2.5
## 低於這個大小的聲響只會轉頭看。
const STARTLE_LOUDNESS := 0.5
const STARTLE_GESTURE := &"flinch"
const COWER_GESTURE := &"cover_head"

## 做過的 once 反應（NpcData.reactions 的位置）；存在人物的檢查點狀態裡。
var reacted: Dictionary[int, bool] = {}
## 統計（測試用）。
var reactions_done := 0
var startles := 0
var cowers := 0

var _actor: CutsceneActor
var _data: NpcData
var _near := false
var _cooldown := 0.0
var _startle_cooldown := 0.0
var _noise_times: Array[float] = []
var _time := 0.0
var _cowering := false
var _quiet := 0.0
var _look_left := 0.0
var _look_dir := 0


func _init(actor: CutsceneActor, data: NpcData) -> void:
	_actor = actor
	_data = data


func is_cowering() -> bool:
	return _cowering


## 正在轉頭看聲音來源時回傳面向（-1／1），否則 0（照原本規則面向玩家或原本的方向）。
func look_direction() -> int:
	return _look_dir if _look_left > 0.0 else 0


## 每格呼叫。player_position 是玩家位置（沒有玩家時傳 Vector2.INF）；talking 時不做任何反應。
## 回傳 true＝玩家剛走進注意範圍、可以反應：呼叫端再用 react(條件) 挑反應（條件只在需要時才組，不每格配置）。
func step(delta: float, origin: Vector2, player_position: Vector2, talking: bool) -> bool:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_startle_cooldown = maxf(0.0, _startle_cooldown - delta)
	_look_left = maxf(0.0, _look_left - delta)
	if _cowering:
		_quiet += delta
		if _quiet >= COWER_QUIET:
			_stand_up()
	var near := player_position != Vector2.INF and origin.distance_to(player_position) <= NOTICE_RANGE
	var noticed := near and not _near and not talking and not _cowering and _cooldown <= 0.0
	_near = near
	return noticed


## 走近的反應：挑一個符合條件的反應做手勢。context：{talks, seen, deaths, flag, item}（與挑對話同一套條件）。回傳有沒有做。
func react(context: Dictionary) -> bool:
	if _data == null or _actor == null or _data.reactions.is_empty():
		return false
	var index := _data.pick_reaction(int(context.get("talks", 0)), context.get("seen", Callable()), int(context.get("deaths", 0)),
			context.get("flag", Callable()), context.get("item", Callable()), reacted)
	if index < 0:
		return false
	var reaction := _data.reactions[index]
	if not _actor.play_gesture(reaction.gesture):
		return false
	if reaction.once:
		reacted[index] = true
	reactions_done += 1
	_cooldown = REACTION_COOLDOWN
	return true


## 聽到聲響：在範圍內就縮一下並轉頭看；COWER_WINDOW 秒內第 COWER_COUNT 聲就蹲下抱頭。回傳有沒有反應。
func hear(origin: Vector2, source: Vector2, loudness: float, talking: bool) -> bool:
	if _actor == null or talking or loudness <= 0.0 or origin.distance_to(source) > NOISE_RADIUS * loudness:
		return false
	if absf(source.x - origin.x) > 2.0:
		_look_dir = 1 if source.x > origin.x else -1
		_look_left = LOOK_HOLD
	if loudness < STARTLE_LOUDNESS:
		return true  # 小聲響（試開鎖住的門）只轉頭看，不會縮、也不算進蹲下的次數
	_quiet = 0.0
	_noise_times.append(_time)
	while not _noise_times.is_empty() and _time - _noise_times[0] > COWER_WINDOW:
		_noise_times.pop_front()
	if _cowering:
		if _startle_cooldown <= 0.0:  # 又一聲：抱頭的手再壓緊一次
			_startle_cooldown = STARTLE_COOLDOWN
			_actor.play_gesture(COWER_GESTURE)
		return true
	if _noise_times.size() >= COWER_COUNT:
		_cower()
		return true
	if _startle_cooldown > 0.0:
		return true
	_startle_cooldown = STARTLE_COOLDOWN
	if _actor.play_gesture(STARTLE_GESTURE):
		startles += 1
	return true


func _cower() -> void:
	_cowering = true
	_quiet = 0.0
	cowers += 1
	_actor.set_loop(&"", 1.0)
	_actor.set_pose(&"squat")
	_actor.play_gesture(COWER_GESTURE)


func _stand_up() -> void:
	_cowering = false
	_noise_times.clear()
	_actor.release_gesture()  # 放下抱頭的手，同時站起來
	if _data != null:
		_actor.set_pose(_data.pose)
		_actor.set_loop(_data.loop, _data.loop_scale)


## 檢查點狀態（只存 once 反應做過沒有；蹲著、轉頭這些暫時的狀態不存）。
func capture() -> Array:
	var list: Array = []
	for index in reacted:
		list.append(index)
	return list


func restore(state: Variant) -> void:
	reacted.clear()
	if typeof(state) == TYPE_ARRAY:
		for index: Variant in state:
			if typeof(index) in [TYPE_INT, TYPE_FLOAT]:
				reacted[int(index)] = true
