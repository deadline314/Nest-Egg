class_name PatternBoss
extends Enemy
## 資料驅動的頭目（NE-253）：招式、階段、攻擊習慣、鍊子（地盤）與部位開關都來自 data/bosses/<id>.json（BossPattern）。
## 這個類別只提供「招式種類」的動作（撲咬、點射、吠叫震波、標記轟炸、跳壓、蓄力重擊、扇形投擲、衝向地點）與共用流程，新頭目以資料組合，不必再寫一份狀態機。
## 共用機制（都由資料開啟）：階段增援（summon）、階段事件（event，交給子類別的 _on_phase_event）、玩家身上的標記與地墊（BossMark）、
## 標籤（tags，部位規則 tag:<名稱> 用）、階段組（phase_sets，例如劇情頭目復原後換一套階段）。
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
## 蓄力重擊：出招（往前踏、判定）最長的時間。
const SLAM_MAX_TIME := 0.6
## 蓄力重擊往前踏時，離玩家多近就停（像素，從身體前緣算）。
const SLAM_STOP_GAP := 12.0
## 衝向地點：最長時間（撞牆或到不了就停）。
const RUSH_MAX_TIME := 1.6

var pattern: BossPattern
var phase := 0
## 目前使用的階段組（BossPattern.phase_sets 的名稱）。
var phase_set := BossPattern.DEFAULT_SET
## 頭目腳本掛上的標籤（部位規則 tag:<名稱>、子類別判斷用）。
var tags := PackedStringArray()
## 玩家身上的標記與地墊（資料有 mark 才建立）。
var mark: BossMark
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
## 蓄力重擊：這一擊的結果（hit 打中、blocked 被擋、whiff 揮空）、判定是否已經出過。
var _slam_result: StringName = &""
var _slam_done := false
var _slam_query := RectangleShape2D.new()
## 衝向地點的目標 x。
var _rush_x := 0.0
## 收招時間（進入收招時依結果與階段算好）；硬直秒數（0＝依招式資料）。
var _recover_time := 0.4
var _stagger_override := 0.0
## 增援：還活著的、已經叫出來的總數、下一次的倒數。
var _summons: Array[WeakRef] = []
var _summoned := 0
var _summon_left := 0.0


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
	fsm.add(&"recover", _recover_tick, _recover_enter)
	fsm.add(&"yanked", _yanked_tick, _yanked_enter, _yanked_exit)
	fsm.add(&"phase_shift", _phase_shift_tick, _phase_shift_enter)
	for kind in pattern.custom_kinds:
		if not _implements_kind(kind):
			push_error("[PatternBoss] %s 的資料宣告了招式種類「%s」，但 %s 沒有實作；用到它的招式不會被選" % [data.id, kind, get_script().resource_path])
	if not pattern.mark_config.is_empty():
		mark = BossMark.new()
		mark.name = "BossMark"
		add_child(mark)
		mark.configure(self, pattern.mark_config, String(data.id))
	_apply_phase(pattern.phase_for(_health_ratio(), phase_set), false)
	if pattern.wake_range > 0.0:
		fsm.start(&"dormant")
	else:
		_wake()


func _health_ratio() -> float:
	return float(health.current) / float(maxi(1, health.max_health))


func current_phase() -> Dictionary:
	var list := pattern.phase_list(phase_set)
	return list[clampi(phase, 0, list.size() - 1)]


## 換一套階段（例如劇情頭目復原後、制伏中）；perform 時演出階段轉換。
func use_phase_set(set_name: String, perform := true) -> void:
	phase_set = set_name if pattern.phase_sets.has(set_name) else BossPattern.DEFAULT_SET
	if phase_set != set_name:
		RigLibrary.report_once("pattern_boss_set:%s:%s" % [data.id, set_name], "[PatternBoss] %s 沒有階段組「%s」，改用 default" % [data.id, set_name])
	_apply_phase(pattern.phase_for(_health_ratio(), phase_set), perform)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func set_tag(tag: String, on: bool) -> void:
	if on and not tags.has(tag):
		tags.append(tag)
	elif not on and tags.has(tag):
		tags.remove_at(tags.find(tag))
	_refresh_parts()


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
	EventBus.boss_started.emit(pattern.bar_name if not pattern.bar_name.is_empty() else data.display_name, health.max_health)
	EventBus.boss_health_changed.emit(health.current, health.max_health)
	Feel.play(&"boss_intro")
	if mark != null:
		mark.start()
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
	var candidates: Array[StringName] = []
	for band in habit_bands():
		candidates = _filter_moves(pattern.habits.get(band, []), available)
		if not candidates.is_empty():
			break
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


