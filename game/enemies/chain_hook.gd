extends StrikeEnemy
## 鎖鏈鐵鉤（把玩家拉近）
## 行為：發現玩家後抖動鎖鏈蓄力（地上畫出鉤子要飛的路線），甩出鐵鉤；鉤中玩家就把人拖到面前，拖到了再捅一下。
## 應對：預兆時離開那條線、跳過鉤子或舉盾擋下（擋下鉤子會彈回）；被鉤住後有三種解法——
##       衝刺掙脫、用子彈或近戰打斷鎖鏈（鎖鏈中段有受擊框）、或直接打暈鉤子的主人。拉扯有時間上限；被拖到牆邊就停，不會卡進牆裡。
## 數值（EnemyData.strike）：throw_range 射程、throw_speed 飛行速度、reel_speed 拉扯速度、reel_time 最長拉扯秒數、chain_health 鎖鏈耐久、stab_damage 拉到面前的一擊。

const HOOK_RADIUS := 5.0
const CHAIN_LINK_SIZE := Vector2(14.0, 14.0)
const ARRIVE_DISTANCE := 26.0
const BREAK_STUN := 0.9
const WALL_MASK_FALLBACK := 1

var _throw_dir := Vector2.RIGHT
var _hook_pos := Vector2.ZERO
var _hook_travel := 0.0
var _retract := false
var _hooked_player: Player
var _reel_left := 0.0
var _link_health: HealthComponent
var _link: Hurtbox


func _setup_states() -> void:
	super._setup_states()
	fsm.add(&"throw", _throw_tick, _throw_enter)
	fsm.add(&"reel", _reel_tick, _reel_enter, _reel_exit)


func _on_stunned() -> void:
	if fsm.is_in(&"throw") or fsm.is_in(&"reel"):
		_release()
		fsm.transition(&"recover")
		return
	super._on_stunned()


func _exit_tree() -> void:
	_release()


## 預兆：鎖鏈的路線（直線）取代矩形，讓玩家看出鉤子會往哪裡飛；後段鎖定方向。
func _windup_tick(delta: float) -> void:
	super._windup_tick(delta)
	if fsm.time_in_state < data.telegraph_time * FACE_LOCK_RATIO:
		_throw_dir = _aim_at_target()


func _strike_enter() -> void:
	# 鉤子不走一般的出招判定，直接進入甩出。
	fsm.transition.call_deferred(&"throw")


func _aim_at_target() -> Vector2:
	var dir := (_target_point() - _hand_world()).normalized()
	if absf(dir.x) < 0.2:
		dir.x = 0.2 * facing
	return dir.normalized()


func _hand_world() -> Vector2:
	return global_position + _hand_point()


# --- 甩出 ---------------------------------------------------------------

func _throw_enter() -> void:
	velocity.x = 0.0
	_hook_pos = _hand_world()
	_hook_travel = 0.0
	_retract = false
	_pass_hit = false
	CharacterSounds.play(data.id, &"attack", -6.0)


func _throw_tick(delta: float) -> void:
	velocity.x = 0.0
	var speed := float(spec["throw_speed"])
	var step := speed * delta
	if _retract:
		var home := _hand_world()
		_hook_pos = _hook_pos.move_toward(home, step * 1.6)
		if _hook_pos.distance_to(home) < 4.0:
			fsm.transition(&"recover")
		return
	var next := _hook_pos + _throw_dir * step
	if _blocked_by_wall(_hook_pos, next) or _hook_travel + step >= float(spec["throw_range"]):
		_retract = true
		return
	_hook_pos = next
	_hook_travel += step
	_check_hook_hit()


func _blocked_by_wall(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.SOLID)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _check_hook_hit() -> void:
	var shape := CircleShape2D.new()
	shape.radius = HOOK_RADIUS
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, _hook_pos)
	params.collision_mask = Layers.PLAYER_HURTBOX
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 2):
		var hurtbox := hit.get("collider") as Hurtbox
		if hurtbox == null:
			continue
		var player := hurtbox.get_parent() as Player
		var side := signf(_hook_pos.x - global_position.x)
		var info := DamageInfo.create(int(spec["damage"]), Combat.Team.ENEMY, StringName(str(spec["source_id"])), Vector2(side * 60.0, -40.0))
		info.origin = _center()
		info.attacker = weakref(self)
		match hurtbox.receive(info):
			Hurtbox.Result.DAMAGED:
				if player != null:
					_hooked_player = player
					fsm.transition(&"reel")
					return
				_retract = true
				return
			Hurtbox.Result.BLOCKED:
				Fx.impact(_hook_pos, -_throw_dir, Palette.CYAN, 6)
				_retract = true
				return
			_:
				continue


# --- 拉扯 ---------------------------------------------------------------

