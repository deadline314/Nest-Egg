class_name PlayerVisual
extends Node2D
## 玩家外觀（暫代美術，全部以程式繪製）。
## 全年齡化設計：以「裝甲片逐片剝落、光紋變暗」表現受傷程度，取代原作的服裝破損。

const ARMOR_PLATES: Array[Rect2] = [
	Rect2(-5, -18, 3, 3),  # 左肩
	Rect2(2, -18, 3, 3),   # 右肩
	Rect2(-3, -16, 6, 4),  # 胸甲
	Rect2(-4, -11, 8, 2),  # 腰帶
	Rect2(-4, -8, 3, 3),   # 左腿甲
	Rect2(1, -8, 3, 3),    # 右腿甲
]
const FIRE_FLASH_TIME := 0.06
const FINISHER_FLASH_TIME := 0.2
## 擠壓伸展回彈速度（越大回彈越快）。
const SQUASH_RECOVERY := 14.0
const RECOIL_KICK := 3.0
const PARRY_FLASH_TIME := 0.25
const BLOCK_FLASH_TIME := 0.1
const SHIELD_RADIUS := 13.0

var player: Player

var _time := 0.0
var _fire_flash := 0.0
var _fire_color := Palette.CYAN
var _finisher_flash := 0.0
var _last_plate_count := -1
var _parry_flash := 0.0
var _block_flash := 0.0
var _squash := Vector2.ONE
var _recoil := 0.0


func notify_fired(color: Color) -> void:
	_fire_flash = FIRE_FLASH_TIME
	_fire_color = color
	_recoil = RECOIL_KICK


func notify_jump() -> void:
	_squash = Vector2(0.75, 1.25)


func notify_land(impact: float) -> void:
	var amount := lerpf(0.12, 0.35, impact)
	_squash = Vector2(1.0 + amount, 1.0 - amount)


func notify_parry() -> void:
	_parry_flash = PARRY_FLASH_TIME


func notify_block() -> void:
	_block_flash = BLOCK_FLASH_TIME


func notify_dash() -> void:
	_squash = Vector2(1.3, 0.8)


func notify_finisher() -> void:
	_finisher_flash = FINISHER_FLASH_TIME


func notify_hurt() -> void:
	var plates := _plate_count()
	if _last_plate_count > plates:
		# 剝落的裝甲片化為碎片噴出。
		Fx.burst(global_position + Vector2(0, -12), Palette.ARMOR, 6 * (_last_plate_count - plates), 140.0, 0.45)
	_last_plate_count = plates


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	_fire_flash = maxf(0.0, _fire_flash - delta)
	_finisher_flash = maxf(0.0, _finisher_flash - delta)
	_parry_flash = maxf(0.0, _parry_flash - delta)
	_block_flash = maxf(0.0, _block_flash - delta)
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, SQUASH_RECOVERY * delta))
	_recoil = move_toward(_recoil, 0.0, 40.0 * delta)
	scale = _squash
	if _last_plate_count < 0:
		_last_plate_count = _plate_count()
	# 受傷無敵期間閃爍（衝刺／終結技的無敵不閃爍）。
	var blinking := player.health != null and player.health.is_invulnerable() \
			and player.state == Player.State.NORMAL and int(_time * 20.0) % 2 == 0
	modulate.a = 0.35 if blinking else 1.0
	visible = player.state != Player.State.DEAD and player.state != Player.State.MOUNTED
	queue_redraw()


func _plate_count() -> int:
	if player == null or player.health == null:
		return ARMOR_PLATES.size()
	return ceili(player.health.ratio() * ARMOR_PLATES.size())


