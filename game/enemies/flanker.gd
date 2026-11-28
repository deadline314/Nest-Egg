extends "res://game/enemies/slasher.gd"
## 繞後的切割者（NE-424）：發現玩家後不正面衝，而是找玩家的背後出手。
## 行為：
## - 玩家背對牠：壓低身子快步貼近，到了斬擊距離就從背後蓄力撲斬（預兆比正面長一點，因為玩家看著另一邊）。
## - 玩家面對牠：在一段距離外對峙、跟著玩家移動；對峙久了就蹲下預告，從玩家頭上翻過去落在背後，接著蓄力撲斬。
## - 玩家背後沒有落腳處（背靠牆、背後是懸崖或通電的積水、頭頂太低或有走道）：翻不過去，只能像一般切割者從正面撲斬。
## - 從背後出手時要整個人在畫面裡才開始蓄力（鏡頭往瞄準方向看，背後的畫面窄），不從畫面外偷砍。
## 對付：背靠牆站，牠就繞不到後面；看到牠蹲下要翻就轉身，格擋或閃開落地後的那一斬。
## 數值都在 data.behavior_params（見 DEFAULTS），沒寫的用預設值。

const DEFAULTS := {
	"standoff": 1.4,          # 被玩家正面盯著多久之後翻過去（秒，再乘難度的冷卻倍率）
	"keep_near": 76.0,        # 對峙時最近的距離：更近就往後退
	"keep_far": 120.0,        # 對峙時最遠的距離：更遠就靠近
	"strike_range": 84.0,     # 在玩家背後時，距離這麼近就出手
	"behind_telegraph": 0.2,  # 從背後出手時預兆多加的秒數
	"vault_tell": 0.4,        # 翻越前蹲下預告的秒數
	"vault_up": 300.0,        # 翻越的起跳速度（像素／秒，往上）：最高點約離地 50，剛好越過主角的頭
	"vault_land": 44.0,       # 落在玩家背後多遠
	"sneak_scale": 1.3,       # 在玩家背後貼近時的速度倍率
	"lose_range": 1.6,        # 距離超過偵測範圍的幾倍就放棄、回去巡邏
}
## 高度差超過這麼多就不追（例如玩家在高台上）。
const MAX_HEIGHT_DIFF := 70.0
## 看不到玩家多久之後放棄。
const LOSE_SIGHT_TIME := 1.0
## 翻越需要的頭頂空間：最高點再加上外觀身高（骨架外觀約是判定身高的 1.4 倍）；走道的鋼樑畫在碰撞下方，留這麼多才不會擦到。
const VISUAL_HEIGHT := 1.4
## 在背後時，貼到這麼近就算不在畫面裡也出手（不會再更近）。
const MIN_STRIKE_RANGE := 26.0
## 「在畫面裡」要離畫面邊緣多少（螢幕像素）。
const SCREEN_MARGIN := 40.0
## 翻越預告弧線的點數（每格重畫，點數固定，不配置新陣列以外的東西）。
const ARC_POINTS := 16

var _standoff := 0.0
var _unseen := 0.0
var _vault_target := Vector2.ZERO
## 這一次出手是從玩家背後（給測試與預兆用）。
var striking_from_behind := false


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"stalk", _stalk_tick, _stalk_enter)
	fsm.add(&"vault_tell", _vault_tell_tick, _vault_tell_enter)
	fsm.add(&"vault", _vault_tick, _vault_enter, _vault_exit)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"leap", _leap_tick, _leap_enter, _leap_exit)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"patrol")


func _param(key: String) -> float:
	return float(data.behavior_params.get(key, DEFAULTS[key]))


func _on_stunned() -> void:
	if fsm.is_in(&"vault_tell") or fsm.is_in(&"vault") or fsm.is_in(&"windup") or fsm.is_in(&"leap"):
		fsm.transition(&"recover")


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _can_see_target(data.detect_range, MAX_HEIGHT_DIFF):
		fsm.transition(&"stalk")


# ---------------------------------------------------------------------------
# 找背後
# ---------------------------------------------------------------------------

## 玩家背對的那一側（-1 左、1 右）；不是玩家就當作面向右。
func _player_back() -> int:
	var player := _target() as Player
	return -player.facing if player != null else -1