## 這一次選招依序看的習慣帶：剛被扯回 → 玩家帶著標記走向亮墊（搶地墊）→ 玩家身上標記很多（貪）→ 距離帶。
func habit_bands() -> PackedStringArray:
	var bands := PackedStringArray()
	if _yanked_recently:
		bands.append("after_yank")
	if mark != null:
		if mark.stacks >= pattern.pad_stacks and mark.player_heading_to_lit_pad():
			bands.append("pad")
		if mark.stacks >= pattern.marked_stacks:
			bands.append("marked")
	bands.append(_band())
	return bands


## 招式本身的使用條件：撲咬要玩家在同一層地面附近、牠能撲到的方向；衝向地墊要有亮著的地墊。
func _move_usable(id: StringName) -> bool:
	var target := _target()
	if target == null:
		return false
	match StringName(pattern.moves[id]["kind"]):
		&"lunge":  # 同一層地面、而且朝玩家的方向還有鍊子長度可以撲
			return absf(target.global_position.y - global_position.y) < 48.0 and _leash_room(signi(int(target.global_position.x - global_position.x))) > 24.0
		&"rush":
			if str(pattern.moves[id]["params"].get("target", "pad")) == "pad":
				return mark != null and mark.rush_target_x(global_position) != INF
	var kind := StringName(pattern.moves[id]["kind"])
	if pattern.custom_kinds.has(kind):
		return _implements_kind(kind) and _custom_move_usable(id, kind)
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
		&"rush":
			_plan_rush()
		var kind:
			_custom_windup_enter(kind)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	var kind := StringName(_move().get("kind", &""))
	# 蓄力重擊最後 lock 秒不再轉身（看到判定區定住就能閃）；點射與扇形投擲鎖定瞄準。
	if kind == &"bark" or (kind == &"slam" and _telegraph_left > _param("lock", 0.3)) or ((kind == &"burst" or kind == &"fan") and not is_aim_locked()):
		_face_target()
		_aim_dir = _direction_to_target()
	elif pattern.custom_kinds.has(kind):
		_custom_windup_tick(kind, _delta)
		if not fsm.is_in(&"windup"):
			return  # 子類別在預兆中改了狀態（例如被打斷）
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
		&"slam":
			_slam_result = &"whiff"
			_slam_done = false
			velocity.x = facing * _param("advance_speed", 160.0) * _speed()
			Sfx.play(&"dash", -8.0)
		&"fan":
			_fire_fan()
		&"rush":
			velocity.x = signf(_rush_x - global_position.x) * _param("speed", 300.0) * _speed()
			Fx.dust(global_position, 8, 90.0)
			Sfx.play(&"dash", -4.0)
		var kind:
			_custom_act_enter(kind)


func _act_tick(delta: float) -> void:
	match StringName(_move()["kind"]):
		&"lunge":
			_lunge_tick(delta)
		&"burst":
			_burst_tick()
		&"pounce":
			if fsm.time_in_state >= POUNCE_MIN_AIR and is_on_floor():
				_pounce_land()
		&"slam":
			_slam_tick()
		&"rush":
			_rush_tick(delta)
		&"bark", &"missiles", &"fan":
			fsm.transition(&"recover")
		var kind:
			_custom_act_tick(kind, delta)


## 收招時間：招式資料的 recover × 階段的 recover_scale；蓄力重擊揮空時再乘 whiff_recover（撲空的反擊空檔），被擋下乘 blocked_recover。
func _recover_enter() -> void:
	var seconds := float(_move().get("recover", 0.4)) * float(current_phase().get("recover_scale", 1.0))
	if StringName(_move().get("kind", &"")) == &"slam":
		match _slam_result:
			&"whiff":
				seconds *= _param("whiff_recover", 2.0)
			&"blocked":
				seconds *= _param("blocked_recover", 1.5)
	_recover_time = seconds / _speed()


## 收招結束：招式資料有 next 就直接接下一招（連段），否則回到待機。
func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, LUNGE_BRAKE * delta)
	if fsm.time_in_state < _recover_time:
		return
	var next := StringName(str(_params().get("next", "")))
	if next != &"" and pattern.moves.has(next) and _target() != null and _move_usable(next):
		_move_id = next
		_last_move = next
		fsm.transition(&"windup")
		return
	fsm.transition(&"idle")


