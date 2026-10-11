class_name PatternBoss
extends Enemy
## 資料驅動的頭目（NE-253）：招式、階段、攻擊習慣、鍊子（地盤）與部位開關都來自 data/bosses/<id>.json（BossPattern）。
## 這個類別只提供「招式種類」的動作（撲咬、點射、吠叫震波、標記轟炸、跳壓）與共用流程，新頭目以資料組合，不必再寫一份狀態機。
## 流程：睡著（可選）→ 登場 → 待機（依習慣選招）→ 預兆 → 出招 → 收招／被鍊子扯回 → 待機；血量跨過門檻時換階段。
## 階段由目前血量推得，所以持久世界保留的損血（persists_damage）也會保留斷掉的零件與鍊子。
## 設計與格式見 design/15-combat-feel/BOSS_FIGHTS.md。

const INTRO_TIME := 1.0
const PHASE_SHIFT_TIME := 1.2
const IDLE_ACCEL := 400.0
const IDLE_SPEED_SCALE := 0.45
## 錨點附近多近算「回到狗屋」。
const HOME_TOLERANCE := 6.0
## 撲咬停下前的煞車距離；跳壓的上升速度與最大水平速度。
const LUNGE_BRAKE := 900.0
const POUNCE_VELOCITY := 380.0
const POUNCE_MAX_SPEED := 260.0
const POUNCE_MIN_AIR := 0.2
const MISSILE_SOURCE := &"boss_missile"
const MISSILE_COLOR := Color(1.0, 0.45, 0.2)
const CHAIN_LINKS := 18

var pattern: BossPattern
var phase := 0
var _awake := false
var _move_id: StringName = &""
var _last_move: StringName = &""
var _yanked_recently := false
var _staggered := false
var _anchor := Vector2.ZERO
## 招式執行中的暫存：撲咬終點、是否會撞到鍊子盡頭、點射剩餘、飛彈落點、跳壓落點。
var _lunge_end_x := 0.0
var _lunge_hits_leash := false
var _burst_left := 0
## 點射的瞄準方向：預兆最後 lock 秒鎖定（紅線變亮不再跟著玩家），之後每發都沿這條線，玩家看到鎖定就能跳開或舉盾。
var _aim_dir := Vector2.RIGHT
var _marks: PackedVector2Array = []
var _pounce_x := 0.0
var _parts_by_id: Dictionary[StringName, Hurtbox] = {}
var _floor_ray := PhysicsRayQueryParameters2D.new()
## 一場戰鬥只提示一次的引導（裝甲擋下、背部電源露出）。
var _armor_hinted := false
var _hinted_back := false
## 部位目前是否打開，與上次套用時的階段／招式／硬直（變了才重新套用，不每影格改節點）。
var _part_open: Dictionary[StringName, bool] = {}
var _parts_key := ""
## 打斷：這次預兆中打中 break_part 幾次；被打斷的硬直改用 break_stagger 的秒數。
var _break_hits := 0
var _interrupted := false
var _retreat_left := 0.0


func _uses_activation_culling() -> bool:
	return pattern != null and pattern.wake_range > 0.0 and not _awake


func can_be_finished() -> bool:
	return false


func _setup_states() -> void:
	pattern = BossPattern.load_for(data.id)
	_anchor = global_position
	collision_mask = Layers.WORLD  # 頭目不站單向平台，維持戰場節奏
	hurtbox.parts_take_melee = true  # 裝甲頭目：近戰碰到打開的弱點（背部電源）就打弱點
	for part in hurtbox.parts:
		_parts_by_id[part.part_id] = part
		part.hit_blocked.connect(_on_blocked)
		part.hit_received.connect(_on_part_hit)
	health.health_changed.connect(_on_health_changed)
	fsm.add(&"dormant", _dormant_tick)
	fsm.add(&"intro", _intro_tick)
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"act", _act_tick, _act_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.add(&"yanked", _yanked_tick, _yanked_enter, _yanked_exit)
	fsm.add(&"phase_shift", _phase_shift_tick, _phase_shift_enter)
	_apply_phase(pattern.phase_for(_health_ratio()), false)
	if pattern.wake_range > 0.0:
		fsm.start(&"dormant")
	else:
		_wake()


