extends Enemy
## 會叫增援的聯絡員（NE-476）：看到玩家就拿起話筒回報位置，講完增援就從牠背後趕來。
## 行為：
## - 巡邏時看到玩家：停下、把話筒拿到耳邊，頭上的圓環慢慢填滿（call_time 秒，再乘難度的冷卻倍率的倒數：越難越快）；
##   後半段在增援會出現的地方畫出落點記號。
## - 講話的過程要一直看得到玩家：玩家躲到牆、貨箱或蒸汽後面超過 break_time 秒，回報就斷了；被打暈也會斷。
## - 講完：在自己背後（遠離玩家那一側）叫出 count 名增援（資料的 summon），之後保持距離、不再出手；最多叫 max_calls 次。
## 對付：先處理牠——躲到牠看不到的地方讓回報斷掉，或衝過去打暈、打倒；不處理，戰鬥會多出兩個人。
## 數值都在 data.behavior_params（見 DEFAULTS），沒寫的用預設值。

const DEFAULTS := {
	"call_time": 2.0,      # 講完一通回報要多久（秒）
	"break_time": 0.35,    # 看不到玩家多久回報就斷
	"count": 2,            # 一次叫來幾名增援
	"max_calls": 1,        # 最多叫幾次
	"recall": 8.0,         # 兩次呼叫之間至少隔多久（秒）
	"keep_away": 120.0,    # 講完之後和玩家保持的距離
	"spawn_near": 96.0,    # 增援出現在自己背後多遠（第一名）
	"spawn_step": 40.0,    # 後面每一名再遠多少
}
const MAX_HEIGHT_DIFF := 70.0
## 增援的落點記號從回報進度的這一點開始畫。
const MARK_FROM := 0.5
const FAIL_PAUSE := 0.8
## 增援落點彼此之間、與自己之間至少隔多遠。
const MIN_SPAWN_GAP := 24.0

## 已經叫過幾次（測試用）。
var calls_made := 0
## 這一次回報的進度 0~1（測試與畫面用）。
var call_progress := 0.0
## 這一次回報的增援落點（世界座標，腳底）。
var call_spots: Array[Vector2] = []

var _cooldown := 0.4
var _unseen := 0.0
var _summons: Array[WeakRef] = []


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"call", _call_tick, _call_enter, _call_exit)
	fsm.add(&"keep_away", _keep_away_tick)
	fsm.start(&"patrol")


func _param(key: String) -> float:
	return float(data.behavior_params.get(key, DEFAULTS[key]))


## 講話中或講完保持距離時，都算已經發現玩家（戰鬥配樂、「不被發現」挑戰）。
func is_engaged() -> bool:
	return super.is_engaged() or fsm.is_in(&"call") or fsm.is_in(&"keep_away")


func _on_stunned() -> void:
	if fsm.is_in(&"call"):
		_fail_call()


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if not _can_see_target(data.detect_range, MAX_HEIGHT_DIFF):
		return
	if calls_made < int(_param("max_calls")) and _cooldown <= 0.0:
		fsm.transition(&"call")
	else:
		fsm.transition(&"keep_away")


# ---------------------------------------------------------------------------
# 回報
# ---------------------------------------------------------------------------

func _call_time() -> float:
	return _param("call_time") * GameState.difficulty.enemy_cooldown_multiplier


func _call_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_unseen = 0.0
	call_progress = 0.0
	call_spots.clear()
	_start_telegraph(_call_time())
	Sfx.play(&"phone_pickup", -6.0)


func _call_exit() -> void:
	call_progress = 0.0
	_telegraph_left = 0.0