## 收招還剩幾秒（揮空的反擊空檔、測試與機器人用）。
func recover_left() -> float:
	return maxf(0.0, _recover_time - fsm.time_in_state) if fsm.is_in(&"recover") else 0.0


## 最近一次蓄力重擊的結果：hit、blocked、whiff；還沒出過是空白。
func last_slam_result() -> StringName:
	return _slam_result


## 會鎖定瞄準的招式（點射、扇形投擲）：預兆剩下 lock 秒以內就不再跟著玩家。
func is_aim_locked() -> bool:
	var kind := StringName(_move().get("kind", &""))
	return fsm.is_in(&"windup") and (kind == &"burst" or kind == &"fan") and _telegraph_left <= _param("lock", 0.25)


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


## 蓄力重擊的判定區（本地座標）：身體前緣往前 reach、高 height；預兆時畫在地上的就是這一塊。
func slam_rect() -> Rect2:
	var reach := _param("reach", 40.0)
	var height := _param("height", 44.0)
	var front := data.body_size.x * 0.5
	var left := front if facing > 0 else -front - reach
	return Rect2(Vector2(left, -height), Vector2(reach, height))


## 蓄力重擊：往前踏一小步，active_at 秒時判定一次；結果決定收招（打中照常、被擋稍長、揮空最長）。
func _slam_tick() -> void:
	var active_at := _param("active_at", 0.08)
	if not _slam_done and fsm.time_in_state >= active_at:
		_slam_done = true
		velocity.x = 0.0
		var rect := slam_rect()
		_slam_result = _strike_player(global_position + rect.get_center(), rect.size,
				int(_param("damage", 2)) + int(current_phase().get("damage_bonus", 0)),
				StringName(str(_params().get("source", "%s_slam" % data.id))), _param("knockback", 160.0))
		Feel.shake_strength(_param("shake", 4.0), 0.2)
		Fx.dust(global_position + Vector2(facing * (data.body_size.x * 0.5 + _param("reach", 40.0) * 0.6), 0), 10, 110.0)
		Sfx.play(&"explosion_small", -8.0)
	# 往前踏只到貼近玩家為止：不踩進玩家身上（身體接觸不是這一招的判定，沒有預兆的傷害不算數）。
	var target := _target()
	if target != null and signf(target.global_position.x - global_position.x) == float(facing) \
			and absf(target.global_position.x - global_position.x) <= data.body_size.x * 0.5 + SLAM_STOP_GAP:
		velocity.x = 0.0
	if fsm.time_in_state >= clampf(_param("active_time", 0.25), active_at + 0.05, SLAM_MAX_TIME):
		fsm.transition(&"recover")


## 對判定區裡的玩家受擊框造成一次傷害；回傳 hit、blocked（被盾或完美格擋擋下）或 whiff。
func _strike_player(center: Vector2, size: Vector2, amount: int, source: StringName, knock: float) -> StringName:
	_slam_query.size = size
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _slam_query
	params.transform = Transform2D(0.0, center)
	params.collision_mask = Layers.PLAYER_HURTBOX
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 4):
		var box := hit.get("collider") as Hurtbox
		if box == null:
			continue
		var side := signf(box.global_position.x - global_position.x)
		var info := DamageInfo.create(maxi(1, amount), Combat.Team.ENEMY, source, Vector2((side if side != 0.0 else float(facing)) * knock, -60.0))
		info.origin = _center()
		info.attacker = weakref(self)
		match box.receive(info):
			Hurtbox.Result.DAMAGED:
				return &"hit"
			Hurtbox.Result.BLOCKED, Hurtbox.Result.REFLECTED:
				return &"blocked"
	return &"whiff"


## 扇形投擲：預兆最後 lock 秒鎖定方向，出招時沿鎖定方向丟出一排慢速投射物；投射物之間有縫，可以跳過或蹲過。
func _fire_fan() -> void:
	var spec := _projectile(str(_params().get("projectile", "")))
	if spec == null:
		return
	var count := clampi(int(_param("count", 5)), 1, 9)
	var spread := clampf(_param("spread", 40.0), 0.0, 120.0)
	WeaponSystem.fire_spread(spec, _muzzle(), _aim_dir, count, spread, 0.0, Combat.Team.ENEMY, _projectile_speed_multiplier())
	if creature != null:
		creature.kick()
	_rig_input.recoil = 1.0
	Sfx.play(&"shot_spread", -8.0)


