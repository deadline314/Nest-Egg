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
## 整個節點的擠壓伸展只留下原本幅度的這個比例：起跳的伸展、落地的緩衝改由骨架動作（蹬地、膝蓋與骨盆吸收）負責，貼圖不再明顯變形。
const SQUASH_SCALE := 0.3
const PARRY_FLASH_TIME := 0.25
const BLOCK_FLASH_TIME := 0.1
const GHOST_LIFETIME := DashSilhouettePool.LIFETIME
const MAX_GHOSTS := DashSilhouettePool.CAPACITY
## 重生淡入秒數。
const MATERIALIZE_TIME := 0.7
const LASH_SEGMENTS := 10
## 軌跡一開始就已經掃過的比例（0~1，掃出弧度的段落在前 40%）。
const TRAIL_HEAD_START := 0.3
## 電話亭撥號：專屬動作名稱、話筒的手持外觀，以及動作進度中「拿起話筒」與「掛上話筒」的時間點（話筒只在這段期間在手上）。
const PHONE_ACTION := &"rin.phone_call"
const HANDSET_VISUAL := "handset"
const HANDSET_IN := 0.26
const HANDSET_OUT := 0.9
const MELEE_ACTION_PREFIX := "rin.melee_"
## 拿東西時收起了武器外觀，放下後要放回。
var _carry_hid_weapon := false
## 近戰武器平時的發光亮度、出招瞬間的亮度（有上限，HDR 泛光下不過曝）。
const MELEE_GLOW := 1.3
const MELEE_GLOW_SWING := 2.0

var player: Player
var rig: CharacterRig

var _input := RigInput.new()
var _time := 0.0
var _fire_flash := 0.0
## 進行中的揮砍軌跡：{age, trail（資料）, facing}；最多同時兩條，亮度有上限，不走粒子預算。
var _trails: Array[Dictionary] = []
## 手上的近戰武器（握在拳頭裡、有自己的重量）。
var _melee_held: MeleeHeld
## 近戰武器的刃光（真的光源）。
var _blade_light: BladeLight
var _fire_color := Palette.CYAN
var _finisher_flash := 0.0
var _parry_flash := 0.0
var _block_flash := 0.0
var _squash := Vector2.ONE
var _ghost_timer := 0.0
var _ghost_pool: DashSilhouettePool
## 重生淡入剩餘秒數（0＝沒有在重生）。
var _materialize_left := 0.0
var _phone_t := -1.0  # 撥號動作已經過的秒數；負值＝不在撥號
var _phone_weapon := ""
var _shield := ShieldSurface.new()


func _ready() -> void:
	LightKit.mark_emissive(self)
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.setup(SKIN_ID):
		push_error("[PlayerVisual] 主角骨架載入失敗，請確認 art/characters/%s。" % SKIN_ID)
	# 骨架畫在本節點的疊加特效之下。
	rig.show_behind_parent = true
	# 近戰武器排在骨架裡：比前手早畫、和前手同一層，所以在手臂前面、握拳的手指後面。
	_melee_held = MeleeHeld.new()
	_melee_held.name = "MeleeHeld"
	_melee_held.setup(self)
	var front_hand := rig.find_children("hand_front", "Sprite2D", true, false)
	_melee_held.z_index = (front_hand[0] as CanvasItem).z_index if not front_hand.is_empty() else 10
	rig.add_child(_melee_held)
	rig.move_child(_melee_held, 0)
	_blade_light = BladeLight.new()
	_blade_light.name = "BladeLight"
	add_child(_blade_light)
	# Attach a world-space sibling after the parent finishes spawning children.
	_attach_ghost_pool.call_deferred()


func _attach_ghost_pool() -> void:
	if is_instance_valid(_ghost_pool) or not is_inside_tree() or not is_instance_valid(player) or not is_instance_valid(player.get_parent()):
		return
	_ghost_pool = DashSilhouettePool.new()
	_ghost_pool.name = "DashSilhouettes"
	player.get_parent().add_child(_ghost_pool)


func _exit_tree() -> void:
	if is_instance_valid(_ghost_pool):
		_ghost_pool.clear()
		_ghost_pool.queue_free()
	_ghost_pool = null


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