func _health_ratio() -> float:
	return float(health.current) / float(maxi(1, health.max_health))


func current_phase() -> Dictionary:
	return pattern.phases[phase]


func current_move() -> StringName:
	return _move_id


func is_leashed() -> bool:
	return pattern.leash_length > 0.0 and bool(current_phase()["leashed"])


func anchor() -> Vector2:
	return _anchor


func is_awake() -> bool:
	return _awake


# ---------------------------------------------------------------------------
# 睡著、登場、待機
# ---------------------------------------------------------------------------

func _dormant_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _can_see_target(pattern.wake_range, 140.0):
		_wake()


func _wake() -> void:
	if _awake:
		return
	_awake = true
	EventBus.boss_started.emit(data.display_name, health.max_health)
	EventBus.boss_health_changed.emit(health.current, health.max_health)
	Feel.play(&"boss_intro")
	if fsm.current == &"":
		fsm.start(&"intro")
	else:
		fsm.transition(&"intro")


## 從遠處被打到也會醒（遠程武器不能白打睡著的頭目）。
func _on_hit(_info: DamageInfo) -> void:
	if not _awake and not _dying:
		_wake()


func _intro_tick(_delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	if fsm.time_in_state >= INTRO_TIME:
		fsm.transition(&"idle")


## 待機：玩家在地盤外就退回錨點（狗屋），否則慢慢靠近；等冷卻結束依習慣選招。
func _idle_tick(delta: float) -> void:
	_face_target()
	var speed := data.move_speed * IDLE_SPEED_SCALE * _speed()
	var target := _target()
	var desired := 0.0
	if _retreat_left > 0.0:
		# 被扯回後退回狗屋喘口氣，這段時間不出招。
		_retreat_left -= delta
		var back := _anchor.x - global_position.x
		velocity.x = move_toward(velocity.x, signf(back) * speed * 1.6 if absf(back) > HOME_TOLERANCE else 0.0, IDLE_ACCEL * delta)
		fsm.time_in_state = 0.0
		return
	if target != null and is_leashed() and not _within_leash(target.global_position.x):
		var home := _anchor.x - global_position.x
		desired = signf(home) * speed if absf(home) > HOME_TOLERANCE else 0.0
	elif target != null and absf(target.global_position.x - global_position.x) > pattern.close_range:
		desired = facing * speed
	velocity.x = move_toward(velocity.x, _leash_velocity(desired), IDLE_ACCEL * delta)
	if target == null or fsm.time_in_state < _scaled_cooldown(data.attack_cooldown) / _speed():
		return
	var choice := choose_move()
	if choice != &"":
		_move_id = choice
		fsm.transition(&"windup")


## 依攻擊習慣選招：被鍊子扯過就先換招；否則看距離帶（太近、地盤內、地盤外）。不連續用同一招（招式標 repeat 的例外）。
func choose_move() -> StringName:
	var available: Array[StringName] = current_phase()["moves"]
	var band := _band()
	var listed: Array = pattern.habits.get("after_yank", []) if _yanked_recently else pattern.habits.get(band, [])
	var candidates := _filter_moves(listed, available)
	if candidates.is_empty():
		candidates = _filter_moves(available, available)
	if candidates.is_empty():
		return &""
	_yanked_recently = false
	var total := 0.0
	for id in candidates:
		total += float(pattern.moves[id]["weight"])
	var roll := randf() * total
	for id in candidates:
		roll -= float(pattern.moves[id]["weight"])
		if roll <= 0.0:
			_last_move = id
			return id
	_last_move = candidates[-1]
	return candidates[-1]


func _filter_moves(listed: Array, available: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in listed:
		if available.has(id) and (id != _last_move or bool(pattern.moves[id]["repeat"])) and _move_usable(id):
			result.append(id)
	return result


## 招式本身的使用條件：撲咬要玩家在同一層地面附近、牠能撲到的方向。
func _move_usable(id: StringName) -> bool:
	var target := _target()
	if target == null:
		return false
	match StringName(pattern.moves[id]["kind"]):
		&"lunge":  # 同一層地面、而且朝玩家的方向還有鍊子長度可以撲
			return absf(target.global_position.y - global_position.y) < 48.0 and _leash_room(signi(int(target.global_position.x - global_position.x))) > 24.0
	return true


## 距離帶：close（太近）、far（地盤外或很遠）、mid（地盤內中距離）。
func _band() -> String:
	var target := _target()
	if target == null:
		return "mid"
	var dx := absf(target.global_position.x - global_position.x)
	if dx <= pattern.close_range:
		return "close"
	if dx > pattern.far_range or (is_leashed() and not _within_leash(target.global_position.x)):
		return "far"
	return "mid"


# ---------------------------------------------------------------------------
# 預兆、出招、收招
# ---------------------------------------------------------------------------

func _move() -> Dictionary:
	return pattern.moves.get(_move_id, {})


func _params() -> Dictionary:
	return _move().get("params", {})


func _param(key: String, fallback: float) -> float:
	return float(_params().get(key, fallback))


## 預兆時間：難度越簡單越長（冷卻倍率的一半影響），不低於 BossPattern.MIN_TELEGRAPH。
func telegraph_seconds(move_id: StringName) -> float:
	var base := float(pattern.moves.get(move_id, {}).get("telegraph", 0.7))
	var difficulty := lerpf(1.0, GameState.difficulty.enemy_cooldown_multiplier, 0.5)
	return maxf(BossPattern.MIN_TELEGRAPH, base * difficulty / _speed())


func _windup_enter() -> void:
	velocity.x = 0.0
	_break_hits = 0
	_face_target()
	_start_telegraph(telegraph_seconds(_move_id))
	match StringName(_move()["kind"]):
		&"lunge":
			_plan_lunge()
		&"missiles":
			_plan_missiles()
		&"pounce":
			_plan_pounce()


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	var kind := StringName(_move().get("kind", &""))
	if kind == &"bark" or (kind == &"burst" and not is_aim_locked()):
		_face_target()
		_aim_dir = _direction_to_target()
	if not is_telegraphing():
		fsm.transition(&"act")


func _act_enter() -> void:
	match StringName(_move()["kind"]):
		&"lunge":
			velocity.x = signf(_lunge_end_x - global_position.x) * _param("speed", 320.0) * _speed()
			Fx.dust(global_position, 8, 90.0)
			Sfx.play(&"dash", -4.0)
		&"burst":
			_burst_left = int(_param("count", 3))
		&"bark":
			_bark()
		&"missiles":
			_fire_missiles()
		&"pounce":
			var air_time := 2.0 * POUNCE_VELOCITY / _gravity
			velocity = Vector2(clampf((_pounce_x - global_position.x) / air_time, -POUNCE_MAX_SPEED, POUNCE_MAX_SPEED), -POUNCE_VELOCITY)
			Fx.dust(global_position, 8, 80.0)


func _act_tick(delta: float) -> void:
	match StringName(_move()["kind"]):
		&"lunge":
			_lunge_tick(delta)
		&"burst":
			_burst_tick()
		&"pounce":
			if fsm.time_in_state >= POUNCE_MIN_AIR and is_on_floor():
				_pounce_land()
		_:
			fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, LUNGE_BRAKE * delta)
	if fsm.time_in_state >= float(_move().get("recover", 0.4)) / _speed():
		fsm.transition(&"idle")


## 點射的瞄準是否已鎖定（預兆剩下 lock 秒以內）。
func is_aim_locked() -> bool:
	return fsm.is_in(&"windup") and StringName(_move().get("kind", &"")) == &"burst" and _telegraph_left <= _param("lock", 0.25)


func _speed() -> float:
	return float(current_phase()["speed"]) if pattern != null else 1.0


# ---------------------------------------------------------------------------
# 招式種類
# ---------------------------------------------------------------------------

## 撲咬：衝到玩家位置再往前一點；拴著時最遠到鍊子盡頭，撞到盡頭就會被扯回。
func _plan_lunge() -> void:
	var target := _target()
	var dir := float(facing)
	var reach := _param("max_distance", 176.0)
	var goal := global_position.x + dir * reach
	if target != null:
		goal = target.global_position.x + dir * _param("overshoot", 20.0)
		goal = global_position.x + dir * minf(absf(goal - global_position.x), reach)
	_lunge_hits_leash = false
	if is_leashed():
		var limit := _leash_limit(int(dir))
		if (goal - limit) * dir > 0.0:
			goal = limit
			_lunge_hits_leash = true
	_lunge_end_x = goal


## 撲咬：到終點就停（鍊子盡頭是硬停，不會滑過黃黑線）；撞牆或超時也結束。
func _lunge_tick(delta: float) -> void:
	var direction := signf(_lunge_end_x - global_position.x)
	var remaining := absf(_lunge_end_x - global_position.x)
	if is_on_wall() or remaining <= 1.0 or fsm.time_in_state > 2.0:
		velocity.x = 0.0
		# 撞到鍊子盡頭被扯回；或這招本身撲完會失衡（stagger_on_end，例如第三階段的連撲）。
		fsm.transition(&"yanked" if _lunge_hits_leash or bool(_params().get("stagger_on_end", false)) else &"recover")
		return
	var speed := _param("speed", 320.0) * _speed()
	velocity.x = direction * minf(speed, remaining / maxf(delta, 0.0001))


func _burst_tick() -> void:
	velocity.x = 0.0
	if fsm.time_in_state < _param("interval", 0.12):
		return
	var spec := _projectile(str(_params().get("projectile", "")))
	_shoot(spec, _aim_dir)
	_burst_left -= 1
	fsm.time_in_state = 0.0
	if _burst_left <= 0:
		fsm.transition(&"recover")


## 吠叫：左右各一道貼地震波（跳過）。
func _bark() -> void:
	velocity.x = 0.0
	var spec := _projectile(str(_params().get("projectile", "boss_shockwave")))
	var origin := global_position + Vector2(0, -6)
	for side: float in [-1.0, 1.0]:
		_shoot(spec, Vector2(side, 0), origin + Vector2(side * data.body_size.x * 0.5, 0))
	Feel.shake_strength(3.0, 0.2)
	Sfx.play(&"explosion_small", -6.0)
	Fx.flash_light(_head_point(), Palette.WARNING, 120.0, 1.4, 0.2)


## 標記轟炸：預兆開始時在玩家腳下與兩側畫落點，預兆結束時落下（落點不追蹤，離開就躲得掉）。
func _plan_missiles() -> void:
	_marks.clear()
	var target := _target()
	if target == null:
		return
	var count := maxi(1, int(_param("count", 3)))
	var spacing := _param("spacing", 40.0)
	for i in count:
		var x := target.global_position.x + (float(i) - float(count - 1) * 0.5) * spacing
		_marks.append(_floor_at(Vector2(x, target.global_position.y)))


func _fire_missiles() -> void:
	var radius := _param("radius", 22.0)
	var damage := int(_param("damage", 1))
	var source := StringName(str(_params().get("source", MISSILE_SOURCE)))
	for mark in _marks:
		Fx.explosion(mark + Vector2(0, -4), radius, damage, Combat.Team.ENEMY, source, MISSILE_COLOR)
	_marks.clear()


func _plan_pounce() -> void:
	var target := _target()
	_pounce_x = target.global_position.x if target != null else global_position.x
	if is_leashed():
		_pounce_x = clampf(_pounce_x, _leash_limit(-1), _leash_limit(1))


## 跳壓落地：左右震波；落地的硬直打開背部（部位規則 stagger）。
func _pounce_land() -> void:
	velocity.x = 0.0
	Feel.play(&"boss_land")
	Fx.dust(global_position, 12, 120.0)
	Sfx.play(&"explosion", -6.0)
	var spec := _projectile(str(_params().get("projectile", "boss_shockwave")))
	for side: float in [-1.0, 1.0]:
		_shoot(spec, Vector2(side, 0), global_position + Vector2(side * data.body_size.x * 0.5, -6))
	fsm.transition(&"yanked")


## 被鍊子扯回（或跳壓落地）的硬直：往後退一小段、背部電源打開。
func _yanked_enter() -> void:
	_staggered = true
	_yanked_recently = not _interrupted and _lunge_hits_leash and StringName(_move().get("kind", &"")) == &"lunge"
	if _yanked_recently:
		velocity.x = -signf(_lunge_end_x - _anchor.x) * _param("yank_push", 160.0)
		Sfx.play(&"block", -2.0)
		Feel.shake_strength(4.0, 0.25)
		Fx.sparks(_chain_end(), Palette.WARNING, 10, 220.0, 0.3, Vector2(-facing, -0.4), 0.8, 300.0)
		if not _hinted_back:
			_hinted_back = true
			EventBus.toast_requested.emit("背部電源露出了！")
	_refresh_parts()



func _yanked_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, LUNGE_BRAKE * 0.5 * delta)
	var seconds := _param("break_stagger", 1.2) if _interrupted else _param("stagger", 1.6)
	if fsm.time_in_state >= seconds:
		fsm.transition(&"idle")


