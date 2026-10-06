class_name StrikeEnemy
extends Enemy
## 貼身與鎖鏈類攻擊的共用骨架：巡邏 → 靠近 → 預兆（地上顯示攻擊範圍）→ 出招（判定只在出招區間）→ 收招（輸出空檔）。
## 參數在 EnemyData.strike（見 StrikeSpec），各種武器（電鋸臂、液壓鉗、電漿鞭、鎖鏈鐵鉤）各自繼承這裡，只覆寫自己的出招與外觀。
## 公平性：預兆不短於最短預兆；判定框就是預兆畫出來的範圍；單次傷害不到 3、沒有一擊必殺；
## 預兆中被打斷或被完美格擋會暈眩並取消這一擊。

const FACE_LOCK_RATIO := 0.65
const APPROACH_GIVE_UP := 1.4
const RECOVER_FRICTION := 900.0

var spec: Dictionary = {}
var _cooldown := 0.6
## 目前這一輪出招的第幾次判定、以及這一次判定打過沒有（同一次判定只傷害一次）。
var _pass_index := 0
var _pass_hit := false
var _query_shape := RectangleShape2D.new()


func _ready() -> void:
	if data != null:
		spec = StrikeSpec.resolve(data)
	super._ready()


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"approach", _approach_tick)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"strike", _strike_tick, _strike_enter, _strike_exit)
	fsm.add(&"recover", _recover_tick, _recover_enter)
	fsm.start(&"patrol")


func _on_stunned() -> void:
	if fsm.is_in(&"windup") or fsm.is_in(&"strike") or fsm.is_in(&"approach"):
		fsm.transition(&"recover")


# ---------------------------------------------------------------------------
# 狀態
# ---------------------------------------------------------------------------

func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	if _cooldown <= 0.0 and _token_free() and _can_see_target(data.detect_range, 70.0):
		fsm.transition(&"approach")


func _approach_tick(_delta: float) -> void:
	_face_target()
	var gap := _distance_to_target()
	if gap > data.detect_range * APPROACH_GIVE_UP or not _has_line_of_sight():
		fsm.transition(&"patrol")
		return
	if gap <= float(spec["start_range"]):
		velocity.x = 0.0
		fsm.transition(&"windup")
		return
	velocity.x = 0.0 if (is_on_floor() and (is_on_wall() or _is_ledge_ahead())) else facing * data.move_speed * 1.25


func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(data.telegraph_time)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state < data.telegraph_time * FACE_LOCK_RATIO:
		_face_target()
	if not is_telegraphing():
		fsm.transition(&"strike")


func _strike_enter() -> void:
	_pass_index = 0
	_pass_hit = false
	velocity.x = facing * float(spec["advance"])
	CharacterSounds.play(data.id, &"attack", -6.0)


func _strike_tick(_delta: float) -> void:
	velocity.x = facing * float(spec["advance"])
	var hits := int(spec["hits"])
	var active := float(spec["active"])
	# 出招區間內平均分配 hits 次判定；每次判定只傷害一次。
	while _pass_index < hits and fsm.time_in_state >= active * float(_pass_index) / float(hits):
		_pass_index += 1
		_pass_hit = false
		_strike_pass()
	if fsm.time_in_state >= active:
		fsm.transition(&"recover")


func _strike_exit() -> void:
	velocity.x *= 0.3


func _recover_enter() -> void:
	_telegraph_left = 0.0


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, RECOVER_FRICTION * delta)
	if fsm.time_in_state >= data.ability_time:
		_face_target()
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"patrol")


# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------

## 這一次出招用的高度帶（離腳底）；電漿鞭覆寫成這次抽中的那一條。
func _band() -> Vector2:
	return StrikeSpec.band_of(spec)


## 判定框（本地座標，與預兆畫出來的是同一個框）。
func _strike_rect() -> Rect2:
	var band := _band()
	var reach := float(spec["reach"])
	var from := float(spec["reach_from"])
	var x := from if facing > 0 else -from - reach
	return Rect2(Vector2(x, -band.y), Vector2(reach, band.y - band.x))