func _call_tick(delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	_unseen = 0.0 if _sees_target() else _unseen + delta
	if _unseen >= _param("break_time"):
		_fail_call()
		return
	call_progress = clampf(fsm.time_in_state / maxf(0.1, _call_time()), 0.0, 1.0)
	if call_progress >= MARK_FROM and call_spots.is_empty():
		call_spots = _reinforcement_spots()
	if call_progress >= 1.0:
		_complete_call()


## 講話時要「看得到」玩家：中間沒有牆或貨箱，也沒有蒸汽。距離與高度放寬（已經在講了，不會因為玩家退一步就斷）。
func _sees_target() -> bool:
	var target := _target()
	if target == null:
		return false
	var offset := target.global_position - global_position
	if offset.length() > data.detect_range * 1.5 or absf(offset.y) > MAX_HEIGHT_DIFF * 1.5:
		return false
	return _has_line_of_sight() and not _steam_between(target)


func _fail_call() -> void:
	Sfx.play(&"phone_hangup", -6.0)
	Fx.burst(_center() + Vector2(0, -data.body_size.y * 0.6), Palette.WARNING, 4, 40.0, 0.3)
	_cooldown = FAIL_PAUSE + _scaled_cooldown(_param("recall") * 0.5)
	fsm.transition(&"patrol")


func _complete_call() -> void:
	calls_made += 1
	_cooldown = _scaled_cooldown(_param("recall"))
	var spots := call_spots if not call_spots.is_empty() else _reinforcement_spots()
	var target := _target()
	for spot in spots:
		var minion := _spawn_reinforcement(spot)
		if minion != null and target != null:
			minion.raise_alert(target.global_position, 4.0)
	Sfx.play(&"phone_hangup", -6.0)
	Sfx.play(&"beep", -8.0)
	fsm.transition(&"keep_away")


## 增援落點：自己背後（遠離玩家那一側）地面上；被牆擋住或沒有地面就往近處找，再不行改在玩家另一側找。
func _reinforcement_spots() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var target := _target()
	var away := -1 if target != null and target.global_position.x > global_position.x else 1
	var count := int(_param("count"))
	var near := _param("spawn_near")
	var step := _param("spawn_step")
	# 同一側先往遠處排，被牆擋住再往近處補（至少離自己 MIN_SPAWN_GAP），都不行才換到玩家那一側。
	var distances: Array[float] = []
	for i in count:
		distances.append(near + step * i)
	for i in range(1, count + 1):
		distances.append(maxf(MIN_SPAWN_GAP, near - step * 0.6 * i))
	for side: int in [away, -away]:
		for distance in distances:
			if spots.size() >= count:
				return spots
			var spot := _floor_spot(side, distance)
			if spot != Vector2.INF and spots.all(func(other: Vector2) -> bool: return absf(other.x - spot.x) >= MIN_SPAWN_GAP):
				spots.append(spot)
	return spots


func _floor_spot(side: int, distance: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	var waist := Vector2(0, -data.body_size.y * 0.5)
	var at := global_position + Vector2(side * distance, 0.0)
	if not space.intersect_ray(PhysicsRayQueryParameters2D.create(global_position + waist, at + waist, Layers.WORLD)).is_empty():
		return Vector2.INF
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(at + Vector2(0, -16), at + Vector2(0, 24), Layers.SOLID))
	if hit.is_empty():
		return Vector2.INF
	var spot := Vector2(at.x, (hit["position"] as Vector2).y)
	return Vector2.INF if HazardZones.blocks(spot + Vector2(0, -1)) else spot


func _spawn_reinforcement(spot: Vector2) -> Enemy:
	var parent := get_parent() as Node2D
	if parent == null or data.summon == null or data.summon.behavior == null:
		push_error("[Caller] %s 沒有可以叫來的增援（summon）" % data.resource_path)
		return null
	var minion := data.summon.behavior.new() as Enemy
	if minion == null:
		push_error("[Caller] %s 的增援 %s 的 behavior 不是 Enemy" % [data.resource_path, data.summon.id])
		return null
	minion.configure(data.summon)
	minion.position = parent.to_local(spot)
	parent.add_child.call_deferred(minion)
	_summons.append(weakref(minion))
	Fx.dust(spot, 6, 50.0)
	return minion


## 叫來的增援還有幾名活著（測試用）。
func alive_summons() -> int:
	var count := 0
	for ref in _summons:
		var enemy := ref.get_ref() as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dying():
			count += 1
	return count


# ---------------------------------------------------------------------------
# 講完之後
# ---------------------------------------------------------------------------

func _keep_away_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var target := _target()
	if target == null or not _can_see_target(data.detect_range * 1.5, MAX_HEIGHT_DIFF * 1.5):
		velocity.x = 0.0
		if fsm.time_in_state > 3.0:
			fsm.transition(&"patrol")
		return
	_face_target()
	var distance := absf(target.global_position.x - global_position.x)
	var back := -facing
	if distance < _param("keep_away") and not _blocked(back):
		velocity.x = back * data.move_speed * 1.2
	else:
		velocity.x = 0.0
	if calls_made < int(_param("max_calls")) and _cooldown <= 0.0:
		fsm.transition(&"call")


func _blocked(direction: int) -> bool:
	if not is_on_floor():
		return false
	if test_move(global_transform, Vector2(direction * 3.0, 0.0)):
		return true
	var from := global_position + Vector2(direction * (data.body_size.x * 0.5 + 2.0), -2.0)
	if get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 18), Layers.SOLID)).is_empty():
		return true
	return _is_hazard_ahead(direction)


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _rig_state(input: RigInput) -> void:
	input.two_handed = false