func _yanked_exit() -> void:
	_staggered = false
	if _yanked_recently:
		_retreat_left = pattern.leash_retreat
	_interrupted = false
	_refresh_parts()


# ---------------------------------------------------------------------------
# 階段
# ---------------------------------------------------------------------------

func _on_health_changed(current: int, maximum: int) -> void:
	if _awake:
		EventBus.boss_health_changed.emit(current, maximum)
	if current <= 0 or _dying:
		return
	var next := pattern.phase_for(_health_ratio())
	if next > phase:
		_apply_phase(next, _awake)


## 套用階段：換武器外觀、藏起脫落的零件、更新部位與裝甲；演出時停頓並提示（死後回來時直接套用，不演出）。
func _apply_phase(index: int, perform: bool) -> void:
	phase = clampi(index, 0, pattern.phases.size() - 1)
	var config := current_phase()
	if rig != null:
		if config["weapon"] != null:
			rig.set_weapon(str(config["weapon"]))
		for part_name: String in config["hide_parts"]:
			for node: Node in rig.find_children(part_name, "CanvasItem", true, false):
				(node as CanvasItem).visible = false
	_refresh_parts()
	if perform:
		Fx.burst(_center(), Palette.WARNING, 24, 240.0, 0.5)
		if not str(config["enter_toast"]).is_empty():
			EventBus.toast_requested.emit(str(config["enter_toast"]))
		if fsm.is_in(&"act") and StringName(_move().get("kind", &"")) == &"pounce":
			return  # 空中不打斷，落地後再演出
		fsm.transition(&"phase_shift")