## 自己在玩家的哪一側（-1 左、1 右）。
func _side_of_player() -> int:
	var target := _target()
	if target == null:
		return 0
	return 1 if global_position.x >= target.global_position.x else -1


## 目前在玩家背後（玩家看著另一邊）。
func is_behind_player() -> bool:
	return _side_of_player() == _player_back()


func _stalk_enter() -> void:
	_standoff = 0.0
	_unseen = 0.0


func _stalk_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var target := _target()
	if target == null:
		fsm.transition(&"patrol")
		return
	var dx := target.global_position.x - global_position.x
	var far := absf(dx) > data.detect_range * _param("lose_range")
	var too_high := absf(target.global_position.y - global_position.y) > MAX_HEIGHT_DIFF
	_unseen = _unseen + delta if not _has_line_of_sight() else 0.0
	if far or too_high or _unseen >= LOSE_SIGHT_TIME:
		fsm.transition(&"patrol")
		return
	_face_target()
	var distance := absf(dx)
	var ready := _cooldown <= 0.0 and _token_free()
	if is_behind_player():
		_standoff = 0.0
		# 鏡頭跟著玩家的瞄準方向往前看，背後的畫面很窄：要等自己整個進到畫面裡才出手，不從畫面外偷砍。
		if distance <= _param("strike_range") and (_on_screen() or distance <= MIN_STRIKE_RANGE):
			velocity.x = 0.0
			if ready:
				fsm.transition(&"windup")
			return
		_step(facing, data.move_speed * _param("sneak_scale"))
		return
	# 玩家正面看著牠：保持距離，等時機翻過去。
	if distance < _param("keep_near"):
		_step(-facing, data.move_speed)
	elif distance > _param("keep_far"):
		_step(facing, data.move_speed)
	else:
		velocity.x = 0.0
	_standoff += delta
	if _standoff < _param("standoff") * GameState.difficulty.enemy_cooldown_multiplier or not ready:
		return
	_standoff = 0.0
	var landing := _vault_landing()
	if landing != Vector2.INF:
		_vault_target = landing
		fsm.transition(&"vault_tell")
	elif distance <= _param("keep_far") + 20.0:
		# 翻不過去（背靠牆、背後是懸崖或積水）：只能正面出手。
		fsm.transition(&"windup")


## 整個身體都在畫面裡（含預兆的紅線與驚嘆號）。
func is_on_screen() -> bool:
	return _on_screen()


func _on_screen() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return true
	var to_screen := viewport.get_final_transform() * viewport.get_canvas_transform()
	var screen := viewport.get_visible_rect().grow(-SCREEN_MARGIN)
	var half := data.body_size.x * 0.5
	return screen.has_point(to_screen * (global_position + Vector2(-half, -data.body_size.y))) \
			and screen.has_point(to_screen * (global_position + Vector2(half, 0.0)))


## 自己決定的水平移動：遇到牆、懸崖或危險範圍就停下。
func _step(direction: int, speed: float) -> void:
	if is_on_floor() and (_blocked(direction)):
		velocity.x = 0.0
		return
	velocity.x = direction * speed


func _blocked(direction: int) -> bool:
	if test_move(global_transform, Vector2(direction * 3.0, 0.0)):
		return true
	var from := global_position + Vector2(direction * (data.body_size.x * 0.5 + 2.0), -2.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 18), Layers.SOLID)
	if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		return true
	return _is_hazard_ahead(direction)


