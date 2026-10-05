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
const SHIELD_RADIUS := 15.0
const GHOST_INTERVAL := 0.03
const GHOST_LIFETIME := 0.18
const MAX_GHOSTS := 8
## 衝刺速度線的條數與長度、重生淡入秒數、完美反彈星芒的射線數。
const STREAK_COUNT := 3
const STREAK_LENGTH := 34.0
const MATERIALIZE_TIME := 0.7
const PARRY_RAYS := 8
const LASH_SEGMENTS := 10
## 軌跡一開始就已經掃過的比例（0~1，掃出弧度的段落在前 40%）。
const TRAIL_HEAD_START := 0.3
## 電話亭撥號：專屬動作名稱、話筒的手持外觀，以及動作進度中「拿起話筒」與「掛上話筒」的時間點（話筒只在這段期間在手上）。
const PHONE_ACTION := &"rin.phone_call"
const HANDSET_VISUAL := "handset"
const HANDSET_IN := 0.26
const HANDSET_OUT := 0.9
const MELEE_ACTION_PREFIX := "rin.melee_"
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
var _fire_color := Palette.CYAN
var _finisher_flash := 0.0
var _parry_flash := 0.0
var _block_flash := 0.0
var _squash := Vector2.ONE
var _ghost_timer := 0.0
var _ghosts: Array[Vector4] = []  # x, y, 剩餘時間, 衝刺方向（±1）；固定上限，見 MAX_GHOSTS
var _dash_dir := 1.0
## 重生淡入剩餘秒數（0＝沒有在重生）。
var _materialize_left := 0.0
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


## 揮砍軌跡開始。direction 是揮擊朝向（跟著準星的近戰武器會偏離水平）；零向量＝朝面向水平。
func notify_melee_swing(trail: Dictionary, swing_facing: int, direction := Vector2.ZERO) -> void:
	if trail.is_empty():
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


func notify_parry() -> void:
	_parry_flash = PARRY_FLASH_TIME


func notify_block() -> void:
	_block_flash = BLOCK_FLASH_TIME


func notify_dash() -> void:
	_squash = _soft_squash(Vector2(1.2, 0.86))
	_input.dash_started = true


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
	var pose := player.melee_pose() if player.holds_melee_weapon() else ""
	if pose.is_empty():
		_input.action = &""
		return
	_input.action = StringName(MELEE_ACTION_PREFIX + pose)
	_input.action_t = player.melee_pose_progress()


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
	rig.animate(delta, _input)
	_input.recoil = 0.0
	_input.hurt = false
	_input.jumped = false
	_input.landed = 0.0
	_input.dash_started = false


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	_fire_flash = maxf(0.0, _fire_flash - delta)
	for i in range(_trails.size() - 1, -1, -1):
		_trails[i]["age"] = float(_trails[i]["age"]) + delta
		if float(_trails[i]["age"]) >= float((_trails[i]["trail"] as Dictionary).get("life", 0.1)):
			_trails.remove_at(i)
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
	if _materialize_left > 0.0:
		_materialize_left = maxf(0.0, _materialize_left - delta)
		modulate.a = minf(modulate.a, 1.0 - _materialize_left / MATERIALIZE_TIME)
	visible = player.state != Player.State.MOUNTED
	queue_redraw()


func _update_ghosts(delta: float) -> void:
	for i in range(_ghosts.size() - 1, -1, -1):
		_ghosts[i].z -= delta
		if _ghosts[i].z <= 0.0:
			_ghosts.remove_at(i)
	if player.state == Player.State.DASH:
		_dash_dir = signf(player.velocity.x) if absf(player.velocity.x) > 1.0 else _dash_dir
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			if _ghosts.size() >= MAX_GHOSTS:
				_ghosts.remove_at(0)
			_ghosts.append(Vector4(global_position.x, global_position.y, GHOST_LIFETIME, _dash_dir))


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
	_draw_ghosts()
	_draw_materialize()
	_draw_melee_weapon()
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