func _phase_shift_enter() -> void:
	velocity.x = 0.0
	_start_telegraph(PHASE_SHIFT_TIME)
	Feel.play(&"boss_phase_shift")
	Fx.flash_light(_center(), Palette.DANGER, 160.0, 2.0, 0.6)


func _phase_shift_tick(_delta: float) -> void:
	velocity.x = 0.0
	if fsm.time_in_state >= PHASE_SHIFT_TIME:
		fsm.transition(&"idle")


## 部位開關：依資料的規則（常開、某階段、某招出招中、硬直時）。關著的部位若標 armor 仍在畫面上，子彈打到會被擋下彈開；
## 標 hidden 的部位（例如藏在身體裡的背部電源、壞掉的槍臂）關著時打不到。
func _refresh_parts() -> void:
	var move := _move_id if fsm.is_in(&"windup") or fsm.is_in(&"act") else &""
	_parts_key = "%d|%s|%s" % [phase, move, _staggered]
	for id: StringName in _parts_by_id:
		var part := _parts_by_id[id]
		var open := pattern.part_open(id, phase, _staggered, move)
		part.enabled = open or pattern.part_armored_when_closed(id, phase, _staggered)
		part.guard = Callable() if open else _armored_part_guard
		_part_open[id] = open


func is_part_open(id: StringName) -> bool:
	return bool(_part_open.get(id, false))