func _reel_enter() -> void:
	_reel_left = float(spec["reel_time"])
	velocity.x = 0.0
	_build_link()
	if _hooked_player != null:
		_hooked_player.begin_pull(self, float(spec["reel_speed"]), _reel_left)
	EventBus.toast_requested.emit("被鉤住了：衝刺掙脫，或打斷鎖鏈")


func _reel_tick(delta: float) -> void:
	velocity.x = 0.0
	_reel_left -= delta
	if _hooked_player == null or not is_instance_valid(_hooked_player) or _hooked_player.is_dead() or not _hooked_player.is_pulled():
		_release()
		fsm.transition(&"recover")
		return
	_hook_pos = _hooked_player.global_position + Vector2(0.0, -_hooked_player.BODY_SIZE.y * 0.5)
	_move_link()
	var gap := absf(_hooked_player.global_position.x - global_position.x)
	if gap <= ARRIVE_DISTANCE:
		_stab()
		return
	if _reel_left <= 0.0:
		_release()
		fsm.transition(&"recover")


func _reel_exit() -> void:
	_release()


## 拉到面前的一擊。
func _stab() -> void:
	var player := _hooked_player
	_release()
	if player != null and is_instance_valid(player):
		var hurtbox := player.hurtbox
		var info := DamageInfo.create(int(spec["stab_damage"]), Combat.Team.ENEMY, StringName(str(spec["source_id"])), Vector2(signf(player.global_position.x - global_position.x) * 200.0, -90.0))
		info.origin = _center()
		info.attacker = weakref(self)
		hurtbox.receive(info)
		Fx.impact(player.global_position + Vector2(0, -20), Vector2(facing, -0.2), Palette.DANGER, 8)
	fsm.transition(&"recover")


## 解除拉扯並移除鎖鏈的受擊框（重複呼叫安全）。
func _release() -> void:
	if _hooked_player != null and is_instance_valid(_hooked_player):
		_hooked_player.end_pull()
	_hooked_player = null
	if _link != null and is_instance_valid(_link):
		_link.queue_free()
	if _link_health != null and is_instance_valid(_link_health):
		_link_health.queue_free()
	_link = null
	_link_health = null


func _build_link() -> void:
	_link_health = HealthComponent.new()
	add_child(_link_health)
	_link_health.setup(maxi(1, int(spec["chain_health"])), 0.0)
	_link_health.died.connect(_on_chain_broken)
	_link = Hurtbox.new()
	add_child(_link)
	_link.setup(Combat.Team.ENEMY, _link_health, CHAIN_LINK_SIZE)
	_link.hit_material = &"metal"
	_move_link()


func _move_link() -> void:
	if _link != null and is_instance_valid(_link):
		_link.global_position = (_hand_world() + _hook_pos) * 0.5


## 鎖鏈被打斷：玩家恢復自由，鉤子的主人短暫暈眩。
func _on_chain_broken(_info: DamageInfo) -> void:
	var at := _link.global_position if _link != null else _hook_pos
	Fx.burst(at, Palette.WARNING, 10, 180.0, 0.3)
	Sfx.play_named(&"block", -4.0)
	_release()
	stun(BREAK_STUN)


# --- 外觀 ---------------------------------------------------------------

func _rig_aim() -> Vector2:
	if fsm.is_in(&"windup"):
		return Vector2(-facing * 0.5, -0.85).normalized()
	if fsm.is_in(&"throw") or fsm.is_in(&"reel"):
		return _throw_dir
	return Vector2(facing, 0.9).normalized()


func _draw_telegraph_band() -> void:
	var t := clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0)
	var from := _hand_point()
	var to := from + _throw_dir * float(spec["throw_range"])
	var color := LightKit.glow(Palette.DANGER, 1.0 + 1.2 * t)
	color.a = 0.25 + 0.55 * t
	draw_dashed_line(from, to, color, 1.5, 6.0)


func _draw_weapon() -> void:
	var from := _hand_point()
	var color := LightKit.glow(Palette.WARNING, 1.2)
	if fsm.is_in(&"throw") or fsm.is_in(&"reel"):
		var end := to_local(_hook_pos)
		draw_dashed_line(from, end, color, 1.5, 3.0)
		var back := (from - end).normalized()
		var tip := end
		var hook := LightKit.glow(Palette.DANGER if fsm.is_in(&"reel") else Palette.WHITE, 2.0)
		draw_line(tip, tip + back.rotated(0.6) * 7.0, hook, 2.0)
		draw_line(tip, tip + back.rotated(-0.6) * 7.0, hook, 2.0)
		draw_circle(tip, 2.0, hook)
	else:
		# 平時鎖鏈與鐵鉤垂在手邊；預兆時掄動。
		var swing := sin(_anim_time * 24.0) * 5.0 if fsm.is_in(&"windup") else 0.0
		var end := from + Vector2(facing * 4.0 + swing, 12.0)
		draw_dashed_line(from, end, color, 1.5, 3.0)
		draw_circle(end, 2.5, LightKit.glow(Palette.WHITE, 1.4))