## 衝向地點：target＝pad（亮著的地墊，搶在玩家前面踩掉）或 player（玩家腳下）。
func _plan_rush() -> void:
	var target := _target()
	_rush_x = global_position.x
	if str(_params().get("target", "pad")) == "pad" and mark != null:
		var x := mark.rush_target_x(global_position)
		_rush_x = x if x != INF else global_position.x
	elif target != null:
		_rush_x = target.global_position.x
	facing = 1 if _rush_x >= global_position.x else -1


func _rush_tick(delta: float) -> void:
	var remaining := absf(_rush_x - global_position.x)
	if remaining <= 2.0 or is_on_wall() or fsm.time_in_state > RUSH_MAX_TIME:
		velocity.x = 0.0
		if mark != null:
			mark.boss_arrived(global_position)
		fsm.transition(&"recover")
		return
	velocity.x = signf(_rush_x - global_position.x) * minf(_param("speed", 300.0) * _speed(), remaining / maxf(delta, 0.0001))


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
	var seconds := _stagger_override if _stagger_override > 0.0 else (_param("break_stagger", 1.2) if _interrupted else _param("stagger", 1.6))
	if fsm.time_in_state >= seconds:
		fsm.transition(&"idle")


func _yanked_exit() -> void:
	_staggered = false
	if _yanked_recently:
		_retreat_left = pattern.leash_retreat
	_interrupted = false
	_stagger_override = 0.0
	_refresh_parts()


# ---------------------------------------------------------------------------
# 階段
# ---------------------------------------------------------------------------

func _on_health_changed(current: int, maximum: int) -> void:
	if _awake:
		EventBus.boss_health_changed.emit(current, maximum)
	if current <= 0 or _dying:
		return
	var next := pattern.phase_for(_health_ratio(), phase_set)
	if next > phase:
		_apply_phase(next, _awake)


## 套用階段：換武器外觀、藏起脫落的零件、更新部位與裝甲；演出時停頓並提示（死後回來時直接套用，不演出）。
func _apply_phase(index: int, perform: bool) -> void:
	phase = clampi(index, 0, pattern.phase_list(phase_set).size() - 1)
	_summon_left = float((current_phase()["summon"] as Dictionary).get("every", 0.0)) * 0.5
	var config := current_phase()
	if rig != null:
		if config["weapon"] != null:
			rig.set_weapon(str(config["weapon"]))
		for part_name: String in config["hide_parts"]:
			for node: Node in rig.find_children(part_name, "CanvasItem", true, false):
				(node as CanvasItem).visible = false
	elif creature != null:
		# 零件式外觀：藏起整個零件關節（含掛在它下面的零件），例如被打壞的砲塔。
		for part_name: String in config["hide_parts"]:
			if not creature.set_part_hidden(part_name, true):
				RigLibrary.report_once("pattern_boss_hide:%s:%s" % [data.id, part_name], "[PatternBoss] %s 的階段要藏的零件「%s」不在零件式外觀裡" % [data.id, part_name])
	_refresh_parts()
	if perform:
		Fx.burst(_center(), Palette.WARNING, 24, 240.0, 0.5)
		if not str(config["enter_toast"]).is_empty():
			EventBus.toast_requested.emit(str(config["enter_toast"]))
		if not str(config["event"]).is_empty() and _on_phase_event(StringName(str(config["event"]))):
			return  # 子類別接手（例如劇情暫停），不播一般的階段轉換
		if fsm.is_in(&"act") and StringName(_move().get("kind", &"")) == &"pounce":
			return  # 空中不打斷，落地後再演出
		fsm.transition(&"phase_shift")


## 階段事件（資料 phases[].event）：子類別覆寫，回傳 true 代表已經接手，不播一般的階段轉換。
func _on_phase_event(_event: StringName) -> bool:
	return false


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
	_parts_key = _parts_state_key(move)
	for id: StringName in _parts_by_id:
		var part := _parts_by_id[id]
		var open := pattern.part_open(id, phase, _staggered, move, tags)
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
	if _parts_key != _parts_state_key(move):
		_refresh_parts()
	if _awake and fsm.current not in [&"phase_shift", &"intro", &"dormant"]:
		_tick_summons(delta)