## 出招的一次判定：框內有玩家就傷害一次（被格擋、無敵時由受擊框處理）。回傳是否命中。
func _strike_pass() -> bool:
	if _pass_hit:
		return false
	var rect := _strike_rect()
	return _hit_player_in(global_position + rect.get_center(), rect.size)


func _hit_player_in(center: Vector2, size: Vector2) -> bool:
	_query_shape.size = size
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _query_shape
	params.transform = Transform2D(0.0, center)
	params.collision_mask = Layers.PLAYER_HURTBOX
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 4):
		var hurtbox := hit.get("collider") as Hurtbox
		if hurtbox != null and _hit_hurtbox(hurtbox, int(spec["damage"])):
			return true
	return false


## 對一個玩家受擊框造成一次傷害；回傳是否算命中（被格擋與無敵不算）。
func _hit_hurtbox(hurtbox: Hurtbox, amount: int) -> bool:
	var side := signf(hurtbox.global_position.x - global_position.x)
	if side == 0.0:
		side = float(facing)
	var knock: Array = spec["knockback"]
	var info := DamageInfo.create(amount, Combat.Team.ENEMY, StringName(str(spec["source_id"])), Vector2(side * float(knock[0]), float(knock[1])))
	info.origin = _center()
	info.attacker = weakref(self)
	var result := hurtbox.receive(info)
	if result == Hurtbox.Result.DAMAGED:
		_pass_hit = true
		return true
	return result == Hurtbox.Result.BLOCKED


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _rig_aim() -> Vector2:
	if fsm.is_in(&"windup"):
		return Vector2(-facing * 0.5, -0.85).normalized()
	if fsm.is_in(&"strike"):
		return Vector2(facing, 0.15).normalized()
	return Vector2(facing, 0.9).normalized()


func _rig_state(input: RigInput) -> void:
	input.two_handed = false


## 預兆：地上畫出判定框（越接近出招越亮），讓玩家看得出攻擊的外型、範圍與高低。
func _draw_telegraph_band() -> void:
	var t := clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0)
	var rect := _strike_rect()
	var fill := LightKit.glow(Palette.DANGER, 0.8 + 0.8 * t)
	fill.a = 0.1 + 0.22 * t
	draw_rect(rect, fill)
	var edge := LightKit.glow(Palette.DANGER, 1.0 + 1.2 * t)
	edge.a = 0.35 + 0.5 * t
	draw_rect(rect, edge, false, 1.0)


func _draw_overlay() -> void:
	if fsm.is_in(&"windup"):
		_draw_telegraph_band()
	_draw_weapon()


## 武器外觀（各子類別覆寫）；骨架的前手位置用 _hand_point()。
func _draw_weapon() -> void:
	pass


## 前手的本地座標與前臂朝向（沒有骨架時回傳身體前方的預設位置）。
func _hand_point() -> Vector2:
	if rig != null:
		var hand := rig.bone(&"hand_front")
		if hand != null:
			return to_local(hand.global_position)
	return Vector2(facing * 6.0, -data.body_size.y * 0.55)


func _hand_dir() -> Vector2:
	if rig != null:
		var hand := rig.bone(&"hand_front")
		var forearm := rig.bone(&"arm_front_lower")
		if hand != null and forearm != null and hand.global_position.distance_to(forearm.global_position) > 0.01:
			return (hand.global_position - forearm.global_position).normalized()
	return Vector2(facing, 0.3).normalized()


func _draw_body(color: Color) -> void:
	var f := float(facing)
	var h := data.body_size.y
	draw_line(Vector2(-3, -h * 0.4), Vector2(-3, 0), color.darkened(0.45), 3.0)
	draw_line(Vector2(3, -h * 0.4), Vector2(3, 0), color.darkened(0.45), 3.0)
	draw_rect(Rect2(-5, -h * 0.78, 10, h * 0.4), color)
	draw_circle(Vector2(f, -h * 0.86), 4.0, color.darkened(0.3))