func _armored_part_guard(_info: DamageInfo) -> Hurtbox.Guard:
	return Hurtbox.Guard.BLOCK


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if pattern == null or _dying:
		return
	var move := _move_id if fsm.is_in(&"windup") or fsm.is_in(&"act") else &""
	if _parts_key != "%d|%s|%s" % [phase, move, _staggered]:
		_refresh_parts()


## 打斷：招式資料的 break_part 在預兆中被打中 break_hits 次，就取消這招並硬直（背部電源也會露出）。
func _on_part_hit(info: DamageInfo) -> void:
	if not fsm.is_in(&"windup"):
		return
	var params := _params()
	if StringName(str(params.get("break_part", ""))) != info.part:
		return
	_break_hits += 1
	if _break_hits < int(params.get("break_hits", 3)):
		return
	_break_hits = 0
	_telegraph_left = 0.0
	_interrupted = true
	EventBus.toast_requested.emit("打斷了！")
	Feel.shake_strength(3.0, 0.2)
	fsm.transition(&"yanked")


## 裝甲：資料標 armored 的階段，身體（不是部位）擋下子彈與近戰；爆炸與終結技本來就無視（bypass_guard）。
func _guard(_info: DamageInfo) -> Hurtbox.Guard:
	return Hurtbox.Guard.BLOCK if bool(current_phase()["armored"]) else Hurtbox.Guard.NONE


