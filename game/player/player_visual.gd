class_name PlayerVisual
extends Node2D
## 玩家外觀：骨架角色「凜」＋ 疊加特效（護盾、近戰揮砍、終結技光環、槍口閃光、衝刺殘影）。
## 全年齡化設計：受傷時裝甲零件逐片脫落噴飛，看外觀就知道剩多少生命。
## 本節點不翻轉（骨架自己處理面向），疊加特效以世界方向繪製。

const SKIN_ID := "rin"
const FIRE_FLASH_TIME := 0.06
const FINISHER_FLASH_TIME := 0.2
## 擠壓伸展回彈速度（越大回彈越快）。
const SQUASH_RECOVERY := 14.0
const PARRY_FLASH_TIME := 0.25
const BLOCK_FLASH_TIME := 0.1
const SHIELD_RADIUS := 15.0
const GHOST_INTERVAL := 0.03
const GHOST_LIFETIME := 0.18
## 電話亭撥號：專屬動作名稱、話筒的手持外觀，以及動作進度中「拿起話筒」與「掛上話筒」的時間點（話筒只在這段期間在手上）。
const PHONE_ACTION := &"rin.phone_call"
const HANDSET_VISUAL := "handset"
const HANDSET_IN := 0.26
const HANDSET_OUT := 0.9

var player: Player
var rig: CharacterRig

var _input := RigInput.new()
var _time := 0.0
var _fire_flash := 0.0
var _fire_color := Palette.CYAN
var _finisher_flash := 0.0
var _parry_flash := 0.0
var _block_flash := 0.0
var _squash := Vector2.ONE
var _ghost_timer := 0.0
var _ghosts: Array[Vector3] = []  # x, y, 剩餘時間
var _phone_t := -1.0  # 撥號動作已經過的秒數；負值＝不在撥號
var _phone_weapon := ""


func _ready() -> void:
	LightKit.mark_emissive(self)
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.setup(SKIN_ID):
		push_error("[PlayerVisual] 主角骨架載入失敗，請確認 art/characters/%s。" % SKIN_ID)
	# 骨架畫在本節點的疊加特效之下。
	rig.show_behind_parent = true


## 身體中心離腳底的高度（近戰揮砍弧與終結技光環繞著它畫）：肩膀高度的約六成（原本 35 → 22）。
func body_center_height() -> float:
	return shoulder_height(false, 35.0) * 0.62


## 持槍基準點（肩膀）離腳底的高度：直接由骨架量出，蹲下時扣掉骨盆下沉量。骨架載入失敗時回傳 fallback。
func shoulder_height(crouching: bool, fallback: float) -> float:
	if rig == null or not rig.is_valid():
		return fallback
	var height := rig.anchor_height()
	if crouching:
		height -= (rig.animator.current_hip_drop() if rig.animator != null and bool(rig.animator._motion.get("grounding", false)) else HumanoidAnimator.CROUCH_DROP) * rig.body_scale()
	return height


func set_weapon_visual(visual_id: String) -> void:
	if rig != null:
		rig.set_weapon(visual_id)


## 槍口世界座標（骨架無效時退回角色前方）。
func muzzle_global() -> Vector2:
	if rig != null and rig.is_valid():
		return rig.muzzle_global()
	return player.aim_origin() + player.aim_dir * 12.0


func on_health_changed(ratio: float, decreased: bool) -> void:
	if rig != null:
		rig.set_armor_ratio(ratio, decreased)


func notify_fired(color: Color) -> void:
	_fire_flash = FIRE_FLASH_TIME
	_fire_color = color
	_input.recoil = 1.0


func notify_jump() -> void:
	_squash = Vector2(0.82, 1.18)


func notify_land(impact: float) -> void:
	var amount := lerpf(0.08, 0.22, impact)
	_squash = Vector2(1.0 + amount, 1.0 - amount)


func notify_parry() -> void:
	_parry_flash = PARRY_FLASH_TIME


func notify_block() -> void:
	_block_flash = BLOCK_FLASH_TIME


func notify_dash() -> void:
	_squash = Vector2(1.2, 0.86)


func notify_finisher() -> void:
	_finisher_flash = FINISHER_FLASH_TIME


## 開始撥號：先收起手上的武器（空手），動作進行到拿起話筒時換成話筒。
func begin_phone() -> void:
	_phone_t = 0.0
	_phone_weapon = ""
	set_weapon_visual("")


## 撥號結束：放回原本的武器。
func end_phone(weapon_visual_id: String) -> void:
	_phone_t = -1.0
	_input.action = &""
	_input.action_t = 0.0
	set_weapon_visual(weapon_visual_id)


## 撥號動作的進度 0~1（不在撥號時回傳 -1）。
func phone_progress() -> float:
	return clampf(_phone_t / Player.PHONE_DURATION, 0.0, 1.0) if _phone_t >= 0.0 else -1.0


func _update_phone(delta: float) -> void:
	if _phone_t < 0.0:
		return
	_phone_t += delta
	var progress := clampf(_phone_t / Player.PHONE_DURATION, 0.0, 1.0)
	_input.action = PHONE_ACTION
	_input.action_t = progress
	var want := HANDSET_VISUAL if progress >= HANDSET_IN and progress < HANDSET_OUT else ""
	if want != _phone_weapon:
		_phone_weapon = want
		set_weapon_visual(want)