func _parts_state_key(move: StringName) -> String:
	return "%s|%d|%s|%s|%s" % [phase_set, phase, move, _staggered, ",".join(tags)]


# ---------------------------------------------------------------------------
# 增援（階段資料的 summon）
# ---------------------------------------------------------------------------

func _tick_summons(delta: float) -> void:
	var config: Dictionary = current_phase()["summon"]
	if config.is_empty() or data.summon == null or data.summon.behavior == null or _summoned >= int(config["total"]):
		return
	_summon_left -= delta
	if _summon_left > 0.0:
		return
	_summon_left = float(config["every"])
	if alive_summons() >= int(config["max_alive"]):
		return
	var tiles: PackedFloat32Array = config["spawn_tiles"]
	_spawn_summon(tiles[_summoned % tiles.size()] * 16.0)


func _spawn_summon(x: float) -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var minion := data.summon.behavior.new() as Enemy
	if minion == null:
		push_error("[PatternBoss] %s 的增援 %s 的 behavior 不是 Enemy" % [data.id, data.summon.id])
		return
	minion.configure(data.summon)
	var at := _floor_at(Vector2(x, global_position.y - 8.0))
	minion.position = parent.to_local(at)
	parent.add_child.call_deferred(minion)
	_summons.append(weakref(minion))
	_summoned += 1
	Fx.burst(at + Vector2(0, -16.0), data.summon.color, 10, 120.0)


## 還活著的增援數（死掉或移除的會從清單拿掉）。
func alive_summons() -> int:
	var kept: Array[WeakRef] = []
	for ref in _summons:
		var minion := ref.get_ref() as Enemy
		if minion != null and not minion.is_queued_for_deletion() and not minion.is_dying():
			kept.append(ref)
	_summons = kept
	return kept.size()


## 這場已經叫出來的增援總數（重試時不會因為重新進場而變多：增援只在頭目醒著時才出現）。
func summoned_total() -> int:
	return _summoned


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



## 完美格擋讓攻擊者暈眩：招式資料有 parry_stagger 的（例如蓄力重擊）改成硬直並打開硬直時的部位；其他招式照舊不受影響。
func _on_stunned() -> void:
	if not (fsm.is_in(&"windup") or fsm.is_in(&"act")):
		return
	var seconds := _param("parry_stagger", 0.0)
	if seconds <= 0.0:
		return
	_stagger_override = seconds
	_slam_result = &"blocked"
	fsm.transition(&"yanked")


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


## 鍊子在身上的扣點（世界座標）：脖子骨頭（零件式外觀用頭的關節），都沒有時用頸部高度。
func _chain_end() -> Vector2:
	var anchor := anchor_node(&"neck") if rig != null else anchor_node(&"head")
	if anchor != null:
		return anchor.global_position
	return global_position + Vector2(0, -data.body_size.y * 0.8)


func _head_point() -> Vector2:
	var anchor := anchor_node(&"head")
	if anchor != null:
		return anchor.global_position
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


## 目前的姿勢名稱：招式資料的 pose_windup／pose_act，其他狀態用資料的 poses；沒有就是空字串。
## 骨架外觀當成骨架動作名，零件式外觀當成零件動畫的狀態名。
func _current_pose() -> StringName:
	var pose: StringName = &""
	if fsm.is_in(&"windup"):
		pose = _move().get("pose_windup", &"")
	elif fsm.is_in(&"act"):
		pose = _move().get("pose_act", &"")
	if pose == &"":
		pose = pattern.state_poses.get(fsm.current, &"")
	return pose


func _creature_state() -> StringName:
	var pose := _current_pose()
	return pose if pose != &"" else super._creature_state()


## 骨架動作由招式資料決定（pose_windup／pose_act），睡著時蹲低。
func _update_rig_action() -> void:
	var action := _current_pose()
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
			&"slam":
				_draw_slam_zone(t)
			&"fan":
				_draw_fan_lines(t)
			&"rush":
				var color := Color(LightKit.glow(Palette.DANGER, 1.2 + t), 0.3 + 0.4 * t)
				draw_line(Vector2(0, -2), Vector2(_rush_x - global_position.x, -2), color, 2.0)
	if not _marks.is_empty():
		var t := 1.0 - clampf(_telegraph_left / maxf(0.01, telegraph_seconds(_move_id)), 0.0, 1.0)
		var radius := _param("radius", 22.0)
		for mark in _marks:
			var at := to_local(mark)
			draw_arc(at, radius, 0.0, TAU, 28, Color(LightKit.glow(Palette.DANGER, 1.6), 0.5 + 0.4 * t), 1.5)
			draw_arc(at, radius * (1.0 - t), 0.0, TAU, 20, Color(LightKit.glow(Palette.DANGER, 2.2), 0.7), 1.0)
	_draw_custom()
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