func _on_blocked(info: DamageInfo) -> void:
	super._on_blocked(info)
	if not _armor_hinted:
		_armor_hinted = true
		EventBus.toast_requested.emit("裝甲擋下了——瞄準發橙光的部位")



func _on_stunned() -> void:
	pass


# ---------------------------------------------------------------------------
# 鍊子（地盤）
# ---------------------------------------------------------------------------

func _within_leash(x: float) -> bool:
	return absf(x - _anchor.x) <= pattern.leash_length + pattern.close_range


## 拴著時身體中心最遠能到的位置：身體前緣剛好碰到地上的黃黑線（線畫在錨點 ± 鍊長）。
func _leash_limit(direction: int) -> float:
	return _anchor.x + direction * maxf(0.0, pattern.leash_length - data.body_size.x * 0.5)


## 往 direction 方向還能走多遠（拴著時）。
func _leash_room(direction: int) -> float:
	if not is_leashed():
		return INF
	return maxf(0.0, (_leash_limit(direction) - global_position.x) * direction) if direction != 0 else 0.0


func _leash_velocity(desired: float) -> float:
	if not is_leashed() or desired == 0.0:
		return desired
	return desired if _leash_room(signi(int(signf(desired)))) > 4.0 else 0.0


## 鍊子在身上的扣點（世界座標）：脖子骨頭，沒有骨架用頸部高度。
func _chain_end() -> Vector2:
	if rig != null and rig.has_bone(&"neck"):
		return rig.bone(&"neck").global_position
	return global_position + Vector2(0, -data.body_size.y * 0.8)


func _head_point() -> Vector2:
	if rig != null and rig.has_bone(&"head"):
		return rig.bone(&"head").global_position
	return global_position + Vector2(0, -data.body_size.y)


# ---------------------------------------------------------------------------
# 擊敗
# ---------------------------------------------------------------------------

func _play_death() -> void:
	var tween := create_tween()
	for i in 5:
		tween.tween_callback(_death_blast)
		tween.tween_interval(0.2)
	tween.tween_callback(_finish_death)


func _death_blast() -> void:
	var offset := Vector2(randf_range(-1.0, 1.0) * data.body_size.x * 0.6, -randf() * data.body_size.y)
	Fx.explosion(global_position + offset, 22.0, 0, Combat.Team.PLAYER, &"", Palette.WARNING)


## 擊敗：有頻道就解開機關、收起血條（關卡繼續）；沒有頻道就是關卡頭目，通知關卡結束。
func _finish_death() -> void:
	Fx.flash_light(_center(), Palette.WHITE, 160.0, 2.0, 0.5)
	Fx.burst(_center(), Palette.CYAN, 28, 260.0, 0.6)
	Feel.play(&"boss_death")
	if pattern.gate_channel == &"":
		EventBus.boss_defeated.emit()
	else:
		EventBus.boss_bar_closed.emit()
		EventBus.mechanism_toggled.emit(pattern.gate_channel, true)
		if not pattern.unlock_text.is_empty():
			EventBus.toast_requested.emit(pattern.unlock_text)
	queue_free()


# ---------------------------------------------------------------------------
# 外觀：骨架姿勢與預兆
# ---------------------------------------------------------------------------

func _rig_aim() -> Vector2:
	return _direction_to_target() if _target() != null else Vector2(facing, 0.1).normalized()