## 揮砍軌跡開始。direction 是揮擊朝向（跟著準星的近戰武器會偏離水平）；零向量＝朝面向水平。
func notify_melee_swing(trail: Dictionary, swing_facing: int, direction := Vector2.ZERO) -> void:
	if trail.is_empty():
		return
	# 鞭類武器的鞭身自己會甩（NE-276），不再疊一條畫出來的波浪軌跡。
	if str(trail.get("style", "arc")) == "lash" and _melee_held != null and _melee_held.whip() != null and _melee_held.whip().is_laid():
		return
	if _trails.size() >= MeleeData.MAX_TRAILS:
		_trails.remove_at(0)
	var base := direction.angle() if direction != Vector2.ZERO else (0.0 if swing_facing > 0 else PI)
	# 起始就畫出一小段：命中頓幀會凍住玩家，凍結的那一刻軌跡要已經看得到，不能等解凍才開始揮。
	_trails.append({"age": float(trail.get("life", 0.1)) * TRAIL_HEAD_START, "trail": trail, "facing": swing_facing, "base": base})
	queue_redraw()  # 命中頓幀會馬上凍住這個節點的處理，所以這一影格就要重畫


## 腳步聲是否跟著骨架的落腳事件走（兩腳正在跑步落腳）；false 時（蹲著、骨架無效…）由玩家腳本依距離計步。
func is_stepping() -> bool:
	return rig != null and rig.is_valid() and rig.animator != null and rig.animator.is_stepping()


## 領走自上次呼叫以來的落腳次數（每隻腳著地一次）；骨架無效時回傳 0。
func consume_footfalls() -> int:
	return rig.animator.consume_footfalls() if rig != null and rig.is_valid() and rig.animator != null else 0


func notify_fired(color: Color) -> void:
	_fire_flash = FIRE_FLASH_TIME
	_fire_color = color
	_input.recoil = 1.0


func notify_jump() -> void:
	_squash = _soft_squash(Vector2(0.82, 1.18))
	_input.jumped = true


func notify_land(impact: float) -> void:
	var amount := lerpf(0.08, 0.22, impact)
	_squash = _soft_squash(Vector2(1.0 + amount, 1.0 - amount))
	_input.landed = maxf(impact, 0.01)


## 把擠壓縮放縮小到 SQUASH_SCALE（1,1 是不變形）。
func _soft_squash(full: Vector2) -> Vector2:
	return Vector2.ONE + (full - Vector2.ONE) * SQUASH_SCALE


func notify_parry(at := Vector2.INF) -> void:
	_parry_flash = PARRY_FLASH_TIME
	_shield.notify_impact(at - (player.global_position + Vector2(0, -Player.BODY_SIZE.y * 0.5)) if at.is_finite() and player != null else _shield.direction)


func notify_block(at := Vector2.INF) -> void:
	_block_flash = BLOCK_FLASH_TIME
	_shield.notify_impact(at - (player.global_position + Vector2(0, -Player.BODY_SIZE.y * 0.5)) if at.is_finite() and player != null else _shield.direction)


func notify_dash() -> void:
	_squash = _soft_squash(Vector2(1.2, 0.86))
	_input.dash_started = true


## Death is synchronous; hitstop/modal pause may prevent the next process tick.
## Retire all world-space samples before death FX or outward callbacks run.
func clear_dash_silhouettes() -> void:
	_ghost_timer = 0.0
	if is_instance_valid(_ghost_pool):
		_ghost_pool.clear()


## 重生：身體從光裡淡入（配合 PlayerFx.respawn 的光環與餘燼）。
func begin_materialize() -> void:
	_materialize_left = MATERIALIZE_TIME


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


## 近戰武器揮擊時播放對應的揮砍動作（資料的 pose → art/rigs/action_poses.json 的 rin.melee_<pose>）；撥號中不覆蓋。
func _update_melee_pose() -> void:
	if _phone_t >= 0.0:
		return
	if _update_carry_pose():
		return
	var pose := player.melee_pose() if player.holds_melee_weapon() else ""
	if pose.is_empty():
		_input.action = &""
		return
	_input.action = StringName(MELEE_ACTION_PREFIX + pose)
	_input.action_t = player.melee_pose_progress()


