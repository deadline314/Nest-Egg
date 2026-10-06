extends Enemy
## 哨戒砲台（固定狙擊）
## 行為：雷射瞄準線以有限轉速追蹤玩家 → 變粗變亮＝鎖定 → 發射高速子彈。
## 應對：鎖定瞬間立刻換位，或躲到掩體後切斷視線；本體耐打，也可以直接繞過。
## 所在區域被電力開關切斷電力時停擺（不再瞄準與射擊）。

const TURN_SPEED := 2.4
const LOCK_TIME := 0.35
const COOLDOWN_AFTER_FIRE := 0.4
const LASER_LENGTH := 400.0

var _aim := Vector2.LEFT
var _shaft: LightShaft
var _cooldown := 0.5


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"track", _track_tick, _track_enter)
	fsm.add(&"lock", _lock_tick)
	fsm.start(&"idle")


func _ready() -> void:
	super._ready()
	if data != null:
		_aim = Vector2(facing, 0)
		_shaft = LightShaft.new()
		_shaft.color = Palette.DANGER
		_shaft.length = LASER_LENGTH * 0.45
		_shaft.half_width = 16.0
		_shaft.halo_radius = 10.0
		_shaft.intensity = 0.0
		add_child(_shaft)


## 光錐跟著砲口與瞄準方向：追蹤時淡、鎖定時亮，待機時熄滅。
func _process(_delta: float) -> void:
	if _shaft == null:
		return
	_shaft.position = to_local(_muzzle())
	_shaft.direction = _aim
	_shaft.intensity = 1.0 if fsm.is_in(&"lock") else (0.45 if fsm.is_in(&"track") else 0.0)


func _on_stunned() -> void:
	fsm.transition(&"idle")


func _muzzle() -> Vector2:
	if creature != null:
		return creature.muzzle_global("barrel")
	return _pivot() + _aim * 10.0


## 砲塔頭與砲管跟著瞄準方向轉（零件隨面向左右翻，所以垂直分量不翻、水平取絕對值）。
func _creature_aim() -> float:
	return atan2(_aim.y, absf(_aim.x))


func _pivot() -> Vector2:
	if creature != null:
		return creature.muzzle_global("head")
	return global_position + Vector2(0, -data.body_size.y * 0.7)


func _idle_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown <= 0.0 and _token_free() and PowerGrid.is_powered(self) and _can_see_target(data.detect_range, 260.0):
		fsm.transition(&"track")


func _track_enter() -> void:
	_start_telegraph(data.telegraph_time + LOCK_TIME)


func _track_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	if not _has_line_of_sight() or not PowerGrid.is_powered(self):
		fsm.transition(&"idle")
		return
	_rotate_aim_toward(_target_point(), delta)
	if fsm.time_in_state >= data.telegraph_time:
		fsm.transition(&"lock")


func _lock_tick(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not PowerGrid.is_powered(self):
		fsm.transition(&"idle")
		return
	if fsm.time_in_state >= LOCK_TIME:
		_shoot(data.projectile, _aim)
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"idle")


func _rotate_aim_toward(point: Vector2, delta: float) -> void:
	var desired := (point - _pivot()).angle()
	var current := _aim.angle()
	var diff := wrapf(desired - current, -PI, PI)
	var step := clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
	_aim = Vector2.RIGHT.rotated(current + step)
	facing = 1 if _aim.x >= 0.0 else -1


func _draw_overlay() -> void:
	if not (fsm.is_in(&"track") or fsm.is_in(&"lock")):
		return
	var locked := fsm.is_in(&"lock")
	var color := LightKit.glow(Palette.DANGER, 2.8 if locked else 1.2)
	color.a = 0.9 if locked else 0.4
	var from := to_local(_muzzle())
	var to := from + _aim * LASER_LENGTH
	# 雷射被牆擋住時截斷，讓玩家清楚看到掩體有效。
	var query := PhysicsRayQueryParameters2D.create(_muzzle(), _muzzle() + _aim * LASER_LENGTH, Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = to_local(hit["position"])
	draw_line(from, to, color, 2.0 if locked else 1.0)


func _draw_body(color: Color) -> void:
	# 霓虹機械風：警示條紋底座、鉻金屬砲塔、紅色感測眼。
	var w := data.body_size.x
	var h := data.body_size.y
	var base := Rect2(-w * 0.6, -h * 0.45, w * 1.2, h * 0.45)
	draw_rect(base, Color("232838"))
	var stripe_x := base.position.x
	while stripe_x < base.end.x - 3.0:
		draw_colored_polygon(PackedVector2Array([Vector2(stripe_x, base.end.y), Vector2(stripe_x + 3, base.position.y),
				Vector2(stripe_x + 6, base.position.y), Vector2(stripe_x + 3, base.end.y)]), Color(Palette.NEON_YELLOW, 0.75))
		stripe_x += 8.0
	draw_rect(base, Color("07080d"), false, 1.0)
	var pivot := Vector2(0, -h * 0.7)
	var chrome := Color("9aa5b8") if color != Palette.WHITE else color
	draw_circle(pivot, w * 0.45, chrome.darkened(0.3))
	draw_arc(pivot, w * 0.45, PI, TAU, 16, chrome.lightened(0.2), 1.5)
	draw_line(pivot, pivot + _aim * 14.0, chrome.darkened(0.1), 4.0)
	draw_line(pivot + _aim * 12.0, pivot + _aim * 15.0, Color("07080d"), 4.0)
	var eye := LightKit.glow(Palette.DANGER, 3.4 if fsm.is_in(&"lock") else 1.6)
	draw_circle(pivot, 2.6, eye)