func _draw() -> void:
	if player == null:
		return
	var f := float(player.facing)
	var crouch := 6.0 if player.is_crouching else 0.0
	var running := player.is_on_floor() and absf(player.velocity.x) > 10.0
	var stride := sin(_time * 18.0) * 2.5 if running else 0.0
	var glow := Palette.CYAN.lerp(Palette.CYAN_DIM, 1.0 - player.health.ratio())

	if player.state == Player.State.DASH:
		draw_rect(Rect2(-f * 16.0 - 5.0, -20, 10, 18), Color(Palette.CYAN, 0.25))
		draw_rect(Rect2(-f * 9.0 - 5.0, -20, 10, 18), Color(Palette.CYAN, 0.4))

	# 腿
	draw_line(Vector2(-2, -9 + crouch * 0.5), Vector2(-2 + stride, 0), Palette.SUIT, 3.0)
	draw_line(Vector2(2, -9 + crouch * 0.5), Vector2(2 - stride, 0), Palette.SUIT, 3.0)
	# 軀幹
	draw_rect(Rect2(-4, -18 + crouch, 8, 10), Palette.SUIT)
	draw_line(Vector2(0, -17 + crouch), Vector2(0, -9 + crouch), LightKit.glow(glow, 1.6), 1.0)
	# 裝甲片（數量 = 剩餘生命比例）
	var plates := _plate_count()
	for i in plates:
		var rect: Rect2 = ARMOR_PLATES[i]
		rect.position.x *= f
		if f < 0.0:
			rect.position.x -= rect.size.x
		rect.position.y += crouch
		draw_rect(rect, Palette.ARMOR)
	# 頭與護目鏡
	var head := Vector2(0, -21 + crouch)
	draw_circle(head, 3.5, Palette.SUIT)
	draw_line(head + Vector2(-1 * f, -0.5), head + Vector2(3.5 * f, -0.5), LightKit.glow(glow, 2.0), 1.5)
	# 長髮（全年齡角色辨識度）
	draw_line(head + Vector2(-2.5 * f, -2), head + Vector2(-5 * f, 4), Palette.CYAN_DIM, 2.0)

	# 手臂砲管指向瞄準方向
	# 開槍時砲管往後縮（視覺後座）。
	var shoulder := Vector2(0, -14 + crouch)
	var muzzle := shoulder + player.aim_dir * (9.0 - _recoil)
	draw_line(shoulder, muzzle, Palette.ARMOR, 3.0)
	draw_circle(muzzle, 1.5, LightKit.glow(glow, 1.5))
	if _fire_flash > 0.0:
		var flash_t := _fire_flash / FIRE_FLASH_TIME
		var tip := muzzle + player.aim_dir * 3.0
		draw_circle(tip, 2.5 + 2.5 * flash_t, LightKit.glow(_fire_color, 3.0))
		draw_line(tip, tip + player.aim_dir * 7.0 * flash_t, LightKit.glow(Palette.WHITE, 3.0), 2.0)

	if player.is_melee_swinging():
		var center := Vector2(f * 6.0, -12)
		var start := -PI * 0.5 if f > 0.0 else PI * 0.5
		draw_arc(center, 13.0, start, start + PI * f, 12, Color(Palette.CYAN, 0.85), 3.0)

	_draw_shield()

	if _finisher_flash > 0.0:
		var t := _finisher_flash / FINISHER_FLASH_TIME
		draw_arc(Vector2(0, -12), 18.0 * (1.5 - t), 0.0, TAU, 24, Color(Palette.WHITE, t), 2.0)


## 能量護盾：沿準星方向的弧形；剛舉起（完美格擋時間窗）時更亮，完美格擋成功時爆閃。
func _draw_shield() -> void:
	if not player.is_blocking and _parry_flash <= 0.0:
		return
	# 本節點會依面向左右翻轉，因此把準星方向換回本地座標。
	var local_aim := Vector2(player.aim_dir.x * player.facing, player.aim_dir.y)
	var center := Vector2(0, -14) + local_aim * 4.0
	var angle := local_aim.angle()
	var half_arc := deg_to_rad(player.tuning.block_arc_degrees * 0.5) * 0.8
	var guard_ratio := clampf(player.guard / player.tuning.guard_max, 0.0, 1.0)
	var intensity := 1.4 + (1.2 if player.is_parry_window() else 0.0) + _block_flash * 10.0 + _parry_flash * 8.0
	var color := LightKit.glow(Palette.CYAN.lerp(Palette.DANGER, 1.0 - guard_ratio), intensity)
	draw_arc(center, SHIELD_RADIUS, angle - half_arc, angle + half_arc, 14, Color(color, 0.25), 6.0)
	draw_arc(center, SHIELD_RADIUS, angle - half_arc, angle + half_arc, 14, color, 1.5)
	if _parry_flash > 0.0:
		var t := _parry_flash / PARRY_FLASH_TIME
		draw_arc(center, SHIELD_RADIUS + (1.0 - t) * 10.0, angle - half_arc, angle + half_arc, 14, Color(LightKit.glow(Palette.WHITE, 3.0), t), 2.0)