## 玩家背後的落腳點（世界座標，腳底）；沒有安全的落腳點時回傳 Vector2.INF。
## 落腳點要有地面、不在危險範圍、和玩家之間沒有牆，而且翻越的路線上方有足夠空間。
func _vault_landing() -> Vector2:
	var target := _target()
	if target == null:
		return Vector2.INF
	var space := get_world_2d().direct_space_state
	var back := _player_back()
	var land := Vector2(target.global_position.x + back * _param("vault_land"), global_position.y)
	# 玩家和落腳點之間（腰的高度）不能有牆：背靠牆就翻不過去。
	var waist := Vector2(0, -data.body_size.y * 0.5)
	var past := land + Vector2(back * data.body_size.x * 0.5, 0)
	if not space.intersect_ray(PhysicsRayQueryParameters2D.create(target.global_position + waist, past + waist, Layers.WORLD)).is_empty():
		return Vector2.INF
	# 落腳處要有地面（高低差 ±16 以內）。
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(land + Vector2(0, -16), land + Vector2(0, 20), Layers.SOLID))
	if floor_hit.is_empty():
		return Vector2.INF
	land.y = (floor_hit["position"] as Vector2).y
	if HazardZones.blocks(land + Vector2(0, -1)):
		return Vector2.INF
	# 起點、中點、落點上方都要有翻越的空間；頭頂的單向走道也算，不穿過去也不擦到。
	var headroom := _vault_peak() + data.body_size.y * VISUAL_HEIGHT
	var mid := (global_position + land) * 0.5
	for point: Vector2 in [global_position, mid, land]:
		var up := PhysicsRayQueryParameters2D.create(point + Vector2(0, -2), point + Vector2(0, -headroom), Layers.SOLID)
		if not space.intersect_ray(up).is_empty():
			return Vector2.INF
	return land


## 翻越時腳底離起點的最高高度（像素）。
func _vault_peak() -> float:
	return _param("vault_up") * _param("vault_up") / (2.0 * maxf(1.0, _gravity))


# ---------------------------------------------------------------------------
# 翻越
# ---------------------------------------------------------------------------

func _vault_tell_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(_param("vault_tell"))


func _vault_tell_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not is_telegraphing():
		fsm.transition(&"vault")


func _vault_enter() -> void:
	var up := _param("vault_up")
	var air_time := 2.0 * up / maxf(1.0, _gravity)
	velocity = Vector2((_vault_target.x - global_position.x) / air_time, -up)
	# 翻過頭頂時不算撞人：只有落地後那一斬會傷人。
	if contact != null:
		contact.active = false
	Fx.dust(global_position, 4, 50.0)
	Sfx.play(&"dash", -8.0, 0.2)


func _vault_exit() -> void:
	if contact != null:
		contact.active = true


func _vault_tick(_delta: float) -> void:
	if is_on_floor() and fsm.time_in_state > MIN_AIR_TIME:
		velocity.x = 0.0
		fsm.transition(&"windup")
	elif is_on_wall():
		velocity.x = 0.0


# ---------------------------------------------------------------------------
# 出手（沿用切割者的蓄力、撲斬、收招；從背後出手時預兆長一點）
# ---------------------------------------------------------------------------

func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	striking_from_behind = is_behind_player()
	_start_telegraph(windup_time())


## 這一次蓄力的秒數。
func windup_time() -> float:
	return data.telegraph_time + (_param("behind_telegraph") if striking_from_behind else 0.0)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < windup_time() * LOCK_RATIO:
		_face_target()
	if not is_telegraphing():
		fsm.transition(&"leap")


func _rig_state(input: RigInput) -> void:
	input.crouching = fsm.is_in(&"windup") or fsm.is_in(&"vault_tell")
	input.two_handed = false


func _draw_overlay() -> void:
	super._draw_overlay()
	# 翻越的預告：一條細弧線從腳下長到玩家背後的落腳點（預告越久畫得越長），落點有一道短刻痕。
	if fsm.is_in(&"vault_tell"):
		var t := clampf(fsm.time_in_state / maxf(0.01, _param("vault_tell")), 0.0, 1.0)
		var color := LightKit.glow(Palette.DANGER, 1.0 + 0.6 * t)
		color.a = 0.35 + 0.4 * t
		var to := to_local(_vault_target)
		var peak := -_vault_peak()
		var reach := 0.35 + 0.65 * t
		var points := PackedVector2Array()
		for i in range(ARC_POINTS + 1):
			var s := reach * float(i) / float(ARC_POINTS)
			points.append(Vector2(to.x * s, lerpf(0.0, to.y, s) + peak * 4.0 * s * (1.0 - s)))
		draw_polyline(points, color, 1.0)
		if t > 0.6:
			draw_line(to + Vector2(0, -6), to + Vector2(0, 1), color, 1.0)