## 骨架動作由招式資料決定（pose_windup／pose_act），睡著時蹲低。
func _update_rig_action() -> void:
	var action: StringName = &""
	if fsm.is_in(&"windup"):
		action = _move().get("pose_windup", &"")
	elif fsm.is_in(&"act"):
		action = _move().get("pose_act", &"")
	if action == &"":
		action = pattern.state_poses.get(fsm.current, &"")
	_rig_input.action = action
	if action == &"":
		_rig_input.action_t = 0.0
		return
	var actions: Variant = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	var duration := 0.5
	if typeof(actions) == TYPE_DICTIONARY and (actions as Dictionary).has(String(action)):
		duration = maxf(0.05, float(((actions as Dictionary)[String(action)] as Dictionary).get("duration", 0.5)))
	_rig_input.action_t = clampf(fsm.time_in_state / duration, 0.0, 1.0)


func _draw_overlay() -> void:
	if is_leashed():
		_draw_leash()
	if fsm.is_in(&"windup"):
		var t := 1.0 - clampf(_telegraph_left / maxf(0.01, telegraph_seconds(_move_id)), 0.0, 1.0)
		match StringName(_move()["kind"]):
			&"lunge":
				_draw_lunge_path(t)
			&"burst":
				var from := to_local(_muzzle())
				var locked := is_aim_locked()
				# 鎖定時變亮變實（不是變粗的光束），HDR 泛光下也不蓋住玩家與落點。
				var color := Color(LightKit.glow(Palette.DANGER, 1.7 if locked else 0.9 + 0.6 * t), 0.85 if locked else 0.2 + 0.4 * t)
				draw_line(from, from + _aim_dir * 180.0, color, 1.0)
				if locked:
					draw_circle(from, 2.0, LightKit.glow(Palette.DANGER, 2.0))
			&"bark":
				var head := to_local(_head_point())
				draw_arc(head, 6.0 + 10.0 * t, 0.0, TAU, 20, Color(LightKit.glow(Palette.WARNING, 2.0), 0.3 + 0.5 * t), 1.5)
			&"pounce":
				_draw_shadow(Vector2(_pounce_x, global_position.y), t)
	if not _marks.is_empty():
		var t := 1.0 - clampf(_telegraph_left / maxf(0.01, telegraph_seconds(_move_id)), 0.0, 1.0)
		var radius := _param("radius", 22.0)
		for mark in _marks:
			var at := to_local(mark)
			draw_arc(at, radius, 0.0, TAU, 28, Color(LightKit.glow(Palette.DANGER, 1.6), 0.5 + 0.4 * t), 1.5)
			draw_arc(at, radius * (1.0 - t), 0.0, TAU, 20, Color(LightKit.glow(Palette.DANGER, 2.2), 0.7), 1.0)
	_draw_open_parts()


## 鍊子：從錨點（狗屋）到脖子；鬆的時候下垂、拉直時發亮。地上的黃黑警示線標出鍊子的盡頭。
func _draw_leash() -> void:
	var start := to_local(_anchor + Vector2(0, -10))
	var end := to_local(_chain_end())
	var span := start.distance_to(end)
	var slack := clampf(1.0 - span / maxf(1.0, pattern.leash_length + 40.0), 0.0, 1.0)
	var taut := fsm.is_in(&"yanked") and _yanked_recently
	var color := LightKit.glow(Palette.WARNING, 2.2) if taut else Color(0.55, 0.55, 0.6, 0.95)
	var sag := Vector2(0, 46.0 * slack)
	var previous := start
	for i in range(1, CHAIN_LINKS + 1):
		var u := float(i) / CHAIN_LINKS
		var point := start.lerp(end, u) + sag * 4.0 * u * (1.0 - u)
		draw_line(previous, point, color, 2.0 if i % 2 == 0 else 1.0)
		previous = point
	for side: float in [-1.0, 1.0]:
		_draw_leash_mark(to_local(Vector2(_anchor.x + side * pattern.leash_length, global_position.y)), side)


## 鍊子盡頭的地面標記：地上一段黃黑相間的警示帶，加一根短樁（往地盤外側延伸，玩家站在帶子外面就安全）。
func _draw_leash_mark(edge: Vector2, side: float) -> void:
	const STRIPES := 6
	const STRIPE := 4.0
	for i in STRIPES:
		var x := edge.x + side * i * STRIPE
		var color := LightKit.glow(Palette.WARNING, 1.3) if i % 2 == 0 else Color(0.06, 0.06, 0.07)
		draw_rect(Rect2(Vector2(minf(x, x + side * STRIPE), edge.y - 2.0), Vector2(STRIPE, 2.0)), color)
	draw_line(edge + Vector2(0, -2.0), edge + Vector2(0, -12.0), LightKit.glow(Palette.WARNING, 1.6), 2.0)
	draw_line(edge + Vector2(0, -12.0), edge + Vector2(-side * 3.0, -12.0), LightKit.glow(Palette.WARNING, 1.6), 2.0)