func _rig_aim() -> Vector2:
	return Vector2(facing, 0.6).normalized()


## 預兆：頭上一個慢慢填滿的圓環（講完就來人），後半段在增援會出現的地方畫落點記號。
func _draw_overlay() -> void:
	if not fsm.is_in(&"call"):
		return
	# 骨架外觀約是判定身高的 1.4 倍：圓環畫在外觀的頭頂上方，不要蓋住臉。
	var head := Vector2(0, -data.body_size.y * 1.45 - 6.0)
	var ring := LightKit.glow(Palette.WARNING, 1.2 + 0.6 * call_progress)
	draw_arc(head, 6.0, 0.0, TAU, 20, Color(ring, 0.3), 1.0)
	draw_arc(head, 6.0, -PI * 0.5, -PI * 0.5 + TAU * call_progress, 20, Color(ring, 0.9), 1.5)
	if call_spots.is_empty():
		return
	var mark := LightKit.glow(Palette.DANGER, 1.2 + 0.4 * call_progress)
	mark.a = 0.35 + 0.45 * smoothstep(MARK_FROM, 1.0, call_progress)
	for spot in call_spots:
		var at := to_local(spot)
		draw_line(at + Vector2(-6, -1), at + Vector2(6, -1), mark, 1.0)
		draw_line(at + Vector2(-4, -9), at + Vector2(0, -4), mark, 1.0)
		draw_line(at + Vector2(4, -9), at + Vector2(0, -4), mark, 1.0)


## 骨架載入失敗時的備用外觀：瘦長身形，手上一支發光的話筒。
func _draw_body(color: Color) -> void:
	var f := float(facing)
	var h := data.body_size.y
	draw_line(Vector2(-3, -h * 0.4), Vector2(-3, 0), color.darkened(0.45), 3.0)
	draw_line(Vector2(3, -h * 0.4), Vector2(3, 0), color.darkened(0.45), 3.0)
	draw_rect(Rect2(-5, -h * 0.8, 10, h * 0.42), color)
	draw_circle(Vector2(f * 1.0, -h * 0.88), 4.0, color.darkened(0.3))
	var handset := Vector2(f * 5.0, -h * (0.88 if fsm.is_in(&"call") else 0.55))
	draw_circle(handset, 1.5, LightKit.glow(Palette.WARNING, 1.6 if fsm.is_in(&"call") else 1.0))