## 撿起、舉著、丟出（NE-254）：雙手空出來（收起武器外觀），播放 rin.carry_* 動作；結束後放回武器。回傳是否正在拿東西。
func _update_carry_pose() -> bool:
	var pose := player.carry.pose() if player.carry != null else &""
	if pose == &"":
		if _carry_hid_weapon:
			_carry_hid_weapon = false
			set_weapon_visual(player.visual_id_of_active_weapon())
		return false
	if not _carry_hid_weapon:
		_carry_hid_weapon = true
		set_weapon_visual("")
	_input.action = pose
	_input.action_t = player.carry.pose_progress()
	return true


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
	_update_melee_pose()
	_input.melee_grip = shows_melee_weapon()
	# 雙手武器：另一隻手握的點用上一格武器的位置（武器要等骨架動完才知道在哪）。
	_input.melee_second = _input.melee_grip and _melee_held.has_second_grip()
	if _input.melee_second:
		_input.melee_second_target = rig.to_local(_melee_held.second_grip())
		_input.melee_second_angle = _melee_held.angle()
	rig.animate(delta, _input)
	_melee_held.update(delta)
	_input.recoil = 0.0
	_input.hurt = false
	_input.jumped = false
	_input.landed = 0.0
	_input.dash_started = false


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	_blade_light.follow(self, delta)
	_fire_flash = maxf(0.0, _fire_flash - delta)
	for i in range(_trails.size() - 1, -1, -1):
		_trails[i]["age"] = float(_trails[i]["age"]) + delta
		if float(_trails[i]["age"]) >= float((_trails[i]["trail"] as Dictionary).get("life", 0.1)):
			_trails.remove_at(i)
	_finisher_flash = maxf(0.0, _finisher_flash - delta)
	_parry_flash = maxf(0.0, _parry_flash - delta)
	_block_flash = maxf(0.0, _block_flash - delta)
	_shield.update(delta, player.is_blocking, player.is_guard_broken(), player.aim_dir, player.tuning.block_arc_degrees)
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, SQUASH_RECOVERY * delta))
	scale = _squash
	# 受傷無敵期間閃爍（衝刺／終結技的無敵不閃爍）。
	var blinking := player.health != null and player.health.is_invulnerable() \
			and player.state == Player.State.NORMAL and int(_time * 20.0) % 2 == 0
	modulate.a = 0.4 if blinking else 1.0
	if _materialize_left > 0.0:
		_materialize_left = maxf(0.0, _materialize_left - delta)
		modulate.a = minf(modulate.a, 1.0 - _materialize_left / MATERIALIZE_TIME)
	visible = player.state != Player.State.MOUNTED
	# Sample after the current frame visibility/materialize alpha is applied.
	_update_ghosts(delta)
	queue_redraw()


func _update_ghosts(delta: float) -> void:
	if not is_instance_valid(_ghost_pool):
		return
	_ghost_pool.tick(delta)
	if (player.state == Player.State.DEAD or player.state == Player.State.MOUNTED) or not is_visible_in_tree():
		clear_dash_silhouettes()
		return
	if player.state != Player.State.DASH:
		_ghost_timer = 0.0
		return
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = DashSilhouettePool.sample_interval()
		_ghost_pool.capture(self)


## 揮砍軌跡：依樣式畫——arc 弧線先快速掃出一個弧再整條淡出（帶一格較細、較早的殘影）、thrust 沿揮擊方向戳出一道漸細的亮線、
## lash 甩出一條彎曲的鞭痕。顏色與樣式在招式資料的 trail（每把武器自己的色）；亮度限制在 TRAIL_BRIGHTNESS_MAX 以內。
func _draw_trail(entry: Dictionary) -> void:
	var trail: Dictionary = entry["trail"]
	var f := float(entry["facing"])
	var life := float(trail.get("life", 0.1))
	var progress := clampf(float(entry["age"]) / life, 0.0, 1.0)
	var sweep := minf(1.0, progress / 0.4)
	var fade := 1.0 - maxf(0.0, (progress - 0.4) / 0.6)
	var radius := float(trail.get("radius", 20.0))
	var arc := deg_to_rad(float(trail.get("arc", 130.0)))
	var center := Vector2(f * 8.0, -body_center_height())
	var base := float(entry.get("base", 0.0 if f > 0.0 else PI))
	var glow := minf(float(trail.get("brightness", 1.7)), MeleeData.TRAIL_BRIGHTNESS_MAX)
	var tint := Color.from_string(str(trail.get("color", "")), Palette.CYAN)
	var width := float(trail.get("width", 3.0))
	match str(trail.get("style", "arc")):
		"thrust":
			var dir := Vector2.RIGHT.rotated(base)
			var tip := center + dir * radius * sweep
			var tail := center + dir * radius * maxf(0.0, sweep - 0.55)
			draw_line(tail, tip, Color(LightKit.glow(tint, glow), fade), width)
			draw_line(tail.lerp(tip, 0.25), tip, Color(LightKit.glow(Palette.WHITE, glow * 0.8), fade * 0.8), maxf(1.0, width * 0.4))
		"lash":
			var dir := Vector2.RIGHT.rotated(base)
			var side := Vector2(-dir.y, dir.x)
			var previous := center
			for i in range(1, LASH_SEGMENTS + 1):
				var t := float(i) / LASH_SEGMENTS
				var wave := sin(t * TAU * 1.2 - progress * 9.0) * 6.0 * t * (1.0 - progress * 0.6)
				var point := center + dir * radius * sweep * t + side * wave
				draw_line(previous, point, Color(LightKit.glow(tint, glow), fade * (0.35 + 0.65 * t)), lerpf(width, width * 0.4, t))
				previous = point
		_:
			var start := base - arc * 0.5 * f
			var end := start + arc * sweep * f
			var color := Color(LightKit.glow(tint, glow), fade)
			draw_arc(center, radius, start, end, 18, color, width)
			draw_arc(center, radius * 0.92, start, end, 18, Color(LightKit.glow(Palette.WHITE, glow * 0.8), fade * 0.7), 1.2)
			if bool(trail.get("afterimage", false)) and sweep > 0.3:
				var back := start + arc * maxf(0.0, sweep - 0.3) * f
				draw_arc(center, radius * 0.85, start, back, 14, Color(LightKit.glow(tint, glow * 0.6), fade * 0.45), width * 0.5)