func _draw_lunge_path(t: float) -> void:
	var from := Vector2(0, -2)
	var to := Vector2(_lunge_end_x - global_position.x, -2)
	var color := Color(LightKit.glow(Palette.DANGER, 1.2 + 1.2 * t), 0.25 + 0.5 * t)
	draw_line(from, from.lerp(to, minf(1.0, t * 1.6)), color, 2.0)
	if _lunge_hits_leash:
		draw_line(to + Vector2(0, -12), to + Vector2(0, 2), Color(LightKit.glow(Palette.WARNING, 2.0), 0.4 + 0.5 * t), 2.0)


func _draw_shadow(world: Vector2, t: float) -> void:
	var at := to_local(world)
	var width := 14.0 + 14.0 * t
	draw_set_transform(at, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, width, Color(0.0, 0.0, 0.0, 0.25 + 0.35 * t))
	draw_arc(Vector2.ZERO, width, 0.0, TAU, 24, Color(LightKit.glow(Palette.DANGER, 1.5), 0.5), 1.5)
	draw_set_transform(Vector2.ZERO)


## 顏色語言：打開的部位（現在打得到的弱點）亮橙色；常開的小部位用細框，硬直或招式中才打開的用脈動光，讓「現在打這裡」一眼看得出來。
func _draw_open_parts() -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 18.0)
	for id: StringName in _parts_by_id:
		if not is_part_open(id):
			continue
		var box := _parts_by_id[id]
		var at := box.shape_offset()
		if str(pattern.parts_open.get(id, "always")) == "always":
			draw_arc(at, 6.0, 0.0, TAU, 16, Color(LightKit.glow(Palette.WARNING, 1.4), 0.55), 1.0)
			continue
		draw_circle(at, 5.0 + pulse * 2.0, Color(LightKit.glow(Palette.WARNING, 2.6), 0.45))
		draw_arc(at, 8.0 + pulse * 2.0, 0.0, TAU, 20, LightKit.glow(Palette.WARNING, 3.0), 1.5)


## 弱點標記由 _draw_open_parts 依「現在是否打開」畫；關著（裝甲）的部位不畫，避免誤導。開發用的受擊框外框照舊。
func _draw_weak_points() -> void:
	if debug_hurtboxes and not _dying:
		super._draw_weak_points()


## 骨架載入失敗時的程式繪製：一塊機甲身體與發光的眼睛。
func _draw_body(color: Color) -> void:
	var w := data.body_size.x
	var h := data.body_size.y
	draw_rect(Rect2(-w * 0.5, -h, w, h * 0.7), color)
	draw_line(Vector2(-w * 0.3, -h * 0.3), Vector2(-w * 0.35, 0), color.darkened(0.45), 5.0)
	draw_line(Vector2(w * 0.3, -h * 0.3), Vector2(w * 0.35, 0), color.darkened(0.45), 5.0)
	var eye := LightKit.glow(Palette.DANGER, 3.5 if is_telegraphing() else 1.8)
	draw_line(Vector2(facing * w * 0.05, -h * 0.85), Vector2(facing * w * 0.35, -h * 0.85), eye, 2.5)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _projectile(id: String) -> ProjectileSpec:
	if not id.is_empty():
		var spec := data.find_projectile(StringName(id))
		if spec != null:
			return spec
	return data.projectile


## 往下找地面（世界座標）；找不到就用原本的高度。
func _floor_at(point: Vector2) -> Vector2:
	_floor_ray.from = point + Vector2(0, -24)
	_floor_ray.to = point + Vector2(0, 240)
	_floor_ray.collision_mask = Layers.SOLID
	var hit := get_world_2d().direct_space_state.intersect_ray(_floor_ray)
	return hit["position"] if not hit.is_empty() else point