func notify_hurt() -> void:
	_input.hurt = true
	if rig != null:
		rig.flash()


func _physics_process(delta: float) -> void:
	if player == null or rig == null:
		return
	_input.velocity = player.velocity
	_input.on_floor = player.is_on_floor()
	# 換彈時槍口壓低朝前下方。
	_input.aim_dir = player.aim_dir if not player.is_reloading() else Vector2(player.facing * 0.6, 0.8).normalized()
	_input.facing = player.facing
	_input.run_speed = player.tuning.run_speed
	_input.crouching = player.is_crouching
	_input.blocking = player.is_blocking
	_input.dashing = player.state == Player.State.DASH
	_input.staggered = player.state == Player.State.STAGGERED
	_input.dead = player.state == Player.State.DEAD
	_update_phone(delta)
	rig.animate(delta, _input)
	_input.recoil = 0.0
	_input.hurt = false


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	_fire_flash = maxf(0.0, _fire_flash - delta)
	_finisher_flash = maxf(0.0, _finisher_flash - delta)
	_parry_flash = maxf(0.0, _parry_flash - delta)
	_block_flash = maxf(0.0, _block_flash - delta)
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, SQUASH_RECOVERY * delta))
	scale = _squash
	_update_ghosts(delta)
	# 受傷無敵期間閃爍（衝刺／終結技的無敵不閃爍）。
	var blinking := player.health != null and player.health.is_invulnerable() \
			and player.state == Player.State.NORMAL and int(_time * 20.0) % 2 == 0
	modulate.a = 0.4 if blinking else 1.0
	visible = player.state != Player.State.MOUNTED
	queue_redraw()


func _update_ghosts(delta: float) -> void:
	for i in range(_ghosts.size() - 1, -1, -1):
		_ghosts[i].z -= delta
		if _ghosts[i].z <= 0.0:
			_ghosts.remove_at(i)
	if player.state == Player.State.DASH:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			_ghosts.append(Vector3(global_position.x, global_position.y, GHOST_LIFETIME))


func _draw() -> void:
	if player == null:
		return
	_draw_ghosts()
	if _fire_flash > 0.0:
		var t := _fire_flash / FIRE_FLASH_TIME
		var tip := to_local(muzzle_global())
		draw_circle(tip, 2.5 + 3.0 * t, LightKit.glow(_fire_color, 3.0))
		draw_line(tip, tip + player.aim_dir * 9.0 * t, LightKit.glow(Palette.WHITE, 3.0), 2.0)
	if player.is_melee_swinging():
		var f := float(player.facing)
		var center := Vector2(f * 8.0, -body_center_height())
		var start := -PI * 0.5 if f > 0.0 else PI * 0.5
		draw_arc(center, 18.0, start, start + PI * f, 14, LightKit.glow(Palette.CYAN, 2.0), 3.0)
	_draw_shield()
	if _finisher_flash > 0.0:
		var t := _finisher_flash / FINISHER_FLASH_TIME
		draw_arc(Vector2(0, -body_center_height()), 26.0 * (1.5 - t), 0.0, TAU, 28, Color(LightKit.glow(Palette.WHITE, 2.0), t), 2.0)


## 衝刺殘影：沿路徑留下漸淡的青色剪影。
func _draw_ghosts() -> void:
	for ghost in _ghosts:
		var local := to_local(Vector2(ghost.x, ghost.y))
		var alpha := ghost.z / GHOST_LIFETIME
		draw_rect(Rect2(local + Vector2(-6, -44), Vector2(12, 44)), Color(Palette.CYAN, 0.18 * alpha))
		draw_line(local + Vector2(0, -44), local, Color(LightKit.glow(Palette.CYAN, 1.5), 0.4 * alpha), 2.0)


## 能量護盾：沿準星方向的弧形；剛舉起（完美格擋時間窗）時更亮，完美格擋成功時爆閃。
func _draw_shield() -> void:
	if not player.is_blocking and _parry_flash <= 0.0:
		return
	var center := to_local(player.aim_origin()) + player.aim_dir * 6.0
	var angle := player.aim_dir.angle()
	var half_arc := deg_to_rad(player.tuning.block_arc_degrees * 0.5) * 0.8
	var guard_ratio := clampf(player.guard / player.tuning.guard_max, 0.0, 1.0)
	var intensity := 1.4 + (1.2 if player.is_parry_window() else 0.0) + _block_flash * 10.0 + _parry_flash * 8.0
	var color := LightKit.glow(Palette.CYAN.lerp(Palette.DANGER, 1.0 - guard_ratio), intensity)
	draw_arc(center, SHIELD_RADIUS, angle - half_arc, angle + half_arc, 16, Color(color, 0.25), 7.0)
	draw_arc(center, SHIELD_RADIUS, angle - half_arc, angle + half_arc, 16, color, 1.5)
	if _parry_flash > 0.0:
		var t := _parry_flash / PARRY_FLASH_TIME
		draw_arc(center, SHIELD_RADIUS + (1.0 - t) * 12.0, angle - half_arc, angle + half_arc, 16, Color(LightKit.glow(Palette.WHITE, 3.0), t), 2.0)