## 蓄力重擊的預兆：地上的判定區從腳邊往前填滿，越接近出招越亮（紅＝要打到你）。
func _draw_slam_zone(t: float) -> void:
	var rect := slam_rect()
	var width := rect.size.x * minf(1.0, t * 1.3)
	var from_x := rect.position.x if facing > 0 else rect.end.x - width
	var color := Color(LightKit.glow(Palette.DANGER, 1.0 + 1.4 * t), 0.25 + 0.5 * t)
	draw_rect(Rect2(Vector2(from_x, -3.0), Vector2(width, 3.0)), color)
	var edge := rect.end.x if facing > 0 else rect.position.x
	draw_line(Vector2(edge, -1.0), Vector2(edge, -10.0 - 8.0 * t), color, 1.5)


## 扇形投擲的預兆：扇形的左右兩條邊線，鎖定後變亮變實。
func _draw_fan_lines(t: float) -> void:
	var origin := to_local(_muzzle())
	var spread := deg_to_rad(clampf(_param("spread", 40.0), 0.0, 120.0))
	var locked := is_aim_locked()
	var color := Color(LightKit.glow(Palette.DANGER, 1.6 if locked else 0.9 + 0.5 * t), 0.7 if locked else 0.2 + 0.35 * t)
	for side: float in [-0.5, 0.5]:
		draw_line(origin, origin + _aim_dir.rotated(spread * side) * 70.0, color, 1.0)


func _draw_shadow(world: Vector2, t: float) -> void:
	var at := to_local(world)
	var width := 14.0 + 14.0 * t
	draw_set_transform(at, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, width, Color(0.0, 0.0, 0.0, 0.25 + 0.35 * t))
	draw_arc(Vector2.ZERO, width, 0.0, TAU, 24, Color(LightKit.glow(Palette.DANGER, 1.5), 0.5), 1.5)
	draw_set_transform(Vector2.ZERO)


## 顏色語言：打開的部位（現在打得到的弱點）亮橙色脈動光，讓「現在打這裡」一眼看得出來。
## 一直打開的部位（例如人形頭目的頭）不畫任何標記：頭上常駐的圈像光環，也違反「敵人身上的介面標記要克制」（NE-262）。
func _draw_open_parts() -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 18.0)
	for id: StringName in _parts_by_id:
		if not is_part_open(id):
			continue
		var box := _parts_by_id[id]
		var at := box.shape_offset()
		if str(pattern.parts_open.get(id, "always")) == "always":
			continue
		draw_circle(at, 5.0 + pulse * 2.0, Color(LightKit.glow(Palette.WARNING, 2.6), 0.45))
		draw_arc(at, 8.0 + pulse * 2.0, 0.0, TAU, 20, LightKit.glow(Palette.WARNING, 3.0), 1.5)


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
# 子類別的自訂招式種類（資料的 custom_kinds）：只覆寫需要的掛鉤
# ---------------------------------------------------------------------------

## 這個子類別有沒有實作某個自訂招式種類；沒有實作的種類不會被選（_setup_states 會記錄錯誤）。
func _implements_kind(_kind: StringName) -> bool:
	return false


## 自訂種類的使用條件（例如要玩家在正面）；預設可用。
func _custom_move_usable(_id: StringName, _kind: StringName) -> bool:
	return true


## 自訂種類的預兆開始（預兆時間已開始計時）。
func _custom_windup_enter(_kind: StringName) -> void:
	pass


## 自訂種類的預兆每影格；可以 transition 到別的狀態（例如被打斷）。
func _custom_windup_tick(_kind: StringName, _delta: float) -> void:
	pass


## 自訂種類的出招開始。
func _custom_act_enter(_kind: StringName) -> void:
	pass


## 自訂種類的出招每影格；預設立即收招，子類別結束時自己 transition 到 recover（或別的狀態）。
func _custom_act_tick(_kind: StringName, _delta: float) -> void:
	fsm.transition(&"recover")


## 子類別的疊加圖層（預兆線、外接零件）；畫在打開部位的光圈底下。
func _draw_custom() -> void:
	pass


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