## 衝刺殘影：沿路徑留下漸淡的青色人形剪影（頭、前傾的軀幹、跨步的腿），加上身後幾道速度線。
func _draw_ghosts() -> void:
	for ghost in _ghosts:
		var local := to_local(Vector2(ghost.x, ghost.y))
		var alpha := ghost.z / GHOST_LIFETIME
		var lean := ghost.w * 6.0
		var body := Color(LightKit.glow(Palette.CYAN, 1.3), 0.3 * alpha)
		var head := local + Vector2(lean * 1.4, -40.0)
		var hip := local + Vector2(0.0, -18.0)
		draw_circle(head, 4.2, body)
		# 軀幹：肩寬、腰窄的梯形，朝衝刺方向前傾。
		draw_colored_polygon(PackedVector2Array([head + Vector2(-5.0, 4.0), head + Vector2(5.0, 4.0), hip + Vector2(3.0, 0.0), hip + Vector2(-3.0, 0.0)]), body)
		draw_line(hip, local + Vector2(-ghost.w * 6.0, 0.0), body, 3.5)
		draw_line(hip, local + Vector2(ghost.w * 8.0, -2.0), body, 3.5)
		draw_line(head + Vector2(0.0, 8.0), head + Vector2(ghost.w * 9.0, 12.0), body, 2.5)
	if player.state == Player.State.DASH:
		for i in STREAK_COUNT:
			var y := -10.0 - float(i) * 12.0
			var length := STREAK_LENGTH * (0.55 + 0.45 * float((i * 7) % 3) / 2.0)
			var from := Vector2(-_dash_dir * 6.0, y)
			draw_line(from, from + Vector2(-_dash_dir * length, 0.0), Color(LightKit.glow(Palette.CYAN, 1.4), 0.4), 1.2)


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
	if player.is_parry_window():
		# 窗口提示：外圈隨剩餘時間收進盾面，收到盾上就是窗口結束。
		var left := clampf(1.0 - player._block_time / player.parry_window_length(), 0.0, 1.0)
		draw_arc(center, SHIELD_RADIUS + 2.0 + 9.0 * left, angle - half_arc, angle + half_arc, 16, Color(LightKit.glow(Palette.WHITE, 2.0), 0.35 + 0.5 * left), 1.5)
	if _parry_flash > 0.0:
		var t := _parry_flash / PARRY_FLASH_TIME
		draw_arc(center, SHIELD_RADIUS + (1.0 - t) * 12.0, angle - half_arc, angle + half_arc, 16, Color(Fx.hdr(Palette.WHITE, 3.0), t), 2.0)
		# 星芒：從盾面中心向外的射線，隨時間變長、變淡。
		for i in PARRY_RAYS:
			var ray := Vector2.RIGHT.rotated(angle + float(i) / PARRY_RAYS * TAU)
			var inner := 4.0 + (1.0 - t) * 6.0
			var outer := inner + (6.0 if i % 2 == 0 else 3.5) * (0.4 + (1.0 - t))
			draw_line(center + ray * inner, center + ray * outer, Color(Fx.hdr(Palette.WHITE, 2.4), t), 1.2)


## 手上的近戰武器：接在骨架前手上、沿前臂方向延伸，跟著揮砍動作轉；出招時更亮。撥號與乘載時不畫。
func _draw_melee_weapon() -> void:
	if not player.holds_melee_weapon() or rig == null or not rig.is_valid() or _phone_t >= 0.0:
		return
	var hand := rig.bone(&"hand_front")
	var forearm := rig.bone(&"arm_front_lower")
	if hand == null or forearm == null:
		return
	var along := (hand.global_position - forearm.global_position).normalized()
	var glow := MELEE_GLOW_SWING if player.is_melee_swinging() else MELEE_GLOW
	MeleeArt.draw(self, to_local(hand.global_position), along, player.loadout.active_weapon(), glow)


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