func _draw() -> void:
	if player == null:
		return
	_draw_materialize()
	if _fire_flash > 0.0:
		var t := _fire_flash / FIRE_FLASH_TIME
		var tip := to_local(muzzle_global())
		draw_circle(tip, 2.5 + 3.0 * t, LightKit.glow(_fire_color, 3.0))
		draw_line(tip, tip + player.aim_dir * 9.0 * t, LightKit.glow(Palette.WHITE, 3.0), 2.0)
	for entry in _trails:
		_draw_trail(entry)
	_draw_shield()
	if _finisher_flash > 0.0:
		var t := _finisher_flash / FINISHER_FLASH_TIME
		draw_arc(Vector2(0, -body_center_height()), 26.0 * (1.5 - t), 0.0, TAU, 28, Color(LightKit.glow(Palette.WHITE, 2.0), t), 2.0)


## 義體方向護盾：與實際方向判定共用身體中心；動畫不改防禦窗口。
func _draw_shield() -> void:
	var center := to_local(player.global_position + Vector2(0, -Player.BODY_SIZE.y * 0.5))
	var ratio := clampf(player.guard / maxf(player.tuning.guard_max, 0.001), 0.0, 1.0)
	var left := clampf(1.0 - player._block_time / maxf(player.parry_window_length(), 0.001), 0.0, 1.0)
	_shield.paint(self, center, ratio, player.is_parry_window(), left, _block_flash, _parry_flash,
		Settings.flash_scale(), Settings.get_feel_scale("shake"))


## 手上現在有沒有畫出近戰武器（撥號、乘載、骨架不可用時不畫）。
func shows_melee_weapon() -> bool:
	return player != null and player.holds_melee_weapon() and rig != null and rig.is_valid() and _phone_t < 0.0 \
			and rig.bone(&"hand_front") != null and rig.bone(&"arm_front_lower") != null


## 近戰武器握在哪裡、朝哪裡（世界座標）：origin 是掌心的握點，x 軸指向刃尖（由 MeleeHeld 算，含拿法與揮動時的拖曳）。
## 先用 shows_melee_weapon() 確認有在畫。
func melee_hold() -> Transform2D:
	return _melee_held.hold()


## 手上的近戰武器節點（量測與測試用）。
func melee_held() -> MeleeHeld:
	return _melee_held


## 重生淡入：腳下收攏的光環，加上一道由上往下收細的光柱。
func _draw_materialize() -> void:
	if _materialize_left <= 0.0:
		return
	var t := _materialize_left / MATERIALIZE_TIME
	var feet := Vector2.ZERO
	draw_arc(feet, 6.0 + 22.0 * t, 0.0, TAU, 28, Color(Fx.hdr(Palette.CYAN, 2.0), 0.8 * t), 1.5)
	var height := body_center_height() * 2.0
	var half_width := 3.0 + 7.0 * t
	draw_colored_polygon(PackedVector2Array([Vector2(-half_width, 0.0), Vector2(half_width, 0.0), Vector2(half_width * 0.4, -height), Vector2(-half_width * 0.4, -height)]), Color(Fx.hdr(Palette.CYAN, 1.5), 0.22 * t))
